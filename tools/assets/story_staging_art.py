"""Adopt frozen staging art without regenerating or overwriting its source.

Manifest controls grading, alpha cleanup and silhouette normals. Even canvas
padding makes half-resolution imports exact; authored source points stay put.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image

import grade
from depth_normals import PROFILES, depth_normal_map
import texture_import

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets_src/pipeline/story_staging_art.json"
MAX_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 4 * 1024 * 1024


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            result.update(chunk)
    return result.hexdigest()


def project_path(root: Path, value: str) -> Path:
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        raise ValueError("Asset path must be project-relative")
    path = (root / value).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as error:
        raise ValueError("Asset path escapes project: " + value) from error
    return path


def preflight(recipe: dict, root: Path) -> list[tuple[dict, Path, Path]]:
    if not isinstance(recipe, dict) or recipe.get("version") != 1 or not isinstance(recipe.get("files"), list) or not 1 <= len(recipe["files"]) <= 16:
        raise ValueError("Staging recipe requires version 1 and 1..16 files")
    jobs = []
    outputs = set()
    inputs = set()
    for entry in recipe["files"]:
        if not isinstance(entry, dict):
            raise ValueError("Staging file entry must be an object")
        source = project_path(root, entry["input"])
        target = project_path(root, entry["output"])
        try:
            target.relative_to((root / "art/environment").resolve())
        except ValueError as error:
            raise ValueError("Staging output escapes environment art: " + entry["output"]) from error
        destinations = {target, target.with_name(target.stem + "_n.png")}
        if target.suffix != ".png" or outputs.intersection(destinations):
            raise ValueError("Invalid or duplicate staging output: " + entry["output"])
        outputs.update(destinations)
        inputs.add(source)
        if source.stat().st_size > MAX_BYTES or digest(source) != entry["sha256"]:
            raise ValueError("Staging source hash or byte budget mismatch: " + entry["input"])
        with Image.open(source) as image:
            if list(image.size) != entry["size"] or image.width * image.height > MAX_PIXELS or image.mode not in ("RGB", "RGBA"):
                raise ValueError("Staging source dimensions or mode mismatch: " + entry["input"])
        floor = entry.get("alpha_floor", 0)
        if entry.get("kind") not in ("scene", "prop") or isinstance(floor, bool) or not isinstance(floor, (int, float)) or not math.isfinite(floor) or not 0 <= floor <= 32:
            raise ValueError("Invalid staging grade kind or alpha floor")
        if entry.get("emission") != "none":
            raise ValueError("This recipe only adopts non-emissive surfaces")
        if not isinstance(entry.get("pad_even", True), bool):
            raise ValueError("pad_even must be boolean")
        grading = entry.get("grade", {})
        if grade.validate({"all": grading}):
            raise ValueError("Invalid staging grade: " + entry["input"])
        numbers = [v for k, v in grading.items() if k != "tint"] + grading.get("tint", [])
        if any(isinstance(v, bool) or not math.isfinite(v) for v in numbers):
            raise ValueError("Staging grade must contain finite numbers")
        normal = entry.get("normal", {})
        if not isinstance(normal, dict) or normal.get("profile", "pillow") not in PROFILES:
            raise ValueError("Invalid staging normal profile")
        for key, value in normal.items():
            if key == "profile":
                continue
            maximum = 128 if key in ("round_px", "detail_sigma") else 8
            if key not in ("round_px", "relief", "detail", "detail_sigma", "gate", "strength") or isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= maximum:
                raise ValueError("Invalid staging normal parameter: " + str(key))
        jobs.append((entry, source, target))
    if inputs.intersection(outputs):
        raise ValueError("Staging output would overwrite a frozen input")
    return jobs


def build(recipe: dict, root: Path = ROOT, apply_import: bool = True) -> dict:
    jobs = preflight(recipe, root)  # Check every source before producing any output.
    staged = []
    receipt = {"version": 1, "files": []}
    try:
        for entry, source, target in jobs:
            with Image.open(source) as image:
                raw = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
            raw[..., :3] = grade.grade_asset(raw[..., :3], entry.get("grade", {}), entry["kind"])
            floor = float(entry.get("alpha_floor", 0)) / 255.0
            raw[..., 3] = np.clip((raw[..., 3] - floor) / (1.0 - floor), 0.0, 1.0)
            body = Image.fromarray(np.uint8(np.clip(raw * 255.0 + 0.5, 0, 255)), "RGBA")
            if entry.get("pad_even", True):
                canvas = Image.new("RGBA", ((body.width + 1) // 2 * 2, (body.height + 1) // 2 * 2))
                canvas.paste(body, (0, 0))
                body = canvas
            normal_input = np.asarray(body, dtype=np.float32) / 255.0
            normal = depth_normal_map(normal_input, **entry.get("normal", {"profile": "flat", "detail": 0.0}))
            normal_image = Image.fromarray(np.uint8(np.clip(normal * 255.0 + 0.5, 0, 255)), "RGBA")
            outputs = []
            for image, destination in ((body, target), (normal_image, target.with_name(target.stem + "_n.png"))):
                destination.parent.mkdir(parents=True, exist_ok=True)
                handle, name = tempfile.mkstemp(prefix=".staging-", suffix=".png", dir=destination.parent)
                os.close(handle)
                temporary = Path(name)
                staged.append((temporary, destination))
                image.save(temporary, "PNG", optimize=True)
                outputs.append({"file": str(destination.relative_to(root)), "size": list(image.size), "bytes": temporary.stat().st_size, "sha256": digest(temporary)})
            receipt["files"].append({"input": entry["input"], "input_sha256": entry["sha256"], "source_size": entry["size"], "canvas_size": list(body.size), "outputs": outputs, "emission": "none"})
        for temporary, destination in staged:
            os.replace(temporary, destination)
        if apply_import:
            texture_import.apply_policy()
        return receipt
    finally:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)


def main() -> int:
    try:
        recipe = json.loads(MANIFEST.read_text(encoding="utf-8"))
        receipt = build(recipe)
        output = ROOT / "assets_src/work/story_staging_art-receipt.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        for entry in receipt["files"]:
            print("STAGING_ART", entry["input"], entry["canvas_size"], entry["outputs"][0]["sha256"])
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("STAGING_ART_FAIL", error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
