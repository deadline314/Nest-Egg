"""Render the pinned CC0 pear as a lit stage contact texture, with its normal map."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

import build_props
import texture_import

ROOT = Path(__file__).resolve().parents[2]
RECIPE = ROOT / "assets_src/pipeline/guest_pear.json"
OUT = ROOT / "art/environment/scene_props/guest_book_contacts"


def main() -> int:
    entries = json.loads(RECIPE.read_text(encoding="utf-8"))["props"]
    if not build_props.render(entries):
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        pid = entry["id"]
        color, normal, _ = build_props.load_passes(entry)
        if color.size != normal.size or color.getchannel("A").getextrema() != (0, 255):
            raise ValueError(f"{pid}: expected matching render passes with a transparent silhouette")
        pixels = np.asarray(color).astype(np.float32) / 255
        pixels[..., :3] = build_props.grade(pixels[..., :3], entry["grade"])
        Image.fromarray(np.rint(pixels * 255).astype(np.uint8)).save(OUT / f"{pid}.png")
        normal.save(OUT / f"{pid}_n.png")
    texture_import.ART = OUT
    return texture_import.finish_pipeline(0)


if __name__ == "__main__":
    raise SystemExit(main())
