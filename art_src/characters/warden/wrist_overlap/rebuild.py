"""Extend the original glove beneath the Warden's cuff on the issued texture grid."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from math import pi, sin
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image


SOURCE = Path(__file__).with_name("hand-before.png")
SOURCE_SHA256 = "64c7d3b601f5d52e1c5b5b831b881cee90e919a3943bd9bbb17b8aecf2bc729e"
DEFAULT_OUTPUT = SOURCE.parent.parent / "overrides/hand.png"
TOP, BOTTOM = 124, 206


def build() -> Image.Image:
    content = SOURCE.read_bytes()
    if sha256(content).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the original Warden glove on its issued grid")
    with Image.open(BytesIO(content)) as source:
        original = np.asarray(source.convert("RGBA"))
    candidate = original.copy()
    # Carry the original cuff color into its transparent edge with a tapered overlap.
    for row in range(TOP, BOTTOM + 1):
        width = round(23 * max(0.0, sin(pi * (row - TOP) / (BOTTOM - TOP))) ** 0.45)
        margin = candidate[row, 38:80]
        extension = original[row, 38 + width:80 + width]
        replace = (extension[:, 3] > margin[:, 3]) & (margin[:, 3] < 235)
        margin[replace] = extension[replace]
    if np.count_nonzero(np.any(candidate != original, axis=2)) != 1536:
        raise ValueError("Warden cuff overlap changed outside its registered source grid")
    return Image.fromarray(candidate)


def save(target: Path) -> None:
    if target.resolve() == SOURCE.resolve():
        raise ValueError(f"{target}: cannot replace the approved glove source")
    with BytesIO() as stream:
        build().save(stream, format="PNG")
        content = stream.getvalue()
    if target.is_file() and target.read_bytes() == content:
        return
    with NamedTemporaryFile(dir=target.parent, suffix=".png", delete=False) as output:
        temporary = Path(output.name)
        output.write(content)
    try:
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    save(parser.parse_args().out)
