"""Draw the safety alcove chair and its removable yellow umbrella."""

from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw


def draw_chair(umbrella: bool) -> Image.Image:
    image = Image.new("RGBA", (128, 112))
    draw = ImageDraw.Draw(image)
    ink = "#211917"
    wood = "#593e32"
    edge = "#8d6651"
    metal = "#42454a"

    draw.polygon([(48, 14), (98, 14), (101, 20), (99, 65), (94, 65), (93, 28),
                  (53, 28), (53, 66), (46, 66), (44, 21)], fill=ink)
    draw.polygon([(48, 17), (96, 17), (97, 22), (96, 61), (94, 61), (95, 25),
                  (50, 25), (50, 62), (47, 62), (47, 22)], fill=wood)
    draw.line([(48, 18), (94, 18)], fill=edge, width=2)
    for x in (51, 92):
        draw.rectangle((x, 20, x + 2, 23), fill=metal)

    draw.polygon([(48, 63), (56, 64), (53, 111), (44, 111)], fill=ink)
    draw.polygon([(88, 64), (96, 63), (101, 111), (92, 111)], fill=ink)
    draw.line([(51, 68), (48, 108)], fill=wood, width=3)
    draw.line([(92, 68), (97, 108)], fill=wood, width=3)
    draw.polygon([(41, 61), (98, 61), (107, 65), (106, 72), (40, 72), (36, 68)], fill=ink)
    draw.polygon([(41, 63), (98, 63), (103, 66), (101, 68), (41, 68), (39, 67)], fill=wood)
    draw.line([(44, 63), (97, 63)], fill=edge)
    draw.polygon([(20, 108), (117, 108), (121, 110), (121, 111), (19, 111)], fill=ink)
    draw.line([(28, 108), (115, 108)], fill=edge, width=2)
    draw.line([(31, 110), (111, 110)], fill=metal)

    if umbrella:
        draw.line([(31, 40), (30, 35), (25, 32), (20, 34), (20, 40), (24, 44),
                   (26, 48), (12, 106)], fill=ink, width=7, joint="curve")
        draw.line([(30, 39), (29, 35), (25, 34), (22, 35), (22, 40), (26, 44)],
                  fill=edge, width=3, joint="curve")
        draw.polygon([(23, 47), (30, 45), (33, 57), (29, 70), (20, 90), (13, 106),
                      (7, 105), (8, 91), (10, 67), (17, 51)], fill=ink)
        draw.polygon([(23, 50), (28, 48), (30, 57), (26, 70), (18, 89), (12, 103),
                      (9, 102), (11, 91), (13, 68), (19, 53)], fill="#ac7c2c")
        draw.polygon([(22, 51), (27, 50), (25, 66), (21, 80), (12, 101), (16, 70)], fill="#d9ae46")
        draw.line([(19, 52), (15, 68), (12, 93)], fill="#e7c361", width=2)
        draw.polygon([(15, 69), (26, 72), (24, 77), (14, 74)], fill=wood)
        draw.line([(16, 70), (24, 72)], fill=edge)
        draw.polygon([(17, 80), (19, 80), (19, 82), (21, 82), (21, 84), (18, 84),
                      (17, 87), (15, 87), (16, 84), (14, 83), (14, 81), (17, 81)], fill="#526f65")
        draw.line([(12, 102), (10, 110)], fill=ink, width=3)
        draw.point((10, 110), fill=metal)
    return image


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    sys.path.insert(0, str(root / "tools/assets"))
    from depth_normals import depth_normal_map

    textures = root / "art/environment/scene_props/yong_hideout"
    for suffix, umbrella in (("chair_umbrella", True), ("chair_empty", False)):
        image = draw_chair(umbrella)
        target = textures / f"yong_hideout__xiaowei_{suffix}.png"
        image.save(target, optimize=True)
        normal = depth_normal_map(np.asarray(image).astype(np.float32) / 255, profile="flat", relief=0.2, detail=0.0)
        Image.fromarray(np.rint(normal * 255).astype(np.uint8)).save(target.with_stem(target.stem + "_n"), optimize=True)
