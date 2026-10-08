"""Check isolated Forward+ joint crops, not hidden by other limbs/armor/glow.

python tools/check_joint_frames.py <rig_joint_audit output directory>
python tools/check_joint_frames.py --self-check
Reports center coverage, disconnected silhouettes and enclosed alpha holes.
Open silhouette notches, artwork/color/lighting and motion still need frame review.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def inspect(alpha):
    solid = alpha >= 128
    # All components and holes count, including a one-pixel defect. No area exemption.
    _, count = ndimage.label(solid, np.ones((3, 3)))
    holes = ndimage.binary_fill_holes(solid) & ~solid
    center = alpha[alpha.shape[0] // 2, alpha.shape[1] // 2]
    return {"components": count, "hole_pixels": int(holes.sum()), "center_alpha": int(center)}


def self_check():
    alpha = np.zeros((32, 32), np.uint8)
    alpha[2:30, 8:24] = 255
    assert inspect(alpha) == {"components": 1, "hole_pixels": 0, "center_alpha": 255}
    alpha[12, 12] = 0
    assert inspect(alpha)["hole_pixels"] == 1  # even a one-pixel hole fails
    alpha[16, :] = 0
    assert inspect(alpha)["components"] == 2 and inspect(alpha)["center_alpha"] == 0
    print("joint checker: intact passes; one-pixel hole and disconnected pair fail")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("directory", nargs="?")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args()
    if args.self_check:
        self_check()
        return
    if not args.directory:
        ap.error("directory required")
    root = Path(args.directory)
    groups = json.loads((root / "frames.json").read_text(encoding="utf8"))
    failures, summary, total = [], {}, 0
    for group in groups:
        for sample in group["samples"]:
            image = np.array(Image.open(root / sample["file"]).convert("RGBA"))
            for cell in group["cells"]:
                x, y, w, h = cell["rect"]
                # Same world-space joint band at both scales; do not count unrelated ends of the cropped limb.
                radius = cell["radius"]
                if radius >= min(w, h) // 2:
                    raise ValueError(f"joint band clipped: {cell}")
                cx, cy = x + w // 2, y + h // 2
                metrics = inspect(image[cy-radius:cy+radius, cx-radius:cx+radius, 3])
                total += 1
                if metrics["components"] != 1 or metrics["hole_pixels"] or metrics["center_alpha"] < 128:
                    failure = dict(cell, pose=group["pose"], zoom=group["zoom"], **sample, **metrics)
                    failures.append(failure)
                    key = f"{cell['char']}/{cell['joint']}/{group['pose']}/{group['zoom']}/{cell['facing']}"
                    summary[key] = summary.get(key, 0) + 1
    report = {"samples": total, "failed_samples": len(failures), "summary": summary, "failures": failures}
    (root / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf8")
    print(f"joint frames: {len(failures)}/{total} failing samples; {root / 'report.json'}")
    for key, count in summary.items():
        print(f"  {key}: {count}")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
