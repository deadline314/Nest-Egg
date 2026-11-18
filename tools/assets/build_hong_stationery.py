"""Draw original guest-room stationery at source pixel resolution."""
from pathlib import Path

from PIL import Image, ImageDraw
import numpy as np

from depth_normals import depth_normal_map

OUTPUT = Path(__file__).resolve().parents[2] / "art/environment/scene_props/guest_book_contacts/hong_stationery.png"


def build(path: Path) -> None:
    image = Image.new('RGBA', (128, 64))
    draw = ImageDraw.Draw(image)
    # Fountain pen, paper and open envelope share a single padded atlas.
    draw.polygon([(5, 32), (13, 23), (46, 4), (55, 3), (59, 7), (56, 12), (21, 29), (8, 34)], fill='#161a24')
    draw.polygon([(14, 24), (48, 5), (55, 5), (56, 8), (19, 28)], fill='#334857')
    draw.line([(23, 21), (50, 6)], fill='#78979f', width=2)
    draw.polygon([(5, 32), (13, 25), (18, 26), (10, 31)], fill='#d3a86d')
    draw.line([(44, 6), (47, 13)], fill='#737357', width=2)

    draw.polygon([(69, 11), (115, 8), (124, 27), (120, 30), (68, 30), (66, 27)], fill='#523a2e')
    draw.polygon([(69, 12), (114, 9), (121, 26), (68, 28)], fill='#e2c597')
    draw.line([(70, 12), (115, 10)], fill='#f2d9af', width=2)
    draw.line([(74, 20), (112, 17)], fill='#987e63', width=1)
    draw.line([(75, 24), (115, 21)], fill='#ad9172', width=1)

    draw.polygon([(3, 59), (6, 48), (22, 39), (65, 39), (77, 49), (75, 59), (69, 61), (6, 61)], fill='#593b2d')
    draw.polygon([(7, 49), (23, 40), (64, 40), (74, 49), (66, 54), (16, 54)], fill='#b18358')
    draw.polygon([(7, 51), (38, 54), (73, 50), (72, 59), (7, 60)], fill='#d1a674')
    draw.line([(7, 59), (26, 53), (53, 53), (71, 58)], fill='#aa7d53', width=1)
    draw.line([(88, 44), (94, 44), (102, 42), (115, 42)], fill='#34404d', width=2)

    for point in ((22, 23), (5, 32), (64 + 6, 27), (67, 36 + 16)):
        assert image.getpixel(point)[3] == 255, point
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    pixels = np.asarray(image, dtype=np.float32) / 255
    normals = depth_normal_map(pixels, profile="flat", relief=.15, detail=0.0)
    Image.fromarray(np.rint(normals * 255).astype(np.uint8)).save(path.with_stem(path.stem + "_n"))


if __name__ == "__main__":
    build(OUTPUT)
