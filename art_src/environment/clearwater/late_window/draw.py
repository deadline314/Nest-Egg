"""Build the late-window exhibit with its interior shade lowered."""

from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw


SILL = Path("art/environment/scene_props/clearwater/clearwater__sill_with_coin.png")


def draw_shade(root: Path) -> Image.Image:
    with Image.open(root / SILL) as file:
        image = file.convert("RGBA")
    if image.size != (522, 240):
        raise ValueError(f"the late-window aperture was calibrated on a 522×240 texture, got {image.size}")
    draw = ImageDraw.Draw(image)
    draw.polygon([(110, 4), (406, 4), (406, 118), (110, 120)], fill="#4e5059")
    draw.polygon([(116, 9), (400, 9), (400, 108), (116, 112)], fill="#85828a")
    for top in (12, 30, 48, 66, 84):
        draw.polygon([(117, top), (399, top), (399, top + 14), (117, top + 16)], fill="#a39a91")
        draw.line([(119, top + 2), (397, top + 1)], fill="#bfb4a2", width=2)
        draw.line([(119, top + 13), (397, top + 12)], fill="#655d60", width=2)
    draw.line([(133, 12), (133, 109)], fill="#6a666a", width=3)
    draw.line([(383, 12), (383, 107)], fill="#6a666a", width=3)
    draw.polygon([(111, 111), (405, 108), (405, 117), (111, 121)], fill="#363845")
    draw.line([(115, 112), (402, 109)], fill="#777576", width=3)
    draw.rectangle((253, 109, 263, 116), fill="#392f31")
    draw.line([(256, 111), (260, 111)], fill="#9d8878", width=2)
    return image


def build(root: Path, target: Path) -> None:
    sys.path.insert(0, str(root / "tools/assets"))
    from depth_normals import depth_normal_map

    shaded = draw_shade(root)
    with Image.open(root / SILL) as source:
        delta = ImageChops.difference(source.convert("RGB"), shaded.convert("RGB"))
    red, green, blue = delta.split()
    covered = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(lambda value: 255 if value else 0)
    normals = depth_normal_map(np.asarray(shaded).astype(np.float32) / 255, profile="flat", relief=.18, detail=.15)
    with Image.open(root / SILL.with_stem(SILL.stem + "_n")) as source:
        changed = Image.fromarray(np.rint(normals * 255).astype(np.uint8))
        normal = Image.composite(changed, source.convert("RGBA"), covered)
    with Image.open(root / SILL.with_stem(SILL.stem + "_glow")) as source:
        glow = source.convert("RGBA")
    glow.putalpha(ImageChops.subtract(glow.getchannel("A"), covered))
    shaded.save(target, optimize=True)
    normal.save(target.with_stem(target.stem + "_n"), optimize=True)
    glow.save(target.with_stem(target.stem + "_glow"), optimize=True)


if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[4]
    target = (Path(sys.argv[2]) if len(sys.argv) > 2 else
              root / "art/environment/scene_props/clearwater/clearwater__late_window_shaded.png")
    build(root, target)
