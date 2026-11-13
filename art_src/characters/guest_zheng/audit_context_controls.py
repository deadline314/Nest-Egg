"""Diagnose actual native controls with measured part/bone origins; not a full acceptance run."""
import json
from pathlib import Path
import sys
import zipfile

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
sys.path.insert(0, str(ROOT / "tools"))
from npc_joint_scope import classify

PART_ANCHOR = {
    "torso": "waist", "head": "neck",
    "arm_front_upper": "shoulder_front", "arm_back_upper": "shoulder_back",
    "arm_front_lower": "elbow_front", "arm_back_lower": "elbow_back",
    "hand_front": "wrist_front", "hand_back": "wrist_back",
    "leg_front_upper": "hip_front", "leg_back_upper": "hip_back",
    "leg_front_lower": "knee_front", "leg_back_lower": "knee_back",
    "foot_front": "ankle_front", "foot_back": "ankle_back",
}


def native_case(run, geometry_run):
    folder = OUT / run
    report = json.loads((folder / "report.json").read_text(encoding="utf8"))
    groups = json.loads((OUT / geometry_run / "frames.json").read_text(encoding="utf8"))
    with zipfile.ZipFile(OUT / (geometry_run + "-source.zip")) as frozen:
        skin = json.loads(frozen.read("art/characters/guest_zheng/character.json"))
        if any(any(float(v) != 0 for v in part.get("offset", [0, 0])) for part in skin["parts"]):
            raise ValueError("A nonzero material offset cannot be treated as an observed bone origin")
    reference_hashes = json.loads((OUT / "npc-performance-final-lf-v1-source-hashes.json").read_text(encoding="utf8"))["before"]
    actual_hashes = json.loads((OUT / (geometry_run + "-source-hashes.json")).read_text(encoding="utf8"))["before"]
    physical = [name for name in reference_hashes if name.startswith(("game/rig/", "art/characters/guest_zheng/", "art/rigs/", "art/motion/guest_zheng"))]
    if any(reference_hashes[name] != actual_hashes.get(name) for name in physical):
        raise ValueError("Controls and complete neighbour coverage have different physical rig/material sources")
    results = []
    for failure in report["failures"]:
        group = next(g for g in groups if g["pose"] == failure["pose"] and g["zoom"] == failure["zoom"])
        cell = next(c for c in group["cells"] if c["char"] == failure["char"] and c["facing"] == failure["facing"])
        assert cell["geometry_frame"] == failure["frame"]
        x, y, w, h = map(int, failure["rect"])
        radius = int(failure["radius"])
        image = np.array(Image.open(folder / failure["file"]).convert("RGBA"))
        alpha = image[y + h // 2 - radius:y + h // 2 + radius, x + w // 2 - radius:x + w // 2 + radius, 3]
        anchors = {}
        for material in cell["geometry_sample"]:
            if material["part"] not in PART_ANCHOR:
                continue
            anchor = PART_ANCHOR[material["part"]]
            anchors[anchor] = np.array([material["to_cell"][0][2] - w // 2 + radius,
                                        material["to_cell"][1][2] - h // 2 + radius])
        # The role has no per-part position offsets: the captured material node
        # origins are its actual parent bone origins. Never substitute missing points.
        full = json.loads((OUT / "npc-performance-final-lf-v1/frames.json").read_text(encoding="utf8"))
        coverage_group = next(g for g in full if g["pose"] == failure["pose"] and g["zoom"] == failure["zoom"])
        covered = {c["joint"] for c in coverage_group["cells"]
                   if c["char"] == failure["char"] and c["facing"] == failure["facing"]}
        result = classify(alpha, failure["joint"], anchors, covered)
        result.update(frame=failure["frame"], facing=failure["facing"], joint=failure["joint"])
        results.append(result)
    return dict(run=run, raw_failed_samples=report["failed_samples"],
                scoped_rejected_samples=sum(r["rejected"] for r in results), results=results)


def main():
    cases = [
        native_case("context-shoulder-base-v1", "context-shoulder-whole-v1"),
        native_case("context-wrist-base-v1", "context-wrist-upperarm-v1"),
        native_case("onepixel-negative-native-v1", "onepixel-negative-native-v1"),
        native_case("onepixel-negative-upperarm-v1", "onepixel-negative-upperarm-v1"),
    ]
    receipt = dict(classification="experimental ROI applied only to measured native controls; not full NPC acceptance",
                   cases=cases, framework="all role render parts use their bone origin, texture pivot is separate")
    (OUT / "native-scope-controls.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    for case in cases:
        print(case["run"], case["raw_failed_samples"], "raw;", case["scoped_rejected_samples"], "scope failures")
    assert [c["scoped_rejected_samples"] for c in cases] == [0, 2, 2, 2]


if __name__ == "__main__":
    main()
