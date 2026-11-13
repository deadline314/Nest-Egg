"""Independent crop-grid prototype; do not change the shared cutter until this proves zero finger drift."""
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np
import cv2
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/crop-phase-prototype-v3"
sys.path.insert(0, str(ROOT / "tools/comfyui"))
import cut_layers


def snap(value):
    rounded = round(float(value))
    return float(rounded) if abs(value - rounded) < 1e-8 else float(value)


def locked(source, part, joints, phase):
    _, alpha = cut_layers._resized_premultiplied(source, 1.0)
    ys, xs = np.nonzero(alpha > 20)
    pivot = joints[part.get("pivot", part["from"])]
    ex, ey = cut_layers.frame(part["mode"], joints[part["from"]], joints[part["to"]])
    relative = np.stack([xs, ys], 1) - pivot
    u, v = relative @ ex, relative @ ey
    lo, hi = part.get("y", (0, source.height))
    low = [u.min() - cut_layers.PAD, v.min() - (0 if lo > 0 else cut_layers.PAD)]
    high = [u.max() + cut_layers.PAD, v.max() + (1 if hi < source.height else cut_layers.PAD)]
    first = [math.floor(snap(low[i] - phase[i])) for i in range(2)]
    last = [math.ceil(snap(high[i] - phase[i])) for i in range(2)]
    bounds = np.asarray(phase) + first
    piv = -bounds
    matrix = np.float32([[ex[0], ey[0], pivot[0] - piv[0] * ex[0] - piv[1] * ey[0]],
                         [ex[1], ey[1], pivot[1] - piv[0] * ex[1] - piv[1] * ey[1]]])
    return matrix, last[0] - first[0], last[1] - first[1], piv


def referenced_remap(source, transform, reference, origin):
	"""Extend OpenCV's original fixed-point sampling lattice to negative indices."""
	matrix = np.asarray(reference, np.float64)
	_, width, height, pivot = transform
	first = np.rint(-pivot - origin).astype(int)
	x = np.arange(width, dtype=np.float64) + first[0]
	y = np.arange(height, dtype=np.float64) + first[1]
	# OpenCV imgwarp.cpp warpAffineBlockline: AB_BITS=10, INTER_BITS=5.
	x_delta = np.rint(matrix[0, 0] * x * 1024).astype(np.int64)
	y_delta = np.rint(matrix[1, 0] * x * 1024).astype(np.int64)
	x_start = np.rint((matrix[0, 1] * y + matrix[0, 2]) * 1024).astype(np.int64) + 16
	y_start = np.rint((matrix[1, 1] * y + matrix[1, 2]) * 1024).astype(np.int64) + 16
	sample_x = (x_start[:, None] + x_delta[None, :]) >> 5
	sample_y = (y_start[:, None] + y_delta[None, :]) >> 5
	map_xy = np.stack((sample_x >> 5, sample_y >> 5), axis=2).astype(np.int16)
	map_phase = (((sample_y & 31) << 5) + (sample_x & 31)).astype(np.uint16)
	prem, alpha = cut_layers._resized_premultiplied(source, 1)
	wa = np.clip(cv2.remap(alpha, map_xy, map_phase, cv2.INTER_CUBIC), 0, 255)
	wc = cv2.remap(prem, map_xy, map_phase, cv2.INTER_CUBIC)
	colour = np.clip(wc / np.maximum(wa[:, :, None] / 255., 1e-3), 0, 255)
	colour[wa < 4] = 0
	return np.dstack((colour, wa)).astype(np.uint8)


def referenced_render(source, transform, reference, origin, reference_size):
    # A new affine origin, even on an integer lattice, changes the backend's
    # intermediate rounding. Preserve its actual original sampling call within
    # the reference footprint; only introduced padding/material uses the extension.
    result = cut_layers.render_part(source, transform, 1)
    old_transform = (reference, reference_size[0], reference_size[1], -origin)
    core = cut_layers.render_part(source, old_transform, 1)
    shift = np.rint(transform[3] + origin).astype(int)
    x, y = map(int, shift)
    result[y:y + core.shape[0], x:x + core.shape[1]] = core
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    joints = {key: np.asarray(value) for key, value in spec["joints"].items()}
    part = spec["parts"]["hand"]
    original = Image.open(WORK / "07_refined/hand.png")
    candidate = Image.open(WORK / "repair_candidates/wrist-v3/hand.png")
    legacy = cut_layers.part_transform(original, part, joints, 1)
    phase = -legacy[3]
    old = cut_layers.render_part(original, legacy, 1)
    locked_old = referenced_render(original, locked(original, part, joints, phase), legacy[0], phase, legacy[1:3])
    assert np.array_equal(old, locked_old)
    transform = locked(candidate, part, joints, phase)
    new = referenced_render(candidate, transform, legacy[0], phase, legacy[1:3])
    shift = transform[3] - legacy[3]
    assert np.max(np.abs(shift - np.rint(shift))) < 1e-8
    dx, dy = np.rint(shift).astype(int)
    aligned = np.zeros_like(new)
    aligned[dy:dy + old.shape[0], dx:dx + old.shape[1]] = old
    finger = np.any(aligned[:, dx + 60:] != new[:, dx + 60:], axis=2)
    Image.fromarray(new).save(OUT / "runtime.png")
    Image.fromarray(aligned).save(OUT / "old-aligned.png")
    receipt = dict(classification="independent CPU prototype; no shared cutter or live asset changed",
                   shared_cutter_sha256=hashlib.sha256(Path(cut_layers.__file__).read_bytes()).hexdigest(),
                   crop_phase=phase.tolist(), unchanged_source_with_phase_exact=True,
                   native_canvas=[new.shape[1], new.shape[0]], pivot=transform[3].tolist(),
                   integer_shift=[int(dx), int(dy)], changed_finger_pixels=int(finger.sum()),
                   source_finger_rgba_exact=True)
    normal_old = cut_layers.make_normal_map(old)
    normal_new = cut_layers.make_normal_map(new)
    normal_aligned = np.zeros_like(normal_new)
    normal_aligned[dy:dy + old.shape[0], dx:dx + old.shape[1]] = normal_old
    changed = np.any(aligned != new, axis=2).astype(np.uint8)
    affected = cv2.dilate(changed, np.ones((7, 7), np.uint8)) > 0
    reference_domain = np.zeros(changed.shape, bool)
    reference_domain[dy:dy + old.shape[0], dx:dx + old.shape[1]] = True
    remote = reference_domain & ~affected
    receipt["changed_normal_pixels_outside_material_kernel"] = int(np.count_nonzero(
        remote & np.any(normal_aligned != normal_new, axis=2)))
    receipt["changed_finger_normal_pixels"] = int(np.count_nonzero(
        np.any(normal_aligned[:, dx + 60:] != normal_new[:, dx + 60:], axis=2)))
    receipt["sampling_method"] = "retain the original backend sampling call in its immutable reference footprint"
    (OUT / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps(receipt, indent=2))
    assert not finger.any(), "Reject sampling-grid candidate: distal original material drifted"
    width, height = new.shape[1], new.shape[0]
    review = Image.new("RGB", (width * 3, height * 2 + 32), (48, 48, 48))
    draw = ImageDraw.Draw(review)
    for row, image in enumerate([Image.fromarray(aligned), Image.fromarray(new)]):
        for column, colour in enumerate([(144, 144, 144), (208, 210, 214), (32, 35, 42)]):
            tile = Image.new("RGB", image.size, colour)
            tile.paste(image, mask=image.getchannel("A"))
            review.paste(tile, (width * column, (height + 16) * row))
            draw.text((width * column, (height + 16) * row + height),
                      "old / integer translation" if row == 0 else "candidate / same pixel lattice", fill="white")
    review.save(OUT / "native-review.png")


if __name__ == "__main__":
    main()
