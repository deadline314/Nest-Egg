"""Repair the approved Collector gunner collar at the traced neck contacts."""

from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from part_overlap import extend_overlap
from registered_layers import write_registered_file


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


def build(root: Path) -> Image.Image:
    return extend_overlap(root / SOURCE, SOURCE_SHA256, CONTACTS)


def build_head(root: Path) -> Image.Image:
    return extend_overlap(root / HEAD_SOURCE, HEAD_SOURCE_SHA256, HEAD_CONTACTS, last_row=HEAD_LAST_SOURCE_ROW)


def _write_image(root: Path, output: Path, image: Image.Image) -> None:
    if output.resolve() in ((root / SOURCE).resolve(), (root / HEAD_SOURCE).resolve()):
        raise ValueError(f"{output}: cannot replace the approved source")
    with BytesIO() as stream:
        image.save(stream, format="PNG")
        write_registered_file(output, stream.getvalue())


def write_output(root: Path, output: Path) -> None:
    _write_image(root, output, build(root))


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="Write only the torso to this path.")
    output = parser.parse_args().out
    if output is not None:
        write_output(ROOT, output)
    else:
        torso, head = build(ROOT), build_head(ROOT)
        _write_image(ROOT, ROOT / OUTPUT, torso)
        _write_image(ROOT, ROOT / HEAD_OUTPUT, head)
