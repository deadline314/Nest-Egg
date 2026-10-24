"""Reconstruct the coat hidden under Old K's separately animated upper arm.

Only RGB inside the frozen shoulder mask is adopted. Alpha, registration and
all other body parts retain their original source. Run from any directory.
"""
from pathlib import Path
import hashlib
import json
import sys

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part


def rebuild():
    manifest = json.loads((HERE / "provenance.json").read_text())
    for relative, expected in manifest["inputs"].items():
        path = ROOT / relative
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Source changed; review registration before rebuilding: {relative}")
    spec = json.loads((ROOT / "tools/comfyui/specs/old_k_side.json").read_text())
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.array(point, float) * scale for name, point in spec["joints"].items()}
    source = Image.open(HERE / "reference/torso-source.png").convert("RGBA")
    original = np.array(source)
    reference = np.array(Image.open(HERE / "reference/torso-runtime.png").convert("RGBA"))
    generated = np.array(Image.open(HERE / "raw/torso-generated.png").convert("RGBA"))
    transform = part_transform(source, spec["parts"]["torso"], joints, scale)
    if not np.array_equal(render_part(source, transform, scale), reference):
        raise ValueError("Original source no longer reproduces the frozen runtime reference")
    matrix, width, height, pivot = transform
    if [width, height] != [241, 334] or not np.allclose(pivot, [122.79, 306.17], atol=.005):
        raise ValueError("Torso registration changed")
    yy, xx = np.indices(original.shape[:2], dtype=np.float32)
    rx = (xx + .5) * scale - .5 - matrix[0, 2]
    ry = (yy + .5) * scale - .5 - matrix[1, 2]
    mask = cv2.remap(np.array(Image.open(HERE / "shoulder-mask.png")), rx, ry,
                     cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT) > 0
    mask &= original[:, :, 3] > 0
    sample = cv2.remap(generated,
                       (rx + .5) * generated.shape[1] / width - .5,
                       (ry + .5) * generated.shape[0] / height - .5,
                       cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    # The generated opaque coat has alpha 250. Its alpha is never adopted.
    if sample[:, :, 3][mask].min() < 250:
        raise ValueError("Generated coat does not cover the entire selected source region")
    result = original.copy()
    result[:, :, :3][mask] = sample[:, :, :3][mask]
    if not np.array_equal(result[:, :, 3], original[:, :, 3]) or not np.array_equal(result[~mask], original[~mask]):
        raise ValueError("Source repair escaped the registered RGB mask")
    output = ROOT / "art_src/characters/old_k/overrides/refined/torso.png"
    if output.exists() and not np.array_equal(np.array(Image.open(output)), result):
        raise ValueError(f"Refusing to replace a different source override: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(result).save(output)
    print(f"Old K torso source rebuilt: {int(mask.sum())} source pixels; original alpha retained")
    return result, transform, scale


if __name__ == "__main__":
    rebuild()
