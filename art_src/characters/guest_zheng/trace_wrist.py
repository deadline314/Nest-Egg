"""Map actual rendered wrist-hole pixel centres back through captured geometry to source.

This diagnosis changes no image, sampling band or verdict. Run after a short
rig_joint_audit --trace-joint=wrist_back capture, whose source bytes are archived.
"""
import json
from pathlib import Path
import sys
import hashlib

import numpy as np
from PIL import Image
from scipy.ndimage import binary_fill_holes

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/comfyui"))


def uv_points(data, point):
    matrix = np.vstack((np.asarray(data["to_cell"]), [0, 0, 1]))
    local = (np.linalg.inv(matrix) @ [*point, 1])[:2]
    if "rect_origin" in data:
        uv = local - data["rect_origin"]
        # Sprite geometry ends at its rectangle; clamp sampling outside that
        # quad would invent a material observation where no fragment exists.
        return [uv] if ((uv >= 0) & (uv < data["size"])).all() else []
    result = []
    for indices in data["triangles"]:
        a, b, c = np.asarray(data["vertices"])[indices]
        weights = np.linalg.solve(np.column_stack((b - a, c - a)), local - a)
        if (weights >= -1e-6).all() and weights.sum() <= 1 + 1e-6:
            a, b, c = np.asarray(data["uv"])[indices]
            result.append(a + weights[0] * (b - a) + weights[1] * (c - a))
    return result


def main():
    folder = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs" / sys.argv[1]
    groups = json.loads((folder / "frames.json").read_text(encoding="utf8"))
    hashes = json.loads((folder.parent / (folder.name + "-source-hashes.json")).read_text(encoding="utf8"))["before"]
    # Refuse to reinterpret an old renderer capture using today's changed crop.
    registration_path = ROOT / "art_src/characters/guest_zheng/cut_registration.json"
    expected = hashes.get(registration_path.relative_to(ROOT).as_posix())
    if expected != hashlib.sha256(registration_path.read_bytes()).hexdigest():
        raise ValueError("This trace lacks the matching frozen cut registration; retain its original saved mapping, or restore the matching source ZIP")
    registrations = json.loads(registration_path.read_text(encoding="utf8"))
    results = []
    for group in groups:
        if group["pose"] != "sit":
            continue
        image = np.array(Image.open(folder / group["samples"][0]["file"]))
        for cell in group["cells"]:
            x, y, w, h = cell["rect"]
            alpha = image[y:y + h, x:x + w, 3] >= 128
            yy, xx = np.nonzero(binary_fill_holes(alpha) & ~alpha)
            for px, py in zip(xx, yy):
                entry = dict(pose=group["pose"], facing=cell["facing"], pixel=[int(px), int(py)], materials=[])
                for data in cell["geometry_first"]:
                    name = "arm_lower" if data["part"] == "arm_back_lower" else "hand"
                    relative = data["texture"].removeprefix("res://")
                    live = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                    if live != hashes[relative]:
                        raise ValueError("Live material differs from the frozen trace; preserve the original source-hole-mapping.json and use its source ZIP")
                    transform = np.asarray(registrations[name]["native_affine"])
                    for uv in uv_points(data, [float(px) + .5, float(py) + .5]):
                        native = transform @ [uv[0] - .5, uv[1] - .5, 1]
                        entry["materials"].append(dict(part=data["part"], uv=uv.tolist(), native=native.tolist()))
                results.append(entry)
    target = folder / "source-hole-mapping.json"
    target.write_text(json.dumps(results, indent=2), encoding="utf8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
