"""Restore the lower helmet overlap from the approved enforcer head."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image


SOURCE = Path("art_src/characters/enforcer/07_refined/head.png")
SOURCE_SHA256 = "177072fef22a7b6c345691aced80c188d64efe6db6d6b5e03ea0b46880130793"
FIRST_COLUMN = 379
LAST_COLUMN = 475
TOP_ROW = 90
BOTTOM_ROW = 170


def build(root: Path) -> Image.Image:
    source = (root / SOURCE).read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved enforcer head source")
    with Image.open(BytesIO(source)) as image:
        original = np.array(image.convert("RGBA"))
    result = original.copy()
    for column in range(FIRST_COLUMN, LAST_COLUMN + 1):
        edge = original[TOP_ROW:BOTTOM_ROW, column]
        solid = np.flatnonzero(edge[:, 3] >= 128)
        taper = min(1, (column - FIRST_COLUMN) / 8, (LAST_COLUMN - column) / 8)
        reach = round(4 * taper)
        if reach == 0:
            continue
        # Extend the concealed blue rim while keeping the yellow visor above it.
        target_rows = solid[-1] + np.arange(-2, reach + 4)
        source_rows = target_rows - reach
        selected = (edge[source_rows, 3] > edge[target_rows, 3]) & (TOP_ROW + target_rows >= 115)
        source_pixels = edge[source_rows[selected]]
        target = result[TOP_ROW:BOTTOM_ROW, column]
        target[target_rows[selected], :3] = np.minimum(source_pixels[:, :3], [38, 65, 96])
        target[target_rows[selected], 3] = source_pixels[:, 3]
    if np.count_nonzero(np.any(result != original, axis=2)) != 419:
        raise ValueError("Enforcer helmet overlap has drifted from its traced source grid")
    return Image.fromarray(result)


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    build(Path(__file__).resolve().parents[4]).save(arguments.out)
