"""Rebuild the enforcer's concealed helmet lining from the approved alpha."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image


SOURCE = Path("art_src/characters/enforcer/07_refined/head.png")
SOURCE_SHA256 = "177072fef22a7b6c345691aced80c188d64efe6db6d6b5e03ea0b46880130793"
OUTPUT = Path("art_src/characters/enforcer/overrides/refined/head.png")
TOP_ROW = 90
BOTTOM_ROW = 170
# The two short bands cover the traced death hinge and raised-aim contacts.
OVERLAPS = ((379, 475, 4, 8), (375, 408, 7, 5), (389, 401, 10, 5), (459, 479, 8, 5))


def build(root: Path) -> Image.Image:
    source = (root / SOURCE).read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved enforcer head source")
    with Image.open(BytesIO(source)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    for column in range(min(band[0] for band in OVERLAPS), max(band[1] for band in OVERLAPS) + 1):
        reach = max(round(depth * max(0, min(1, (column-left)/taper, (right-column)/taper)))
                    for left, right, depth, taper in OVERLAPS)
        if reach == 0:
            continue
        edge = original[TOP_ROW:BOTTOM_ROW, column]
        solid = np.flatnonzero(edge[:, 3] >= 128)
        target_rows = solid[-1] + np.arange(-2, reach + 4)
        target_rows = target_rows[(target_rows >= reach) & (target_rows < len(edge))]
        source_rows = target_rows - reach
        selected = (edge[source_rows, 3] > edge[target_rows, 3]) & (TOP_ROW + target_rows >= 115)
        source_pixels = edge[source_rows[selected]]
        target = result[TOP_ROW:BOTTOM_ROW, column]
        target[target_rows[selected], :3] = np.minimum(source_pixels[:, :3], [38, 65, 96])
        target[target_rows[selected], 3] = source_pixels[:, 3]
    if np.count_nonzero(np.any(result != original, axis=2)) != 612:
        raise ValueError("Enforcer helmet overlap has drifted from its traced source grid")
    # Extend the inner helmet lining beneath the raised forearm.
    for column in range(463, 485):
        lining = result[:169, column].copy()
        reach = min(10, column - 462, 2 * (485 - column))
        edge = int(np.flatnonzero(lining[:, 3] >= 128)[-1])
        rows = np.arange(edge + 1, min(edge + 2 + reach, len(lining)))
        underlap = lining[rows - reach]
        keep = underlap[:, 3] > lining[rows, 3]
        result[rows[keep], column, :3] = np.minimum(underlap[keep, :3], [38, 65, 96])
        result[rows[keep], column, 3] = underlap[keep, 3]
    return Image.fromarray(result)


def write_output(root: Path, output: Path) -> None:
    if output.resolve() == (root / SOURCE).resolve():
        raise ValueError(f"{output}: cannot replace the approved source")
    with BytesIO() as stream:
        build(root).save(stream, format="PNG")
        content = stream.getvalue()
    if output.is_file() and output.read_bytes() == content:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=output.parent, suffix=".png", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=root / OUTPUT)
    write_output(root, parser.parse_args().out)
