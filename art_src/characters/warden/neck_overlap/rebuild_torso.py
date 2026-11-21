"""Rebuild the Warden's fabric overlap below the upper chest plate."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image


SOURCE = Path(__file__).with_name("torso-before.png")
SOURCE_SHA256 = "2a3953222f9a6152d12591ef34234d7bf6d80ba32b850b90b508db349d390796"
OUTPUT = SOURCE.parent.parent / "overrides/torso.png"


def main() -> None:
    source = SOURCE.read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Warden torso grid")
    with Image.open(BytesIO(source)) as image:
        original = np.asarray(image.convert("RGBA"))
    patched = original.copy()
    # Taper the overlap along the upper plate and the fold that opens during defeat.
    for row in range(109, 158):
        end = 376 - max(0, 114 - row) * 3 - max(0, row - 137) * 3
        span = patched[row, 316:end]
        span[span[:, 3] < 235] = original[row, 314]
    # Carry the dark fabric under the slanted plate through the hit reaction.
    rows = (132, 136, 142, 151, 156, 166, 172)
    columns = (370, 376, 376, 398, 404, 422, 426)
    for row in range(rows[0], rows[-1] + 1):
        center = np.interp(row, rows, columns)
        width = min(10, (row - rows[0] + 1) * 2, (rows[-1] - row + 1) * 2)
        left = width + max(0, 5 - abs(row - 151))
        for column in range(int(center - left), int(center + width) + 1):
            reach = left if column < center else width
            opacity = round(220 * min(1, (reach + 1 - abs(column - center)) / 2))
            if opacity > patched[row, column, 3]:
                patched[row, column, :3] = original[row, 314, :3]
                patched[row, column, 3] = opacity
    # Add two tapered returns under the collar where it opens while running or guarding.
    for x, y, half_width, half_height, strength in ((355, 145, 8, 5, 200), (337, 151, 9, 7, 215)):
        for row in range(y - half_height, y + half_height + 1):
            width = half_width * (1 - ((row - y) / half_height) ** 2) ** 0.5
            for column in range(int(x - width), int(x + width) + 1):
                opacity = round(strength * min(1, (width + 1 - abs(column - x)) / 2))
                if opacity > patched[row, column, 3]:
                    patched[row, column, :3] = original[row, 314, :3]
                    patched[row, column, 3] = opacity
    if np.count_nonzero(np.any(patched != original, axis=2)) != 2271:
        raise ValueError("Warden chest overlap has drifted from the registered torso grid")
    with BytesIO() as stream:
        Image.fromarray(patched).save(stream, format="PNG")
        content = stream.getvalue()
    if OUTPUT.is_file() and OUTPUT.read_bytes() == content:
        return
    with NamedTemporaryFile(dir=OUTPUT.parent, suffix=".png", delete=False) as output:
        temporary = Path(output.name)
    try:
        temporary.write_bytes(content)
        temporary.replace(OUTPUT)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
