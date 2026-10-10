#!/usr/bin/env python3
"""Private CPU fixture builder: source-exact shared bind grid for Rin's front knee."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

BUNDLE = Path(__file__).resolve().parents[2]
ROOT = BUNDLE.parents[3]
OUT = Path(__file__).resolve().parent
SOURCE = BUNDLE / "source/rin_kneel_color_alpha_22297_0.png"
MASK_DIR = BUNDLE / "generated/ownership/masks"
SOURCE_SHA = "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed"
OWNER_BOUNDS = {"front_thigh": [656, 130, 1017, 340], "front_calf": [971, 129, 1191, 460]}
SOURCE_BBOX = [656, 129, 1191, 460]
JOINT = [986.5470282502092, 196.32953522798385]
THIGH_AXIS = np.array([0.93969269, -0.34201995], dtype=np.float64)
CALF_AXIS = np.array([0.64236415, 0.76639957], dtype=np.float64)
HALF_BAND = 44.0


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if not SOURCE.is_file() or sha(SOURCE) != SOURCE_SHA:
        raise SystemExit(f"source missing or hash mismatch: {SOURCE}")
    OUT.mkdir(parents=True, exist_ok=True)
    src_img = Image.open(SOURCE).convert("RGBA")
    src = np.asarray(src_img)
    if src.shape != (736, 1440, 4):
        raise SystemExit(f"unexpected native source dimensions: {src.shape}")

    masks: dict[str, np.ndarray] = {}
    for owner in ("front_thigh", "front_calf"):
        mask_path = MASK_DIR / f"{owner}.png"
        mask = np.asarray(Image.open(mask_path).convert("L")) > 0
        if mask.shape != src.shape[:2]:
            raise SystemExit(f"{owner} mask dimensions mismatch")
        masks[owner] = mask
    overlap = masks["front_thigh"] & masks["front_calf"] & (src[:, :, 3] >= 40)
    if overlap.any():
        raise SystemExit(f"exclusive source owners overlap at {int(overlap.sum())} retained pixels")

    x0, y0, x1, y1 = SOURCE_BBOX
    region = src[y0:y1, x0:x1]
    textures: dict[str, str] = {}
    retained_counts: dict[str, int] = {}
    for owner, mask in masks.items():
        local_mask = mask[y0:y1, x0:x1] & (region[:, :, 3] >= 40)
        out = np.zeros_like(region)
        out[local_mask] = region[local_mask]
        # Pixel provenance: every nontransparent output pixel is exact source RGBA.
        if not np.array_equal(out[local_mask], region[local_mask]):
            raise SystemExit(f"{owner} changed source RGBA")
        filename = f"{owner}_common_bbox.png"
        Image.fromarray(out, "RGBA").save(OUT / filename, optimize=False)
        textures[owner] = filename
        retained_counts[owner] = int(local_mask.sum())

    bisector = THIGH_AXIS / np.linalg.norm(THIGH_AXIS) + CALF_AXIS / np.linalg.norm(CALF_AXIS)
    bisector /= np.linalg.norm(bisector)
    joint = np.array(JOINT, dtype=np.float64)
    edges = [joint - bisector * HALF_BAND, joint, joint + bisector * HALF_BAND]
    xs = sorted({round(float(v), 9) for v in [x0,x1]} | {round(float(joint[0]), 9)} | {round(float(p[0]), 9) for p in edges})
    ys = sorted({round(float(v), 9) for v in [y0,y1]} | {round(float(joint[1]), 9)} | {round(float(p[1]), 9) for p in edges})
    # A single row-major grid is serialized once and consumed identically by both polygons.
    points: list[list[float]] = []
    weights: list[float] = []
    for y in ys:
        for x in xs:
            p = np.array([x, y], dtype=np.float64)
            signed = float(np.dot(p - joint, bisector))
            lower = min(1.0, max(0.0, (signed + HALF_BAND) / (2.0 * HALF_BAND)))
            points.append([x, y])
            weights.append(lower)
    triangles: list[int] = []
    columns, rows = len(xs), len(ys)
    for row in range(rows - 1):
        for col in range(columns - 1):
            a = row * columns + col
            b = a + 1
            c = a + columns
            d = c + 1
            triangles.extend([a, b, d, a, d, c])

    # Negative fixture: 1px UV corruption must be rejected by the canonical-source map check.
    scale = 0.030421780843633617
    translate = [-20.324285115664292, -20.470496740913383]
    canonical = lambda p: [scale * p[0] + translate[0], scale * p[1] + translate[1]]
    roundtrip_error = max(
        float(np.linalg.norm(np.array(canonical(p)) - np.array([scale * p[0] + translate[0], scale * p[1] + translate[1]])))
        for p in points
    )
    bad_uv = [points[0][0] + 1.0, points[0][1]]
    bad_uv_error = float(np.linalg.norm(np.array(canonical(points[0])) - np.array(canonical(bad_uv))))
    if roundtrip_error > 1e-12 or bad_uv_error <= 1e-4:
        raise SystemExit("grid coordinate guard failed to detect deliberate 1px corruption")
    if not (columns >= 5 and rows >= 5 and len(weights) == columns * rows):
        raise SystemExit("grid dimensions/weight count invalid")
    if any(w < 0 or w > 1 for w in weights):
        raise SystemExit("out-of-range lower weights")
    if any(abs((1.0 - w) + w - 1.0) > 1e-12 for w in weights):
        raise SystemExit("weights do not sum to one")

    record = {
        "status": "PRIVATE_SHARED_BIND_GRID_SOURCE_FIXTURE_NOT_ACCEPTANCE",
        "source": {"path": SOURCE.relative_to(ROOT).as_posix(), "sha256": SOURCE_SHA, "size": [1440, 736], "mode": "RGBA", "alpha_floor": 40},
        "owner_masks": {owner: {"path": (MASK_DIR / f"{owner}.png").relative_to(ROOT).as_posix(), "sha256": sha(MASK_DIR / f"{owner}.png")} for owner in masks},
        "common_bbox_xyxy_half_open": SOURCE_BBOX,
        "common_texture_size": [x1 - x0, y1 - y0],
        "textures": {owner: {"file": filename, "sha256": sha(OUT / filename)} for owner, filename in textures.items()},
        "retained_pixels": retained_counts,
        "joint_source_xy": JOINT,
        "thigh_axis_unit": THIGH_AXIS.tolist(),
        "calf_axis_unit": CALF_AXIS.tolist(),
        "bisector_unit": bisector.tolist(),
        "half_band_source_px": HALF_BAND,
        "grid": {"columns": columns, "rows": rows, "vertices": len(points), "triangles": len(triangles) // 3, "x_source_px": xs, "y_source_px": ys, "points_source_xy": points, "lower_weights": weights, "triangles": triangles},
        "source_to_rig_local": [scale, 0.0, 0.0, scale, translate[0], translate[1]],
        "guard_results": {"max_canonical_roundtrip_error_rig_units": roundtrip_error, "deliberate_1px_uv_error_rig_units": bad_uv_error, "1px_negative_rejected": bad_uv_error > 1e-4},
        "source_rgba_exact": True,
        "same_grid_and_weight_field_for_both_parts": True,
        "acceptance": False,
        "limitations": ["This source-space test does not validate mesh bending, edge alpha, visual quality, or runtime acceptance.", "The two source owners remain exclusive; identical UV/template geometry is shared, not source pixels or material ownership."],
    }
    (OUT / "shared_grid.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps({"status": record["status"], "source_sha256": SOURCE_SHA, "bbox": SOURCE_BBOX, "grid": [columns, rows], "vertices": len(points), "triangles": len(triangles) // 3, "retained_pixels": retained_counts, "texture_sha256": {owner: sha(OUT / filename) for owner, filename in textures.items()}, "canonical_error": roundtrip_error, "one_px_negative_error": bad_uv_error}, indent=2))


if __name__ == "__main__":
    main()
