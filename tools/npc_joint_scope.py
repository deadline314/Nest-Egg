"""Experimental anatomical ROI diagnosis. Original renderer/checker remain authoritative."""
import numpy as np
from scipy import ndimage
from check_joint_frames import inspect

# Direct anatomical neighbours only: a raised wrist never belongs to the head.
NEIGHBOURS = {
    "waist": ("neck", "hip_front", "hip_back", "shoulder_front", "shoulder_back"),
    "neck": ("waist", "shoulder_front", "shoulder_back"),
    "shoulder_front": ("neck", "waist", "elbow_front"),
    "shoulder_back": ("neck", "waist", "elbow_back"),
    "elbow_front": ("shoulder_front", "wrist_front"),
    "elbow_back": ("shoulder_back", "wrist_back"),
    "wrist_front": ("elbow_front",),
    "wrist_back": ("elbow_back",),
    "hip_front": ("waist", "knee_front"),
    "hip_back": ("waist", "knee_back"),
    "knee_front": ("hip_front", "ankle_front"),
    "knee_back": ("hip_back", "ankle_back"),
    "ankle_front": ("knee_front",),
    "ankle_back": ("knee_back",),
}


def classify(alpha, target, anchors, covered):
    """Pixel-coordinate anchors refer to the same native band; no resampling.

    This only diagnoses open edge notches outside the target's anatomical region.
    It never excuses enclosed holes, disconnected parts, or uncovered centres.
    """
    metrics = inspect(alpha)
    result = dict(raw=metrics, rejected=True, in_scope=[], assigned_exterior=[])
    if metrics["components"] != 1 or metrics["center_alpha"] < 128 or metrics["enclosed_pixels"]:
        result["reason"] = "centre, connectivity or genuinely enclosed material hole"
        return result
    if target not in NEIGHBOURS or target not in anchors:
        raise ValueError("Missing anatomical target: " + target)
    neighbours = NEIGHBOURS[target]
    if any(name not in anchors for name in neighbours):
        raise ValueError("Missing same-frame native neighbouring bone positions")
    solid = alpha >= 128
    holes = ndimage.binary_fill_holes(solid) & ~solid
    for y, x in zip(*np.nonzero(holes)):
        point = np.array([x + .5, y + .5])
        distance = float(np.linalg.norm(point - anchors[target]))
        nearest = min(neighbours, key=lambda n: float(np.linalg.norm(point - anchors[n])))
        other_distance = float(np.linalg.norm(point - anchors[nearest]))
        # One *native* pixel of overlap is conservative: boundary defects count
        # in both relevant regions. This does not alter the alpha/area threshold.
        if distance <= other_distance + 1.0:
            result["in_scope"].append([int(x), int(y)])
        else:
            if nearest not in covered:
                raise ValueError("Missing same-frame isolated neighbouring fixture: " + nearest)
            result["assigned_exterior"].append(dict(pixel=[int(x), int(y)], owner=nearest,
                                                     target_distance=distance, owner_distance=other_distance))
    result["rejected"] = bool(result["in_scope"])
    result["reason"] = "target open notch" if result["rejected"] else "no target defect; exterior requires complete neighbour coverage"
    return result
