"""Rebuild the fabric beneath the Enforcer collar on the approved torso grid."""

from hashlib import sha256
from io import BytesIO
from math import pi, sin
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image


SOURCE = Path(__file__).with_name("torso-before.png")
SOURCE_SHA256 = "51400f87e78cd0e375a22a2d5a4182f8a644bc3f63dd3668d761e73706875669"
OUTPUT = SOURCE.parent.parent / "overrides/torso.png"


def main() -> None:
    content = SOURCE.read_bytes()
    if sha256(content).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Enforcer torso grid")
    with Image.open(BytesIO(content)) as image:
        original = np.asarray(image.convert("RGBA"))
    patched = original.copy()
    # Join the existing fabric edges where the chest plate closes the open cutout.
    for row in range(90, 117):
        opaque_columns = np.flatnonzero(original[row, 180:239, 3] >= 235)
        if opaque_columns.size:
            span = patched[row, 180:181 + opaque_columns[-1]]
            span[span[:, 3] < 235] = original[row, 177]
    # Carry the shaded side seam under the lower edge of the chest plate.
    for row in range(223, 254):
        shift = round(7 * max(0.0, sin(pi * (row - 223) / 30)) ** 0.65)
        margin = patched[row, 236:250]
        extension = original[row, 236 - shift:250 - shift]
        replace = (margin[:, 3] < 235) & (extension[:, 3] > margin[:, 3])
        margin[replace] = extension[replace]
    # Keep the lining behind the raised forearm when the shield is lifted.
    for row in range(72, 101):
        shift = round(12 * max(0.0, sin(pi * (row - 72) / 28)) ** 0.6)
        margin = patched[row, 220:244]
        extension = patched[row, 220 - shift:244 - shift]
        replace = (margin[:, 3] < 235) & (extension[:, 3] > margin[:, 3])
        margin[replace] = extension[replace]
    # Feather the lining behind the collar at the upper aim angle.
    patched[115, 229:231, :3] = patched[114, 229:231, :3]
    patched[115, 229:231, 3] = 80
    # Preserve the fabric overlap at the shoulder through the fall.
    for row, left, right in ((25, 41, 43), (26, 40, 44), (27, 40, 44), (28, 41, 43), (29, 42, 43)):
        for column in range(left, right + 1):
            opacity = 150 if 41 <= column <= 43 and 26 <= row <= 27 else 98
            if opacity > patched[row, column, 3]:
                patched[row, column, :3] = patched[row, 46, :3]
                patched[row, column, 3] = opacity
    if np.count_nonzero(np.any(patched != original, axis=2)) != 1162:
        raise ValueError("Enforcer collar overlap has drifted from the registered torso grid")
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
