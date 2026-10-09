"""Replay the reviewed near-side hand and single boot without repainting the source."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from refine_parts import components

SOURCE_SHA = "ba9af5139d225d492019c24c261bcd1ba9387d1bca7d10e7fd0fa3f5f1931bf3"
MASKS = {
    "hand": ("near_hand", "mask-source.json", "32462c3a380bc3ff7a7c43891e248a7a61d9f3441bacdae0fb610c66411762c2"),
    "foot": ("near_foot", "foot-mask-source.json", "f72640cc2736ce50335a8c719e4362e3bac6e0eecd9513c30e12e5e6ef709a85"),
}


def checked_image(path, digest, mode):
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"Source hash changed: {path}")
    with Image.open(path) as image:
        if image.size != (832, 1216) or image.mode != mode:
            raise ValueError(f"Expected native {mode} 832x1216: {path}")
        return np.array(image)


def rebuild(work):
    source = checked_image(HERE.parent / "base_rgba.png", SOURCE_SHA, "RGBA")
    outputs = {}
    for part, (name, record, digest) in MASKS.items():
        mask = checked_image(HERE / (name + ".png"), digest, "RGB")[:, :, 0]
        if set(np.unique(mask)) != {0, 255}:
            raise ValueError(f"Expected reviewed binary mask: {name}")
        points = json.loads((HERE / record).read_text(encoding="utf8"))["points"][name]
        assert all(mask[y, x] == 255 for x, y in points["pos"])
        assert all(mask[y, x] == 0 for x, y in points["neg"])
        owned = components((mask > 127) & (source[:, :, 3] >= 40), 30)
        pixels = source.copy()
        pixels[:, :, 3][~owned] = 0
        pixels[:, :, :3][~owned] = 0
        assert owned.sum() > 150 and np.array_equal(pixels[owned], source[owned])
        assert not owned[:20].any() and not owned[-20:].any()
        outputs[part] = pixels
    target = work / "overrides/refined"
    target.mkdir(parents=True, exist_ok=True)
    for part, pixels in outputs.items():
        temporary = target / (part + ".tmp.png")
        Image.fromarray(pixels).save(temporary)
        temporary.replace(target / (part + ".png"))
    print("Rebuilt reviewed near hand and single boot; source colors unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=HERE.parent)
    rebuild(parser.parse_args().work)
