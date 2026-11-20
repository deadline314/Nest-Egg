"""Repair the approved Collector gunner collar at the traced neck contacts."""

from argparse import ArgumentParser
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt


SOURCE = Path("art_src/characters/collector_gunner/07_refined/torso.png")
SOURCE_SHA256 = "1c3451b0b5199077a6ac1471b6278737773bf03e96d24ef56fc78872d0d0b8ab"
OUTPUT = Path("art_src/characters/collector_gunner/overrides/refined/torso.png")
CONTACTS = (
    (405.51,125.94,1.8), (393.33,130.99,1.8), (398.20,131.30,2.65),
)


def build(root: Path) -> Image.Image:
    content = (root / SOURCE).read_bytes()
    if sha256(content).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Collector gunner torso")
    with Image.open(BytesIO(content)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    alpha = original[:, :, 3]
    source_y, source_x = distance_transform_edt(alpha < 128, return_distances=False, return_indices=True)
    for x, y, reach in CONTACTS:
        from_x = source_x[round(y), round(x)]
        from_y = source_y[round(y), round(x)]
        left = int(min(x, from_x) - reach - 2)
        right = int(max(x, from_x) + reach + 3)
        top = int(min(y, from_y) - reach - 2)
        bottom = int(max(y, from_y) + reach + 3)
        rows, columns = np.ogrid[top:bottom, left:right]
        vx, vy = x - from_x, y - from_y
        progress = np.clip(((columns + 0.5 - from_x) * vx + (rows + 0.5 - from_y) * vy)
                           / max(vx * vx + vy * vy, 0.01), 0.0, 1.0)
        distance = np.hypot(columns + 0.5 - from_x - progress * vx,
                            rows + 0.5 - from_y - progress * vy)
        coverage = np.clip((reach - distance) * 255.0, 0.0, 255.0).astype(np.uint8)
        region = np.s_[top:bottom, left:right]
        local = result[region]
        mask = (coverage > local[:, :, 3]) & (alpha[region] < 128)
        local[mask, :3] = original[source_y[region][mask], source_x[region][mask], :3]
        local[mask, 3] = coverage[mask]
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
