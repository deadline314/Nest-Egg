"""Rebuild adopted story prop states from immutable, hash-checked sources.

Generation is intentionally separate. This tool never redraws or edits source
colors; it copies the selected artifact and derives the standard silhouette normal.
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
