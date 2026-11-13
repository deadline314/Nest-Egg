"""NPC anatomical region report, alongside the unchanged raw joint checker.

Requires actual same-frame native anchors and complete neighbouring fixtures.
Never accepts enclosed holes, uncovered centres, disconnected parts or absent data.
"""
import argparse
import json
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

from npc_joint_scope import NEIGHBOURS, classify

PERFORMANCES = {"stand", "sit", "sit_talk", "sit_listen", "wave"}
TRANSITIONS = {"sit_down", "stand_up"}


def check(folder, diagnostic=False, expected_chars=None, expected_zooms=None):
    groups = json.loads((folder / "frames.json").read_text(encoding="utf8"))
    if not groups:
        raise ValueError("No native joint groups; zero checks cannot pass")
    raw_report = json.loads((folder / "report.json").read_text(encoding="utf8"))
    expected_samples = sum(len(g["cells"]) * len(g["samples"]) for g in groups)
    if raw_report["samples"] != expected_samples or raw_report["failed_samples"] != len(raw_report["failures"]):
        raise ValueError("Original raw checker coverage does not match the native timeline")
    if any(not g.get("npc_performance") and not g.get("npc_transitions") for g in groups):
        raise ValueError("Anatomical NPC context requires an explicit NPC timeline")
    modes = {(bool(g.get("npc_performance")), bool(g.get("npc_transitions"))) for g in groups}
    if len(modes) != 1:
        raise ValueError("Do not mix performance and transition evidence")
    performance = modes.pop()[0]
    poses = PERFORMANCES if performance else TRANSITIONS
    required_frames = 360 if performance else 120
    if not diagnostic:
        if {g["pose"] for g in groups} != poses:
            raise ValueError("Incomplete applicable NPC performance/transition states")
        if not expected_chars or not expected_zooms:
            raise ValueError("Full acceptance requires explicit expected characters and zooms")
        if {float(g["zoom"]) for g in groups} != set(expected_zooms):
            raise ValueError("Native zoom coverage differs from the requested acceptance scope")
        if {c["char"] for g in groups for c in g["cells"]} != set(expected_chars):
            raise ValueError("Native character coverage differs from the requested acceptance scope")
        if {(g["pose"], float(g["zoom"])) for g in groups} != {(p, z) for p in poses for z in expected_zooms}:
            raise ValueError("Missing NPC state/zoom combination")
        if len(groups) != len(poses) * len(expected_zooms):
            raise ValueError("Duplicated NPC state/zoom groups")
    failures, exterior = [], []
    samples = 0
    for group in groups:
        if not diagnostic and (group.get("diagnostic_include_part") or group.get("negative_control_part")):
            raise ValueError("A diagnostic neighbour/displacement control is not normal acceptance")
        if group.get("prewarm_frames") != 180 or abs(float(group.get("fixed_step", 0)) - 1 / 60) > 1e-12:
            raise ValueError("NPC evidence needs the actual 180-frame prewarm and 60 Hz simulation")
        timeline = group["samples"]
        if not timeline or (not diagnostic and len(timeline) != required_frames):
            raise ValueError("Incomplete native fixed-step timeline")
        if [s["frame"] for s in timeline] != list(range(len(timeline))):
            raise ValueError("Missing, duplicated or reordered native time samples")
        cells = group["cells"]
        if not cells:
            raise ValueError("No native isolated joint cells")
        if len({(c["char"], c["facing"], c["joint"]) for c in cells}) != len(cells):
            raise ValueError("Duplicated isolated joint cells")
        if any(c.get("diagnostic_whole_rig") or c.get("diagnostic_part_texture") for c in cells) and not diagnostic:
            raise ValueError("A deliberate visibility/material control is not normal acceptance")
        covered = {}
        for cell in cells:
            key = f"{cell['char']}/{int(cell['facing'])}"
            covered.setdefault(key, set()).add(cell["joint"])
        if not diagnostic:
            for char in expected_chars:
                for facing in (-1, 1):
                    if covered.get(f"{char}/{facing}") != set(NEIGHBOURS):
                        raise ValueError("Every role/facing needs all fourteen isolated joints")
            if len(cells) != len(expected_chars) * 2 * len(NEIGHBOURS):
                raise ValueError("Unexpected isolated joint cell count")
        for frame in timeline:
            contexts = frame.get("joint_anchors_relative_hip_native_pixels")
            if not contexts:
                raise ValueError("Missing same-frame native bone anchors; CPU estimates are not acceptance data")
            image = np.array(Image.open(folder / frame["file"]).convert("RGBA"))
            for cell in cells:
                x, y, w, h = map(int, cell["rect"])
                radius = int(cell["radius"])
                if radius <= 0 or radius >= min(w, h) // 2 or x < 0 or y < 0 or x + w > image.shape[1] or y + h > image.shape[0]:
                    raise ValueError("The native joint band is missing or clipped")
                key = f"{cell['char']}/{int(cell['facing'])}"
                anchors = {name: np.asarray(point, float) for name, point in contexts[key].items()}
                if any(v.shape != (2,) or not np.isfinite(v).all() for v in anchors.values()):
                    raise ValueError("Invalid same-frame native anatomical positions")
                target = anchors[cell["joint"]]
                band_anchors = {name: value - target + radius for name, value in anchors.items()}
                alpha = image[y + h // 2 - radius:y + h // 2 + radius,
                              x + w // 2 - radius:x + w // 2 + radius, 3]
                result = classify(alpha, cell["joint"], band_anchors, covered[key])
                samples += 1
                item = dict(char=cell["char"], facing=cell["facing"], joint=cell["joint"],
                            pose=group["pose"], zoom=group["zoom"], frame=frame["frame"],
                            file=frame["file"], **result)
                if result["rejected"]:
                    failures.append(item)
                if result["assigned_exterior"]:
                    exterior.append(item)
    report = dict(classification="diagnostic partial scope" if diagnostic else "complete NPC anatomical joint scope",
                  raw_checker_unchanged=True, samples=samples, failed_samples=len(failures),
                  raw_failed_samples=raw_report["failed_samples"],
                  exterior_scope_samples=len(exterior), failures=failures, exterior_scope=exterior,
                  postprocess_source_sha256={
                      name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                      for name in ("check_npc_joint_scope.py", "npc_joint_scope.py", "check_joint_frames.py")})
    (folder / "scope-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--expected-chars")
    parser.add_argument("--expected-zooms")
    args = parser.parse_args()
    chars = args.expected_chars.split(",") if args.expected_chars else None
    zooms = [float(v) for v in args.expected_zooms.split(",")] if args.expected_zooms else None
    report = check(args.folder, args.diagnostic, chars, zooms)
    print("NPC scope:", report["failed_samples"], "/", report["samples"], "failures;",
          report["exterior_scope_samples"], "exterior samples with neighbouring coverage")
    raise SystemExit(1 if report["failed_samples"] else 0)


if __name__ == "__main__":
    main()
