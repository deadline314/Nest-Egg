"""Restore the heavy gunner's collar edge from the approved torso layer."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image


SOURCE = Path("art_src/characters/heavy_gunner/07_refined/torso.png")
SOURCE_SHA256 = "fad177f8c8f76bc3647c61eaa79c266664db106e480f892c6d81958c92c188df"
FIRST_COLUMN = 390
LAST_COLUMN = 488
TOP_ROW = 90
BOTTOM_ROW = 170


def build(root: Path) -> Image.Image:
    source = (root / SOURCE).read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved heavy gunner torso source")
    with Image.open(BytesIO(source)) as image:
        original = np.array(image.convert("RGBA"))
    result = original.copy()
    for column in range(FIRST_COLUMN, LAST_COLUMN + 1):
        edge = original[TOP_ROW:BOTTOM_ROW, column]
        solid = np.flatnonzero(edge[:, 3] >= 128)
        # Local hems traced from the back-tilt and upward-aim frames.
        depth = 8 + 4 * max(0, 1 - abs(column - 416) / 17) + 6 * max(0, 1 - abs(column - 473) / 14)
        taper = min(1, (column - FIRST_COLUMN) / 8, (LAST_COLUMN - column) / 8)
        reach = round(depth * taper)
        if reach == 0:
            continue
        target_rows = solid[0] - np.arange(-2, reach + 4)
        source_rows = target_rows + reach
        selected = edge[source_rows, 3] > edge[target_rows, 3]
        source_pixels = edge[source_rows[selected]]
        target = result[TOP_ROW:BOTTOM_ROW, column]
        target[target_rows[selected], :3] = np.minimum(source_pixels[:, :3], 100)
        target[target_rows[selected], 3] = source_pixels[:, 3]
    if np.count_nonzero(np.any(result != original, axis=2)) != 942:
        raise ValueError("Heavy gunner collar coverage has drifted from the traced source grid")
    return Image.fromarray(result)


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    build(root).save(arguments.out)
