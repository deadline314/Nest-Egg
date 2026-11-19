"""Rebuild the Warden's original dark collar overlap on its existing source grid."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


SOURCE = Path("art_src/characters/warden/07_refined/torso.png")
SOURCE_SHA256 = "e51d5c2b30e481c2dd156a6b073ed6643548368d2eed5bcf13943b21e3a17477"
# These source points cover the seam traced from the original death frames.
OVERLAP = [(405, 105), (418, 105), (428, 110), (441, 117), (443, 123),
           (433, 127), (417, 121), (405, 113)]
COLLAR_SAMPLE = (412, 123)


def build(root: Path) -> Image.Image:
    source = (root / SOURCE).read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Warden collar source")
    with Image.open(BytesIO(source)) as image:
        original = image.convert("RGBA")
    pixels = np.array(original)
    matte = Image.new("L", original.size)
    ImageDraw.Draw(matte).polygon(OVERLAP, fill=255)
    coverage = cv2.GaussianBlur(np.asarray(matte), (3, 3), 0.7)
    added = coverage > pixels[:, :, 3]
    collar_color = original.getpixel(COLLAR_SAMPLE)
    if int(added.sum()) != 289 or collar_color[3] != 255:
        raise ValueError("Warden collar overlap must stay in its registered transparent margin")
    pixels[added, :3] = collar_color[:3]
    pixels[:, :, 3][added] = coverage[added]
    return Image.fromarray(pixels)


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    build(Path(__file__).resolve().parents[4]).save(arguments.out)
