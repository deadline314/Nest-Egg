"""Rebuild Ali's approved raised collar and seated shoulder overlap."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
import sys

import numpy as np
from scipy.ndimage import distance_transform_edt


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from part_overlap import approved_pixels, extend_pixels
from registered_layers import write_registered_file


SOURCE_SHA256 = "99cfbbf2c9dfba1bd28a7a75e4dfe8935ba89a5923eea9e19ab9e93c9305d718"
COLLAR_PIXELS_SHA256 = "c66ac558f33c97139301943fc6530be30dc4391a2ddc80fd1ab238b0e9d29a07"
# NE-250's approved raised-sleeve positions in the original illustration.
COLLAR_REGIONS = (
    (428, 431, 199, 203), (429, 432, 196, 199), (429, 432, 197, 200),
    (434, 437, 198, 201), (436, 439, 196, 199), (444, 447, 195, 198),
)
SEATED_CONTACT = ((434.1, 194.0, 1.55),)


def build(work: Path) -> bytes:
    source = work / "07_refined/torso.png"
    original = approved_pixels(source, SOURCE_SHA256)
    alpha = original[:, :, 3]
    distances, (source_y, source_x) = distance_transform_edt(alpha < 210, return_indices=True)
    collar = original.copy()
    for left, right, top, bottom in COLLAR_REGIONS:
        region = np.s_[top:bottom, left:right]
        replace = (alpha[region] < 128) & (distances[region] < 8)
        local = collar[region]
        local[replace] = original[source_y[region][replace], source_x[region][replace]]
    if sha256(collar.tobytes()).hexdigest() != COLLAR_PIXELS_SHA256:
        raise ValueError(f"{source}: reconstructed raised sleeve differs from the approved pixels")
    del distances, source_y, source_x
    with BytesIO() as out:
        extend_pixels(collar, SEATED_CONTACT).save(out, format="PNG")
        return out.getvalue()


if __name__ == "__main__":
    work = Path(__file__).resolve().parents[1]
    write_registered_file(work / "overrides/refined/torso.png", build(work))
