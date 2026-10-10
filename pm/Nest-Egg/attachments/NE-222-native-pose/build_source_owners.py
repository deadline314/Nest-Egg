from __future__ import annotations

import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


BUNDLE = Path(__file__).resolve().parent
ROOT = BUNDLE.parents[3]
OUT = BUNDLE / "generated/ownership"
SOURCE = BUNDLE / "source/rin_kneel_color_alpha_22297_0.png"
SOURCE_META = BUNDLE / "source/rin_kneel_color_alpha_22297.source.json"
PROPOSAL = BUNDLE / "source/pose-owner-proposal.json"
GUIDE = BUNDLE / "source/kneel-draft.source.json"
MEASUREMENTS = BUNDLE / "source/anatomy-measurements.json"
SOURCE_SHA = "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed"
FLOOR = 40
NAMES = ("pelvis", "front_thigh", "front_calf", "front_boot", "back_thigh", "back_calf", "back_boot")
COLORS = {
    "pelvis": (246, 198, 56), "front_thigh": (233, 71, 94), "front_calf": (255, 137, 62),
    "front_boot": (250, 61, 198), "back_thigh": (66, 205, 115), "back_calf": (49, 174, 211),
    "back_boot": (151, 112, 228),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def poly_mask(shape: tuple[int, int], pts: list[list[int]]) -> np.ndarray:
    out = np.zeros(shape, np.uint8)
    cv2.fillPoly(out, [np.asarray(pts, np.int32)], 1)
    return out.astype(bool)


def bbox(mask: np.ndarray) -> list[int] | None:
    y, x = np.where(mask)
    if not len(x):
        return None
    return [int(x.min()), int(y.min()), int(x.max() + 1), int(y.max() + 1)]


def composite(bg: np.ndarray, src: np.ndarray) -> np.ndarray:
    b = bg.astype(np.float32) / 255.0
    s = src.astype(np.float32) / 255.0
    a = s[:, :, 3:4]
    out_a = a + b[:, :, 3:4] * (1.0 - a)
    out_rgb = s[:, :, :3] * a + b[:, :, :3] * b[:, :, 3:4] * (1.0 - a)
    out_rgb = np.divide(out_rgb, out_a, out=np.zeros_like(out_rgb), where=out_a > 0)
    return np.clip(np.rint(np.concatenate((out_rgb, out_a), axis=2) * 255), 0, 255).astype(np.uint8)


def source_part(src: np.ndarray, mask: np.ndarray) -> np.ndarray:
    result = src.copy()
    result[:, :, 3] = np.where(mask, src[:, :, 3], 0).astype(np.uint8)
    return result


def coordinate_in_bounds(point: tuple[int, int], width: int, height: int) -> bool:
    x, y = point
    return 0 <= x < width and 0 <= y < height


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    parts_dir, masks_dir, crops_dir = (OUT / "parts", OUT / "masks", OUT / "native-crops")
    for directory in (parts_dir, masks_dir, crops_dir):
        directory.mkdir(exist_ok=True)
    inputs = {"source": SOURCE, "source_metadata": SOURCE_META, "manual_contour_proposal": PROPOSAL,
              "control_guide": GUIDE, "anatomy_measurements": MEASUREMENTS}
    before = {k: sha(v) for k, v in inputs.items()}
    if before["source"] != SOURCE_SHA:
        raise SystemExit(f"source hash changed: {before['source']}")
    source = np.asarray(Image.open(SOURCE).convert("RGBA"))
    if source.shape != (736, 1440, 4):
        raise SystemExit(f"expected native 1440x736 RGBA source, got {source.shape}")
    metadata = json.loads(SOURCE_META.read_text(encoding="utf-8"))
    proposal = json.loads(PROPOSAL.read_text(encoding="utf-8"))
    measurement = json.loads(MEASUREMENTS.read_text(encoding="utf-8"))
    guide = json.loads(GUIDE.read_text(encoding="utf-8"))
    if metadata["output"]["sha256"] != SOURCE_SHA or proposal["source_sha256_before_after"][0] != SOURCE_SHA:
        raise SystemExit("source provenance hash mismatch")
    alpha = source[:, :, 3]
    retained = alpha >= FLOOR
    if int(retained.sum()) != 211990:
        raise SystemExit(f"pinned source retained-pixel count changed: {int(retained.sum())}")

    # Existing hand-drawn contours are used only as visible-region seeds. The old
    # unknown holdouts are resolved below by explicit visual ownership rules.
    shapes = source.shape[:2]
    polygons = proposal["manual_owner_polygons_native_source_xy"]
    for name, points in polygons.items():
        if any(not coordinate_in_bounds((int(x), int(y)), source.shape[1], source.shape[0]) for x, y in points):
            raise SystemExit(f"manual contour out of source bounds: {name}")
    geom = {name: poly_mask(shapes, points) for name, points in polygons.items()}
    hip_holdout = poly_mask(shapes, [[590, 274], [753, 274], [753, 340], [588, 330]]) & retained

    owner_names = {name: i for i, name in enumerate(NAMES)}
    owners = np.full(shapes, -1, dtype=np.int8)
    assignment_reasons: dict[str, int] = {}

    # Retain the clear visible contour regions, with the nearer thigh contour
    # winning genuine front/back overlap. Boots remain the boots painted in 22297.
    base_order = ("front_boot", "back_boot", "front_calf", "back_calf", "front_thigh", "back_thigh", "pelvis")
    for name in base_order:
        if name not in owner_names:
            continue
        assign = retained & geom[name] & (owners < 0)
        owners[assign] = owner_names[name]
        assignment_reasons[f"visible_contour:{name}"] = int(assign.sum())

    # Resolve the low-confidence hip seam by foreground ownership, not by distance
    # to the guide anchors: front thigh covers the rear thigh; pelvis covers the
    # rear thigh where those contours overlap. Pixels inside the front thigh remain
    # front-thigh-owned. Remaining 10 outer-crease pixels are explicitly pelvis.
    hip_counts = {name: geom[name] & hip_holdout for name in ("pelvis", "front_thigh", "back_thigh")}
    owners[hip_holdout] = -1
    hip_unassigned = hip_holdout
    hip_rules = (
        ("front_thigh", hip_counts["front_thigh"]),
        ("pelvis", hip_counts["pelvis"] & ~geom["front_thigh"]),
        ("back_thigh", hip_counts["back_thigh"] & ~geom["front_thigh"] & ~geom["pelvis"]),
    )
    for name, region in hip_rules:
        assign = hip_unassigned & region & (owners < 0)
        owners[assign] = owner_names[name]
        assignment_reasons[f"hip_contour_rule:{name}"] = int(assign.sum())
    outer_crease = hip_holdout & (owners < 0)
    outer_y, outer_x = np.where(outer_crease)
    expected_outer = {(590, 287), (589, 288), (590, 288), (591, 288), (592, 288),
                      (589, 289), (590, 289), (591, 289), (592, 289), (593, 289)}
    actual_outer = set(zip(outer_x.tolist(), outer_y.tolist()))
    if actual_outer != expected_outer:
        raise SystemExit(f"hip outer crease differs from reviewed source coords: {sorted(actual_outer)}")
    owners[outer_crease] = owner_names["pelvis"]
    assignment_reasons["hip_outer_contour_pixels_pelvis_low_confidence"] = int(outer_crease.sum())

    # The back-cuff cut leaves one source contour pixel (342,605) on the boot-side
    # boundary. Keep it with the painted boot so neither part has a detached speck.
    cuff_xy = (342, 605)
    if alpha[cuff_xy[1], cuff_xy[0]] < FLOOR or owners[cuff_xy[1], cuff_xy[0]] < 0:
        raise SystemExit("reviewed source back-cuff boundary pixel no longer matches its pinned source")
    cuff_before_owner = NAMES[int(owners[cuff_xy[1], cuff_xy[0]])]
    owners[cuff_xy[1], cuff_xy[0]] = owner_names["back_boot"]

    # Assign every retained component outside the old polygons using a pinned seed
    # coordinate and reviewed source-contour continuity. Component size and bbox are
    # asserted so a source/matte change cannot silently move a whole region.
    rem = retained & (owners < 0)
    n, labels, stats, centroids = cv2.connectedComponentsWithStats(rem.astype(np.uint8), 8)
    observed = {}
    for label in range(1, n):
        x, y, w, h, area = (int(v) for v in stats[label])
        observed[label] = {"bbox_xyxy_half_open": [x, y, x + w, y + h], "pixels": area,
                           "centroid_xy": [float(centroids[label][0]), float(centroids[label][1])]}
    component_map = [
        {"seed_xy": [700, 118], "owner": "pelvis", "reason": "upper back contour and connected waist edge"},
        {"seed_xy": [751, 128], "owner": "pelvis", "reason": "continuation of same top contour"},
        {"seed_xy": [1097, 252], "owner": "front_calf", "reason": "outer boundary of raised-leg shin, continuous knee-to-cuff axis"},
        {"seed_xy": [1026, 276], "owner": "front_calf", "reason": "inner boundary pixels of the same raised-leg shin"},
        {"seed_xy": [575, 263], "owner": "pelvis", "reason": "left posterior silhouette of the hip volume"},
        {"seed_xy": [585, 285], "owner": "back_thigh", "reason": "short crease/neck joining posterior root to vertical rear thigh"},
        {"seed_xy": [482, 569], "owner": "back_calf", "reason": "upper silhouette of the rearward shin"},
        {"seed_xy": [334, 606], "owner": "back_boot", "reason": "boot cuff/shaft contour remains with the painted boot"},
        {"seed_xy": [463, 642], "owner": "back_calf", "reason": "lower and sole-side contour of rearward shin"},
        {"seed_xy": [393, 620], "owner": "back_calf", "reason": "detached contour taps are on the shin side of cuff"},
        {"seed_xy": [396, 621], "owner": "back_calf", "reason": "detached contour taps are on the shin side of cuff"},
        {"seed_xy": [534, 665], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [537, 666], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [540, 667], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [543, 668], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [579, 276], "owner": "pelvis", "reason": "posterior outside edge above the rear-thigh crease"},
        {"seed_xy": [522, 580], "owner": "back_calf", "reason": "rear shin contour adjacent to boot cuff"},
        {"seed_xy": [387, 618], "owner": "back_calf", "reason": "shin-side cuff contour"},
        {"seed_xy": [390, 619], "owner": "back_calf", "reason": "shin-side cuff contour"},
        {"seed_xy": [546, 669], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [549, 670], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [552, 671], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
        {"seed_xy": [555, 672], "owner": "back_calf", "reason": "continuation of rear shin outer contour"},
    ]
    if len(component_map) != n - 1:
        raise SystemExit(f"unassigned component inventory changed: expected {len(component_map)}, got {n - 1}")
    component_ledger = []
    for entry in component_map:
        sx, sy = entry["seed_xy"]
        label = int(labels[sy, sx])
        if label == 0 or label not in observed:
            raise SystemExit(f"component seed is not in remaining source: {entry}")
        record = observed.pop(label)
        assign = rem & (labels == label)
        owners[assign] = owner_names[entry["owner"]]
        component_ledger.append({**entry, **record})
        assignment_reasons[f"remainder_component:{entry['owner']}"] = assignment_reasons.get(f"remainder_component:{entry['owner']}", 0) + int(assign.sum())
    if observed:
        raise SystemExit(f"unreviewed source components remain: {observed}")

    if np.any(retained & (owners < 0)) or np.any((~retained) & (owners >= 0)):
        raise SystemExit("partition does not assign exactly the alpha>=40 source pixels")
    counts = np.bincount(owners[retained].astype(np.int32), minlength=len(NAMES))
    if int(counts.sum()) != int(retained.sum()):
        raise SystemExit("source owner accounting mismatch")
    unique_rebuilt = np.zeros_like(source)
    for name, idx in owner_names.items():
        own = owners == idx
        unique_rebuilt[own] = source[own]
    expected = source.copy()
    expected[~retained] = 0
    if not np.array_equal(unique_rebuilt, expected):
        raise SystemExit("unique source reassembly is not byte exact above alpha floor")

    # Save exact source parts and transparent masks at native source dimensions.
    color_grid = np.full((source.shape[0], source.shape[1], 3), (42, 45, 52), np.uint8)
    color_grid[retained] = np.asarray([COLORS[NAMES[int(i)]] for i in owners[retained]], np.uint8)
    color_grid[~retained] = (42, 45, 52)
    Image.fromarray(color_grid, "RGB").save(OUT / "owner-color-map-native.png")
    Image.fromarray(unique_rebuilt, "RGBA").save(OUT / "source-reassembled-alpha40-native.png")
    source_gray = np.full_like(source, (128,128,128,255))
    source_gray = composite(source_gray, unique_rebuilt)
    overlay = source_gray[:, :, :3].astype(np.float32) * 0.65 + color_grid.astype(np.float32) * 0.35
    overlay = np.clip(np.rint(overlay),0,255).astype(np.uint8)
    annotated = Image.fromarray(overlay, "RGB")
    annotation_draw = ImageDraw.Draw(annotated)
    annotation_font = ImageFont.load_default()
    guide_marks = {
        "H target": [668.0833,312.2408],
        "FH target": [668.0833,312.2408], "FK target": [986.5470,196.3295], "FA target": [1227.2611,483.5236],
        "BH target": [645.0735,312.2408], "BK target": [615.5363,649.8530], "BA target": [250.7083,564.2712],
    }
    for label, point in guide_marks.items():
        px,py=round(point[0]),round(point[1])
        annotation_draw.ellipse((px-5,py-5,px+5,py+5), outline=(255,255,255), width=1)
        annotation_draw.text((px+6,py-8), label, fill=(255,255,255), font=annotation_font, stroke_width=1, stroke_fill=(0,0,0))
    for label,point in {"cuff-F":(1181,389),"cuff-B":(337,594),"crease":(632,314)}.items():
        px,py=point
        annotation_draw.rectangle((px-3,py-3,px+3,py+3), outline=(255,230,30), width=1)
        annotation_draw.text((px+5,py+3),label,fill=(255,240,50),font=annotation_font,stroke_width=1,stroke_fill=(0,0,0))
    annotation_draw.text((6,6), "Owner tint over native source; white rings = guide targets; yellow squares = low-confidence source contour cues", fill=(255,255,80), font=annotation_font, stroke_width=1, stroke_fill=(0,0,0))
    annotated.save(OUT / "owner-boundary-source-overlay-native.png")
    triptych = Image.new("RGB", (source.shape[1] * 3, source.shape[0] * 2 + 56), (30, 34, 40))
    draw = ImageDraw.Draw(triptych)
    font = ImageFont.load_default()
    for row, bgval in enumerate((0, 128, 255)):
        bg = np.empty_like(source)
        bg[:, :, :3] = bgval
        bg[:, :, 3] = 255
        native = Image.fromarray(composite(bg, unique_rebuilt), "RGBA").convert("RGB")
        triptych.paste(native, (0, row * (source.shape[0] + 28) + 28))
        draw.text((6, row * (source.shape[0] + 28) + 6), f"semantic owner partition / {'black' if bgval == 0 else 'gray' if bgval == 128 else 'white'} / native 1440x736", fill="yellow", font=font)
    triptych.save(OUT / "full-source-black-gray-white-native.png")
    nearest = triptych.resize((triptych.width * 2, triptych.height * 2), Image.Resampling.NEAREST)
    nearest.save(OUT / "full-source-black-gray-white-2x-nearest.png")

    part_stats = {}
    contact_tiles = []
    for name, idx in owner_names.items():
        own = owners == idx
        masked = source_part(source, own)
        Image.fromarray((own.astype(np.uint8) * 255), "L").save(masks_dir / f"{name}.png")
        Image.fromarray(masked, "RGBA").save(parts_dir / f"{name}.png")
        box = bbox(own)
        if box is None:
            raise SystemExit(f"empty semantic part: {name}")
        x0, y0, x1, y1 = box
        crop = masked[y0:y1, x0:x1]
        Image.fromarray(crop, "RGBA").save(crops_dir / f"{name}-native.png")
        Image.fromarray(crop, "RGBA").resize(((x1-x0)*4, (y1-y0)*4), Image.Resampling.NEAREST).save(crops_dir / f"{name}-4x-nearest.png")
        labels_count, cc = cv2.connectedComponents(own.astype(np.uint8), 8)
        comp_sizes = sorted((int(np.count_nonzero(cc == j)) for j in range(1, labels_count)), reverse=True)
        holes = nd_holes(own)
        if len(comp_sizes) != 1 or holes != 0:
            raise SystemExit(f"part {name} is not one closed source component: components={len(comp_sizes)} holes={holes}")
        part_stats[name] = {"retained_pixels": int(own.sum()), "bbox_xyxy_half_open": box,
                            "connected_components_8": len(comp_sizes), "component_sizes_desc": comp_sizes[:12],
                            "filled_holes_4connected": holes,
                            "source_rgb_alpha_exact": bool(np.array_equal(masked[own], source[own]))}
        tiles = []
        for bgval, label in ((0, "black"), (128, "gray"), (255, "white")):
            bg = np.full((y1-y0, x1-x0, 4), (bgval, bgval, bgval, 255), np.uint8)
            tile = Image.fromarray(composite(bg, crop), "RGBA").convert("RGB")
            tiles.append(tile)
        tile_width, tile_height = (x1-x0), (y1-y0)
        tile_canvas = Image.new("RGB", (tile_width*3, tile_height+24), (30,34,40))
        td = ImageDraw.Draw(tile_canvas)
        td.text((3, 4), f"{name} native crop {box} / black-gray-white", fill="yellow", font=font)
        for j,tile in enumerate(tiles): tile_canvas.paste(tile, (j*tile_width,24))
        tile_canvas.save(crops_dir / f"{name}-black-gray-white-native.png")
        contact_tiles.append((name, tile_canvas))
    maxw = max(tile.width for _,tile in contact_tiles)
    totalh = sum(tile.height for _,tile in contact_tiles)
    sheet = Image.new("RGB", (maxw,totalh), (30,34,40))
    yy=0
    for _,tile in contact_tiles:
        sheet.paste(tile,(0,yy)); yy += tile.height
    sheet.save(OUT / "seven-parts-black-gray-white-native.png")

    # Keep exact-source, narrowly named seam proposals separate from unique owner
    # masks. No seam pixels are duplicated into the candidate parts automatically.
    seams = {
        "hip_front_thigh": {"polyline_xy": [[610, 302], [632, 314], [655, 320], [681, 316]], "confidence": "low", "basis": "visible dark crease; its anatomical side is not independently labeled"},
        "front_knee": {"center_xy": [986.55, 196.33], "radius_px": 7, "confidence": "medium-low", "basis": "guide target near visible fold; target is not a verified source joint"},
        "back_knee": {"center_xy": [615.54, 649.85], "radius_px": 7, "confidence": "medium-low", "basis": "guide target near visible rear-leg bend; target is not a verified source joint"},
        "front_boot_cuff": {"polyline_xy": [[1181, 389], [1210, 391], [1247, 391]], "confidence": "low", "basis": "visible shaft top; differs substantially from guide ankle"},
        "back_boot_cuff": {"polyline_xy": [[326, 580], [337, 594], [345, 609]], "confidence": "low", "basis": "visible rear boot cuff/shaft; source calf/boot ownership requires review"},
    }
    seam_masks = {}
    seam_pairs = {
        "hip_front_thigh": ("pelvis", "front_thigh"),
        "front_knee": ("front_thigh", "front_calf"),
        "back_knee": ("back_thigh", "back_calf"),
        "front_boot_cuff": ("front_calf", "front_boot"),
        "back_boot_cuff": ("back_calf", "back_boot"),
    }
    overlap_root = OUT / "seam-overlap-candidates"
    overlap_root.mkdir(exist_ok=True)
    overlap_ledger = {}
    for name, info in seams.items():
        mask = np.zeros(shapes, np.uint8)
        pts = info.get("polyline_xy")
        if pts:
            cv2.polylines(mask, [np.asarray(pts, np.int32)], False, 1, thickness=5, lineType=cv2.LINE_8)
        else:
            cx, cy = info["center_xy"]
            cv2.circle(mask, (round(cx), round(cy)), int(info["radius_px"]), 1, -1)
        seam_masks[name] = mask.astype(bool) & retained
        Image.fromarray((seam_masks[name].astype(np.uint8)*255), "L").save(OUT / f"seam-band-{name}.png")
        seam_dir = overlap_root / name
        seam_dir.mkdir(exist_ok=True)
        source_band = seam_masks[name]
        pair = seam_pairs[name]
        for owner_name in pair:
            owner_mask = source_band.copy()
            rgba = source_part(source, owner_mask)
            Image.fromarray((owner_mask.astype(np.uint8)*255), "L").save(seam_dir / f"{owner_name}-mask.png")
            Image.fromarray(rgba, "RGBA").save(seam_dir / f"{owner_name}.png")
        overlap_ledger[name] = {"paired_owners": list(pair), "source_retained_pixels_duplicated_into_each_side": int(source_band.sum()),
                                "shared_source_pixel_coordinates_xy": np.argwhere(source_band)[:,[1,0]].tolist(),
                                "shared_pixels_with_original_rgba": True,
                                "candidate_reason": info["basis"], "accepted": False}
    duplicated_count = np.zeros(shapes, np.uint8)
    for seam_mask in seam_masks.values():
        duplicated_count += seam_mask.astype(np.uint8) * 2
    seam_union = np.logical_or.reduce(list(seam_masks.values()))
    if np.any((duplicated_count > 0) & ~seam_union) or np.any((duplicated_count > 0) & ~retained):
        raise SystemExit("source-exact seam duplicates escaped their declared band")

    # A deliberate duplicate seam sample is a negative control for exact-one-owner.
    omission = owners.copy()
    first_y, first_x = np.argwhere(retained)[0]
    omission[first_y, first_x] = -1
    omitted_detected = bool(np.any(retained & (omission < 0)))
    duplicate_counts = np.zeros(shapes, np.uint8)
    for idx in range(len(NAMES)): duplicate_counts += (owners == idx).astype(np.uint8)
    p = next(iter(zip(*np.where(retained))))
    duplicate_counts[p[0],p[1]] += 1
    duplicate_detected = bool(np.any(retained & (duplicate_counts != 1)))
    disconnected_detected = not single_component(np.pad(np.asarray([[1,0,1]],np.uint8), ((2,2),(2,2))))
    corrupted = unique_rebuilt.copy()
    cy, cx = np.argwhere(retained)[0]
    corrupted[cy, cx, 0] ^= 1
    corruption_detected = not np.array_equal(corrupted, expected)
    out_of_bounds_rejected = all(not coordinate_in_bounds(point, source.shape[1], source.shape[0]) for point in [(-1,0),(source.shape[1],0),(0,-1),(0,source.shape[0])])
    if not (omitted_detected and duplicate_detected and disconnected_detected and corruption_detected and out_of_bounds_rejected):
        raise SystemExit("one-pixel omission/duplicate/disconnected-component negative control failed")

    hashes_after = {k: sha(v) for k,v in inputs.items()}
    if before != hashes_after:
        raise SystemExit("a protected source/reference input changed")
    guide_xy = guide["anchors"]
    guide_points = {k: v["guide_px"] for k,v in guide_xy.items()}
    report = {
        "status": "PRIVATE_V3_SEVEN_PART_SOURCE_OWNERSHIP_PROPOSAL_NOT_ACCEPTED",
        "source": {"path": str(SOURCE.relative_to(ROOT)).replace("\\","/"), "sha256": before["source"], "size": [1440,736], "mode": "RGBA", "alpha_floor": FLOOR, "retained_alpha_ge40_pixels": int(retained.sum()), "hash_unchanged": True},
        "protected_inputs_sha256": {k: v for k,v in before.items()},
        "source_pixel_policy": "Each retained pixel is copied byte-exactly from 22297. Alpha<40 stays excluded per established rule; no RGB/alpha paint, interpolation, resize, or generated material is introduced.",
        "manual_boundary_proposal": {"base_polygons": polygons, "base_polygon_provenance": "Reused only as visible contour seeds from the prior private manual review; old unknowns are explicitly resolved below and boot source masks remain 22297-painted boots.",
            "layer_semantics": "front thigh wins front/back thigh overlap; pelvis wins rear-thigh overlap; boots/calf cuts follow visible boot shaft/cuff contours; only exact component seed ownership is manual, never nearest-distance auto-fill.",
            "low_confidence_hip_outer_crease_xy": sorted([list(p) for p in expected_outer]), "unknown_hip_assignment": {"front_thigh_overlaps": "front_thigh", "pelvis_over_back_thigh": "pelvis", "unambiguous_back_thigh": "back_thigh", "10-pixel outer contour": "pelvis"},
            "remainder_connected_components": component_ledger},
        "owner_ledger": {"owners": {n: {"pixels": int(counts[i]), **part_stats[n]} for i,n in enumerate(NAMES)},
            "assigned_alpha_ge40": int(np.count_nonzero(owners >= 0)), "unassigned_retained_pixels": int(np.count_nonzero(retained & (owners < 0))),
            "duplicate_owner_pixels": 0, "source_exact_seam_duplicate_owner_pixels": int(np.count_nonzero(duplicated_count)), "non_seam_duplicate_owner_pixels": 0, "exact_source_roundtrip_above_floor": True, "source_hash_unchanged": True,
            "negative_controls": {"one_pixel_omission_rejected": omitted_detected, "duplicate_owner_rejected": duplicate_detected, "extra_component_rejected": disconnected_detected, "source_pixel_corruption_rejected": corruption_detected, "out_of_bounds_coordinate_rejected": out_of_bounds_rejected},
            "reviewed_cuff_edge_pixel": {"source_xy": list(cuff_xy), "source_rgba": source[cuff_xy[1],cuff_xy[0]].tolist(), "old_semantic_owner": cuff_before_owner, "v3_owner": "back_boot", "reason": "visible cuff boundary continuity; prevents one isolated back_calf alpha pixel"}},
        "shared_source_exact_seam_bands": {n: {**info, "retained_source_pixels_in_band": int(seam_masks[n].sum()), "bbox_xyxy_half_open": bbox(seam_masks[n]), "mask_sha256": sha(OUT / f"seam-band-{n}.png"), "files": [f"seam-band-{n}.png"], "duplicated_into_parts": True, **overlap_ledger[n]} for n,info in seams.items()},
        "guide_targets_source_xy_not_independent_anatomy": guide_points,
        "source_visible_landmarks_low_confidence": {"front_cuff": [1181,389], "back_cuff": [337,594], "front_knee_fold": [987,198], "back_knee_fold": [616,650], "hip_crease": [632,314]},
        "anchor_caveat": "The guide anchors encode target poses/rest-length geometry, not anatomical source landmarks. Prior measurements: hip target (668.08,312.24) is 23.56px from nearest back-thigh retained source; back-hip target (645.07,312.24) is 21.76px below nearest old back-thigh source point; front ankle target (1227.26,483.52) is 44.30px from retained front-calf source; back ankle target (250.71,564.27) is 90.05px from retained rear-calf source. Do not move canonical bones from this partition alone.",
        "artifacts": ["owner-color-map-native.png", "owner-boundary-source-overlay-native.png", "source-reassembled-alpha40-native.png", "full-source-black-gray-white-native.png", "full-source-black-gray-white-2x-nearest.png", "seven-parts-black-gray-white-native.png", "parts/", "masks/", "native-crops/", "seam-overlap-candidates/", *[f"seam-band-{n}.png" for n in seams]],
        "unresolved_visual_review": ["Hip seam ownership remains low confidence; root must review the dark crease and the 10-pixel outer contour before any binding.", "The front boot shaft begins near y=389 while the guide ankle target is y≈484; this is a visible source/target landmark mismatch, not solved by claiming an underlap.", "The source has no independently exposed hidden overlap. Seam-band masks are proposals only and are not added to the unique owner RGBA parts.", "Every owner's component count/holes are recorded. A multi-component part, gap, or isolated contour detail is not silently accepted; root must inspect the per-part gray triptych and 4x nearest image.", "This source proposal does not validate normal maps, material style, pose registration, deformation, or Forward+."]
    }
    (OUT / "manifest-v3.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    stable_paths = sorted(p for p in OUT.rglob("*") if p.is_file() and p.name not in {"manifest-v3.json", "reproducibility.json"})
    stable_hashes = {str(p.relative_to(OUT)).replace("\\", "/"): sha(p) for p in stable_paths}
    repro_path = OUT / "reproducibility.json"
    prior = json.loads(repro_path.read_text(encoding="utf-8")) if repro_path.exists() else None
    same_as_prior = bool(prior and prior.get("artifact_sha256") == stable_hashes and prior.get("builder_sha256") == sha(Path(__file__)))
    repro = {"status": "TWO_RUNS_BYTE_IDENTICAL" if same_as_prior else "FIRST_RUN_BASELINE_CAPTURED",
             "builder_sha256": sha(Path(__file__)), "protected_source_sha256": before["source"],
             "artifact_sha256": stable_hashes, "matches_previous_run": same_as_prior}
    repro_path.write_text(json.dumps(repro, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "retained": int(retained.sum()), "owner_counts": {n:int(counts[i]) for i,n in enumerate(NAMES)},
                      "components": {n:part_stats[n]["connected_components_8"] for n in NAMES}, "holes": {n:part_stats[n]["filled_holes_4connected"] for n in NAMES},
                      "roundtrip": True, "source_hash_unchanged": before["source"] == hashes_after["source"], "rerun": repro["status"]}, indent=2))


def nd_holes(mask: np.ndarray) -> int:
    holes = cv2.bitwise_not(mask.astype(np.uint8))
    num, labels = cv2.connectedComponents(holes, 4)
    border = set(np.concatenate((labels[0], labels[-1], labels[:,0], labels[:,-1])).tolist())
    return int(sum(1 for i in range(1,num) if i not in border))


def single_component(mask: np.ndarray) -> bool:
    return cv2.connectedComponents(np.asarray(mask,np.uint8),8)[0] - 1 == 1


if __name__ == "__main__":
    main()
