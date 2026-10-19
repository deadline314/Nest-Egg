"""Register Ali's isolated seated trouser part on her unchanged source skeleton.

CPU-only source calibration. Original standing artwork and other parts are preserved.
Call before cut_layers through recipe.source_rebuilds. --publish adds only the new
pose texture and pose metadata to the existing character, without recutting other parts.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "01_design/isolated-trousers.png"
SOURCE_SHA = "3473fbe6a478d3ee5fcc69cd5daca045bcfbddfc2a1caa2f5a402bb78e90f4a0"
HIP = np.array([300.0, 600.0])
KNEE = np.array([1270.0, 535.0])
ACROSS = 0.30


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError(f"{SOURCE}: source changed; existing delivery retained")
    for original_path, expected_sha in {'art_src/characters/ali/07_refined/pelvis.png': '5b08dffc3f6f8d3428efa9803531121f8dab9c96f30f2a48088c2c7c9281d9d1', 'art_src/characters/ali/07_refined/leg_upper.png': '25822898047eda6b3eb6621abf4ba57fbc103ebd387b7004312ddb262d82cf88', 'art_src/characters/ali/base_rgba.png': '979103f94dc470a667d109cdab830fde1dd11be2664e0ee68bebdbbd3bd31db6'}.items():
        if hashlib.sha256((ROOT / original_path).read_bytes()).hexdigest() != expected_sha:
            raise ValueError(f"{original_path}: approved source changed; seated delivery retained")
    spec = json.loads((ROOT / "tools/comfyui/specs/ali_side.json").read_text())
    pixels = np.array(Image.open(SOURCE).convert("RGBA"))
    yy, xx = np.mgrid[:pixels.shape[0], :pixels.shape[1]]
    # Waist is already supplied by the original pelvis; the knee keeps a short
    # overlap for the existing shin. No copied far leg or invented fill pixels.
    source_axis = (KNEE - HIP) / np.linalg.norm(KNEE - HIP)
    forward = (xx - HIP[0]) * source_axis[0] + (yy - HIP[1]) * source_axis[1]
    keep = (yy >= 350) & (((xx < 1190) & (yy < 740)) | (np.hypot(xx - KNEE[0], yy - KNEE[1]) <= 155)) & (pixels[:, :, 3] >= 40)
    keep &= forward <= np.linalg.norm(KNEE - HIP) + 40.0  # original shin supplies the knee's forward/lower overlap
    standing = np.array(Image.open(ROOT / "art_src/characters/ali/07_refined/leg_upper.png").convert("RGBA"))
    wanted = standing[standing[:, :, 3] > 250, :3].astype(float)
    have = pixels[keep & (pixels[:, :, 3] > 250), :3].astype(float)
    gain = wanted.mean(axis=0) / have.mean(axis=0)
    pixels[keep, :3] = (pixels[keep, :3].astype(float) * gain).clip(0, 255).round().astype(np.uint8)
    pixels[~keep] = 0
    Image.fromarray((keep * 255).astype(np.uint8)).save(HERE / "source-mask.png")
    target_hip, target_knee = (np.array(spec["joints"][key], float) for key in ["hip", "knee"])
    source_axis = (KNEE - HIP) / np.linalg.norm(KNEE - HIP)
    target_axis = (target_knee - target_hip) / np.linalg.norm(target_knee - target_hip)
    along = np.linalg.norm(target_knee - target_hip) / np.linalg.norm(KNEE - HIP)
    source_basis = np.column_stack([source_axis, [-source_axis[1], source_axis[0]]])
    target_basis = np.column_stack([target_axis * along, np.array([-target_axis[1], target_axis[0]]) * ACROSS])
    linear = target_basis @ source_basis.T
    transform = np.column_stack([linear, target_hip - linear @ HIP])
    size = Image.open(ROOT / "art_src/characters/ali/base_rgba.png").size
    premultiplied = pixels.astype(np.float32)
    premultiplied[:, :, :3] *= premultiplied[:, :, 3:] / 255.0
    out = cv2.warpAffine(premultiplied, transform, size, flags=cv2.INTER_AREA)
    alpha = out[:, :, 3:]
    out[:, :, :3] = np.where(alpha > 0, out[:, :, :3] / np.maximum(alpha, 1e-3) * 255.0, 0)
    layer = Image.fromarray(out.clip(0, 255).round().astype(np.uint8))
    target = ROOT / "art_src/characters/ali/poses/sit/leg_upper.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    layer.save(target)
    report = {"source": str(SOURCE.relative_to(ROOT)), "sha256": SOURCE_SHA,
              "source_hip": HIP.tolist(), "source_knee": KNEE.tolist(), "across": ACROSS,
              "target_hip": target_hip.tolist(), "target_knee": target_knee.tolist(),
              "along": float(along), "source_to_canvas": transform.tolist(), "color_gain": gain.tolist(), "forward_knee_overlap_source_pixels": 40,
              "canvas": list(size), "source_mask": "source-mask.png", "alpha_floor": 40,
              "sampling": "premultiplied affine INTER_AREA, then existing cut_layers density and warp; not a new HD illustration",
              "output_sha256": hashlib.sha256(target.read_bytes()).hexdigest()}
    (HERE / "calibration.json").write_text(json.dumps(report, indent=2) + "\n")
    # The original pelvis contains the standing trouser cap below its mint hem.
    # In sit, those trouser pixels belong to the newly authored thigh. Preserve
    # every retained shirt texel; remove only that duplicate ownership by alpha.
    pelvis_path = ROOT / "art_src/characters/ali/07_refined/pelvis.png"
    pelvis_data = np.array(Image.open(pelvis_path).convert("RGBA"))
    colors = pelvis_data[:, :, :3].astype(np.int16)
    rows, cols = np.mgrid[:pelvis_data.shape[0], :pelvis_data.shape[1]]
    shirt = (colors[:, :, 1] - colors[:, :, 0] >= 7) & (colors[:, :, 1] - colors[:, :, 2] >= 3)
    shirt &= (rows >= 500) & (rows <= 590) & (pelvis_data[:, :, 3] >= 40)
    hems = np.where(shirt, rows, -1).max(axis=0)
    columns = np.flatnonzero(hems >= 0)
    if len(columns) < 100:
        raise ValueError("Ali original shirt hem could not be identified; delivery retained")
    boundary = np.interp(np.arange(len(hems)), columns, hems[columns]) + 3.0
    pelvis_data[rows > boundary[None, :]] = 0
    pelvis_layer = Image.fromarray(pelvis_data)
    pelvis_layer.save(target.parent / "pelvis.png")
    report["pelvis_ownership"] = {"source": str(pelvis_path.relative_to(ROOT)),
        "sha256": hashlib.sha256(pelvis_path.read_bytes()).hexdigest(),
        "method": "source mint-shirt hem plus 3 original outline pixels; original RGB retained, duplicate standing trouser cap assigned to seated thigh",
        "green_over_red_min": 7, "green_over_blue_min": 3, "search_rows": [500, 590],
        "hem_min_max": [float(hems[columns].min()), float(hems[columns].max())]}
    (HERE / "calibration.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.publish:
        sys.path.insert(0, str(ROOT / "tools/comfyui"))
        from cut_layers import part_transform, render_part, NOTE
        ratio = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
        joints = {name: np.array(point, float) * ratio for name, point in spec["joints"].items()}
        runtime = ROOT / "art/characters/ali"
        character_file = runtime / "character.json"
        character = json.loads(character_file.read_text())
        pending = []
        entries = []
        depth = spec["pose_parts"]["sit"].get("slot_z", {})
        for part_name, part_source in [("pelvis", pelvis_layer), ("leg_upper", layer)]:
            part = {k: v for k, v in spec["parts"][part_name].items() if k != "y"}
            geometry = part_transform(part_source, part, joints, ratio)
            if geometry is None:
                raise ValueError(f"Ali seated {part_name} is empty; delivery retained")
            _, width, height, pivot = geometry
            encoded = render_part(part_source, geometry, ratio)
            name = part_name + "_sit"
            pending.append((runtime / "parts" / (name + ".png"), encoded))
            character["textures"][name] = {"file": "parts/" + name + ".png", "size": [width, height], "pivot": [round(float(v), 2) for v in pivot], "note": NOTE}
            entries += [{"slot": use["name"], "texture": name, "bone": use["bone"], **({"z": depth[use["name"]]} if use["name"] in depth else {})} for use in part["uses"]]
        character.setdefault("pose_parts", {})["sit"] = {"parts": entries}
        for output, encoded in pending:
            Image.fromarray(encoded).save(output)
        character_file.write_text(json.dumps(character, ensure_ascii=False, indent=2) + "\n")
        print(f"Ali sit: pelvis and thigh, density ratio={ratio:.6f}; original standing textures and rig untouched")
    print("Ali seated source registered; no model loaded")


if __name__ == "__main__":
    main()
