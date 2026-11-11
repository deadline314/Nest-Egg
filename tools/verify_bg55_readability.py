"""Recompute BG55 enemy measurements from the original floating viewport bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

FORMATS = {14: ("<f2", 3), 15: ("<f2", 4), 10: ("<f4", 3), 11: ("<f4", 4)}


def transform_values(transform: str | list) -> list[float]:
    return list(map(float, transform)) if isinstance(transform, list) else [float(v) for v in re.findall(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", transform)]


def mapped_rect(feet: list[float], transform: str | list, density: float, ring: int, width: int, height: int) -> list[int]:
    values = transform_values(transform)
    assert len(values) == 6, transform
    xx, xy, yx, yy, ox, oy = values
    fx, fy = feet
    corners = np.array([[fx - 9 - ring, fy - 44 - ring], [fx + 9 + ring, fy - 44 - ring],
                        [fx - 9 - ring, fy - 4 + ring], [fx + 9 + ring, fy - 4 + ring]])
    raster = (corners @ np.array([[xx, xy], [yx, yy]]) + [ox, oy]) * density
    start = np.maximum(np.floor(raster.min(axis=0)), [0, 0]).astype(int)
    end = np.minimum(np.ceil(raster.max(axis=0)), [width, height]).astype(int)
    if np.any(end <= start):
        return [0, 0, 0, 0]
    return [int(start[0]), int(start[1]), int(end[0] - start[0]), int(end[1] - start[1])]


def mapped_world_box(box: list[float], record: dict) -> list[int]:
    x, y, w, h = box
    xx, xy, yx, yy, ox, oy = transform_values(record.get("canvas_transform_values", record["canvas_transform"]))
    corners = np.array([[x, y], [x + w, y], [x, y + h], [x + w, y + h]])
    raster = (corners @ np.array([[xx, xy], [yx, yy]]) + [ox, oy]) * record["density"]
    start = np.maximum(np.floor(raster.min(axis=0)), [0, 0]).astype(int)
    end = np.minimum(np.ceil(raster.max(axis=0)), [record["width"], record["height"]]).astype(int)
    assert np.all(end > start)
    return [*start.tolist(), *(end - start).tolist()]


def parts_from_pixels(rgb: np.ndarray, body: list[int], outer: list[int]) -> dict[str, float]:
    # An explicit pixel mask selects the ring; it does not use a world-space
    # area as a denominator or call the Godot mapper under test.
    x, y, w, h = body
    ox, oy, ow, oh = outer
    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    inside = luma[y:y + h, x:x + w].reshape(-1)
    yy, xx = np.mgrid[oy:oy + oh, ox:ox + ow]
    ring = luma[oy:oy + oh, ox:ox + ow][~((xx >= x) & (xx < x + w) & (yy >= y) & (yy < y + h))]
    if not inside.size or not ring.size:
        return dict(inner=0.0, body=0.0, outer=0.0, bright=0.0, dark=0.0)
    outside = float(ring.mean())
    inner = float(np.quantile(inside, 0.9, method="lower"))
    dark_body = float(np.quantile(inside, 0.25 if outside >= 0.12 else 0.5, method="lower"))
    return dict(inner=inner, body=dark_body, outer=outside,
                bright=(inner - outside) / (outside + 0.02), dark=(outside - dark_body) / (outside + 0.02))


def exposure_bound(rgb: np.ndarray, enemy: dict, record: dict) -> dict:
    x, y, w, h = enemy.get("visual_world_bounds_values", transform_values(enemy["visual_world_bounds"]))
    xx, xy, yx, yy, ox, oy = transform_values(record.get("canvas_transform_values", record["canvas_transform"]))
    # Include a 24-world-pixel margin for the adjacent hand/weapon drawables.
    corners = np.array([[x - 24, y - 24], [x + w + 24, y - 24], [x - 24, y + h + 24], [x + w + 24, y + h + 24]])
    raster = (corners @ np.array([[xx, xy], [yx, yy]]) + [ox, oy]) * record["density"]
    start = np.maximum(np.floor(raster.min(axis=0)), [0, 0]).astype(int)
    end = np.minimum(np.ceil(raster.max(axis=0)), [record["width"], record["height"]]).astype(int)
    region = rgb[start[1]:end[1], start[0]:end[0]]
    assert region.size > 0
    white = int(np.all(region > 0.92, axis=-1).sum())
    return dict(screen_rect=[*start.tolist(), *(end - start).tolist()], white_pixels_including_background=white,
                pixels_including_background=int(region.shape[0] * region.shape[1]), hdr_channel_peak=float(region.max()),
                visible_body_white_ratio=0.0 if white == 0 else None,
                scope="zero white pixels in this containing rectangle proves none on the visible actor; nonzero is not an enemy-only ratio")


def verify(folder: Path, require_owners: bool = False, require_contact: bool = False) -> dict:
    images: dict[tuple, np.ndarray] = {}
    cells = measurements = control_failures = 0
    results = []
    owners_complete = True
    physical_support_complete = True
    for index in sorted(folder.glob("*/*-index.json")):
        data = json.loads(index.read_bytes())
        for shot in data["shots"]:
            probe = shot["bg55"]
            records = probe["records"]
            assert records and records[0]["label"] == "A0"
            cells += 1
            first = records[0]
            valid = True
            for record in records:
                owners = record["held"].get("lighting_owners")
                owners_complete = owners_complete and owners is not None
                if require_owners:
                    assert owners is not None, "capture predates complete held-owner synchronization"
                if owners is not None:
                    assert owners["valid"]
                    active = [light for light in owners["scene_lights"] if light.get("budget_visible", light["visible"]) and light["enabled"]]
                    # Old v2 snapshots only retained effective tree visibility.
                    # A parent's hidden state can make that lower than the
                    # owner's count of selected light.visible flags.
                    if all("budget_visible" in light for light in owners["scene_lights"]):
                        assert len(active) == owners["active_lights"]
                    else:
                        assert len(active) <= owners["active_lights"]
                    assert sum(light["shadow"] for light in active) == owners["active_shadow_lights"]
                    source_transform = np.array(transform_values(record.get("canvas_transform_values", record["canvas_transform"])))
                    for wall in owners["wall_shadows"]:
                        assert wall["camera_synchronized"]
                        if wall["enabled"] and not wall["suspended"]:
                            actual_transform = np.array(transform_values(wall.get("caster_transform_values", wall["caster_transform"])))
                            if "viewport_final_transform" in owners:
                                final = transform_values(owners.get("viewport_final_transform_values", owners["viewport_final_transform"]))
                                def affine(v):
                                    return np.array([[v[0], v[2], v[4]], [v[1], v[3], v[5]], [0, 0, 1]])
                                expected = np.diag([0.5, 0.5, 1]) @ affine(final) @ affine(source_transform)
                                assert np.max(np.abs(affine(actual_transform) - expected)) <= 0.0001
                            else:
                                assert record["width"] == 1280 and record["height"] == 720 and record["density"] == 2
                                assert np.max(np.abs(actual_transform - source_transform * record["density"] * 0.5)) <= 0.0001
                bodies = owners.get("physics_bodies") if owners is not None else None
                support = record["held"].get("player_support")
                complete = bodies is not None and support is not None
                physical_support_complete = physical_support_complete and complete
                if require_contact:
                    assert complete, "capture predates preservation of physics bodies / true support contact"
                    assert bodies and all(body["space_valid"] and body["disable_mode"] == 2 for body in bodies)
                    if record["player_visible"]:
                        assert support["found"] and support["solver_contact"] and support["valid"]
                        gap = support["floor"][1] - support["feet"][1]
                        assert abs(gap - support["gap"]) <= 0.000001 and abs(gap) <= support["safe_margin"] + 0.001
                        assert support["normal"][1] < -0.99 and support["solver_normal"][1] < -0.99
                        shadow = record["player_contact_shadow"]
                        assert shadow["cast"] and shadow["visible"]
                        assert abs(shadow["bounds"][1] - (support["floor"][1] - 2)) <= 0.001
                    for enemy in record["enemies"]:
                        if enemy["uses_gravity"]:
                            floor = enemy["ground_support"]
                            assert floor["found"] and abs(floor["gap"]) <= floor["safe_margin"] + 0.001, (enemy["id"], floor)
                if not probe["diagnostic_only"]:
                    assert record["world_environment"]["active"] and record["world_environment"]["glow_enabled"], "formal capture lacks Main HDR bloom"
                    if record["player_visible"]:
                        assert record["weapon_light"]["origin_error"] <= 0.0001 and record["weapon_light"]["fade_level"] >= 0.999
                key = (index.parent, record["raw_sha256"])
                if key not in images:
                    raw = (index.parent / record["files"]["raw"]).read_bytes()
                    assert hashlib.sha256(raw).hexdigest() == record["raw_sha256"], record["files"]
                    dtype, channels = FORMATS[record["format"]]
                    pixels = np.frombuffer(raw, dtype=dtype).reshape(int(record["height"]), int(record["width"]), channels).astype(np.float64)
                    assert np.isfinite(pixels).all()
                    shown = np.asarray(Image.open(index.parent / record["files"]["png"]).convert("RGB"), dtype=np.float64) / 255
                    rgb = pixels[..., :3]
                    expected = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1 / 2.4) - 0.055)
                    assert np.max(np.abs(shown - np.clip(expected, 0, 1))) <= 1 / 255 + 0.00001, record["files"]
                    images[key] = rgb
                rgb = images[key]
                valid = valid and record["held"] == first["held"]
                if record["label"] == "A1" or record["label"].startswith("restore-"):
                    valid = valid and record["raw_sha256"] == first["raw_sha256"]
                for enemy in record["enemies"]:
                    body = mapped_rect(enemy["feet"], record.get("canvas_transform_values", record["canvas_transform"]), record["density"], 0, record["width"], record["height"])
                    outer = mapped_rect(enemy["feet"], record.get("canvas_transform_values", record["canvas_transform"]), record["density"], 20, record["width"], record["height"])
                    assert body == enemy["screen_rect"] and outer == enemy["outer_screen_rect"], (index, enemy["id"], "geometry")
                    expected_parts = parts_from_pixels(rgb, body, outer)
                    for name, value in expected_parts.items():
                        assert abs(value - enemy["parts"][name]) <= 0.000002, (index, enemy["id"], name, value, enemy["parts"][name])
                    contrast = max(expected_parts["bright"], expected_parts["dark"])
                    assert abs(contrast - enemy["contrast"]) <= 0.000002
                    assert enemy["passed"] == (contrast >= 0.45)
                    measurements += 1
            product = next((r for r in records if r["label"] == "product"), None)
            if product is not None:
                last = records[-1]
                valid = valid and last["raw_sha256"] == product["raw_sha256"] and last["held"] == product["held"]
            player_check = None
            last = records[-1]
            if last["player_visible"]:
                rgb = images[(index.parent, last["raw_sha256"])]
                px, py = shot["player_world"]
                body = mapped_world_box([px - 9, py - 58, 18, 54], last)
                outer = mapped_world_box([px - 29, py - 78, 58, 94], last)
                parts = parts_from_pixels(rgb, body, outer)
                contrast = max(parts["bright"], parts["dark"])
                luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
                def mean(box):
                    x, y, w, h = mapped_world_box(box, last)
                    return float(luma[y:y + h, x:x + w].mean())
                below = mean([px - 24, py + 8, 48, 6])
                edge = (mean([px - 24, py, 48, 3]) - below) / (below + 0.02)
                assert abs(contrast - shot["player_contrast"]) <= 0.000002
                assert abs(edge - shot["edge_contrast"]) <= 0.000002
                player_check = dict(contrast=contrast, edge=edge, passed=contrast >= 0.6 and edge >= 1.0)
            assert probe["controls_valid"] == valid, (index, "control verdict")
            control_failures += not valid
            results.append(dict(level=data["level"], column=shot["column"], row=shot["row"], controls_valid=valid,
                                player_from_raw=player_check,
                                observations=[dict(label=r["label"], player_visible=r["player_visible"],
                                                   enemies=[dict(id=e["id"], feet=e["feet"], contrast=e["contrast"], passed=e["passed"],
                                                                 exposure=exposure_bound(images[(index.parent, r["raw_sha256"])], e, r))
                                                            for e in r["enemies"]]) for r in records]))
    assert cells > 0, "No BG55 controlled cell was checked"
    return dict(cells=cells, unique_native_images=len(images), enemy_measurements=measurements,
                control_failures=control_failures, camera_dependent_owners_complete=owners_complete,
                physical_support_complete=physical_support_complete, results=results)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--require-owners", action="store_true")
    parser.add_argument("--require-contact", action="store_true")
    args = parser.parse_args()
    report = verify(args.folder, args.require_owners, args.require_contact)
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        args.out.write_bytes(text.encode())
    print(json.dumps({key: value for key, value in report.items() if key != "results"}))
    raise SystemExit(1 if report["control_failures"] else 0)
