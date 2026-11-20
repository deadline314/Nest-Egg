"""Rebuild Egret's oilskin overlap at the traced shoulder contacts."""

from io import BytesIO
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from part_overlap import extend_overlap
from registered_layers import write_registered_file


PARTS = {
    "torso": (
        "aec3e85d1a461e20b7467832bed14aa84deb257c22503049794ff790fc7a2d9d",
        ((457.85, 176.89, 2.6), (463.59, 176.54, 2.65), (469.33, 176.20, 2.55),
         (475.07, 175.85, 2.55), (452.46, 182.98, 2.5)),
        None,
    ),
    "arm_upper": (
        "1c6df6d498a761c1547b6ec69094cdd46ce7232dc085eb489f2f3ce3377eb366",
        ((439.90, 349.43, 2.8), (438.75, 355.07, 2.7), (437.60, 360.70, 2.6),
         (436.46, 366.33, 2.4)),
        440,  # Stop at the original atlas footprint.
    ),
}


def build(work: Path) -> dict[str, bytes]:
    parts = {}
    for name, (digest, contacts, last_column) in PARTS.items():
        source = work / "07_refined" / f"{name}.png"
        image = extend_overlap(source, digest, contacts, last_column=last_column)
        with BytesIO() as stream:
            image.save(stream, format="PNG")
            parts[name] = stream.getvalue()
    return parts


if __name__ == "__main__":
    work = Path(__file__).resolve().parents[1]
    for name, data in build(work).items():
        write_registered_file(work / "overrides/refined" / f"{name}.png", data)
