"""Rebuild the source-owned 22308 support-hand crop; no generation or runtime edits."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
RAW = HERE / "source/rin_ne222_support_context_22308_0.png"
MASK = HERE / "sam/support_hand.png"
EXPECTED_BBOX = (267, 358, 493, 500)
EXPECTED_SIZE = (226, 142)
EXPECTED_SCALE = 0.018283541156251144
EXPECTED_PIVOT = (26.0822, 25.9259)
PINNED = {
    "raw": (RAW, "993fed5e839300642bb0e0ce9ba841de8d02c6ea7529ef750ecfce1d38d30c3a"),
    "sam_mask": (MASK, "70a724378cb2f452be7465f845af5ce26db83cc6295ebd88a25316900a888baa"),
    "context_ref": (HERE / "source/actual-support-context-nearest2-reference.png", "1aea812967ced6ab731ab06aeba3f6ffbba70940d0b6199079438d9802e13da4"),
    "source_crop": (HERE / "source/actual-rifle-back_human-crop-native.png", "62d42bfa01e7a96f3134a91521b60ea444b2ec32efac37fe041ac77b3ae67ca0"),
    "qwen_graph": (HERE / "source/rin_ne222_support_context_22308.graph.json", "d198151c33f27b9e08fb47577b489a6256eef7f982cfc0dd3eaf06626e3db799"),
    "qwen_job": (HERE / "source/rin_ne222_support_context_22308.job.json", "068a89724791c4f96e48cf014e0d2287070b5bb0cb867d1439583e34ab692c6a"),
    "sam_graph": (HERE / "sam/sam_5098bda3.graph.json", "9f6582bb44387427f0b8fc812d74cb121437aa346d06b06c487c0f3d1e6ed5e0"),
    "sam_points": (HERE / "sam/point-spec.json", "60d2130e169b005671ac0efb314ed88c6f0fd19570e91a514c16cfa6e3ed842d"),
    "source_metadata": (HERE / "source/candidate.json", "dad378ebe854a8d26ff921415fb99b85ebcaed2deb96c0f3c5f6930b8d9e556f"),
    "cut_layers": (ROOT / "tools/comfyui/cut_layers.py", "5c662add546e3ccc0b23f1e0e8a817f8d86608a4e53dc923cf47e8b7cdf64154"),
}
EXPECTED_OUTPUTS = {
    "hand_back.png": "d4da7778be1c6df46797795d2aff09799bb928fa645df278afe16825a2ee4f89",
    "hand_back_n.png": "22e3eeeb6699cdfd7b0141b2418661b85d40e2ebe9ffb78afd33e96d5ef8e6a7",
}
CHECKS = 0


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check(ok: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not ok:
        raise AssertionError(message)


def validate_geometry(bbox: tuple[int, int, int, int], scale: float, pivot: tuple[float, float]) -> bool:
    return (bbox == EXPECTED_BBOX and math.isfinite(scale) and abs(scale - EXPECTED_SCALE) < 1e-12
            and len(pivot) == 2 and all(math.isfinite(v) for v in pivot)
            and all(abs(a - b) < 1e-4 for a, b in zip(pivot, EXPECTED_PIVOT)))


def alpha_is_exact_owner(rgba: np.ndarray, mask: np.ndarray) -> bool:
    return rgba.shape[:2] == mask.shape and np.array_equal(rgba[:, :, 3], mask)


def load_inputs() -> tuple[Image.Image, Image.Image, tuple[int, int, int, int]]:
    source_bytes: dict[str, bytes] = {}
    for name, (path, expected) in PINNED.items():
        check(path.is_file(), f"missing pinned input {name}: {path}")
        data = path.read_bytes()
        source_bytes[name] = data
        check(sha_bytes(data) == expected, f"pinned hash mismatch: {name}")
    raw = Image.open(RAW)
    mask_image = Image.open(MASK)
    check(raw.mode == "RGBA" and raw.size == (768, 768), "raw Qwen output must be native 768x768 RGBA")
    check(mask_image.mode == "RGB" and mask_image.size == raw.size, "SAM owner must be 768x768 RGB mask")
    raw_alpha = np.asarray(raw.getchannel("A"), dtype=np.uint8)
    check(int(raw_alpha.min()) == 252 and int(raw_alpha.max()) == 255 and not np.any(raw_alpha == 0),
          "raw image alpha distribution changed; the raw image has no transparent pixels")
    mask_rgb = np.asarray(mask_image, dtype=np.uint8)
    check(np.array_equal(mask_rgb[:, :, 0], mask_rgb[:, :, 1]) and np.array_equal(mask_rgb[:, :, 0], mask_rgb[:, :, 2]),
          "SAM mask RGB channels diverge")
    mask = mask_rgb[:, :, 0]
    check(set(np.unique(mask).tolist()) <= {0, 255}, "SAM ownership mask is not binary")
    components, _ = cv2.connectedComponents(mask, connectivity=8)
    check(components - 1 == 1, "expected exactly one connected support-hand owner")
    bbox = mask_image.getchannel("R").getbbox()
    check(bbox == EXPECTED_BBOX, f"SAM owner bbox changed: {bbox}")
    check(int(np.count_nonzero(mask)) == 23399, "SAM owner pixel count changed")
    qwen_meta = json.loads((HERE / "source/candidate.json").read_text(encoding="utf-8"))
    qwen_graph = json.loads((HERE / "source/rin_ne222_support_context_22308.graph.json").read_text(encoding="utf-8"))
    check(qwen_meta["requested_seed"] == 22308 and qwen_meta["raw_sha256"] == PINNED["raw"][1], "Qwen job metadata is inconsistent")
    check(qwen_graph["6"]["inputs"]["seed"] == 22308 and qwen_graph["6"]["inputs"]["steps"] == 25, "Qwen graph seed/steps changed")
    check(qwen_graph["6"]["inputs"]["cfg"] == 1.0 and qwen_graph["1c"]["inputs"]["device"] == "off", "Qwen graph settings changed")
    return raw, mask_image, bbox


def build(out_dir: Path) -> dict:
    raw, mask_image, bbox = load_inputs()
    check(validate_geometry(bbox, EXPECTED_SCALE, EXPECTED_PIVOT), "registered crop/scale/pivot contract is invalid")
    x0, y0, x1, y1 = bbox
    crop = raw.crop(bbox).copy()
    owner = mask_image.getchannel("R").crop(bbox)
    crop.putalpha(owner)
    rgba = np.asarray(crop, dtype=np.uint8)
    owner_array = np.asarray(owner, dtype=np.uint8)
    check(crop.size == EXPECTED_SIZE, "registered output size changed")
    check(alpha_is_exact_owner(rgba, owner_array), "candidate alpha differs from SAM owner")
    check(np.array_equal(rgba[:, :, :3], np.asarray(raw.crop(bbox), dtype=np.uint8)[:, :, :3]), "owned RGB is not literal Qwen source RGB")
    check(int(np.count_nonzero(rgba[:, :, 3])) == 23399, "candidate visible pixels changed")

    # Negative controls are executed against pure in-memory values; no source is changed.
    extra_mask = owner_array.copy()
    extra_y, extra_x = np.argwhere(extra_mask == 0)[0]
    extra_mask[extra_y, extra_x] = 255
    check(not alpha_is_exact_owner(rgba, extra_mask), "one-pixel foreign-owner negative was not caught")
    missing_mask = owner_array.copy()
    miss_y, miss_x = np.argwhere(missing_mask == 255)[0]
    missing_mask[miss_y, miss_x] = 0
    check(not alpha_is_exact_owner(rgba, missing_mask), "one-pixel missing-owner negative was not caught")
    check(not validate_geometry((x0 + 1, y0, x1, y1), EXPECTED_SCALE, EXPECTED_PIVOT), "wrong-crop negative was not caught")
    check(not validate_geometry(bbox, 0.04205, EXPECTED_PIVOT), "wrong-scale negative was not caught")
    check(not validate_geometry(bbox, EXPECTED_SCALE, (0.0, 0.0)), "wrong-pivot negative was not caught")
    changed_source = RAW.read_bytes() + b"x"
    check(sha_bytes(changed_source) != PINNED["raw"][1], "source-hash negative was not caught")

    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    from cut_layers import make_normal_map
    normal = make_normal_map(rgba)
    check(normal.shape == rgba.shape and np.array_equal(normal[:, :, 3], rgba[:, :, 3]), "normal output size/alpha differs")
    outputs = {"hand_back.png": rgba, "hand_back_n.png": normal}
    out_dir.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = {}
    for name, pixels in outputs.items():
        image = Image.fromarray(pixels, "RGBA")
        image.save(out_dir / name)
        written = (out_dir / name).read_bytes()
        hashes[name] = sha_bytes(written)
        check(hashes[name] == EXPECTED_OUTPUTS[name], f"rebuilt output differs from reviewed candidate: {name}")
    manifest = {
        "status": "REGISTERED_NATIVE_SUPPORT_HAND_PARTIAL_DELIVERY",
        "raw_output_alpha": {"min": 252, "max": 255, "transparent_pixels": 0, "extraction": "SAM 3.1 binary owner mask; not native alpha transparency"},
        "sam_owner": {"bbox_xyxy": list(bbox), "size": [x1 - x0, y1 - y0], "opaque_pixels": 23399, "connected_components_8": 1},
        "registration": {"pivot_wrist_px": list(EXPECTED_PIVOT), "texture_scale": EXPECTED_SCALE, "existing_hand_back_grip_offset_skeleton_units": [1.67408, -0.01506], "bone_or_grip_change": False},
        "outputs_sha256": hashes,
        "inputs_sha256": {name: expected for name, (_, expected) in PINNED.items()},
        "checks": CHECKS,
        "negative_controls": {"one_pixel_extra_owner": "caught", "one_pixel_missing_owner": "caught", "wrong_crop": "caught", "wrong_scale": "caught", "wrong_pivot": "caught", "changed_source_hash": "caught"},
        "normal_map": "tools/comfyui/cut_layers.py:make_normal_map; generated from cropped RGB + SAM alpha",
        "visual_status": "Registered support-hand source; native production API and wrist evidence are recorded separately. Thumb is occluded by rifle draw order; this is not whole-character or all-animation acceptance.",
    }
    (out_dir / "build-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8", newline="\n")
    print(json.dumps({"status": manifest["status"], "checks": CHECKS, "bbox": list(bbox), "size": list(EXPECTED_SIZE), "hashes": hashes}, indent=2))
    return manifest


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=HERE / "overrides")
    args = ap.parse_args()
    build(args.out.resolve())
