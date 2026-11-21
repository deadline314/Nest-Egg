"""Rebuild the Warden helmet's guard-pose underlap on the registered texture grid."""

import argparse
import json
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import sys

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "art_src/characters/warden/07_refined/head.png"
SOURCE_SHA256 = "7e8d39403c36f30e806daa54dec41172f2cae775df690e99b30bb0fddf0b7083"


def build() -> Image.Image:
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    from cut_layers import part_transform, render_part

    source = SOURCE.read_bytes()
    if sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError(f"{SOURCE}: expected the approved Warden helmet source")
    spec = json.loads((ROOT / "tools/comfyui/specs/warden_side.json").read_text(encoding="utf-8"))
    part = spec["parts"]["head"]
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.array(point, dtype=float) * scale for name, point in spec["joints"].items()}
    with Image.open(BytesIO(source)) as image:
        head = image.convert("RGBA")
    transform = part_transform(head, part, joints, scale)
    original = render_part(head, transform, scale, crop_phase=part.get("crop_phase"))
    if original.shape != (235, 214, 4):
        raise ValueError("Warden helmet crop has drifted from its registered size")
    result = original.copy()
    # Carry the dark lining a little farther behind the raised shoulder.
    result[140, 12, :3] = original[140, 16, :3]
    result[140, 12, 3] = 82
    result[141:146, 11:13, :3] = original[141:146, 16:17, :3]
    result[141:146, 11:13, 3] = [82, 125]
    margin = result[146:150, 10:14]
    alpha = np.array([133, 190, 190, 190], dtype=np.uint8)
    extend = margin[:, :, 3] < alpha
    lining = np.broadcast_to(original[146:150, 16:17, :3], margin[:, :, :3].shape)
    margin[:, :, :3][extend] = lining[extend]
    margin[:, :, 3] = np.maximum(margin[:, :, 3], alpha)
    # Continue the same lining across the two neighboring contacts as the helmet falls.
    for row, first, coverage, donor in ((151, 15, (72, 145), 17), (152, 16, (80,), 17),
                                         (152, 18, (135, 135), 21), (153, 19, (81,), 21)):
        edge = result[row, first:first + len(coverage)]
        edge[:, :3] = original[row, donor, :3]
        edge[:, 3] = coverage
    changed = np.any(result != original, axis=2)
    if np.count_nonzero(changed) != 32 or np.any(result[:, :, 3] < original[:, :, 3]):
        raise ValueError("Warden helmet underlap has drifted from its traced source grid")
    return Image.fromarray(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    output = parser.parse_args().out
    if output.resolve() == SOURCE.resolve():
        raise ValueError(f"{output}: cannot replace the approved source")
    build().save(output)
