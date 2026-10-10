"""Reproduce a reviewed ComfyUI stage extension without changing centre pixels.

Prepare/processing run on CPU; only explicit --generate loads a model. Each
entry retains source/raw/output SHA, prompt, seed, registration and world origin.
Review and native adoption remain separate from successful processing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets_src/pipeline/qwen_stage_extensions.json"
MAX_PIXELS = 4_000_000
MAX_FILE_BYTES = 1_572_864


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_path(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise ValueError("Missing project-relative asset path")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Asset escapes project: {relative}")
    return path


def size_pair(raw: list, label: str) -> tuple[int, int]:
    if not isinstance(raw, list) or len(raw) != 2 or any(type(v) is not int or v <= 0 for v in raw):
        raise ValueError(f"{label}: expected two positive integers")
    if raw[0] * raw[1] > MAX_PIXELS:
        raise ValueError(f"{label}: exceeds bounded decoded image budget")
    return tuple(raw)


def checked_image(path: Path, expected_sha: str, size: tuple[int, int]) -> np.ndarray:
    if path.stat().st_size > 16_777_216 or digest(path) != expected_sha:
        raise ValueError(f"{path}: source SHA or file budget mismatch")
    with Image.open(path) as image:
        if image.size != size:
            raise ValueError(f"{path}: expected {size}, got {image.size}")
        return np.asarray(image.convert("RGB"))


def prepare(entry: dict, root: Path = ROOT) -> Path:
    original = checked_image(project_path(root, entry["original"]), entry["original_sha256"], size_pair(entry["original_size"], "original_size"))
    guide_size = size_pair(entry["reference_size"], "reference_size")
    centre_size = size_pair(entry["reference_centre_size"], "reference_centre_size")
    padding = entry["reference_padding_xy"]
    if len(padding) != 2 or any(type(v) is not int or v < 0 for v in padding):
        raise ValueError("reference_padding_xy: expected nonnegative integer pair")
    if tuple(centre_size[i] + 2 * padding[i] for i in range(2)) != guide_size:
        raise ValueError("reference dimensions and padding disagree")
    small = np.asarray(Image.fromarray(original).resize(centre_size, Image.Resampling.LANCZOS))
    guide = np.pad(small, ((padding[1], padding[1]), (padding[0], padding[0]), (0, 0)), mode="edge")
    path = project_path(root, entry["reference"])
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(guide).save(path)
    if digest(path) != entry["reference_sha256"]:
        raise ValueError(f"{path}: reference reconstruction differs; no generation queued")
    return path


def compose(entry: dict, root: Path = ROOT) -> dict:
    original_size = size_pair(entry["original_size"], "original_size")
    original = checked_image(project_path(root, entry["original"]), entry["original_sha256"], original_size)
    raw_path = project_path(root, entry["raw"])
    raw_size = size_pair(entry["raw_size"], "raw_size")
    raw = checked_image(raw_path, entry["raw_sha256"], raw_size)
    canvas_size = size_pair(entry["registration_canvas"], "registration_canvas")
    matrix = np.asarray(entry["registration_matrix"], dtype=np.float64)
    if matrix.shape != (2, 3) or not np.isfinite(matrix).all():
        raise ValueError("registration_matrix: expected finite affine transform")
    scale = float(np.hypot(matrix[0, 0], matrix[1, 0]))
    rotation = math.degrees(math.atan2(matrix[1, 0], matrix[0, 0]))
    if not (0.85 <= scale <= 1.35 and abs(rotation) <= 1.0) or not np.allclose(matrix[:, :2], [[matrix[0, 0], -matrix[1, 0]], [matrix[1, 0], matrix[0, 0]]], atol=1e-9):
        raise ValueError("registration_matrix: unsafe scale/rotation/shear")
    w, h = canvas_size
    corners = np.array([[0, 0, 1], [w-1, 0, 1], [0, h-1, 1], [w-1, h-1, 1]], dtype=float) @ cv2.invertAffineTransform(matrix).T
    continuation = [max(0., -corners[:, 0].min()), max(0., -corners[:, 1].min()), max(0., corners[:, 0].max()-(w-1)), max(0., corners[:, 1].max()-(h-1))]
    if any(value > limit for value, limit in zip(continuation, [32, 96, 32, 32])):
        raise ValueError("registration_matrix: excessive border continuation")
    x0, y0 = entry["original_canvas_xy"]
    ow, oh = original_size
    if type(x0) is not int or type(y0) is not int or x0 < 0 or y0 < 0 or x0+ow > w or y0+oh > h:
        raise ValueError("original_canvas_xy: centre exceeds registration canvas")
    crop = entry["crop_xywh"]
    if not isinstance(crop, list) or len(crop) != 4 or any(type(v) is not int for v in crop):
        raise ValueError("crop_xywh: expected four integers")
    cx, cy, cw, ch = crop
    size_pair([cw, ch], "crop size")
    if cx < 0 or cy < 0 or cx+cw > w or cy+ch > h or cx > x0 or cy > y0 or cx+cw < x0+ow or cy+ch < y0+oh:
        raise ValueError("crop_xywh: crop must retain whole original")
    scale_world = entry["scale"]
    world_origin, original_origin = entry["world_origin"], entry["original_world_origin"]
    if type(scale_world) not in (int, float) or not math.isfinite(scale_world) or not 0 < scale_world <= 16:
        raise ValueError("scale: invalid world scale")
    for origin in [world_origin, original_origin]:
        if not isinstance(origin, list) or len(origin) != 2 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 100000 for v in origin):
            raise ValueError("world_origin: expected finite bounded pair")
    if entry["source_width"] != cw or any(abs(world_origin[i]+([x0-cx, y0-cy][i])*scale_world-original_origin[i]) > 1e-6 for i in range(2)):
        raise ValueError("world_origin/source_width: original furniture would move or shrink")
    expanded = np.asarray(Image.fromarray(raw).resize(canvas_size, Image.Resampling.LANCZOS))
    base = cv2.warpAffine(expanded, matrix, canvas_size, flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
    # Match only the new margin to the nearest original edge; the original
    # itself is never graded or blended. This is seam matching, not global grade.
    fade = entry["edge_match_fade_px"]
    if type(fade) is not int or not 1 <= fade <= 128:
        raise ValueError("edge_match_fade_px: expected 1..128")
    yy, xx = np.indices((h, w), dtype=np.int32)
    nx, ny = np.clip(xx, x0, x0+ow-1), np.clip(yy, y0, y0+oh-1)
    distance = np.maximum(np.abs(xx-nx), np.abs(yy-ny))
    weight = np.clip(1.0-(distance-1)/fade, 0.0, 1.0)
    weight[distance == 0] = 0
    correction = original[ny-y0, nx-x0].astype(np.float32)-base[ny, nx]
    blended = np.clip(base+weight[..., None]*correction, 0, 255).round().astype(np.uint8)
    blended[y0:y0+oh, x0:x0+ow] = original
    result = Image.fromarray(blended).crop((cx, cy, cx+cw, cy+ch))
    output = project_path(root, entry["out"])
    output.parent.mkdir(parents=True, exist_ok=True)
    # Write to a sibling first: a failed SHA/budget check preserves existing art.
    temporary = output.with_name(output.name+".candidate")
    try:
        result.save(temporary, "WEBP", lossless=True, method=6)
        if temporary.stat().st_size > MAX_FILE_BYTES or digest(temporary) != entry["out_sha256"]:
            raise ValueError(f"{output}: reviewed output SHA or asset budget differs")
        with Image.open(temporary) as image:
            centre = image.convert("RGB").crop((x0-cx, y0-cy, x0-cx+ow, y0-cy+oh))
            if centre.tobytes() != original.tobytes():
                raise ValueError(f"{output}: original centre pixels changed")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return {"id": entry["id"], "out_sha256": digest(output), "centre_unchanged": True, "bytes": output.stat().st_size, "size": [cw, ch], "border_continuation_source_px_ltrb": continuation, "native_adopted": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("version") != 1:
        raise ValueError("Unsupported stage extension recipe version")
    entries = manifest["images"]
    if args.only and set(args.only)-{e["id"] for e in entries}:
        parser.error("Unknown extension ID")
    for entry in entries:
        if args.only and entry["id"] not in args.only:
            continue
        if args.prepare or args.generate:
            reference = prepare(entry)
            if args.generate:
                sys.path.insert(0, str(ROOT/"tools/comfyui"))
                from comfy_api import qwen
                if entry["batch_size"] != 1 or entry["cache_device"] != "off" or entry["resolution"] != 0 or type(entry["steps"]) is not int or not 1 <= entry["steps"] <= 50:
                    raise ValueError("Generation recipe exceeds reviewed single-image/cache-off settings")
                paths = qwen(entry["prompt"], w=entry["reference_size"][0], h=entry["reference_size"][1], resolution=entry["resolution"], steps=entry["steps"], seed=entry["seed"], images=[reference], prefix="stage_extension_"+entry["id"], retries=1, cache_device="off")
                if len(paths) != 1 or digest(paths[0]) != entry["raw_sha256"]:
                    raise ValueError("New candidate differs from reviewed raw; inspect and register separately")
                raw = project_path(ROOT, entry["raw"])
                raw.parent.mkdir(parents=True, exist_ok=True)
                raw.write_bytes(paths[0].read_bytes())
            else:
                print(reference)
                continue
        print(json.dumps(compose(entry), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"[StageExtension] {error}", file=sys.stderr)
        sys.exit(2)
