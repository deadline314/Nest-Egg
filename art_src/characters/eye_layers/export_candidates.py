#!/usr/bin/env python3
"""Derive private head eye-state textures with the production cut transform."""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import make_normal_map, part_transform, render_part, sha256, validate_eye_state_sources  # noqa: E402
from cut_rig_parts import glow_layer  # noqa: E402

HERE = Path(__file__).resolve().parent
RECIPE = HERE / "export_recipe.json"
PRIVATE_EXPORT_ROOT = ROOT / ".godot/eye-state-export"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def private_output_path(root: Path, requested: Path | None) -> Path:
    """Resolve an output target confined to the ignored eye-export workspace."""
    private_root = (root / ".godot/eye-state-export").resolve()
    candidate = requested or private_root
    if not candidate.is_absolute():
        candidate = root / candidate
    lexical = Path(os.path.abspath(candidate))
    if lexical != private_root and private_root not in lexical.parents:
        raise ValueError(f"eye-state exports must stay under the private export directory: {lexical}")
    current = private_root
    if current.is_symlink():
        raise ValueError(f"private export directory must not be a symlink: {current}")
    for component in lexical.relative_to(private_root).parts:
        current = current / component
        if current.is_symlink():
            raise ValueError(f"eye-state export path must not traverse a symlink: {current}")
    resolved = lexical.resolve()
    if resolved != private_root and private_root not in resolved.parents:
        raise ValueError(f"resolved eye-state output escapes its private export directory: {resolved}")
    if resolved == private_root and requested is not None and lexical != private_root:
        raise ValueError(f"eye-state output path resolves to the export root through an alias: {lexical}")
    return resolved


def source_head_path(work: Path, part: str) -> Path:
    source_dir = work / "07_refined" if (work / "07_refined").exists() else work / "06_parts"
    override = work / "overrides/refined" / f"{part}.png"
    return override if override.is_file() else source_dir / f"{part}.png"


def gray_composite(image: Image.Image, box: tuple[int, int, int, int], scale: int = 1) -> Image.Image:
    crop = image.crop(box)
    bg = Image.new("RGBA", crop.size, (128, 128, 128, 255))
    bg.alpha_composite(crop)
    if scale != 1:
        bg = bg.resize((bg.width * scale, bg.height * scale), Image.Resampling.NEAREST)
    return bg.convert("RGB")


def eye_crop_box(mask_points: list[list[float]], affine: np.ndarray, k: float, size: tuple[int, int], padding: int = 3) -> tuple[int, int, int, int]:
    inverse = cv2.invertAffineTransform(affine)
    mapped = []
    for x, y in mask_points:
        mapped.append(inverse @ np.array([x * k, y * k, 1.0], dtype=float))
    xs, ys = [p[0] for p in mapped], [p[1] for p in mapped]
    x0 = max(0, math.floor(min(xs)) - padding)
    y0 = max(0, math.floor(min(ys)) - padding)
    x1 = min(size[0], math.ceil(max(xs)) + padding + 1)
    y1 = min(size[1], math.ceil(max(ys)) + padding + 1)
    if x1 <= x0 or y1 <= y0:
        raise ValueError("transformed eye mask has an empty crop")
    return x0, y0, x1, y1


def make_contact(open_image: Image.Image, half: Image.Image, closed: Image.Image,
                 eye_box: tuple[int, int, int, int], destination: Path, skin_id: str) -> None:
    states = [("open", open_image), ("half", half), ("closed", closed)]
    previews = [gray_composite(image, (0, 0, image.width, image.height)) for _, image in states]
    details = [gray_composite(image, eye_box, 12) for _, image in states]
    gutter, title_h, label_h = 8, 22, 18
    row1_h = max(image.height for image in previews)
    row2_h = max(image.height for image in details)
    width = max(sum(image.width for image in previews) + 4 * gutter,
                sum(image.width for image in details) + 4 * gutter)
    sheet = Image.new("RGB", (width, title_h + label_h + row1_h + gutter + label_h + row2_h + gutter), (31, 35, 43))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 4), f"{skin_id} | unchanged open / half / closed | head native + 12x nearest eye", fill=(245, 245, 245))
    y = title_h + label_h
    x = gutter
    for (label, _), image in zip(states, previews):
        draw.text((x, title_h), f"{label} head", fill=(245, 245, 245))
        sheet.paste(image, (x, y))
        x += image.width + gutter
    y += row1_h + gutter + label_h
    x = gutter
    for (label, _), image in zip(states, details):
        draw.text((x, y - label_h), f"{label} eye", fill=(245, 245, 245))
        sheet.paste(image, (x, y))
        x += image.width + gutter
    sheet.save(destination)


def export_one(root: Path, item_id: str, mapping: dict, candidate_manifest: dict,
               staging: Path) -> dict:
    recipe_path = root / mapping["recipe"]
    recipe = read_json(recipe_path)
    spec_path = root / recipe["spec"]
    spec = read_json(spec_path)
    work = root / recipe["work"]
    skin_id = recipe["id"]
    candidate_id = mapping["candidate_id"]
    source_record = candidate_manifest["characters"][candidate_id]
    source_path = root / source_record["source"]
    selected_head = source_head_path(work, "head")
    expected_hash = source_record["source_sha256"]
    if selected_head.resolve() != source_path.resolve():
        raise ValueError(f"{skin_id}: selected cut head differs from candidate source: {selected_head} != {source_path}")
    if sha256(selected_head) != expected_hash:
        raise ValueError(f"{skin_id}: selected cut head SHA mismatch")

    char_path = root / "art" / "characters" / skin_id / "character.json"
    current_character = read_json(char_path)
    part_name = "head"
    if part_name not in spec.get("parts", {}) or part_name not in current_character.get("textures", {}):
        raise ValueError(f"{skin_id}: missing source or current head texture")
    part = spec["parts"][part_name]
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.array(point, dtype=float) * k for name, point in spec["joints"].items()}
    with Image.open(selected_head) as image:
        if image.mode != "RGBA":
            raise ValueError(f"{skin_id}: cut source head must be RGBA, got {image.mode}")
        original = image.copy()
    transform = part_transform(original, part, joints, k)
    if transform is None:
        raise ValueError(f"{skin_id}: head source has no visible pixels")
    affine, width, height, pivot = transform
    texture = current_character["textures"][part_name]
    if texture.get("size") != [width, height]:
        raise ValueError(f"{skin_id}: production head texture size {texture.get('size')} != cut transform {[width, height]}")
    expected_pivot = [round(float(pivot[0]), 2), round(float(pivot[1]), 2)]
    if texture.get("pivot") != expected_pivot:
        raise ValueError(f"{skin_id}: production head pivot {texture.get('pivot')} != cut transform {expected_pivot}")
    open_path = root / "art/characters" / skin_id / texture["file"]
    before_open_hash = sha256(open_path)
    with Image.open(open_path) as image:
        if image.mode != "RGBA" or image.size != (width, height):
            raise ValueError(f"{skin_id}: current open head is not native RGBA {[width, height]}")
        open_image = image.copy()
    rebuilt_open = render_part(original, transform, k)
    if not np.array_equal(rebuilt_open, np.array(open_image)):
        raise ValueError(f"{skin_id}: current open head is not byte-identical to the selected cut source rebuild")

    candidate_dir = root / "art_src/characters/eye_layers/corrected_candidates/characters" / candidate_id
    sources = {
        "original_head": {"path": str(selected_head.relative_to(root)).replace("\\", "/"), "sha256": expected_hash},
        "half": {"path": str((candidate_dir / "half.png").relative_to(root)).replace("\\", "/"),
                 "sha256": source_record["outputs_sha256"]["half"]},
        "closed": {"path": str((candidate_dir / "closed.png").relative_to(root)).replace("\\", "/"),
                   "sha256": source_record["outputs_sha256"]["closed"]},
    }
    eye_spec = {"part": "head", "half_texture": "head_half", "closed_texture": "head_closed",
                "timing": {}, "sources": sources, "eye_mask": source_record["eye_mask"]}
    _, native_states = validate_eye_state_sources(eye_spec, selected_head, tuple(original.size))

    output_parts = staging / skin_id / "parts"
    output_parts.mkdir(parents=True, exist_ok=True)
    state_records = {}
    state_images = {}
    glow_kind = spec.get("glow", {}).get("head")
    threshold = spec.get("glow_threshold", {})
    for state, texture_name in (("half", "head_half"), ("closed", "head_closed")):
        rgba = render_part(native_states[state], transform, k)
        if rgba.shape != (height, width, 4):
            raise AssertionError(f"{skin_id}/{state}: transformed output canvas differs")
        diffuse_path = output_parts / f"{texture_name}.png"
        Image.fromarray(rgba, "RGBA").save(diffuse_path)
        normal_path = output_parts / f"{texture_name}_n.png"
        Image.fromarray(make_normal_map(rgba), "RGBA").save(normal_path)
        glow_path = None
        if glow_kind:
            glow = glow_layer(rgba[:, :, :3], rgba[:, :, 3], glow_kind,
                              threshold.get("sat", 140), threshold.get("val", 190))
            if glow is not None:
                glow_path = output_parts / f"{texture_name}_glow.png"
                Image.fromarray(glow, "RGBA").save(glow_path)
        with Image.open(diffuse_path) as saved:
            if saved.mode != "RGBA" or saved.size != (width, height) or saved.tobytes() != rgba.tobytes():
                raise AssertionError(f"{skin_id}/{state}: saved diffuse differs from derived output")
        with Image.open(normal_path) as saved_normal:
            if saved_normal.mode != "RGBA" or saved_normal.size != (width, height) or not np.array_equal(np.array(saved_normal)[:, :, 3], rgba[:, :, 3]):
                raise AssertionError(f"{skin_id}/{state}: normal map canvas/alpha mismatch")
        state_images[state] = Image.fromarray(rgba, "RGBA")
        state_records[state] = {
            "texture": texture_name,
            "size": [width, height],
            "pivot": expected_pivot,
            "diffuse": str(diffuse_path.relative_to(staging)).replace("\\", "/"),
            "diffuse_sha256": sha256(diffuse_path),
            "normal": str(normal_path.relative_to(staging)).replace("\\", "/"),
            "normal_sha256": sha256(normal_path),
            "glow": str(glow_path.relative_to(staging)).replace("\\", "/") if glow_path else None,
            "glow_sha256": sha256(glow_path) if glow_path else None,
        }

    eye_box = eye_crop_box(source_record["eye_mask"], affine, k, (width, height))
    contact = staging / skin_id / "contact.png"
    make_contact(open_image, state_images["half"], state_images["closed"], eye_box, contact, skin_id)
    if sha256(open_path) != before_open_hash:
        raise AssertionError(f"{skin_id}: formal open head changed during private export")

    runtime_metadata = {"part": "head", "half_texture": "head_half", "closed_texture": "head_closed", "timing": {}}
    return {
        "skin_id": skin_id,
        "candidate_id": candidate_id,
        "recipe": str(recipe_path.relative_to(root)).replace("\\", "/"),
        "spec": str(spec_path.relative_to(root)).replace("\\", "/"),
        "cut_source": str(selected_head.relative_to(root)).replace("\\", "/"),
        "source_sha256": expected_hash,
        "candidate_sources": sources,
        "canvas": list(original.size),
        "scale_k": k,
        "affine_destination_to_source": affine.tolist(),
        "texture_size": [width, height],
        "pivot": expected_pivot,
        "eye_mask": source_record["eye_mask"],
        "eye_crop": list(eye_box),
        "open_texture": str(open_path.relative_to(root)).replace("\\", "/"),
        "open_texture_sha256": before_open_hash,
        "runtime_metadata": runtime_metadata,
        "states": state_records,
        "contact": str(contact.relative_to(staging)).replace("\\", "/"),
        "normal_method": "CPU port of NormalMapMaker.make(source, 2, 3.0, 1.4)",
        "glow_kind": glow_kind,
        "glow_threshold": threshold,
    }


def export(root: Path = ROOT, recipe_path: Path = RECIPE, output_override: Path | None = None) -> dict:
    recipe = read_json(recipe_path)
    if recipe.get("version") != 1 or not isinstance(recipe.get("characters"), dict):
        raise ValueError("unsupported eye-state export recipe")
    candidate_manifest = read_json(root / recipe["candidate_manifest"])
    requested_output = output_override or root / recipe["output"]
    output = private_output_path(root, requested_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="eye-state-export-", dir=output.parent) as temp_dir:
        staging = Path(temp_dir) / "payload"
        staging.mkdir()
        (staging / ".gdignore").touch()
        characters = {}
        for skin_id, mapping in recipe["characters"].items():
            characters[skin_id] = export_one(root, skin_id, mapping, candidate_manifest, staging)
        result = {
            "status": "source-derived candidate export; runtime and stage acceptance are not asserted",
            "recipe": str(recipe_path.relative_to(root)).replace("\\", "/"),
            "candidate_manifest": recipe["candidate_manifest"],
            "characters": characters,
        }
        (staging / "manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        backup = Path(temp_dir) / "previous"
        if output.is_symlink():
            raise ValueError(f"eye-state output must not be a symlink: {output}")
        if output.exists() and not output.is_dir():
            raise ValueError(f"eye-state output must be a directory: {output}")
        if output.exists():
            os.replace(output, backup)
        try:
            os.replace(staging, output)
        except Exception:
            if backup.exists() and not output.exists():
                os.replace(backup, output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, default=RECIPE)
    parser.add_argument("--output", type=Path, help="private output override; defaults to recipe output")
    args = parser.parse_args()
    recipe_path = args.recipe if args.recipe.is_absolute() else ROOT / args.recipe
    output_override = args.output if args.output is None or args.output.is_absolute() else ROOT / args.output
    result = export(ROOT, recipe_path, output_override)
    print(f"Exported {len(result['characters'])} eye-state candidates to {output_override or ROOT / read_json(recipe_path)['output']}")


if __name__ == "__main__":
    main()
