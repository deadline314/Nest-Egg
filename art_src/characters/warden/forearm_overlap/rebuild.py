"""Rebuild the inside edge of the Warden's issued forearm armor."""

from hashlib import sha256
from io import BytesIO
from math import pi, sin
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image


SOURCE = Path(__file__).with_name("armor_forearm-before.png")
SOURCE_SHA256 = "e39208da9b995ef332e698daac074e1c4c033c6492236228b26933669f6cf7c2"
OUTPUT = SOURCE.parent.parent / "overrides/armor_forearm.png"


def main() -> None:
    source = SOURCE.read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Warden forearm plate")
    with Image.open(BytesIO(source)) as image:
        original = np.asarray(image.convert("RGBA"))
    patched = original.copy()
    # Keep the paint under adjacent armor during the mirrored death transition.
    bands = ((90, 98, 51, 63, 14, 0.65), (84, 94, 56, 69, 12, 0.45))
    for top, bottom, left, right, depth, taper in bands:
        for row in range(top, bottom + 1):
            phase = pi * (row - top) / (bottom - top)
            shift = round(depth * max(0.0, sin(phase)) ** taper)
            margin = patched[row, left:right]
            extension = original[row, left + shift:right + shift]
            replace = (margin[:, 3] < 235) & (extension[:, 3] > margin[:, 3])
            margin[replace] = extension[replace]
    # Extend the inside edge below the glove where the arm crosses the hip.
    edge = ((258, 260), (258, 261), (258, 262), (258, 263), (259, 263), (259, 262), (259, 262),
            (260, 262), (261, 263), (260, 264), (258, 264), (258, 265), (260, 265))
    edge_alpha = []
    for row, (left, right) in enumerate(edge, 358):
        opacity = 155 if row < 366 else 185
        edge_alpha.append((row, left, right, opacity, round(0.66 * opacity)))
    # Back the cuff where the rear plate crosses the hip during the final fall.
    cuff_right = (263, 265, 266, 266, 266, 265, 265, 266, 266, 267, 267, 267, 267, 267, 266)
    edge_alpha.extend((row, 259, right, 225, 150) for row, right in enumerate(cuff_right, 357))
    for row, left, right, opacity, feathered in edge_alpha:
        alpha = np.full(right - left + 1, opacity, dtype=np.uint8)
        alpha[-1] = feathered
        margin = patched[row, left:right + 1]
        extend = alpha > margin[:, 3]
        margin[extend, :3] = original[row, 256, :3]
        margin[extend, 3] = alpha[extend]
    if np.count_nonzero(np.any(patched != original, axis=2)) != 159:
        raise ValueError("Warden forearm overlap has drifted from its registered source grid")
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
