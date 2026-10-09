#!/usr/bin/env python3
"""Read-only alpha audit for character source and accepted runtime PNGs."""
from __future__ import annotations

import csv
import hashlib
import json
from collections import Counter
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "project.godot").is_file() and (candidate / "art").is_dir():
            return candidate
    raise RuntimeError(f"Could not find project.godot above {start}")


ROOT = find_repo_root(Path(__file__).resolve())
OUT = ROOT / ".godot/ne90-alpha-roster-audit"
ATTACHMENT = ROOT / "pm/Nest-Egg/images/NE-90-user-alpha-failure.png"
THRESHOLDS = (0, 1, 4, 20, 127, 254)
REVIEW_LIMIT = 30


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def working_snapshot() -> dict:
    status = __import__("subprocess").run(["git", "status", "--porcelain=v1", "-uall"], cwd=ROOT,
                                         capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    diff = __import__("subprocess").run(["git", "diff", "--binary", "HEAD"], cwd=ROOT,
                                       capture_output=True).stdout
    return {
        "head": __import__("subprocess").run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                                             text=True, encoding="utf-8").stdout.strip(),
        "status_lines": status,
        "status_line_count": len(status),
        "tracked_diff_sha256": hashlib.sha256(diff).hexdigest(),
        "tracked_diff_bytes": len(diff),
    }


def alpha_metrics(rgba: np.ndarray) -> dict:
    if rgba.ndim != 3 or rgba.shape[2] != 4:
        raise ValueError(f"expected RGBA array, got shape {rgba.shape}")
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    total = int(alpha.size)
    counts_le = {str(t): int(np.count_nonzero(alpha <= t)) for t in THRESHOLDS}
    bins = {
        "alpha_0": int(np.count_nonzero(alpha == 0)),
        "alpha_1": int(np.count_nonzero(alpha == 1)),
        "alpha_2_4": int(np.count_nonzero((alpha >= 2) & (alpha <= 4))),
        "alpha_5_20": int(np.count_nonzero((alpha >= 5) & (alpha <= 20))),
        "alpha_21_127": int(np.count_nonzero((alpha >= 21) & (alpha <= 127))),
        "alpha_128_254": int(np.count_nonzero((alpha >= 128) & (alpha <= 254))),
        "alpha_255": int(np.count_nonzero(alpha == 255)),
    }
    alpha_pos = alpha > 0
    alpha_low = (alpha > 0) & (alpha <= 20)
    alpha_partial = (alpha > 0) & (alpha < 255)
    chroma = rgb.max(axis=2).astype(np.int16) - rgb.min(axis=2).astype(np.int16)
    # These are descriptive channel-spread buckets, not pass/fail cutoffs.
    low_chroma = {
        "alpha_1_4_chroma_ge_64": int(np.count_nonzero((alpha >= 1) & (alpha <= 4) & (chroma >= 64))),
        "alpha_1_20_chroma_ge_64": int(np.count_nonzero(alpha_low & (chroma >= 64))),
        "alpha_1_20_bright_color_ge_220": int(np.count_nonzero(alpha_low & (rgb.max(axis=2) >= 220))),
    }
    near_white = rgb.min(axis=2) >= 220
    blue_fringe = (rgb[:, :, 2].astype(np.int16) >= rgb[:, :, 0].astype(np.int16) + 40) & (rgb[:, :, 2].astype(np.int16) >= rgb[:, :, 1].astype(np.int16) + 20)
    partial_color_descriptive = {
        "partial_alpha_near_white_rgb_ge_220": int(np.count_nonzero(alpha_partial & near_white)),
        "partial_alpha_blue_dominant": int(np.count_nonzero(alpha_partial & blue_fringe)),
        "alpha_21_254_near_white_rgb_ge_220": int(np.count_nonzero((alpha >= 21) & (alpha <= 254) & near_white)),
        "alpha_21_254_blue_dominant": int(np.count_nonzero((alpha >= 21) & (alpha <= 254) & blue_fringe)),
        "alpha_128_254_near_white_rgb_ge_220": int(np.count_nonzero((alpha >= 128) & (alpha <= 254) & near_white)),
        "alpha_128_254_blue_dominant": int(np.count_nonzero((alpha >= 128) & (alpha <= 254) & blue_fringe)),
    }
    # alpha=0 RGB is deliberately excluded: it is invisible and may be
    # arbitrary (including magenta); only nonzero-alpha pixels are counted.
    low_colors = Counter(map(tuple, rgb[alpha_low].reshape(-1, 3).tolist()))
    low_color_top = [{"rgb": list(color), "count": int(count)} for color, count in low_colors.most_common(8)]

    binary = (alpha > 127).astype(np.uint8)
    component_count, labels, stats, _centroids = cv2.connectedComponentsWithStats(binary, 8)
    sizes = sorted((int(v) for v in stats[1:, cv2.CC_STAT_AREA]), reverse=True)
    largest_label = int(np.argmax(stats[1:, cv2.CC_STAT_AREA]) + 1) if sizes else 0
    largest_stat = stats[largest_label] if largest_label else None
    nonprimary_sizes = sizes[1:] if sizes else []
    component_rows = []
    for label in range(1, component_count):
        row = stats[label]
        component_rows.append({"label": int(label), "area": int(row[cv2.CC_STAT_AREA]),
                               "bbox_xyxy": [int(row[cv2.CC_STAT_LEFT]), int(row[cv2.CC_STAT_TOP]),
                                             int(row[cv2.CC_STAT_LEFT] + row[cv2.CC_STAT_WIDTH]),
                                             int(row[cv2.CC_STAT_TOP] + row[cv2.CC_STAT_HEIGHT])]})
    component_rows.sort(key=lambda row: row["area"], reverse=True)
    edge = np.zeros_like(binary, dtype=bool)
    edge[0, :] = True
    edge[-1, :] = True
    edge[:, 0] = True
    edge[:, -1] = True
    edge_visible = edge & (alpha > 0)
    largest_component = (labels == largest_label).astype(np.uint8) if largest_label else np.zeros_like(binary)
    distance = cv2.distanceTransform((1 - largest_component).astype(np.uint8), cv2.DIST_L2, 3)
    fringe = (largest_component == 0) & (distance > 0) & (distance <= 4.0) & (alpha > 0)
    fringe_bins = {
        "edge_band_1_4px_alpha_1_4": int(np.count_nonzero(fringe & (alpha <= 4))),
        "edge_band_1_4px_alpha_5_20": int(np.count_nonzero(fringe & (alpha >= 5) & (alpha <= 20))),
        "edge_band_1_4px_alpha_21_127": int(np.count_nonzero(fringe & (alpha >= 21) & (alpha <= 127))),
        "edge_band_1_4px_alpha_128_254": int(np.count_nonzero(fringe & (alpha >= 128) & (alpha <= 254))),
        "edge_band_1_4px_near_white": int(np.count_nonzero(fringe & near_white)),
        "edge_band_1_4px_blue_dominant": int(np.count_nonzero(fringe & blue_fringe)),
        "edge_band_1_4px_rgb_chroma_ge_64": int(np.count_nonzero(fringe & (chroma >= 64))),
    }
    corner_size = min(32, rgba.shape[0] // 2, rgba.shape[1] // 2)
    corners = [alpha[:corner_size, :corner_size], alpha[:corner_size, -corner_size:],
               alpha[-corner_size:, :corner_size], alpha[-corner_size:, -corner_size:]]
    corner_counts = [int(np.count_nonzero(c > 0)) for c in corners]
    return {
        "size": [int(rgba.shape[1]), int(rgba.shape[0])],
        "pixels": total,
        "alpha_le_counts": counts_le,
        "alpha_bins": bins,
        "alpha_0_fraction": bins["alpha_0"] / total if total else 0.0,
        "low_alpha_chroma_descriptive": low_chroma,
        "partial_alpha_color_descriptive": partial_color_descriptive,
        "subject_edge_band_1_4px_descriptive": fringe_bins,
        "low_alpha_nonzero_rgb_top8": low_color_top,
        "alpha_gt_127_component_count_including_background": int(component_count),
        "alpha_gt_127_component_sizes_top10": sizes[:10],
        "alpha_gt_127_components_top10_area_and_bbox": component_rows[:10],
        "alpha_gt_127_nonprimary_components_top10_area_and_bbox": [row for row in component_rows if row["label"] != largest_label][:10],
        "alpha_gt_127_largest_component_bbox_xyxy": ([int(largest_stat[cv2.CC_STAT_LEFT]), int(largest_stat[cv2.CC_STAT_TOP]),
                                                         int(largest_stat[cv2.CC_STAT_LEFT] + largest_stat[cv2.CC_STAT_WIDTH]),
                                                         int(largest_stat[cv2.CC_STAT_TOP] + largest_stat[cv2.CC_STAT_HEIGHT])] if largest_stat is not None else None),
        "alpha_gt_127_nonprimary_component_count": len(nonprimary_sizes),
        "alpha_gt_127_nonprimary_pixels": int(sum(nonprimary_sizes)),
        "alpha_gt_127_largest_nonprimary_component": int(max(nonprimary_sizes, default=0)),
        "visible_pixels_on_outermost_canvas_border": int(edge_visible.sum()),
        "corner_32x32_visible_pixel_counts_tl_tr_bl_br": corner_counts,
        "alpha_bbox_xyxy": list(Image.fromarray(alpha).getbbox()) if np.any(alpha) else None,
    }


def self_test() -> dict:
    opaque = np.zeros((8, 8, 4), dtype=np.uint8)
    opaque[:, :, :3] = (220, 5, 230)
    opaque[:, :, 3] = 255
    m_opaque = alpha_metrics(opaque)
    assert m_opaque["alpha_bins"]["alpha_0"] == 0
    assert m_opaque["alpha_0_fraction"] == 0.0

    magenta_transparent = np.zeros((8, 8, 4), dtype=np.uint8)
    magenta_transparent[:, :, :3] = (255, 0, 255)
    m_magenta = alpha_metrics(magenta_transparent)
    assert m_magenta["alpha_bins"]["alpha_0"] == 64
    assert m_magenta["low_alpha_nonzero_rgb_top8"] == []

    alpha2 = np.zeros((8, 8, 4), dtype=np.uint8)
    alpha2[:, :, :3] = (255, 0, 255)
    alpha2[3, 3, 3] = 2
    m_alpha2 = alpha_metrics(alpha2)
    assert m_alpha2["alpha_bins"]["alpha_2_4"] == 1
    assert m_alpha2["low_alpha_chroma_descriptive"]["alpha_1_4_chroma_ge_64"] == 1
    assert m_alpha2["low_alpha_nonzero_rgb_top8"] == [{"rgb": [255, 0, 255], "count": 1}]
    return {"opaque_rgba_is_not_transparent": True,
            "alpha_zero_magenta_is_not_counted_as_visible_rgb_noise": True,
            "alpha_two_colored_pixel_is_detected_as_low_alpha_chroma": True}


def creature_models() -> tuple[list[dict], dict[Path, list[str]], dict]:
    configs: list[dict] = []
    texture_users: dict[Path, list[str]] = {}
    missing: list[dict] = []
    for config_path in sorted((ROOT / "art/creatures").glob("*.json")):
        data = json.loads(config_path.read_text(encoding="utf-8"))
        if "parts" in data:
            model_type = "part_creature_sprite_parts"
        elif "head" in data and "segment" in data:
            model_type = "worm_creature_sprite_geometry"
        elif "body" in data and "tentacle" in data:
            model_type = "chain_creature_sprite_mesh_geometry"
        else:
            model_type = "unknown_or_test_creature_config"
        base_dir = data.get("dir", f"res://art/creatures/{config_path.stem}/")
        if isinstance(base_dir, str) and base_dir.startswith("res://"):
            base_dir = ROOT / base_dir.removeprefix("res://")
        else:
            base_dir = (ROOT / str(base_dir)).resolve()
        refs: set[Path] = set()

        def visit(node):
            if isinstance(node, dict):
                for key, value in node.items():
                    if isinstance(value, str) and value.lower().endswith(".png"):
                        if value.startswith("res://"):
                            refs.add(ROOT / value.removeprefix("res://"))
                        elif key == "file":
                            refs.add(Path(base_dir) / value)
                        elif value.startswith("art/"):
                            refs.add(ROOT / value)
                    visit(value)
            elif isinstance(node, list):
                for value in node:
                    visit(value)

        visit(data)
        resolved_refs = sorted((p.resolve() for p in refs), key=lambda p: str(p).casefold())
        existing = []
        absent = []
        normal_companions = []
        for ref in resolved_refs:
            if ref.is_file():
                existing.append(ref)
                texture_users.setdefault(ref, []).append(config_path.stem)
                normal_path = ref.with_name(ref.stem + "_n.png")
                if normal_path.is_file():
                    normal_companions.append(normal_path.resolve())
                    texture_users.setdefault(normal_path.resolve(), []).append(config_path.stem + " (companion normal)")
            else:
                absent.append(ref)
                missing.append({"model": config_path.relative_to(ROOT).as_posix(), "missing_texture": display_path(ref)})
        configs.append({
            "model": config_path.relative_to(ROOT).as_posix(),
            "model_sha256": digest(config_path),
            "id": config_path.stem,
            "model_type": model_type,
            "runtime_png_reference_count": len(existing),
            "runtime_png_references": [display_path(p) for p in existing],
            "normal_companion_count": len(normal_companions),
            "normal_companions": [display_path(p) for p in normal_companions],
            "missing_png_references": [display_path(p) for p in absent],
            "zero_png_is_not_a_pass": len(existing) == 0,
        })

    enemies = []
    for data_path in sorted((ROOT / "data/enemies").glob("*.tres")):
        text = data_path.read_text(encoding="utf-8")
        def capture(field: str) -> str:
            import re
            match = re.search(rf"^{field}\s*=\s*\"([^\"]*)\"", text, flags=re.MULTILINE)
            return match.group(1) if match else ""
        enemy_id = capture("id") or data_path.stem
        rig_skin = capture("rig_skin")
        creature_skin = capture("creature_skin")
        enemies.append({
            "enemy_data": data_path.relative_to(ROOT).as_posix(),
            "enemy_data_sha256": digest(data_path),
            "enemy_id": enemy_id,
            "rig_skin": rig_skin,
            "creature_skin": creature_skin,
            "appearance_source": ("creature_config_pngs" if creature_skin else ("humanoid_rig_character_pngs" if rig_skin else "procedural_vector_draw_no_character_png")),
            "note": "watchdog intentionally borrows warden rig/character textures" if enemy_id == "watchdog" and rig_skin == "warden" else "",
        })
    return configs, texture_users, {"missing_creature_pngs": missing, "enemy_bindings": enemies}


def inventory(creature_texture_users: dict[Path, list[str]]) -> tuple[list[tuple[Path, str]], list[str]]:
    found: dict[Path, str] = {}
    missing: list[str] = []
    recipes_dir = ROOT / "tools/comfyui/recipes"
    for recipe_path in sorted(recipes_dir.glob("*.json")):
        recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
        work = ROOT / recipe["work"]
        if not work.is_dir():
            missing.append(f"{recipe_path.relative_to(ROOT).as_posix()}: recipe work directory missing: {recipe['work']}")
        # Classify process inputs by their actual directory, not by filename guesses.
        for path, status in [
            (work / "base_rgba.png", "recipe_source_base"),
            (work / "04_stages", "intermediate_stage_generated"),
            (work / "05_groups", "segmentation_groups_not_final"),
            (work / "07_refined", "refined_source_not_runtime_accepted"),
            (work / "overrides/refined", "active_refined_override_if_consumed"),
        ]:
            if path.is_file() and path.suffix.lower() == ".png":
                found[path] = status
            elif path.is_dir():
                for png in sorted(path.rglob("*.png")):
                    found[png] = status
            elif path.name == "base_rgba.png":
                missing.append(f"{recipe_path.relative_to(ROOT).as_posix()}: missing recipe source {path.relative_to(ROOT).as_posix()}")
        generated = work / "_gen"
        if generated.is_dir():
            for png in sorted(generated.rglob("*.png")):
                found[png] = "unaccepted_generated_candidate"
    for folder in sorted((ROOT / "art/characters").glob("*")):
        parts = folder / "parts"
        if parts.is_dir():
            for png in sorted(parts.glob("*.png")):
                if png.stem.endswith("_n"):
                    found[png] = "runtime_character_normal_map"
                elif png.stem.endswith("_glow"):
                    found[png] = "runtime_character_glow"
                else:
                    found[png] = "runtime_character_part"
    for png in sorted((ROOT / "art/portraits").glob("*.png")):
        found[png] = "runtime_portrait"
    creatures = ROOT / "art/creatures"
    for png in sorted(creatures.rglob("*.png")):
        users = creature_texture_users.get(png.resolve(), [])
        is_test = png.parent == creatures and png.stem.startswith("test_")
        if png.stem.endswith("_n"):
            found[png] = "runtime_creature_normal_map_referenced" if users else "runtime_creature_normal_map_unreferenced"
        elif is_test:
            found[png] = "test_fixture_creature_png"
        else:
            found[png] = "runtime_creature_texture_referenced" if users else "runtime_creature_texture_unreferenced"
    creature_sources = ROOT / "art_src/creatures"
    if creature_sources.is_dir():
        for png in sorted(creature_sources.rglob("*.png")):
            found[png] = "unaccepted_generated_candidate" if "_gen" in png.relative_to(creature_sources).parts else "creature_source_not_runtime_accepted"
    if ATTACHMENT.is_file():
        found[ATTACHMENT] = "user_attachment_screenshot_not_source_asset"
    else:
        missing.append(f"repo attachment not present yet: {ATTACHMENT.relative_to(ROOT).as_posix()}")
    return sorted(found.items(), key=lambda item: str(item[0]).casefold()), missing


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return f"<external>/{path.name}"


def composite_sheet(path: Path, out_path: Path, metrics: dict) -> dict:
    with Image.open(path) as im:
        rgba = im.convert("RGBA")
    alpha = np.asarray(rgba.getchannel("A"))
    # Use the main >127 component for the subject crop so alpha=1 magenta
    # noise across the background cannot expand the edge preview to the canvas.
    main_box = metrics.get("alpha_gt_127_largest_component_bbox_xyxy")
    if not main_box:
        box = (0, 0, rgba.width, rgba.height)
    else:
        pad = 16
        box = (max(0, main_box[0] - pad), max(0, main_box[1] - pad),
               min(rgba.width, main_box[2] + pad), min(rgba.height, main_box[3] + pad))
    crop = rgba.crop(box)
    colors = [(0, 0, 0), (255, 255, 255), (0, 160, 160)]
    labels = ["source RGBA native crop", "alpha over black", "alpha over white", "alpha over teal"]
    strip_h = 24
    sheet = Image.new("RGB", (crop.width * 4, crop.height + strip_h), (35, 35, 35))
    draw = ImageDraw.Draw(sheet)
    raw_rgb = crop.convert("RGB")
    sheet.paste(raw_rgb, (0, strip_h))
    for i, color in enumerate(colors, start=1):
        bg = Image.new("RGBA", crop.size, (*color, 255))
        sheet.paste(Image.alpha_composite(bg, crop).convert("RGB"), (i * crop.width, strip_h))
    for i, label in enumerate(labels):
        draw.text((i * crop.width + 4, 5), label, fill=(255, 255, 255))
    sheet.save(out_path)
    # Four 64x64 native corner crops, each shown over the same backgrounds.
    corner_boxes = [(0, 0, min(64, rgba.width), min(64, rgba.height)),
                    (max(0, rgba.width - 64), 0, rgba.width, min(64, rgba.height)),
                    (0, max(0, rgba.height - 64), min(64, rgba.width), rgba.height),
                    (max(0, rgba.width - 64), max(0, rgba.height - 64), rgba.width, rgba.height)]
    corner_w = min(64, rgba.width)
    corner_h = min(64, rgba.height)
    corner_sheet = Image.new("RGB", (corner_w * 16, corner_h + strip_h), (35, 35, 35))
    corner_draw = ImageDraw.Draw(corner_sheet)
    idx = 0
    for corner_name, corner_box in zip(("top-left", "top-right", "bottom-left", "bottom-right"), corner_boxes):
        corner = rgba.crop(corner_box)
        corner_draw.text((idx * corner_w + 2, 5), f"{corner_name} raw", fill=(255, 255, 255))
        corner_sheet.paste(corner.convert("RGB"), (idx * corner_w, strip_h))
        idx += 1
        for bg_name, color in zip(("black", "white", "teal"), colors):
            corner_bg = Image.new("RGBA", corner.size, (*color, 255))
            corner_sheet.paste(Image.alpha_composite(corner_bg, corner).convert("RGB"), (idx * corner_w, strip_h))
            corner_draw.text((idx * corner_w + 2, 5), f"{corner_name} {bg_name}", fill=(255, 255, 255))
            idx += 1
    corner_path = out_path.with_name(out_path.stem + "__corners.png")
    corner_sheet.save(corner_path)
    return {"main_component_bbox_xyxy_native": main_box, "edge_crop_xyxy_native": list(box),
            "edge_sheet_size_no_resizing": list(sheet.size), "edge_labels": labels,
            "corner_crop_boxes_xyxy_native": [list(b) for b in corner_boxes],
            "corner_sheet": display_path(corner_path), "corner_sheet_size_no_resizing": list(corner_sheet.size)}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tests = self_test()
    working_before = working_snapshot()
    creature_config_rows, creature_texture_users, creature_reference_data = creature_models()
    model_paths = sorted([ROOT / row["model"] for row in creature_config_rows] +
                         [ROOT / row["enemy_data"] for row in creature_reference_data["enemy_bindings"]],
                         key=lambda p: str(p).casefold())
    model_hashes_before = {display_path(path): digest(path) for path in model_paths}
    entries = []
    before = {}
    file_inventory, missing_inputs = inventory(creature_texture_users)
    for path, status in file_inventory:
        try:
            raw_hash = digest(path)
            rel_path = display_path(path)
            before[rel_path] = raw_hash
            with Image.open(path) as im:
                mode = im.mode
                bands = list(im.getbands())
                rgba = np.asarray(im.convert("RGBA"))
            metrics = alpha_metrics(rgba)
            entry = {"path": rel_path,
                            "classification": status, "file_sha256_before": raw_hash,
                            "file_size_bytes": path.stat().st_size, "png_mode": mode,
                            "channels": bands, "has_alpha_channel_in_file": "A" in bands,
                            "alpha_has_transparency": metrics["alpha_bins"]["alpha_0"] > 0,
                            "alpha_has_partial_values": metrics["alpha_bins"]["alpha_1"] > 0 or any(
                                metrics["alpha_bins"][k] > 0 for k in ("alpha_2_4", "alpha_5_20", "alpha_21_127", "alpha_128_254")),
                            **metrics}
            if path.resolve() in creature_texture_users:
                entry["referenced_by_creature_configs"] = sorted(set(creature_texture_users[path.resolve()]))
            entries.append(entry)
        except Exception as exc:
            entries.append({"path": display_path(path),
                            "classification": status, "error": f"{type(exc).__name__}: {exc}"})

    # Descriptive triage rank: partial-alpha chroma, alpha 1..4 count, then
    # outer-canvas visible pixels. It does not define a correctness threshold.
    def score(entry: dict) -> tuple:
        if "error" in entry:
            return (-1, -1, -1)
        low = entry["low_alpha_chroma_descriptive"]
        edge = entry["subject_edge_band_1_4px_descriptive"]
        return (edge["edge_band_1_4px_rgb_chroma_ge_64"], low["alpha_1_20_chroma_ge_64"],
                entry["visible_pixels_on_outermost_canvas_border"])

    scored = [e for e in entries if e.get("has_alpha_channel_in_file") and "error" not in e]
    source_classes = {"recipe_source_base", "intermediate_stage_generated", "segmentation_groups_not_final",
                      "refined_source_not_runtime_accepted", "active_refined_override_if_consumed",
                      "unaccepted_generated_candidate", "creature_source_not_runtime_accepted"}
    runtime_classes = {"runtime_character_part", "runtime_portrait", "runtime_creature_texture_referenced",
                       "runtime_creature_texture_unreferenced", "test_fixture_creature_png"}
    source_priority = sorted((e for e in scored if e["classification"] in source_classes), key=score, reverse=True)
    runtime_priority = sorted((e for e in scored if e["classification"] in runtime_classes), key=score, reverse=True)
    priority = source_priority + runtime_priority
    review = OUT / "review"
    review.mkdir(exist_ok=True)
    # Include the user's screenshot and the reported Slasher P stage even if
    # their descriptive ranking would otherwise omit them; then add top source
    # and accepted-runtime samples for side-by-side human review.
    mandatory_paths = {display_path(ATTACHMENT), "art_src/characters/slasher/04_stages/P.png"}
    selected = [e for e in scored if e["path"] in mandatory_paths]
    selected.extend(source_priority[:14])
    selected.extend(runtime_priority[:14])
    unique_selected = []
    seen_paths = set()
    for entry in selected:
        if entry["path"] not in seen_paths:
            unique_selected.append(entry)
            seen_paths.add(entry["path"])
    reviewed = []
    for entry in unique_selected[:REVIEW_LIMIT]:
        src = ROOT / entry["path"]
        source_tag = hashlib.sha256(entry["path"].encode("utf-8")).hexdigest()[:8]
        safe_name = (entry["classification"] + "__" + src.stem + "__" + source_tag).replace(" ", "_")
        sheet = review / f"{safe_name}.png"
        entry["review_sheet"] = display_path(sheet)
        entry["review_crop"] = composite_sheet(src, sheet, entry)
        reviewed.append(entry["path"])

    after = {key: digest(ROOT / key) for key in before}
    changed = [key for key in before if before[key] != after[key]]
    if changed:
        raise SystemExit(f"FAIL: scanned input hash changed during read-only audit: {changed[:10]}")
    model_hashes_after = {display_path(path): digest(path) for path in model_paths}
    changed_models = [path for path in model_hashes_before if model_hashes_before[path] != model_hashes_after[path]]
    if changed_models:
        raise SystemExit(f"FAIL: scanned model/config hash changed during read-only audit: {changed_models[:10]}")
    working_after = working_snapshot()

    aggregate = Counter(e.get("classification", "unknown") for e in entries)
    mode_counts = Counter(e.get("png_mode", "ERROR") for e in entries)
    alpha_summary = {}
    for key in ("alpha_0", "alpha_1", "alpha_2_4", "alpha_5_20", "alpha_21_127", "alpha_128_254", "alpha_255"):
        alpha_summary[key] = sum(e.get("alpha_bins", {}).get(key, 0) for e in entries)
    result = {
        "repo": ".", "head": working_before["head"],
        "working_tree_snapshot": {"before": working_before, "after": working_after,
                                  "same_status_and_tracked_diff": working_before == working_after,
                                  "interpretation": "PNG and model/config hashes below are computed from current working-tree bytes; HEAD only anchors the diff snapshot."},
        "audit_scope": ["recipe actual work base_rgba", "recipe 04_stages PNGs", "recipe 05_groups PNGs", "recipe 07_refined PNGs", "recipe overrides/refined PNGs", "recipe work _gen PNGs (explicitly unaccepted candidates)", "art/characters/*/parts PNGs split into color/normal/glow", "art/portraits PNGs", "art/creatures/**/*.png with config references", "art_src/creatures/**/*.png with _gen explicitly unaccepted", "art/creatures/*.json referenced PNG mapping", "data/enemies/*.tres skin mapping including procedural-only and borrowed skins", "repo PM attachment if present"],
        "missing_expected_inputs": missing_inputs,
        "read_only_hashes_unchanged": True, "scanned_png_count": len(entries), "classification_counts": dict(aggregate),
        "png_mode_counts": dict(mode_counts), "pixel_totals_by_alpha_bin_across_files_not_deduplicated": alpha_summary,
        "self_tests": tests, "reviewed_composite_paths": reviewed,
        "creature_models": creature_config_rows,
        "creature_model_zero_png_configs": [row["model"] for row in creature_config_rows if row["runtime_png_reference_count"] == 0],
        "missing_creature_png_references": creature_reference_data["missing_creature_pngs"],
        "enemy_appearance_bindings": creature_reference_data["enemy_bindings"],
        "enemy_no_explicit_rig_or_creature_skin_not_passes": [row["enemy_id"] for row in creature_reference_data["enemy_bindings"] if not row["rig_skin"] and not row["creature_skin"]],
        "model_config_hashes_before": model_hashes_before,
        "model_config_hashes_after": model_hashes_after,
        "model_config_hashes_unchanged": not changed_models,
        "priority_order_is_descriptive_only": "sorted by RGB chroma spread>=64 within a 1..4 native-pixel band outside largest alpha>127 component, then alpha 1..20 chroma spread, then outer-border visibility; no pass/fail thresholds",
        "source_priority_paths": [e["path"] for e in source_priority[:20]],
        "runtime_priority_paths": [e["path"] for e in runtime_priority[:20]],
        "errors": [e for e in entries if "error" in e],
        "files": entries,
        "source_hashes_before": before,
        "source_hashes_after": after,
    }
    (OUT / "working-tree-snapshot.json").write_text(
        json.dumps(result["working_tree_snapshot"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "alpha-audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    fields = ["path", "classification", "png_mode", "has_alpha_channel_in_file", "alpha_has_transparency", "size", "pixels",
              "alpha_le_0", "alpha_le_1", "alpha_le_4", "alpha_le_20", "alpha_le_127", "alpha_le_254",
              "alpha_0_fraction", "alpha_0", "alpha_1", "alpha_2_4", "alpha_5_20", "alpha_21_127", "alpha_128_254", "alpha_255",
              "alpha_1_4_chroma_ge_64", "alpha_1_20_chroma_ge_64", "alpha_1_20_bright_color_ge_220",
              "partial_alpha_near_white_rgb_ge_220", "partial_alpha_blue_dominant", "alpha_21_254_near_white_rgb_ge_220", "alpha_21_254_blue_dominant",
              "edge_band_1_4px_alpha_1_4", "edge_band_1_4px_alpha_5_20", "edge_band_1_4px_alpha_21_127", "edge_band_1_4px_alpha_128_254",
              "edge_band_1_4px_near_white", "edge_band_1_4px_blue_dominant", "edge_band_1_4px_rgb_chroma_ge_64",
              "alpha_gt_127_component_count_including_background", "alpha_gt_127_nonprimary_component_count",
              "alpha_gt_127_nonprimary_pixels", "visible_pixels_on_outermost_canvas_border", "corner_32x32_visible_pixel_counts_tl_tr_bl_br",
              "file_sha256_before", "review_sheet"]
    with (OUT / "alpha-audit.csv").open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for e in entries:
            row = dict(e)
            row.update(row.get("alpha_bins", {}))
            row.update({f"alpha_le_{threshold}": value for threshold, value in row.get("alpha_le_counts", {}).items()})
            row.update(row.get("low_alpha_chroma_descriptive", {}))
            row.update(row.get("partial_alpha_color_descriptive", {}))
            row.update(row.get("subject_edge_band_1_4px_descriptive", {}))
            writer.writerow(row)

    # Resolve recurring accepted-runtime findings separately from raw stages.
    runtime_classes = {"runtime_character_part", "runtime_portrait", "runtime_creature_texture_referenced",
                       "runtime_creature_texture_unreferenced", "runtime_creature_normal_map_referenced",
                       "runtime_creature_normal_map_unreferenced", "runtime_character_normal_map",
                       "runtime_character_glow", "test_fixture_creature_png"}
    runtime = [e for e in entries if e.get("classification") in runtime_classes]
    creature_runtime = [e for e in entries if e.get("classification", "").startswith("runtime_creature_") or e.get("classification") == "test_fixture_creature_png"]
    source = [e for e in entries if e.get("classification") in ("recipe_source_base", "intermediate_stage_generated", "segmentation_groups_not_final", "refined_source_not_runtime_accepted", "active_refined_override_if_consumed", "unaccepted_generated_candidate", "creature_source_not_runtime_accepted")]
    report = [
        "# 角色透明背景與 alpha 盤點",
        "",
        f"- Repo HEAD: `{result['head']}`",
        f"- Working-tree snapshot: {working_before['status_line_count']} status entries; tracked diff SHA-256 `{working_before['tracked_diff_sha256']}` ({working_before['tracked_diff_bytes']} bytes); scan start/end status+diff identical={working_before == working_after}. Asset metrics use current file bytes, including uncommitted PNGs; source hashes are listed in JSON.",
        f"- 只讀盤點：{len(entries)} 張 PNG；掃描前後檔案 SHA-256 完全一致。",
        f"- 類別數量：`{json.dumps(dict(aggregate), ensure_ascii=False)}`",
        f"- 原檔 PNG mode：`{json.dumps(dict(mode_counts), ensure_ascii=False)}`。RGBA/RGB mode 僅描述通道格式，另以 alpha0 與 partial bins 判斷實際透明。",
        "- 每檔 alpha ≤0/1/4/20/127/254 的像素計數在 CSV `alpha_le_*` 欄位及 JSON `alpha_le_counts`；alpha 精確 bins 另列，避免只看到「RGBA」就認定透明背景。",
        "- 全部檔案像素 alpha bin 合計（因檔案可能含多個版本，不去重）：`" + json.dumps(alpha_summary, ensure_ascii=False) + "`。",
        "- alpha=0 像素的 RGB 完全不計入可見色邊；1–4、5–20、21–127、128–254 分別列出，低 alpha 色彩只作描述性優先級，不代表全部都是瑕疵。",
        "- `alpha>127` 的連通元件數與非最大元件只作結構指標；四角與最外圈可見 alpha 數值提供給人工判斷，不自動當作失敗。",
        "- 自檢：" + json.dumps(tests, ensure_ascii=False),
        "",
        "## 優先人工檢視清單",
        "",
        "下列來源與正式 runtime 分開排序，描述性排序不是驗收門檻：最大 alpha>127 主體外 1–4 原生像素帶內 RGB channel spread ≥64 的像素數，再看 alpha 1–20 色彩、最外圈可見像素數。normal map 與 glow map 已分類另列，不拿法線色值當 RGB 色邊。先檢查附件與 Slasher stage P，再對照 runtime 部件；此表不能替代角色原生渲染驗收。",
    ]
    for group_title, group in (("來源/中間圖", source_priority), ("正式 runtime 色彩貼圖/肖像", runtime_priority)):
        report += ["", f"### {group_title}", ""]
        for e in group[:20]:
            edge = e["subject_edge_band_1_4px_descriptive"]
            report.append(f"- `{e['classification']}` `{e['path']}` — {e['png_mode']} {e['size']}; alpha0={e['alpha_bins']['alpha_0']}, α1={e['alpha_bins']['alpha_1']}, α2–4={e['alpha_bins']['alpha_2_4']}, α5–20={e['alpha_bins']['alpha_5_20']}; α1–20 chroma≥64={e['low_alpha_chroma_descriptive']['alpha_1_20_chroma_ge_64']}, partial near-white={e['partial_alpha_color_descriptive']['partial_alpha_near_white_rgb_ge_220']}, partial blue-dominant={e['partial_alpha_color_descriptive']['partial_alpha_blue_dominant']}; 1–4px subject-edge near-white={edge['edge_band_1_4px_near_white']}, blue={edge['edge_band_1_4px_blue_dominant']}, chroma≥64={edge['edge_band_1_4px_rgb_chroma_ge_64']}; canvas-edge visible={e['visible_pixels_on_outermost_canvas_border']}; review=`{e.get('review_sheet','not in top 30')}`")
    attachment_entry = next((e for e in entries if e.get("classification") == "user_attachment_screenshot_not_source_asset"), None)
    if attachment_entry:
        stage_p = next((e for e in entries if e.get("path") == "art_src/characters/slasher/04_stages/P.png"), None)
        stage_grey = next((e for e in entries if e.get("path") == "art_src/characters/slasher/04_stages/P_grey.png"), None)
        report += ["", "## 使用者附件 (獨立於 repository source)", "",
                   f"- `{attachment_entry['path']}`: {attachment_entry['png_mode']} {attachment_entry['size']}, SHA-256 `{attachment_entry['file_sha256_before']}`; alpha bins `{json.dumps(attachment_entry['alpha_bins'], ensure_ascii=False)}`; α1–20 top RGB `{json.dumps(attachment_entry['low_alpha_nonzero_rgb_top8'], ensure_ascii=False)}`; subject-edge band counts `{json.dumps(attachment_entry['subject_edge_band_1_4px_descriptive'], ensure_ascii=False)}`; review=`{attachment_entry.get('review_sheet','not selected')}`。此附件是 RGBA 截圖，不等於遊戲執行證據。",
                   f"- 直接來源比對限制：附件是 {attachment_entry['size']}；repo `04_stages/P.png` 是 {stage_p['size'] if stage_p else 'missing'}（RGBA），`P_grey.png` 是 {stage_grey['size'] if stage_grey else 'missing'}（{stage_grey['png_mode'] if stage_grey else 'missing'}）。附件尺寸不同且不是目前 P/P_grey 的原檔 copy；視覺色調較接近 maroon 的 P_grey，但不能只憑相似外觀宣稱來源。"]
    report += ["", "## 正式 runtime PNG 概況", ""]
    for e in sorted(runtime, key=lambda r: r["path"]):
        report.append(f"- `{e['path']}` — {e['png_mode']} {e['size']}; alpha0={e['alpha_bins']['alpha_0']} ({e['alpha_0_fraction']:.3%}), alpha1={e['alpha_bins']['alpha_1']}, alpha2–4={e['alpha_bins']['alpha_2_4']}, alpha5–20={e['alpha_bins']['alpha_5_20']}, alpha>127 nonprimary components={e['alpha_gt_127_nonprimary_component_count']}.")
    report += ["", "## 非人形 creature model 與貼圖來源", "",
               f"- 掃描 `art/creatures/*.json` 設定 {len(creature_config_rows)} 個；引用 0 張 PNG 的設定數={len(result['creature_model_zero_png_configs'])}，不可當作通過；缺失引用數={len(creature_reference_data['missing_creature_pngs'])}。引用清單與每個模型類型在 JSON `creature_models`。",
               "- Creature 設定摘要：" + "; ".join(f"`{row['id']}` ({row['model_type']}, PNG={row['runtime_png_reference_count']}, normal={row['normal_companion_count']})" for row in creature_config_rows) + ".",
               "- 零 PNG Creature 設定：" + (", ".join(f"`{name}`" for name in result["creature_model_zero_png_configs"]) if result["creature_model_zero_png_configs"] else "無（0 個；這只表示設定引用到現存 PNG，不等同視覺通過）") + ".",
               f"- art/creatures runtime/test/normal 圖共 {len(creature_runtime)} 張；art_src/creatures source與`_gen`候選已分開分類。Creature JSON 直接 PNG 引用解析自設定檔字串，normal companion 依實際 `_n.png` 同名檔檢查。",
               "- EnemyData 沒有明確 `rig_skin`/`creature_skin`、會走 Enemy 程式繪製路徑的項目：" + (", ".join(f"`{name}`" for name in result["enemy_no_explicit_rig_or_creature_skin_not_passes"]) if result["enemy_no_explicit_rig_or_creature_skin_not_passes"] else "無（0/34；JSON 仍保存完整 34 筆綁定）") + ".",
               "- EnemyData 外觀綁定：" + "; ".join(f"`{row['enemy_id']}` (rig=`{row['rig_skin'] or '—'}`, creature=`{row['creature_skin'] or '—'}`)" for row in creature_reference_data["enemy_bindings"]) + ".",
               "- 看門狗 `watchdog` 明確使用 `rig_skin=warden`，即借用 Warden 骨架角色貼圖。",
               "",
               "## 原始/中間分件來源注意事項", "",
               "Recipe 的 base/stage/group/refined/override 與 `_gen` 都按來源階段分類；`04_stages` 和 `_gen` 圖即使目前帶 alpha，也不自動代表已接受。`_gen` 標為未接受候選；`05_groups`/`07_refined` 是分件輸入，不等同最終 runtime part。請以 `alpha-audit.csv` / JSON 的來源路徑和 SHA 回到實際 workflow/人工確認。",
               "",
               "預期輸入缺漏：" + (json.dumps(missing_inputs, ensure_ascii=False) if missing_inputs else "無。"),
               "", "## 合成裁切與限制", "",
               f"前 {min(REVIEW_LIMIT, len(unique_selected))} 個帶 alpha 的候選輸出原尺寸、未縮放裁切：原始 RGBA、alpha over black/white/teal 四欄。裁切框是 native pixel bbox 並加 16px 邊界，另有 64x64 原始四角合成板，所有檔名均在 repo-relative `review/`。零 alpha 區域即使 RGB 是洋紅也不可見，不能用該 RGB 本身作為問題證據。",
               "",
               "本報告是 CPU 圖像資料檢查，不宣稱人眼驗收、遊戲截圖通過或所有角色透明度缺陷已修復；沒有修改正式檔案，也未執行 Godot/GPU/ComfyUI。"]
    (OUT / "alpha-audit-summary.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"scanned={len(entries)} runtime={len(runtime)} source/intermediate={len(source)} errors={len(result['errors'])} review={len(reviewed)}")
    print("json=.godot/ne90-alpha-roster-audit/alpha-audit.json\ncsv=.godot/ne90-alpha-roster-audit/alpha-audit.csv\nsummary=.godot/ne90-alpha-roster-audit/alpha-audit-summary.md")
    return 0 if not result["errors"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
