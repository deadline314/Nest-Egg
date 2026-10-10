#!/usr/bin/env python3
"""Reproducible CPU source-owner/UV-domain audit for NE-222 boot meshes.

Inputs are bundled beside this script. No project, Godot, GPU, network, or extra
Python dependency is needed; the existing Pillow and NumPy environment is used (no new dependency is required).
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DEFAULT_IMAGES = ROOT / "pm/Nest-Egg/images/NE-222-source-domain-review"
SOURCE = HERE / "inputs/source/rin_kneel_color_alpha_22297_0.png"
REGISTRATION = HERE / "inputs/source/registration-v3-report.json"
MANIFEST = HERE / "inputs/source/ownership-manifest-v3.json"
MESHES = {"v1": HERE / "inputs/mesh/boot-mesh-v1.json", "v2": HERE / "inputs/mesh/boot-mesh-v2.json"}
INPUTS = {
    "source": SOURCE,
    "registration": REGISTRATION,
    "owner_manifest": MANIFEST,
    "front_boot_mask": HERE / "inputs/source/front_boot-mask.png",
    "back_boot_mask": HERE / "inputs/source/back_boot-mask.png",
    "front_boot_texture": HERE / "inputs/source/front_boot-texture.png",
    "back_boot_texture": HERE / "inputs/source/back_boot-texture.png",
    "mesh_v1": MESHES["v1"],
    "mesh_v2": MESHES["v2"],
}
EXPECTED_SHA256 = {
    "source": "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed",
    "registration": "21feaaa1f80ddd57d5bb534b5bbe47ef3e0cf2d72c6585aa0da1ba4f48aab6d6",
    "owner_manifest": "0faa30113e70881a8cca5c6b90a3806bf65370d1b6cc5391fc66ae94556c7b43",
    "front_boot_mask": "92f658fdc34c2c2833e0e042e413f0daf5d1b5f91e124de9f5e884e2f1e60b35",
    "back_boot_mask": "5428edc0811173ae5c9c028e828c5870b9ed62e96cb362b8bf7937f100217d10",
    "front_boot_texture": "c60c56c8dbb69f3bf9024798c95083f1f2e967cb93a754b4ab52267e61fd6168",
    "back_boot_texture": "8e3d9fbd02d40497f345b886aaef48b1acb704d1b88b92d32d3045c3d6934276",
    "mesh_v1": "00ca8795d476921c22425359694f95a81450480302223f770a3b096fe6a1c0e5",
    "mesh_v2": "2eef3819ca86070e8c84349391edfb9d046f01c274b29fb497df478adc69dd08",
}
PARTS = ("front", "back")
VERSIONS = ("v1", "v2")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha256(path.read_bytes())


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def load_inputs() -> tuple[np.ndarray, dict[str, Any], dict[str, dict[str, Any]], dict[str, Any]]:
    hashes = {name: file_sha(path) for name, path in INPUTS.items()}
    for name, expected in EXPECTED_SHA256.items():
        if hashes[name] != expected:
            raise AssertionError(f"input SHA mismatch: {name}: {hashes[name]} != {expected}")
    source = np.array(Image.open(SOURCE).convert("RGBA"))
    if source.shape != (736, 1440, 4):
        raise AssertionError(f"unexpected source dimensions/mode: {source.shape}")
    reg = json.loads(REGISTRATION.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    meshes = {version: json.loads(path.read_text(encoding="utf-8")) for version, path in MESHES.items()}
    if reg["source"]["sha256"] != hashes["source"] or reg["source"]["alpha_floor"] != 40:
        raise AssertionError("registration source provenance or alpha floor changed")
    return source, reg, meshes, {"sha256": hashes, "manifest": manifest}


def inside_triangles(points: np.ndarray, uvs: np.ndarray, indices: np.ndarray) -> np.ndarray:
    """Return whether each pixel center is in the union of UV triangles."""
    covered = np.zeros(len(points), dtype=bool)
    eps = 1e-9
    for tri in indices:
        a, b, c = uvs[tri]
        area2 = float((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        if abs(area2) <= 1e-12:
            raise AssertionError(f"degenerate UV triangle in coverage domain: {tri.tolist()}")
        ab = (b - a)
        bc = (c - b)
        ca = (a - c)
        pa = points - a
        pb = points - b
        pc = points - c
        c1 = ab[0] * pa[:, 1] - ab[1] * pa[:, 0]
        c2 = bc[0] * pb[:, 1] - bc[1] * pb[:, 0]
        c3 = ca[0] * pc[:, 1] - ca[1] * pc[:, 0]
        covered |= ((c1 >= -eps) & (c2 >= -eps) & (c3 >= -eps)) | ((c1 <= eps) & (c2 <= eps) & (c3 <= eps))
    return covered


def clipped_uv_triangles_y(uvs: np.ndarray, indices: np.ndarray, max_y: float) -> tuple[np.ndarray, np.ndarray]:
    """Geometrically clip each UV triangle to y <= max_y (Sutherland-Hodgman)."""
    vertices: list[list[float]] = []
    triangles: list[list[int]] = []
    for tri in indices:
        polygon = [uvs[int(i)].astype(float).tolist() for i in tri]
        clipped: list[list[float]] = []
        for idx, end in enumerate(polygon):
            start = polygon[idx - 1]
            start_in = start[1] <= max_y + 1e-12
            end_in = end[1] <= max_y + 1e-12
            if end_in:
                if not start_in:
                    t = (max_y - start[1]) / (end[1] - start[1])
                    clipped.append([start[0] + t * (end[0] - start[0]), max_y])
                clipped.append(end)
            elif start_in:
                t = (max_y - start[1]) / (end[1] - start[1])
                clipped.append([start[0] + t * (end[0] - start[0]), max_y])
        # Remove repeated consecutive vertices caused by a vertex landing
        # exactly on the clip line before fan triangulation.
        clean: list[list[float]] = []
        for point in clipped:
            if not clean or np.linalg.norm(np.asarray(point) - np.asarray(clean[-1])) > 1e-12:
                clean.append(point)
        if len(clean) > 1 and np.linalg.norm(np.asarray(clean[0]) - np.asarray(clean[-1])) <= 1e-12:
            clean.pop()
        if len(clean) < 3:
            continue
        base = len(vertices)
        vertices.extend(clean)
        for i in range(1, len(clean) - 1):
            a, b, c = np.asarray(clean[0]), np.asarray(clean[i]), np.asarray(clean[i + 1])
            area2 = float((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
            if abs(area2) > 1e-12:
                triangles.append([base, base + i, base + i + 1])
    if not triangles:
        return np.zeros((0, 2), dtype=np.float64), np.zeros((0, 3), dtype=np.int64)
    return np.asarray(vertices, dtype=np.float64), np.asarray(triangles, dtype=np.int64)


def owner_geometry(part: str, source: np.ndarray, reg: dict[str, Any]) -> dict[str, Any]:
    owner = reg["owners"][f"{part}_boot"]
    x0, y0, x1, y1 = map(int, owner["crop_bbox_xyxy_half_open"])
    mask_path = INPUTS[f"{part}_boot_mask"]
    texture_path = INPUTS[f"{part}_boot_texture"]
    mask_img = Image.open(mask_path)
    if mask_img.mode != "L" or mask_img.size != (1440, 736):
        raise AssertionError(f"{part} owner mask must be full-canvas L 1440x736")
    mask = np.array(mask_img) > 0
    ys, xs = np.where(mask)
    count = int(mask.sum())
    actual_mask_bbox = [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]
    if actual_mask_bbox != owner["mask_bbox_xyxy_half_open"]:
        raise AssertionError(f"{part} mask bbox disagrees with registration: {actual_mask_bbox}")
    if not owner.get("source_rgba_exact") or owner.get("source_sha256") != file_sha(SOURCE):
        raise AssertionError(f"{part} registration does not pin exact source RGBA")
    if owner.get("color_sha256") != file_sha(texture_path):
        raise AssertionError(f"{part} texture SHA disagrees with registration")
    if count != owner["owned_alpha_ge40_pixels"]:
        raise AssertionError(f"{part} owner count disagrees with registration: {count}")
    if not np.all(source[ys, xs, 3] >= reg["source"]["alpha_floor"]):
        raise AssertionError(f"{part} owner contains source alpha below floor 40")
    if np.any(xs < x0) or np.any(xs >= x1) or np.any(ys < y0) or np.any(ys >= y1):
        raise AssertionError(f"{part} source owner falls outside declared texture crop")
    tex = np.array(Image.open(texture_path).convert("RGBA"))
    if tex.shape[:2] != (y1 - y0, x1 - x0):
        raise AssertionError(f"{part} crop size differs from source mapping: {tex.shape[:2]}")
    local_y = ys - y0
    local_x = xs - x0
    crop_match = np.all(tex[local_y, local_x] == source[ys, xs], axis=1)
    if not bool(np.all(crop_match)):
        mismatch = np.where(~crop_match)[0]
        raise AssertionError(f"{part} source RGBA mismatch at {len(mismatch)} owned crop samples; first source xy={list(zip(xs[mismatch[:5]].tolist(), ys[mismatch[:5]].tolist()))}")
    points = np.column_stack((local_x + 0.5, local_y + 0.5)).astype(np.float64)
    return {
        "owner": owner,
        "mask": mask,
        "source_xy": np.column_stack((xs, ys)),
        "local_xy": np.column_stack((local_x, local_y)),
        "points_uv": points,
        "texture": tex,
        "crop_bbox": [x0, y0, x1, y1],
        "rgba_matches": int(crop_match.sum()),
        "owner_count": count,
        "max_owned_local_y": int(local_y.max()),
    }


def mesh_data(mesh_doc: dict[str, Any], part: str) -> tuple[dict[str, Any], np.ndarray, np.ndarray, np.ndarray]:
    pose = next(iter(mesh_doc["pose_parts"].values()))
    slot = f"foot_{part}"
    record = next((item for item in pose["parts"] if item.get("slot") == slot), None)
    if record is None:
        raise AssertionError(f"mesh does not contain {slot}")
    raw_mesh = record["mesh"]
    raw_uv = raw_mesh["uvs"]
    raw_vertices = raw_mesh["vertices"]
    for label, values in (("UV", raw_uv), ("skeleton vertex", raw_vertices)):
        if not isinstance(values, list) or any(not isinstance(point, list) or len(point) != 2 for point in values):
            raise AssertionError(f"{slot} {label} data must be a list of 2D numeric points")
        if any(type(value) not in (int, float) for point in values for value in point):
            raise AssertionError(f"{slot} {label} coordinates must be JSON numbers")
    uv = np.asarray(raw_uv, dtype=np.float64)
    vertices = np.asarray(raw_vertices, dtype=np.float64)
    raw_triangles = raw_mesh["triangles"]
    if uv.ndim != 2 or uv.shape[1] != 2 or vertices.shape != uv.shape:
        raise AssertionError(f"{slot} vertices/UV arrays must be matching Nx2 arrays")
    if not np.isfinite(uv).all() or not np.isfinite(vertices).all():
        raise AssertionError(f"{slot} contains non-finite UV or skeleton vertex values")
    if not isinstance(raw_triangles, list) or len(raw_triangles) == 0 or len(raw_triangles) % 3:
        raise AssertionError(f"{slot} triangle indices must be a non-empty flat list of triplets")
    if any(type(value) is not int for value in raw_triangles):
        raise AssertionError(f"{slot} triangle indices must be JSON integers (no bool/float truncation)")
    tri = np.asarray(raw_triangles, dtype=np.int64).reshape((-1, 3))
    if np.any(tri < 0) or np.any(tri >= len(uv)):
        raise AssertionError(f"{slot} has invalid triangle index")
    left = uv[tri[:, 1]] - uv[tri[:, 0]]
    right = uv[tri[:, 2]] - uv[tri[:, 0]]
    areas = left[:, 0] * right[:, 1] - left[:, 1] * right[:, 0]
    if np.any(np.abs(areas) <= 1e-12):
        raise AssertionError(f"{slot} has zero-area UV triangles")
    return record, uv, vertices, tri


def vertex_mapping(uv: np.ndarray, vertices: np.ndarray, crop_bbox: list[int], affine: list[float]) -> dict[str, Any]:
    """Check each mesh vertex against the published source-to-skeleton affine."""
    if len(affine) != 6 or not np.isfinite(np.asarray(affine, dtype=np.float64)).all():
        raise AssertionError("guide source_to_skeleton must be six finite affine values")
    a, b, c, d, tx, ty = map(float, affine)
    linear = np.asarray([[a, c], [b, d]], dtype=np.float64)
    if abs(float(np.linalg.det(linear))) <= 1e-15:
        raise AssertionError("guide source_to_skeleton affine is singular")
    x0, y0, _, _ = crop_bbox
    source_vertices = uv + np.asarray([x0, y0], dtype=np.float64)
    expected = np.column_stack((a * source_vertices[:, 0] + c * source_vertices[:, 1] + tx,
                                b * source_vertices[:, 0] + d * source_vertices[:, 1] + ty))
    skeleton_error = vertices - expected
    source_error = np.linalg.solve(linear, skeleton_error.T).T
    error_px = np.linalg.norm(source_error, axis=1)
    tolerance_px = 1e-4
    return {
        "affine_source_to_skeleton": [a, b, c, d, tx, ty],
        "mesh_vertex_count": int(len(uv)),
        "vertices_tested": int(len(uv)),
        "max_error_skeleton_units": float(np.linalg.norm(skeleton_error, axis=1).max()),
        "max_error_source_pixels": float(error_px.max()),
        "tolerance_source_pixels": tolerance_px,
        "per_vertex_source_xy": source_vertices.tolist(),
        "per_vertex_uv": uv.tolist(),
        "per_vertex_skeleton_xy": vertices.tolist(),
        "per_vertex_expected_skeleton_xy": expected.tolist(),
        "per_vertex_error_source_pixels": error_px.tolist(),
        "mapping": "PASS" if float(error_px.max()) <= tolerance_px else "FAIL",
    }


def analyze() -> dict[str, Any]:
    source, reg, mesh_docs, _ = load_inputs()
    affine = reg["guide"]["source_to_skeleton"]
    result: dict[str, Any] = {
        "purpose": "source-owner pixel-center coverage and UV-vertex-to-source/skeleton mapping; CPU evidence only",
        "source": {"path": "inputs/source/rin_kneel_color_alpha_22297_0.png", "sha256": file_sha(SOURCE), "size": [1440, 736], "mode": "RGBA", "alpha_floor": 40},
        "coordinate_rule": "owner pixel center (x+0.5,y+0.5) maps to local texture UV (x-crop_x0+0.5,y-crop_y0+0.5); mesh vertex maps as source_xy=(uv.x+crop_x0,uv.y+crop_y0), then through guide.source_to_skeleton; single texture, no atlas",
        "mapping_tolerance": "max source-domain vertex error <= 0.0001 source pixel; this accommodates float serialization only and rejects a 1 px shift",
        "owner_masks": {},
        "mesh_inputs": {},
        "parts": {},
        "one_pixel_inset_negative_control": {},
        "one_pixel_uv_shift_negative_control": {},
        "limitations": [
            "This checks whether given owner pixels are addressable and whether UV vertices map to their recorded skeleton vertices; it does not validate semantic ownership/anatomy.",
            "The two source-pose boot meshes are unaccepted candidates; this report does not certify NE-222 or any native rendered pose.",
        ],
    }
    result["guide_mapping"] = {"registration_report": "inputs/source/registration-v3-report.json", "source_to_skeleton": list(affine)}
    for v in VERSIONS:
        result["mesh_inputs"][v] = {"path": f"inputs/mesh/boot-mesh-{v}.json", "sha256": file_sha(MESHES[v]), "pose_id": next(iter(mesh_docs[v]["pose_parts"].keys()))}
    geometry = {part: owner_geometry(part, source, reg) for part in PARTS}
    mesh_records: dict[tuple[str, str], tuple[dict[str, Any], np.ndarray, np.ndarray, np.ndarray]] = {}
    for part in PARTS:
        g = geometry[part]
        result["owner_masks"][part] = {
            "path": f"inputs/source/{part}_boot-mask.png",
            "sha256": file_sha(INPUTS[f"{part}_boot_mask"]),
            "mask_bbox_xyxy_half_open": g["owner"]["mask_bbox_xyxy_half_open"],
            "crop_bbox_xyxy_half_open": g["crop_bbox"],
            "owned_pixel_count": g["owner_count"],
            "source_rgba_crop_equal_owned_pixels": g["rgba_matches"],
            "source_rgba_crop_mismatches": g["owner_count"] - g["rgba_matches"],
            "texture_path": f"inputs/source/{part}_boot-texture.png",
            "texture_sha256": file_sha(INPUTS[f"{part}_boot_texture"]),
        }
        result["parts"][part] = {}
        for version in VERSIONS:
            record, uv, vertices, tri = mesh_data(mesh_docs[version], part)
            mesh_records[(part, version)] = (record, uv, vertices, tri)
            mesh_texture = mesh_docs[version]["textures"][record["texture"]]
            crop_w = g["crop_bbox"][2] - g["crop_bbox"][0]
            crop_h = g["crop_bbox"][3] - g["crop_bbox"][1]
            if mesh_texture["size"] != [crop_w, crop_h]:
                raise AssertionError(f"{version} {part} mesh texture dimensions disagree with registration crop")
            covered = inside_triangles(g["points_uv"], uv, tri)
            misses = np.where(~covered)[0]
            miss_src = g["source_xy"][misses]
            mapping = vertex_mapping(uv, vertices, g["crop_bbox"], affine)
            result["parts"][part][version] = {
                "uv_vertex_count": int(len(uv)),
                "triangle_count": int(len(tri)),
                "owner_pixel_centers_tested": g["owner_count"],
                "covered_owner_pixel_centers": int(covered.sum()),
                "uncovered_owner_pixel_centers": int(len(misses)),
                "uncovered_source_xy_first_20": miss_src[:20].astype(int).tolist(),
                "coverage": "PASS" if len(misses) == 0 else "FAIL",
                "uv_vertex_source_skeleton_mapping": mapping,
            }
            if version == "v2" and mapping["mapping"] != "PASS":
                raise AssertionError(f"{part} v2 UV vertices do not map to their source skeleton vertices")

    # Valid-domain translation control: +1 source pixel in U must retain every
    # owner sample while disagreeing with the unchanged skeleton vertices.
    shift_results: dict[str, Any] = {}
    for part in PARTS:
        g = geometry[part]
        record, uv, vertices, tri = mesh_records[(part, "v2")]
        shifted_uv = uv + np.asarray([1.0, 0.0])
        shifted_coverage = inside_triangles(g["points_uv"], shifted_uv, tri)
        mapping = vertex_mapping(shifted_uv, vertices, g["crop_bbox"], affine)
        missing = int((~shifted_coverage).sum())
        if missing != 0:
            raise AssertionError(f"{part} +1px UV shift must leave owner-domain coverage intact; got {missing} misses")
        if mapping["mapping"] != "FAIL" or abs(mapping["max_error_source_pixels"] - 1.0) > 1e-9:
            raise AssertionError(f"{part} +1px UV shift was not rejected by source-to-skeleton mapping")
        shift_results[part] = {
            "uv_delta_source_pixels": [1.0, 0.0],
            "owner_pixel_centers_tested": g["owner_count"],
            "coverage_missing_after_shift": missing,
            "coverage": "PASS (negative control must isolate mapping from domain coverage)",
            "mapping_after_shift": mapping,
            "observed": "FAIL as expected: 1 source-pixel UV translation disagrees with unchanged skeleton vertices",
        }
    result["one_pixel_uv_shift_negative_control"] = shift_results

    # Clip each v2 UV triangle one source pixel inward from the real bottom
    # contour. This rejects owner pixels, not transparent crop padding.
    inset: dict[str, Any] = {}
    for part in PARTS:
        g = geometry[part]
        _, uv, _, tri = mesh_records[(part, "v2")]
        ordinary = inside_triangles(g["points_uv"], uv, tri)
        local_edge_row = g["max_owned_local_y"]
        clipped_uv, clipped_tri = clipped_uv_triangles_y(uv, tri, float(local_edge_row))
        inset_covered = inside_triangles(g["points_uv"], clipped_uv, clipped_tri)
        if not np.all(ordinary):
            raise AssertionError(f"{part} V2 source owner must pass before inset control")
        missed = np.where(~inset_covered)[0]
        edge_sel = g["local_xy"][:, 1] == local_edge_row
        edge_indices = np.where(edge_sel)[0]
        removed_edge = np.intersect1d(missed, edge_indices, assume_unique=True)
        if len(removed_edge) != len(edge_indices) or len(edge_indices) == 0:
            raise AssertionError(f"{part} 1px source-edge inset did not reject the entire actual owner edge row")
        syx = g["source_xy"][removed_edge]
        if not np.all(g["mask"][syx[:, 1], syx[:, 0]]):
            raise AssertionError(f"{part} inset negative control selected non-owner/padding points")
        inset[part] = {
            "mesh": "each V2 UV triangle geometrically clipped at y <= local source row {0} (one source pixel inward from the actual owned bottom edge)".format(local_edge_row),
            "clip_method": "Sutherland-Hodgman per triangle against a horizontal source-domain half-plane; clipped polygons are fan-triangulated and retested with the same pixel-center coverage checker",
            "owned_edge_source_y": int(g["crop_bbox"][1] + local_edge_row),
            "owned_edge_local_row": int(local_edge_row),
            "owned_source_pixels_on_edge": int(len(edge_indices)),
            "uncovered_owner_pixel_centers_after_inset": int(len(missed)),
            "newly_uncovered_actual_edge_xy": g["source_xy"][removed_edge].astype(int).tolist(),
            "transparent_padding_used": False,
            "expected_negative_control": "FAIL: same checker must report missing owner pixels",
            "observed": "FAIL as expected" if len(missed) > 0 else "INVALID_CONTROL",
        }
        if len(missed) == 0:
            raise AssertionError(f"{part} inset negative control unexpectedly passed")
    result["one_pixel_inset_negative_control"] = inset
    result["registration_report"] = {"path": "inputs/source/registration-v3-report.json", "sha256": file_sha(REGISTRATION)}
    result["ownership_manifest"] = {"path": "inputs/source/ownership-manifest-v3.json", "sha256": file_sha(MANIFEST)}
    return result


def panel_image(part: str, version: str, g: dict[str, Any], mesh_doc: dict[str, Any], *, inset: bool = False, shift_x: float = 0.0) -> Image.Image:
    _, uv, _, tri = mesh_data(mesh_doc, part)
    uv = uv + np.asarray([shift_x, 0.0])
    tex = Image.fromarray(g["texture"], "RGBA")
    background = Image.new("RGBA", tex.size, (76, 76, 76, 255))
    canvas = Image.alpha_composite(background, tex).convert("RGB")
    owner_crop = g["mask"][g["crop_bbox"][1]:g["crop_bbox"][3], g["crop_bbox"][0]:g["crop_bbox"][2]]
    points = g["points_uv"]
    covered = inside_triangles(points, uv, tri)
    if inset:
        clipped_uv, clipped_tri = clipped_uv_triangles_y(uv, tri, float(g["max_owned_local_y"]))
        covered = inside_triangles(points, clipped_uv, clipped_tri)
    misses = np.zeros(owner_crop.shape, dtype=bool)
    missxy = g["local_xy"][~covered]
    if len(missxy):
        misses[missxy[:, 1], missxy[:, 0]] = True
    rgba = np.array(canvas.convert("RGBA")).astype(np.uint16)
    red = np.array([238, 38, 88, 175], dtype=np.uint16)
    rgb = rgba[..., :3]
    rgb[misses] = ((rgb[misses] * (255 - red[3]) + red[:3] * red[3]) // 255).astype(np.uint16)
    canvas = Image.fromarray(np.concatenate((rgb.astype(np.uint8), np.full((*owner_crop.shape, 1), 255, dtype=np.uint8)), axis=2), "RGBA").convert("RGB")
    draw = ImageDraw.Draw(canvas)
    draw_uv, draw_tri = (clipped_uv_triangles_y(uv, tri, float(g["max_owned_local_y"])) if inset else (uv, tri))
    for t in draw_tri:
        poly = [(round(float(draw_uv[i, 0])), round(float(draw_uv[i, 1]))) for i in t]
        draw.line(poly + [poly[0]], fill=(20, 225, 245), width=1)
    # Green traces the real owner edge; red then highlights any omitted edge.
    ys, xs = np.where(owner_crop)
    for y, x in zip(ys, xs):
        if x == 0 or y == 0 or x == owner_crop.shape[1] - 1 or y == owner_crop.shape[0] - 1 or not (owner_crop[y - 1, x] and owner_crop[y + 1, x] and owner_crop[y, x - 1] and owner_crop[y, x + 1]):
            draw.point((int(x), int(y)), fill=(72, 255, 128))
    if inset:
        row = g["max_owned_local_y"]
        for x in range(owner_crop.shape[1]):
            if owner_crop[row, x]:
                draw.point((x, row), fill=(255, 30, 20))
    return canvas


def build_images(result: dict[str, Any]) -> dict[str, bytes]:
    source, reg, mesh_docs, _ = load_inputs()
    geometry = {part: owner_geometry(part, source, reg) for part in PARTS}
    panel_w, panel_h, label_h = 340, 330, 26
    sheet = Image.new("RGB", (panel_w * 4, (panel_h + label_h) * 2), (44, 46, 50))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    cell_specs = [
        (0, 0, "Front boot · v1 · holes in magenta", "front", "v1", False, 0.0),
        (1, 0, "Front boot · v2 · owner coverage", "front", "v2", False, 0.0),
        (2, 0, "Front boot · v2 · 1px owner-edge inset", "front", "v2", True, 0.0),
        (3, 0, "Front v2 UV+1px · domain PASS / map FAIL", "front", "v2", False, 1.0),
        (0, 1, "Back boot · v1 · holes in magenta", "back", "v1", False, 0.0),
        (1, 1, "Back boot · v2 · owner coverage", "back", "v2", False, 0.0),
        (2, 1, "Back boot · v2 · 1px owner-edge inset", "back", "v2", True, 0.0),
        (3, 1, "Back v2 UV+1px · domain PASS / map FAIL", "back", "v2", False, 1.0),
    ]
    for col, row, label, part, version, inset, shift_x in cell_specs:
        x0, y0 = col * panel_w, row * (panel_h + label_h)
        draw.text((x0 + 5, y0 + 5), label, fill=(245, 245, 245), font=font)
        image = panel_image(part, version, geometry[part], mesh_docs[version], inset=inset, shift_x=shift_x)
        sheet.paste(image.convert("RGB"), (x0 + 5, y0 + label_h))
        draw.rectangle((x0, y0 + label_h, x0 + panel_w - 1, y0 + label_h + panel_h - 1), outline=(110, 110, 110))
    native = io.BytesIO()
    sheet.save(native, format="PNG", optimize=False)
    scaled = sheet.resize((sheet.width * 3, sheet.height * 3), Image.Resampling.NEAREST)
    zoom = io.BytesIO()
    scaled.save(zoom, format="PNG", optimize=False)

    # Full source context: source remains at 1:1; owner regions and crop windows
    # are overlays, not alterations to the original source PNG.
    base = Image.fromarray(source, "RGBA")
    bg = Image.new("RGBA", base.size, (76, 76, 76, 255))
    context = Image.alpha_composite(bg, base).convert("RGB")
    overlay = Image.new("RGBA", context.size, (0, 0, 0, 0))
    ov = ImageDraw.Draw(overlay)
    for part, color in (("front", (255, 110, 32, 80)), ("back", (40, 170, 255, 80))):
        g = geometry[part]
        mask = g["mask"]
        pix = np.zeros((736, 1440, 4), dtype=np.uint8)
        pix[mask] = color
        overlay = Image.alpha_composite(overlay, Image.fromarray(pix, "RGBA"))
        x0, y0, x1, y1 = g["crop_bbox"]
        ImageDraw.Draw(overlay).rectangle((x0, y0, x1 - 1, y1 - 1), outline=(245, 245, 20, 255), width=1)
        ImageDraw.Draw(overlay).text((x0 + 3, y0 + 3), f"{part}_boot crop", fill=(255, 255, 255, 255), font=font)
    context = Image.alpha_composite(context.convert("RGBA"), overlay).convert("RGB")
    ctx = io.BytesIO()
    context.save(ctx, format="PNG", optimize=False)
    return {
        "boot_uv_domain_native.png": native.getvalue(),
        "boot_uv_domain_nearest3x.png": zoom.getvalue(),
        "source_owner_context_native.png": ctx.getvalue(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "results", help="report output folder (default: package/results)")
    parser.add_argument("--images-out", type=Path, default=DEFAULT_IMAGES, help="evidence image folder (default: repo pm/Nest-Egg/images/NE-222-source-domain-review)")
    args = parser.parse_args()
    out_dir = args.out.resolve()
    image_dir = args.images_out.resolve()
    first = analyze()
    images_first = build_images(first)
    second = analyze()
    images_second = build_images(second)
    if canonical_json(first) != canonical_json(second):
        raise AssertionError("repeat analysis differs")
    if {k: sha256(v) for k, v in images_first.items()} != {k: sha256(v) for k, v in images_second.items()}:
        raise AssertionError("repeat rendered evidence image hashes differ")
    first["verifier_sha256"] = file_sha(Path(__file__).resolve())
    first["determinism"] = {
        "repeat_analysis_equal": True,
        "repeat_image_hashes_equal": True,
        "analysis_payload_sha256": sha256(canonical_json(first)),
        "images_sha256": {name: sha256(data) for name, data in images_first.items()},
        "repeat_runs": 2,
    }
    input_manifest = {
        "note": "Bundled input snapshot; paths below are relative to this package.",
        "files": {name: {"path": path.relative_to(HERE).as_posix(), "sha256": file_sha(path), "bytes": path.stat().st_size} for name, path in INPUTS.items()},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    image_dir.mkdir(parents=True, exist_ok=True)
    (HERE / "input-manifest.json").write_bytes(canonical_json(input_manifest))
    (out_dir / "verification.json").write_bytes(canonical_json(first))
    for name, data in images_first.items():
        (image_dir / name).write_bytes(data)
    print("NE-222 source-domain CPU verifier: PASS")
    print(f"source: {first['source']['sha256']} RGBA 1440x736; alpha floor 40")
    for part in PARTS:
        m = first["owner_masks"][part]
        print(f"{part}_boot: owner={m['owned_pixel_count']} RGBA crop mismatches={m['source_rgba_crop_mismatches']}")
        for version in VERSIONS:
            r = first["parts"][part][version]
            mapping = r["uv_vertex_source_skeleton_mapping"]
            print(f"  {version}: vertices={r['uv_vertex_count']} triangles={r['triangle_count']} covered={r['covered_owner_pixel_centers']} missing={r['uncovered_owner_pixel_centers']} domain={r['coverage']} mapping={mapping['mapping']} max_error_px={mapping['max_error_source_pixels']:.12g}")
        n = first["one_pixel_inset_negative_control"][part]
        shift = first["one_pixel_uv_shift_negative_control"][part]
        print(f"  V2 owned-edge 1px inset: FAIL as expected; edge samples={n['owned_source_pixels_on_edge']} missing={n['uncovered_owner_pixel_centers_after_inset']}; transparent padding used=no")
        print(f"  V2 UV +1px mapping control: domain missing={shift['coverage_missing_after_shift']}, mapping={shift['mapping_after_shift']['mapping']} (must fail), max_error_px={shift['mapping_after_shift']['max_error_source_pixels']:.12g}")
    print("repeat: analysis and all 3 image hashes identical across 2 builds")
    print(f"report: {out_dir / 'verification.json'}")
    print(f"images: {image_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"NE-222 source-domain CPU verifier: FAIL: {type(exc).__name__}: {exc}")
        raise
