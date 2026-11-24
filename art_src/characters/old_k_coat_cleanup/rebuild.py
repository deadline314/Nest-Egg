"""Rebuild Old K's local coat repairs from his sleeve-free garment stage."""
from hashlib import sha256
from pathlib import Path
from tempfile import NamedTemporaryFile
import json
import sys

import cv2
import numpy as np
from PIL import Image


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHADOW_EDGE = [
    (289, 399), (314, 393), (365, 390), (390, 403), (412, 451), (428, 473),
    (435, 502), (446, 557), (445, 614), (446, 652), (438, 714), (415, 735),
    (374, 737), (345, 724), (331, 708), (320, 640), (310, 593), (300, 561),
    (291, 508), (285, 467), (282, 423),
]
ARMHOLE_EDGE = [
    (300, 237), (321, 221), (352, 228), (375, 254), (395, 285),
    (407, 323), (406, 359), (395, 394), (378, 408), (341, 416),
    (313, 408), (294, 384), (283, 347), (286, 302), (292, 263),
]


def checked_image(path, expected):
    if sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f"Review the coat repair registration after the source changes: {path}")
    with Image.open(path) as image:
        return image.convert("RGBA")


def feather(shape, outline, pixels):
    mask = np.zeros(shape, np.uint8)
    cv2.fillPoly(mask, [np.asarray(outline, dtype=np.int32)], 255)
    return np.minimum(cv2.distanceTransform(mask, cv2.DIST_L2, cv2.DIST_MASK_PRECISE) / pixels, 1.0)


def replace_cloth(original, sample, blend, where):
    if original.shape != sample.shape or original.shape[:2] != blend.shape:
        raise ValueError(f"Coat registration dimensions differ: {where}")
    affected = (original[:, :, 3] != 0) & (blend > 0)
    if not affected.any() or sample[:, :, 3][affected].min() < 240:
        raise ValueError(f"Coat repair samples transparent or missing fabric: {where}")
    rgb = original[:, :, :3]
    amount = blend[affected, None]
    result = original.copy()
    result[:, :, :3][affected] = np.rint(
        rgb[affected] * (1.0 - amount) + sample[:, :, :3][affected] * amount
    ).astype(np.uint8)
    return Image.fromarray(result)


def prepare(root):
    sys.path.insert(0, str(root / "tools/comfyui"))
    from cut_layers import part_transform, render_part

    manifest = json.loads((HERE / "sources.json").read_bytes())
    hashes = manifest["source_sha256"]
    stage_path = manifest["source"]
    fabric = np.asarray(checked_image(root / stage_path, hashes[stage_path]))
    spec = json.loads((root / "tools/comfyui/specs/old_k_side.json").read_bytes())
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.asarray(point, dtype=float) * scale for name, point in spec["joints"].items()}
    base = root / "art_src/characters/old_k/overrides"
    shadow = feather(fabric.shape[:2], SHADOW_EDGE, 8.0)
    armhole = feather(fabric.shape[:2], ARMHOLE_EDGE, 17.0)
    # The original stage still has a drawn armhole. Gather brown cloth from a
    # nearby solid section of the same coat for that area.
    y, x = np.indices(fabric.shape[:2], dtype=np.float32)
    plain = cv2.remap(fabric, 327 + (x - 283) * 0.79, 635 + (y - 222) * 0.77, cv2.INTER_LINEAR)
    output = {}
    for part, name in manifest["parts"].items():
        original = checked_image(root / name, hashes[name])
        blend = shadow.copy()
        if part == "pelvis":
            # Below this seam the same piece contains a trouser hip cap.
            blend[spec["parts"]["pelvis"]["y"][1]:, :] = 0.0
        repaired = replace_cloth(
            np.asarray(original), plain if part == "torso" else fabric,
            armhole if part == "torso" else blend, name,
        )
        if part != "torso":
            output[base / "refined" / f"{part}.png"] = repaired
            continue
        transform = part_transform(original, spec["parts"][part], joints, scale)
        if transform is None:
            raise ValueError(f"Could not register {name} to its game texture")
        previous = render_part(original, transform, scale)
        updated = render_part(repaired, transform, scale)
        reference = np.array(checked_image(HERE / "torso-reference.png", manifest["reference_sha256"]))
        if previous.shape != reference.shape or not np.allclose(transform[3], [122.79, 306.17], atol=0.005):
            raise ValueError("The torso has a revised texture size or pivot. Review the coat repair registration.")
        changed = np.any(previous[:, :, :3] != updated[:, :, :3], axis=2)
        reference[changed, :3] = updated[changed, :3]
        output[base / "torso.png"] = Image.fromarray(reference)
    return output


def publish(images):
    for path, image in images.items():
        if path.exists():
            with Image.open(path) as existing:
                if np.array_equal(np.asarray(existing), np.asarray(image)):
                    continue
        path.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(dir=path.parent, suffix=".png", delete=False) as handle:
            temporary = Path(handle.name)
        try:
            image.save(temporary)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    publish(prepare(ROOT))