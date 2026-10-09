"""CPU-only isolated replay and semantic checks for the reviewed slasher hand/boot rebuild."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


HERE = Path(__file__).resolve().parent
ROOT = next((parent for parent in (HERE, *HERE.parents) if (parent / "project.godot").is_file()), None)
if ROOT is None:
    raise RuntimeError(f"Could not locate project.godot from {HERE}")
PRIVATE = ROOT / ".godot/ne90-slasher-final-repro"
PYTHON = Path(sys.executable)
REBUILD = ROOT / "art_src/characters/slasher/near_hand_repair/rebuild.py"
CUT = ROOT / "tools/comfyui/cut_layers.py"
SPEC = ROOT / "tools/comfyui/specs/slasher_side.json"
SOURCE_WORK = ROOT / "art_src/characters/slasher"
FORMAL_CHAR = ROOT / "art/characters/slasher"
FORMAL_RIG = ROOT / "art/rigs/slasher.json"
REFINED = SOURCE_WORK / "07_refined"
SOURCE = SOURCE_WORK / "base_rgba.png"
EXPECTED_SOURCE_SHA = "ba9af5139d225d492019c24c261bcd1ba9387d1bca7d10e7fd0fa3f5f1931bf3"
MASKS = {
    "hand": ("near_hand", "mask-source.json", "32462c3a380bc3ff7a7c43891e248a7a61d9f3441bacdae0fb610c66411762c2"),
    "foot": ("near_foot", "foot-mask-source.json", "f72640cc2736ce50335a8c719e4362e3bac6e0eecd9513c30e12e5e6ef709a85"),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def hash_matches(data: bytes, expected: str) -> bool:
    return hashlib.sha256(data).hexdigest() == expected


def validate_rebuilt_rgba(actual: np.ndarray, source: np.ndarray, owned: np.ndarray) -> bool:
    if actual.shape != source.shape or actual.dtype != np.uint8:
        return False
    expected_alpha = np.where(owned, source[:, :, 3], 0).astype(np.uint8)
    expected_rgb = np.zeros_like(source[:, :, :3])
    expected_rgb[owned] = source[:, :, :3][owned]
    return (np.array_equal(actual[:, :, 3], expected_alpha) and
            np.array_equal(actual[:, :, :3], expected_rgb))


def alpha_components(alpha: np.ndarray, threshold: int = 1) -> list[int]:
    count, _, stats, _ = cv2.connectedComponentsWithStats((alpha >= threshold).astype(np.uint8), connectivity=8)
    return sorted((int(stats[index, cv2.CC_STAT_AREA]) for index in range(1, count)), reverse=True)


def read_rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        require(image.mode == "RGBA", f"Expected RGBA at {path}, got {image.mode}")
        return np.array(image)


def source_ownership() -> tuple[np.ndarray, dict[str, dict]]:
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    from refine_parts import components

    require(hash_matches(SOURCE.read_bytes(), EXPECTED_SOURCE_SHA), "Source RGBA hash mismatch")
    source = read_rgba(SOURCE)
    require(source.shape == (1216, 832, 4), f"Unexpected source array shape: {source.shape}")
    details: dict[str, dict] = {}
    rebuild_dir = REBUILD.parent
    for part, (mask_stem, record_name, expected_mask_sha) in MASKS.items():
        mask_path = rebuild_dir / f"{mask_stem}.png"
        record_path = rebuild_dir / record_name
        require(hash_matches(mask_path.read_bytes(), expected_mask_sha), f"Reviewed mask SHA mismatch: {mask_path}")
        raw_mask = read_rgb_mask(mask_path)
        require(set(np.unique(raw_mask)) == {0, 255}, f"Mask must stay binary: {mask_path}")
        record = json.loads(record_path.read_text(encoding="utf-8"))
        require(record["source_sha256"] == EXPECTED_SOURCE_SHA, f"Mask record source hash mismatch: {record_name}")
        require(record["mask_sha256"] == expected_mask_sha, f"Mask record mask hash mismatch: {record_name}")
        points = record["points"][mask_stem]
        positives = [(int(x), int(y)) for x, y in points["pos"]]
        negatives = [(int(x), int(y)) for x, y in points["neg"]]
        require(all(raw_mask[y, x] == 255 for x, y in positives), f"Positive SAM point outside {mask_stem} mask")
        require(all(raw_mask[y, x] == 0 for x, y in negatives), f"Negative SAM point inside {mask_stem} mask")
        thresholded = (raw_mask > 127) & (source[:, :, 3] >= 40)
        before_areas = alpha_components(np.where(thresholded, 255, 0).astype(np.uint8))
        owned = components(thresholded, 30)
        after_areas = alpha_components(np.where(owned, 255, 0).astype(np.uint8))
        require(owned.sum() > 150, f"No meaningful owned alpha for {part}")
        details[part] = {
            "mask_file": str(mask_path.relative_to(ROOT)).replace("\\", "/"),
            "mask_sha256": expected_mask_sha,
            "record_file": str(record_path.relative_to(ROOT)).replace("\\", "/"),
            "record_sha256": sha(record_path),
            "positive_points_native": positives,
            "negative_points_native": negatives,
            "positive_count": len(positives),
            "negative_count": len(negatives),
            "foreground_mask_pixels_before_component_filter": int(thresholded.sum()),
            "connected_components_before_filter_areas_desc": before_areas,
            "owned_alpha_pixels_after_existing_30px_component_rule": int(owned.sum()),
            "connected_components_after_filter_areas_desc": after_areas,
            "removed_pixels_from_existing_component_rule": int(thresholded.sum() - owned.sum()),
            "owned_source_bbox_xyxy_inclusive": [int(np.nonzero(owned)[1].min()), int(np.nonzero(owned)[0].min()),
                                                    int(np.nonzero(owned)[1].max()), int(np.nonzero(owned)[0].max())],
            "owned_source_alpha_y_max": int(np.nonzero(owned)[0].max()),
            "alpha_source_pixel_count_alpha_ge_40": int(((source[:, :, 3] >= 40) & owned).sum()),
            "owned_mask": owned,
        }
    return source, details


def read_rgb_mask(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        require(image.mode == "RGB" and image.size == (832, 1216), f"Expected native RGB mask: {path}")
        return np.array(image)[:, :, 0]


def write_foot_ground_evidence(source: np.ndarray, owned: np.ndarray, ground_y: int) -> str:
    from PIL import ImageDraw

    x0, y0, x1, y1 = 280, 1030, 510, 1216
    base = Image.fromarray(source, "RGBA").crop((x0, y0, x1, y1))
    background = Image.new("RGBA", base.size, (116, 116, 116, 255))
    background.alpha_composite(base)
    draw = ImageDraw.Draw(background)
    crop_owned = owned[y0:y1, x0:x1]
    for yy, xx in zip(*np.nonzero(crop_owned)):
        draw.point((int(xx), int(yy)), fill=(40, 210, 235, 255))
    draw.line((0, ground_y - y0, x1 - x0 - 1, ground_y - y0), fill=(255, 55, 45, 255), width=1)
    ground_x = np.flatnonzero(owned[ground_y])
    for x in ground_x:
        draw.rectangle((int(x) - x0 - 2, ground_y - y0 - 3, int(x) - x0 + 2, ground_y - y0 + 3), outline=(255, 245, 40, 255))
    scaled = background.resize((background.width * 3, background.height * 3), Image.Resampling.NEAREST)
    path = PRIVATE / "foot-ground-ownership.png"
    scaled.save(path)
    return path.relative_to(ROOT).as_posix()


def replay_run(label: str) -> dict:
    work = PRIVATE / label / "work"
    char_dir = PRIVATE / label / "char"
    rig_path = PRIVATE / label / "rig" / "slasher.json"
    if work.exists() or char_dir.exists() or rig_path.parent.exists():
        raise RuntimeError(f"Refusing to overwrite existing private run: {PRIVATE / label}")
    work.mkdir(parents=True)
    shutil.copy2(SOURCE, work / "base_rgba.png")
    shutil.copytree(REFINED, work / "07_refined")
    char_dir.mkdir(parents=True)
    rig_path.parent.mkdir(parents=True)

    commands = [
        [str(PYTHON), str(REBUILD), "--work", str(work)],
        [str(PYTHON), str(CUT), "--spec", str(SPEC), "--work", str(work), "--char", str(char_dir), "--rig", str(rig_path)],
    ]
    logs = []
    for index, command in enumerate(commands):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        logs.append({"command": command, "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode != 0:
            raise RuntimeError(f"run {label} command {index} failed: {result.stdout}\n{result.stderr}")
    return {"label": label, "work": work, "char": char_dir, "rig": rig_path, "logs": logs}


def output_manifest(run: dict) -> dict[str, str]:
    outputs = {"character.json": run["char"] / "character.json", "rig/slasher.json": run["rig"],
               "overrides/refined/hand.png": run["work"] / "overrides/refined/hand.png",
               "overrides/refined/foot.png": run["work"] / "overrides/refined/foot.png"}
    outputs.update({f"parts/{path.name}": path for path in sorted((run["char"] / "parts").glob("*.png"))})
    return {name: sha(path) for name, path in outputs.items()}


def raw_joint_overlap(run: dict, source: np.ndarray) -> dict:
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    from cut_layers import part_transform, render_part

    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    factor = float(spec["tex_px_per_wp"]) / float(spec["illustration_px_per_wp"])
    joints = {name: np.array(point, dtype=float) * factor for name, point in spec["joints"].items()}
    palm_native = tuple(map(float, spec["joints"]["palm"]))
    transforms = {}
    rendered = {}
    for name in ("arm_lower", "hand"):
        part_config = spec["parts"][name]
        src_path = run["work"] / "overrides/refined/hand.png" if name == "hand" else REFINED / f"{name}.png"
        with Image.open(src_path) as image:
            image_rgba = image.convert("RGBA")
        transform = part_transform(image_rgba, part_config, joints, factor)
        require(transform is not None, f"No output transform for {name}")
        rendered[name] = render_part(image_rgba, transform, factor)
        transforms[name] = transform

    positions = {}
    for name, (affine, _, _, _) in transforms.items():
        p = np.array([palm_native[0] * factor, palm_native[1] * factor, 1.0], dtype=np.float32)
        # cut_layers passes A to warpAffine with WARP_INVERSE_MAP: A maps
        # destination pixels to source coordinates. Invert it for this query.
        positions[name] = (cv2.invertAffineTransform(affine) @ p).tolist()

    def nearest_alpha(array: np.ndarray, point: list[float]) -> dict:
        yy, xx = np.nonzero(array[:, :, 3] >= 20)
        require(len(xx) > 0, "Rendered part has no alpha>=20 pixels")
        distances = np.hypot(xx - point[0], yy - point[1])
        ix = int(np.argmin(distances))
        return {"nearest_alpha20_pixel": [int(xx[ix]), int(yy[ix])], "distance_texture_px": float(distances[ix]),
                "within_1px": bool(distances[ix] <= 1.0), "within_3px": bool(distances[ix] <= 3.0)}

    return {
        "spec_palm_wrist_native": list(palm_native),
        "spec_fingertip_native": list(map(float, spec["joints"]["fingertip"])),
        "near_hand_texture_palm_point": positions["hand"],
        "near_arm_lower_texture_palm_point": positions["arm_lower"],
        "hand_opaque_contact": nearest_alpha(rendered["hand"], positions["hand"]),
        "arm_lower_opaque_contact": nearest_alpha(rendered["arm_lower"], positions["arm_lower"]),
        "arm_lower_native_output_components_alpha20": alpha_components(rendered["arm_lower"][:, :, 3], 20),
        "hand_native_output_components_alpha20": alpha_components(rendered["hand"][:, :, 3], 20),
        "measurement_note": "Distance is to true output alpha rendered by the production cut_layers transform; 3px is reported descriptively only, not a new acceptance threshold.",
    }


def main() -> None:
    PRIVATE.mkdir(parents=True, exist_ok=True)
    source, ownership = source_ownership()
    # Preserve the earlier exploratory run folders; this corrected pair uses the
    # inverse map of cut_layers' WARP_INVERSE_MAP affine when measuring joint gaps.
    replay_prefix = f"replay-{time.time_ns()}"
    runs = [replay_run(f"{replay_prefix}-a"), replay_run(f"{replay_prefix}-b")]

    source_checks = {}
    for run in runs:
        for part, data in ownership.items():
            output_path = run["work"] / "overrides/refined" / f"{part}.png"
            actual = read_rgba(output_path)
            valid = validate_rebuilt_rgba(actual, source, data["owned_mask"])
            require(valid, f"Source RGB/alpha preservation mismatch for {run['label']} {part}")
            source_checks[f"{run['label']}/{part}"] = {
                "sha256": sha(output_path), "dimensions": [actual.shape[1], actual.shape[0]],
                "alpha_nonzero_pixels": int((actual[:, :, 3] > 0).sum()),
                "alpha_ge_40_pixels": int((actual[:, :, 3] >= 40).sum()),
                "connected_components_alpha1_areas_desc": alpha_components(actual[:, :, 3], 1),
                "source_rgb_and_alpha_exact_for_owned_mask": valid,
                "native_palm_wrist_alpha": int(source[570, 333, 3]),
                "native_sole_probe_alpha": int(source[1180, 327, 3]) if part == "foot" else None,
            }

    manifest_a = output_manifest(runs[0])
    manifest_b = output_manifest(runs[1])
    require(manifest_a == manifest_b, "Isolated cut output hashes differ between runs")

    formal_override_compare = {}
    for part in MASKS:
        formal_override = SOURCE_WORK / "overrides/refined" / f"{part}.png"
        replay_override = runs[0]["work"] / "overrides/refined" / f"{part}.png"
        formal_pixels = read_rgba(formal_override)
        replay_pixels = read_rgba(replay_override)
        exact = np.array_equal(formal_pixels, replay_pixels)
        formal_override_compare[part] = {"formal_sha256": sha(formal_override), "replay_sha256": sha(replay_override),
                                         "pixel_exact": exact}
        require(exact, f"Formal source override differs from isolated rebuild: {part}")

    formal_pngs = {path.name: path for path in sorted((FORMAL_CHAR / "parts").glob("*.png")) if not path.name.endswith("_n.png")}
    replay_pngs = {path.name: path for path in sorted((runs[0]["char"] / "parts").glob("*.png"))}
    formal_names = sorted(formal_pngs)
    replay_names = sorted(replay_pngs)
    require(formal_names == replay_names, f"Formal/runtime part PNG set differs: formal={formal_names}, replay={replay_names}")
    png_compare = {}
    for name in formal_names:
        formal_image = read_rgba(formal_pngs[name])
        replay_image = read_rgba(replay_pngs[name])
        pixel_equal = np.array_equal(formal_image, replay_image)
        png_compare[name] = {"formal_sha256": sha(formal_pngs[name]), "replay_sha256": sha(replay_pngs[name]),
                             "dimensions_formal": [formal_image.shape[1], formal_image.shape[0]],
                             "dimensions_replay": [replay_image.shape[1], replay_image.shape[0]],
                             "pixel_exact": pixel_equal}
        require(pixel_equal, f"Formal part differs from isolated cut output: {name}")

    formal_character = json.loads((FORMAL_CHAR / "character.json").read_text(encoding="utf-8"))
    replay_character = json.loads((runs[0]["char"] / "character.json").read_text(encoding="utf-8"))
    formal_rig = json.loads(FORMAL_RIG.read_text(encoding="utf-8"))
    replay_rig = json.loads(runs[0]["rig"].read_text(encoding="utf-8"))
    char_equal = formal_character == replay_character
    rig_equal = formal_rig == replay_rig
    require(char_equal and rig_equal, "Formal character/rig semantics differ from isolated cut output")

    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    source_contact = raw_joint_overlap(runs[0], source)
    ground_y = int(spec["ground_y"])
    foot_owned = ownership["foot"]["owned_mask"]
    foot_evidence_image = write_foot_ground_evidence(source, foot_owned, ground_y)
    sole_x = np.flatnonzero(foot_owned[ground_y])
    source_contact["foot_native_ground_y"] = ground_y
    source_contact["foot_owned_alpha_pixels_on_ground_line"] = int(len(sole_x))
    source_contact["foot_owned_alpha_ground_x_min_max"] = [int(sole_x.min()), int(sole_x.max())] if len(sole_x) else None
    source_contact["foot_source_alpha_at_ground_pixels"] = [int(value) for value in source[ground_y, sole_x, 3]]
    require(len(sole_x) > 0, "Reviewed near boot has no owned opaque source pixels on ground_y=1192")
    source_contact["foot_native_positive_sole_marker"] = [327, 1180]
    source_contact["foot_native_positive_sole_marker_alpha"] = int(source[1180, 327, 3])
    source_contact["native_ground_crop_image"] = foot_evidence_image
    first_label = runs[0]["label"]
    foot_raw = source_checks[f"{first_label}/foot"]
    require(foot_raw["alpha_nonzero_pixels"] > 100, "Near boot override is empty")

    # In-memory negative controls: each malformed condition must be rejected without touching source files.
    sample = read_rgba(runs[0]["work"] / "overrides/refined/hand.png")
    owned_hand = ownership["hand"]["owned_mask"]
    require(not hash_matches(SOURCE.read_bytes(), "0" * 64), "Bad-hash negative control was not rejected")
    all_opaque = sample.copy()
    all_opaque[:, :, 3] = 255
    all_opaque[:, :, :3] = source[:, :, :3]
    require(not validate_rebuilt_rgba(all_opaque, source, owned_hand), "All-opaque alpha negative control was accepted")
    changed_rgb = sample.copy()
    y, x = np.argwhere(owned_hand)[0]
    changed_rgb[y, x, 0] = (int(changed_rgb[y, x, 0]) + 1) % 256
    require(not validate_rebuilt_rgba(changed_rgb, source, owned_hand), "Mutated source RGB negative control was accepted")

    source_hash = sha(SOURCE)
    report = {
        "scope": "CPU-only private replay of reviewed near hand and single boot plus cut-layer comparison; no Godot/GPU/ComfyUI run",
        "source": {"path": str(SOURCE.relative_to(ROOT)).replace("\\", "/"), "sha256": source_hash,
                   "dimensions": [source.shape[1], source.shape[0]], "mode": "RGBA"},
        "spec": {"path": str(SPEC.relative_to(ROOT)).replace("\\", "/"),
                 "sha256": sha(SPEC), "palm_wrist": spec["joints"]["palm"],
                 "fingertip": spec["joints"]["fingertip"], "ground_y": spec["ground_y"]},
        "rebuild_script": {"path": str(REBUILD.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(REBUILD)},
        "runs": [{"label": run["label"], "commands": run["logs"]} for run in runs],
        "masks_and_rebuilt_overrides": {part: {key: value for key, value in data.items() if key != "owned_mask"}
                                        for part, data in ownership.items()},
        "override_outputs": source_checks,
        "repeatability": {"all_runtime_part_and_semantic_file_hashes_equal": manifest_a == manifest_b,
                          "output_file_sha256": manifest_a},
        "formal_source_override_comparison": formal_override_compare,
        "formal_runtime_comparison": {"diffuse_part_png_names_match": formal_names == replay_names,
                                      "diffuse_part_pngs_pixel_exact": all(row["pixel_exact"] for row in png_compare.values()),
                                      "diffuse_part_pngs": png_compare,
                                      "character_json_semantic_equal": char_equal,
                                      "rig_json_semantic_equal": rig_equal,
                                      "character_json_sha256_formal": sha(FORMAL_CHAR / "character.json"),
                                      "character_json_sha256_replay": sha(runs[0]["char"] / "character.json"),
                                      "rig_json_sha256_formal": sha(FORMAL_RIG),
                                      "rig_json_sha256_replay": sha(runs[0]["rig"])},
        "native_wrist_and_single_boot_checks": source_contact,
        "negative_controls": {"wrong_source_sha_rejected": True,
                              "all_opaque_alpha_rejected": True,
                              "one_channel_owned_source_rgb_mutation_rejected": True,
                              "mutated_pixel_native": [int(x), int(y)]},
        "not_verified": ["runtime scene animation and combat", "full armor removal and underneath-body coverage", "Forward+ lighting/native screenshot", "near/far foot pose visual acceptance"],
    }
    (PRIVATE / "repro.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (PRIVATE / "repro.md").write_text(render_markdown(report), encoding="utf-8")
    print(json.dumps({"report": str(PRIVATE / "repro.json"), "repeatable_files": len(manifest_a),
                      "diffuse_pngs": len(formal_names), "character_semantic_equal": char_equal,
                      "rig_semantic_equal": rig_equal, "hand_wrist": source_contact["hand_opaque_contact"],
                      "arm_lower_wrist": source_contact["arm_lower_opaque_contact"],
                      "hand_alpha": source_checks[f"{first_label}/hand"]["alpha_nonzero_pixels"],
                      "foot_alpha": foot_raw["alpha_nonzero_pixels"]}, ensure_ascii=False, indent=2))


def render_markdown(report: dict) -> str:
    first_run = next(iter(report["override_outputs"])).split("/", 1)[0]
    hand = report["masks_and_rebuilt_overrides"]["hand"]
    foot = report["masks_and_rebuilt_overrides"]["foot"]
    compare = report["formal_runtime_comparison"]
    contact = report["native_wrist_and_single_boot_checks"]
    lines = [
        "# Slasher near-hand / single-boot final replay",
        "",
        "CPU-only source rebuild and deterministic cut-layer verification. No Godot, GPU, ComfyUI, or runtime combat was run.",
        "",
        f"Source `{report['source']['path']}` SHA-256 `{report['source']['sha256']}`; spec `{report['spec']['path']}` SHA-256 `{report['spec']['sha256']}`.",
        "",
        "Both private isolated runs replayed `near_hand_repair/rebuild.py --work <run>/work` followed by `cut_layers.py` with the same official spec. All output hashes matched between runs.",
        "",
        "| Override | Positive / negative SAM points | Mask components before → after existing 30px rule | Opaque owned pixels |",
        "|---|---:|---|---:|",
        f"| hand | {hand['positive_count']} / {hand['negative_count']} | {hand['connected_components_before_filter_areas_desc']} → {hand['connected_components_after_filter_areas_desc']} | {hand['owned_alpha_pixels_after_existing_30px_component_rule']} |",
        f"| foot | {foot['positive_count']} / {foot['negative_count']} | {foot['connected_components_before_filter_areas_desc']} → {foot['connected_components_after_filter_areas_desc']} | {foot['owned_alpha_pixels_after_existing_30px_component_rule']} |",
        "",
        f"Formal runtime diffuse PNG set matches and all {len(compare['diffuse_part_pngs'])} PNGs are pixel-identical to isolated output. `character.json` semantic equality: **{compare['character_json_semantic_equal']}**; `slasher.json` semantic equality: **{compare['rig_json_semantic_equal']}**.",
        "",
        f"The two rebuilt full-canvas overrides also match the formal registered overrides pixel-for-pixel: `{report['formal_source_override_comparison']}`.",
        "",
        f"Spec wrist/palm is `{contact['spec_palm_wrist_native']}`, fingertip `{contact['spec_fingertip_native']}`. Using the production cut affine, hand nearest alpha≥20 is {contact['hand_opaque_contact']}; arm-lower nearest alpha≥20 is {contact['arm_lower_opaque_contact']}. Distances are measurements, not an added acceptance threshold.",
        "",
        f"Near boot source alpha contains {report['override_outputs'][f'{first_run}/foot']['alpha_nonzero_pixels']} nonzero pixels after the reviewed binary mask and existing component rule. At spec ground_y={contact['foot_native_ground_y']}, {contact['foot_owned_alpha_pixels_on_ground_line']} owned opaque pixels span x={contact['foot_owned_alpha_ground_x_min_max']}; the reviewed positive sole point `{contact['foot_native_positive_sole_marker']}` has source alpha {contact['foot_native_positive_sole_marker_alpha']}. The native alpha/ownership crop is `{contact['native_ground_crop_image']}`. This source check does not certify posed runtime foot contact.",
        "",
        "Negative controls passed: an incorrect source hash is rejected; an all-opaque false-alpha image is rejected; changing one RGB channel in an owned source pixel is rejected. The actual rebuild preserved source RGB and source alpha on the owned mask exactly.",
        "",
        "Not covered: runtime animation/combat, full armor removal or underlayer coverage, native Forward+ lighting, and visual acceptance of both feet/facings. Root's planned affected suites and screenshots remain separate acceptance evidence.",
        "",
        "See `repro.json` for exact commands, exit codes, logs, hashes, dimensions, alpha counts, and per-file comparisons.",
        "",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    main()
