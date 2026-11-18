"""Rerender the folded raincoat, loose hood and pear-soup bowl."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from depth_normals import depth_normal_map

OUTPUT = Path(__file__).resolve().parents[2] / "art/environment/scene_props/guest_book_contacts/chen_soup_props.png"


def build(path: Path) -> None:
    image = Image.new('RGBA', (128, 96))
    d = ImageDraw.Draw(image)
    d.polygon([(4, 31), (13, 23), (24, 13), (56, 12), (72, 19), (77, 36), (69, 42), (12, 43)], fill='#172329')
    d.polygon([(7, 31), (24, 15), (56, 14), (70, 20), (73, 31), (50, 36), (24, 34), (10, 38)], fill='#40565b')
    d.polygon([(10, 38), (28, 34), (49, 37), (72, 32), (69, 40), (12, 41)], fill='#304148')
    d.line([(12, 33), (28, 21), (49, 22), (56, 28), (69, 24)], fill='#678079', width=2)
    d.line([(15, 37), (35, 31), (55, 33), (69, 29)], fill='#253139', width=2)
    d.line([(24, 19), (41, 15), (54, 16)], fill='#9b9582', width=1)

    d.polygon([(87, 26), (89, 15), (96, 7), (109, 3), (120, 7), (124, 18), (119, 28), (109, 35), (98, 34)], fill='#17252b')
    d.polygon([(90, 25), (96, 11), (110, 5), (119, 9), (121, 17), (115, 26), (109, 32), (99, 30)], fill='#547070')
    d.polygon([(96, 26), (101, 15), (113, 12), (117, 16), (113, 24), (106, 29)], fill='#27383e')
    d.line([(92, 23), (97, 13), (108, 7), (117, 9)], fill='#90a296', width=2)
    d.line([(98, 31), (108, 33), (117, 26)], fill='#a5987a', width=1)

    d.polygon([(3, 63), (8, 59), (76, 59), (82, 64), (76, 77), (65, 86), (59, 91), (26, 91), (18, 87), (8, 76)], fill='#544238')
    d.polygon([(6, 65), (13, 63), (72, 63), (78, 65), (74, 75), (64, 84), (58, 88), (27, 88), (20, 84), (12, 75)], fill='#d7c6af')
    d.polygon([(12, 72), (26, 75), (58, 76), (73, 72), (67, 81), (58, 86), (27, 86), (21, 82)], fill='#b1a18d')
    d.ellipse([3, 53, 81, 72], fill='#6b5347')
    d.ellipse([5, 54, 79, 70], fill='#e8d2af')
    d.ellipse([11, 57, 74, 68], fill='#a87844')
    d.arc([13, 58, 72, 67], 187, 340, fill='#d9ad68', width=2)
    d.polygon([(24, 62), (33, 59), (38, 62), (34, 64)], fill='#e1b980')
    d.polygon([(49, 62), (55, 59), (62, 61), (58, 64)], fill='#edd198')

    for x, y in ((96, 15), (109, 33), (34, 77), (43, 91)):
        assert image.getpixel((x, y))[3] == 255
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    pixels = np.asarray(image, dtype=np.float32) / 255
    normals = depth_normal_map(pixels, profile="flat", relief=.2, detail=0.0)
    Image.fromarray(np.rint(normals * 255).astype(np.uint8)).save(path.with_stem(path.stem + "_n"))


if __name__ == "__main__":
    build(OUTPUT)
