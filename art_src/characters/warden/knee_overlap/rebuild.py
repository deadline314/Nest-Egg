"""Recreate the Warden's thigh overlap under the original front knee."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image

SOURCE_SHA256 = "619af3ee2e005b8c2f28e1839f3c31ad17c38665850dfbcfa8847f8a2afc8eb4"


def build(work: Path) -> Image.Image:
    path = work / "07_refined/leg_upper.png"
    source = path.read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{path}: expected the approved Warden thigh source")
    with Image.open(BytesIO(source)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    # Only the left edge of the thigh at the traced crouch and jump contact.
    for row in range(735, 748):
        reach = round(5 * min(1.0, min(row - 735, 747 - row) / 3.0))
        edge = result[row, 346:356]
        extension = original[row, 346 + reach:356 + reach]
        replace = extension[:, 3] > edge[:, 3]
        edge[replace] = extension[replace]
    if np.count_nonzero(np.any(result != original, axis=2)) != 51:
        raise ValueError("Warden knee overlap has drifted from its traced source grid")
    return Image.fromarray(result)


def install(work: Path) -> None:
    target = work / "overrides/refined/leg_upper.png"
    with BytesIO() as stream:
        build(work).save(stream, format="PNG")
        content = stream.getvalue()
    if target.is_file() and target.read_bytes() == content:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=target.parent, suffix=".png", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    install(Path(__file__).resolve().parents[1])
