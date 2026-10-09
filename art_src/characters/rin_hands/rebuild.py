"""Reproduce the independent Rin left arm and two gripping attachments, then use the normal cutter."""
import hashlib
import io
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


work = Path(__file__).resolve().parent
root = work.parents[2]
record = json.loads((work / "manifest.json").read_text(encoding="utf8"))
for path, digest in record["sources"].items():
    assert hashlib.sha256((work / path).read_bytes()).hexdigest() == digest, f"source changed: {path}"
assert hashlib.sha256((root / record["approved_source"]).read_bytes()).hexdigest() == record["approved_sha256"]

layers = {}
upper = np.array(Image.open(work / record["mechanical_wrist"]["upper"]))
original_upper = np.array(Image.open(work / record["mechanical_wrist"]["original_upper"]))
for x, y in record["mechanical_wrist"]["missing_upper_pixels"]:
    assert upper[y, x, 3] < 128 and original_upper[y, x, 3] >= 253, "invalid original mechanical-arm repair source"
    upper[y, x] = original_upper[y, x]
upper[upper[:, :, 3] < 4] = 0
layers["arm_upper"] = Image.fromarray(upper)
for name, path in record["open_layers"].items():
    pixels = np.array(Image.open(work / path))
    assert pixels.shape == (1216, 832, 4), f"invalid RGBA layer: {path}"
    pixels[pixels[:, :, 3] < 4] = 0
    layers[name] = Image.fromarray(pixels)
forearm = np.array(Image.open(work / record["mechanical_wrist"]["forearm"]))
connector = np.array(Image.open(work / record["mechanical_wrist"]["hand"]))
connector[:542] = 0
connector[573:] = 0
selected = connector[:, :, 3] > forearm[:, :, 3]
forearm[selected] = connector[selected]
forearm[forearm[:, :, 3] < 4] = 0
layers["arm_lower"] = Image.fromarray(forearm)
rest_hand = np.array(Image.open(work / record["mechanical_wrist"]["hand"]))
connector = np.array(Image.open(work / record["mechanical_wrist"]["forearm"]))
connector[:528] = 0
connector[560:] = 0
selected = connector[:, :, 3] > rest_hand[:, :, 3]
rest_hand[selected] = connector[selected]
rest_hand[rest_hand[:, :, 3] < 4] = 0
layers["hand"] = Image.fromarray(rest_hand)
for name, config in record["grips"].items():
    pixels = np.array(Image.open(work / config["raw"]).convert("RGBA"), dtype=np.float32)
    mask = np.array(Image.open(work / config["mask"]).convert("L"))
    assert mask.shape == pixels.shape[:2], f"mask size differs: {name}"
    if config["mask_dilation"]:
        radius = config["mask_dilation"]
        mask = cv2.dilate(mask, np.ones((radius * 2 + 1, radius * 2 + 1), np.uint8))
    pixels[:, :, 3] = np.minimum(pixels[:, :, 3], mask)
    pixels[:, :, :3] *= pixels[:, :, 3:4] / 255.0
    warped = cv2.warpAffine(pixels, np.float32(config["matrix"]), (832, 1216), flags=cv2.INTER_CUBIC)
    warped[:, :, 3] = np.clip(warped[:, :, 3], 0, 255)
    warped[:, :, :3] /= np.maximum(warped[:, :, 3:4] / 255.0, 1e-3)
    warped[:config["clip_above_y"]] = 0
    warped[warped[:, :, 3] < 4] = 0
    if name == "hand_grip":
        # Keep the approved mechanical wrist; the generated attachment supplies the curled fingers.
        connector = np.array(layers["arm_lower"])
        connector[:528] = 0
        connector[573:] = 0
        selected = connector[:, :, 3] > warped[:, :, 3]
        warped[selected] = connector[selected]
    layers[name] = Image.fromarray(np.clip(warped, 0, 255).astype(np.uint8))
rest_hand = np.array(layers["hand"])
wrist_patch = np.array(Image.open(work / record["mechanical_wrist"]["original_hand"]))
for x, y in record["mechanical_wrist"]["missing_connector_pixels"]:
    assert rest_hand[y, x, 3] < 128 and wrist_patch[y, x, 3] >= 253, "invalid mechanical connector repair source"
    rest_hand[y, x] = wrist_patch[y, x]
layers["hand"] = Image.fromarray(rest_hand)
for name, image in layers.items():
    assert image.mode == "RGBA" and image.size == (832, 1216), f"invalid derived layer: {name}"
    anchor = (372, 248) if name in ("arm_left_upper", "arm_upper") else (374, 560)
    assert image.getpixel(anchor)[3] >= 253, f"unpainted attachment: {name}"
    data = io.BytesIO()
    image.save(data, format="PNG")
    assert hashlib.sha256(data.getvalue()).hexdigest() == record["outputs"][name], f"output changed: {name}"
for name, image in layers.items():
    target = root / "art_src/characters/rin2/overrides/refined" / f"{name}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target)
print("hand sources: approved source unchanged; 8 native-density layers reproduced with original chrome highlights and opaque attachments")
