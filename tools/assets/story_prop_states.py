"""Rebuild story states from immutable sources; generation stays separate.

Version 2 delegates grading/normals/imports to the shared staging producer.
Version 1 preserves the historical copy-based recipe. Neither rewrites sources.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image
from depth_normals import depth_normal_map
import texture_import

ROOT = Path(__file__).resolve().parents[2]


def build():
    recipe = json.loads((ROOT / "assets_src/pipeline/story_prop_states.json").read_text())
    if recipe["version"] == 2:
        # Keep the established entry point while sharing one canonical producer.
        from story_staging_art import build as build_staging
        ids = recipe.get("staging_ids")
        if not isinstance(ids, list) or not ids or any(not isinstance(value, str) for value in ids) or len(set(ids)) != len(ids):
            raise ValueError("Story prop delegation requires unique staging ids")
        staging = json.loads((ROOT / "assets_src/pipeline/story_staging_art.json").read_text())
        selected = [entry for entry in staging["files"] if entry.get("id") in ids]
        if len(selected) != len(ids):
            raise ValueError("Story prop delegation contains unknown staging ids")
        build_staging({"version": 1, "files": selected}, ROOT)
        return
    if recipe["version"] != 1:
        raise ValueError("Unsupported story prop recipe")
    for entry in recipe["files"]:
        source = ROOT / entry["input"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError("Story prop source changed: " + entry["input"])
        target = ROOT / entry["output"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        rgba = np.array(Image.open(source).convert("RGBA"), dtype=np.float32) / 255.0
        normal = depth_normal_map(rgba, profile="flat", round_px=6.0, relief=0.1, detail=0.0)
        Image.fromarray(np.clip(normal * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(
            target.with_name(target.stem + "_n.png"), optimize=True)
    texture_import.apply_policy()


if __name__ == "__main__":
    build()
