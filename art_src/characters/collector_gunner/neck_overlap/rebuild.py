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
    (455.25,170.05,2.5), (461.55,178.56,2.15),
    (449.17,170.52,2.1), (455.11,173.93,2.3),
)


HEAD_SOURCE = Path("art_src/characters/collector_gunner/07_refined/head.png")
HEAD_SOURCE_SHA256 = "aec1c2d4ea25d6125471a0bf5c7e2fbb2be40b8a3fd45c38dd6903b3d21f7d1c"
HEAD_OUTPUT = Path("art_src/characters/collector_gunner/overrides/refined/head.png")
HEAD_CONTACTS = (
    (460.03,153.46,2.1), (462.99,158.30,2.3), (460.96,154.06,2.0),
    (454.93,156.42,2.25), (452.75,152.56,2.0),
    (435.84,147.04,2.2), (438.80,152.14,2.1), (436.34,149.57,2.15),
)
HEAD_LAST_SOURCE_ROW = 158


def _extend(root: Path, source: Path, expected: str, contacts: tuple, last_row: int | None = None) -> Image.Image:
    content = (root / source).read_bytes()
    if sha256(content).hexdigest() != expected:
        raise ValueError(f"{source}: expected the approved Collector gunner source")
    with Image.open(BytesIO(content)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    alpha = original[:, :, 3]
    source_y, source_x = distance_transform_edt(alpha < 128, return_distances=False, return_indices=True)
    for x, y, reach in contacts:
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
        if last_row is not None:
            mask &= rows <= last_row
        local[mask, :3] = original[source_y[region][mask], source_x[region][mask], :3]
        local[mask, 3] = coverage[mask]
    return Image.fromarray(result)


def build(root: Path) -> Image.Image:
    return _extend(root, SOURCE, SOURCE_SHA256, CONTACTS)


def build_head(root: Path) -> Image.Image:
    return _extend(root, HEAD_SOURCE, HEAD_SOURCE_SHA256, HEAD_CONTACTS, HEAD_LAST_SOURCE_ROW)


def _write_image(root: Path, output: Path, image: Image.Image) -> None:
    if output.resolve() in ((root / SOURCE).resolve(), (root / HEAD_SOURCE).resolve()):
        raise ValueError(f"{output}: cannot replace the approved source")
    with BytesIO() as stream:
        image.save(stream, format="PNG")
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


def write_output(root: Path, output: Path) -> None:
    _write_image(root, output, build(root))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="Write only the torso to this path.")
    output = parser.parse_args().out
    if output is not None:
        write_output(root, output)
    else:
        torso, head = build(root), build_head(root)
        _write_image(root, root / OUTPUT, torso)
        _write_image(root, root / HEAD_OUTPUT, head)
