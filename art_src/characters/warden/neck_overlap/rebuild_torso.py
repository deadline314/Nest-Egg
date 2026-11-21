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
    if np.count_nonzero(np.any(patched != original, axis=2)) != 1515:
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
