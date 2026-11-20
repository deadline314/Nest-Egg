"""Extend the approved Sweeper collar along the traced helmet contacts."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt


SOURCE = Path("art_src/characters/sweeper/07_refined/torso.png")
SOURCE_SHA256 = "36459d05e41933e8da29dd5b4ead3998263abeacdba7a805cab54c005a0e91a2"
OUTPUT = Path("art_src/characters/sweeper/overrides/refined/torso.png")
BACK_COLLAR = (357, 146, 385, 170)
FRONT_COLLAR = (423, 211, 455, 234)
FALL_CONTACTS = ((440.32, 217.75), (447.49, 224.05))


def build(root: Path) -> Image.Image:
    content = (root / SOURCE).read_bytes()
    if sha256(content).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Sweeper torso")
    with Image.open(BytesIO(content)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    alpha = original[:, :, 3]
    distance, (source_y, source_x) = distance_transform_edt(alpha < 128, return_indices=True)
    for x0, y0, x1, y1 in (BACK_COLLAR, FRONT_COLLAR):
        region = np.s_[y0:y1, x0:x1]
        reach = 6.5
        if (x0, y0, x1, y1) == FRONT_COLLAR:
            # Taper the lining around the two early-fall contacts so the shoulder contour stays open.
            y, x = np.ogrid[y0:y1, x0:x1]
            nearest = np.minimum(*(np.hypot(x - cx, y - cy) for cx, cy in FALL_CONTACTS))
            reach += 3.0 * np.clip(1.0 - nearest / 9.0, 0.0, 1.0)
        coverage = np.clip((reach - distance[region]) * 255.0, 0, 255).astype(np.uint8)
        selected = (coverage > alpha[region]) & (alpha[region] < 128)
        collar = result[region]
        collar[selected, :3] = original[source_y[region][selected], source_x[region][selected], :3]
        collar[selected, 3] = coverage[selected]
    if np.count_nonzero(np.any(result != original, axis=2)) != 439:
        raise ValueError(f"{SOURCE}: collar overlap differs from the traced source")
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
