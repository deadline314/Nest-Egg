"""Keep the same authored native fingertip contact when hidden wrist material changes the crop."""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part


def main():
    reference = WORK / "02_pose/hand_contact_original.json"
    original = json.loads(reference.read_text(encoding="utf8"))
    if hashlib.sha256((WORK / "base_rgba.png").read_bytes()).hexdigest() != original["base_sha256"]:
        raise ValueError("The authored native fingertip belongs to a different retained source")
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {key: np.asarray(value, float) * k for key, value in spec["joints"].items()}
    source = WORK / "07_refined/hand.png"
    image = Image.open(source)
    transform = part_transform(image, spec["parts"]["hand"], joints, k)
    affine = np.vstack((transform[0], [0, 0, 1]))
    native = np.asarray(original["native_affine_point"], float) * k
    point = (np.linalg.inv(affine) @ [*native, 1])[:2]
    pixels = render_part(image, transform, k, crop_phase=spec["parts"]["hand"].get("crop_phase"))
    x, y = np.floor(point).astype(int)
    if not (0 <= y < pixels.shape[0] and 0 <= x < pixels.shape[1] and pixels[y, x, 3] >= 128):
        raise ValueError("Registered fingertip no longer lands on actual opaque hand material")
    result = dict(classification="same original native contact, re-registered through actual cut affine",
                  original_reference=reference.relative_to(ROOT).as_posix(),
                  reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),
                  source_hand_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  native_affine_point=original["native_affine_point"], runtime_point=np.round(point, 6).tolist(),
                  runtime_size=[pixels.shape[1], pixels.shape[0]], k=k)
    (WORK / "hand_contact.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    registrations = {}
    for name, part in spec["parts"].items():
        layer_path = WORK / "07_refined" / (name + ".png")
        layer = Image.open(layer_path)
        mapping, width, height, pivot = part_transform(layer, part, joints, k)
        registrations[name] = dict(native_affine=mapping.tolist(), runtime_size=[width, height],
                                   pivot=pivot.tolist(), k=k,
                                   refined_source_sha256=hashlib.sha256(layer_path.read_bytes()).hexdigest())
    (WORK / "cut_registration.json").write_text(json.dumps(registrations, indent=2) + "\n", encoding="utf8")
    print("same native fingertip ->", result["runtime_point"], "in", result["runtime_size"])


if __name__ == "__main__":
    main()
