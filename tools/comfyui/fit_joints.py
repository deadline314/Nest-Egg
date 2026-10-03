"""Fill the joints (and the scale numbers) a new character's spec leaves empty, from SAM 3D Body's keypoints and the picture.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/fit_joints.py --spec tools/comfyui/specs/trooper_side.json --work art_src/characters/trooper

Reads   <work>/keypoints.json (pose step), <work>/base_rgba.png, the spec.
Writes  the spec: only values that are null/missing are filled; a joint you typed by hand is never touched.
        <work>/02_pose/joints.png   every joint drawn on the picture, to check by eye (the keypoints are a starting point, not the answer).
Filled: joints hip, waist, neck, head, head_top, shoulder, elbow, palm, fingertip, knee, ankle, toe, ground_y,
        illustration_px_per_wp (picture pixels per rig unit, from spec["height"] = world height in px and spec["scale"]),
        weapon_anchor.reach (from the arm length).
The character faces right, so the near side is SAM 3D Body's "right_*".
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

JOINTS = ["hip", "waist", "neck", "head", "head_top", "shoulder", "elbow", "palm", "fingertip", "knee", "ankle", "toe"]


def fit(spec: dict, points: dict, alpha: np.ndarray) -> dict:
    """Return {name: [x, y]} for every joint the keypoints can give."""
    kp = {k: np.array(v, float) for k, v in points.items()}
    need = ["right_shoulder", "right_elbow", "right_wrist", "left_hip", "right_hip", "right_knee", "right_ankle", "right_big_toe", "neck"]
    missing = [n for n in need if n not in kp]
    if missing:
        raise ValueError(f"keypoints.json lacks {missing}")
    ys, xs = np.nonzero(alpha > 127)
    hip = (kp["left_hip"] + kp["right_hip"]) / 2
    neck = kp["neck"]
    wrist, elbow = kp["right_wrist"], kp["right_elbow"]
    out = {
        "hip": hip,
        "neck": neck,
        "head": neck + [0, -6],
        "head_top": np.array([neck[0] + 8, float(ys.min())]),
        "waist": hip + (neck - hip) * 0.35,
        "shoulder": kp["right_shoulder"],
        "elbow": elbow,
        "palm": wrist,
        "fingertip": wrist + (wrist - elbow) / max(np.linalg.norm(wrist - elbow), 1e-6) * 0.62 * np.linalg.norm(wrist - elbow),
        "knee": kp["right_knee"],
        "ankle": kp["right_ankle"],
        "toe": kp["right_big_toe"],
    }
    return {k: [round(float(v[0]), 1), round(float(v[1]), 1)] for k, v in out.items()}


def resolve(value, joints: dict) -> float:
    """'@waist+20' -> the waist joint's y plus 20; numbers pass through."""
    if not isinstance(value, str):
        return value
    text = value.lstrip("@")
    for sign in ("+", "-"):
        if sign in text:
            name, offset = text.split(sign, 1)
            return round(joints[name][1] + (float(offset) if sign == "+" else -float(offset)))
    return round(joints[text][1])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    args = ap.parse_args()
    spec_path, work = Path(args.spec), Path(args.work)
    spec = json.loads(spec_path.read_text(encoding="utf8"))
    kp_path = work / "keypoints.json"
    if not kp_path.exists():
        raise SystemExit(f"[fit_joints] {kp_path} is missing - run the pose step first")
    points = json.loads(kp_path.read_text(encoding="utf8"))["points"]
    base = np.array(Image.open(work / "base_rgba.png").convert("RGBA"))
    found = fit(spec, points, base[:, :, 3])
    joints = spec.setdefault("joints", {})
    filled = []
    for name in JOINTS:
        if joints.get(name) is None:
            joints[name] = found[name]
            filled.append(name)
    ys = np.nonzero(base[:, :, 3] > 127)[0]
    if spec.get("ground_y") is None:
        spec["ground_y"] = int(ys.max())
        filled.append("ground_y")
    if spec.get("illustration_px_per_wp") is None:
        height_px = spec["ground_y"] - joints["head_top"][1]
        spec["illustration_px_per_wp"] = round(float(height_px) / (float(spec["height"]) / float(spec.get("scale", 1.0))), 2)
        filled.append("illustration_px_per_wp")
    anchor = spec.get("weapon_anchor")
    if anchor is not None and anchor.get("reach") is None:
        arm = (math.dist(joints["shoulder"], joints["elbow"]) + math.dist(joints["elbow"], joints["palm"])) / spec["illustration_px_per_wp"]
        anchor["reach"] = round(0.57 * arm, 2)
        filled.append("weapon_anchor.reach")
    dp = spec.get("dialog_portrait")
    if dp is not None and dp.get("box") is None:  # head and shoulders: a square sized from the head-to-neck distance
        top, neck = joints["head_top"], joints["neck"]
        side = 1.4 * (neck[1] - top[1])
        x0 = neck[0] - side * 0.55
        dp["box"] = [round(x0), round(top[1] - 8), round(x0 + side), round(top[1] - 8 + side)]
        filled.append("dialog_portrait.box")
    n_cuts = 0
    for p in spec["parts"].values():  # cut heights written as "@joint+20" in the template become pixel rows
        if "y" in p and any(isinstance(v, str) for v in p["y"]):
            p["y"] = [resolve(v, joints) for v in p["y"]]
            n_cuts += 1
    if n_cuts:
        filled.append(f"{n_cuts} cut heights")
    spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"  fit_joints: filled {', '.join(filled) if filled else 'nothing (everything was already set)'}")
    overlay = Image.new("RGBA", (base.shape[1], base.shape[0]), (110, 110, 120, 255))
    overlay.alpha_composite(Image.fromarray(base))
    d = ImageDraw.Draw(overlay)
    for name, (x, y) in joints.items():
        d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(255, 0, 0, 255), width=2)
        d.text((x + 7, y - 6), name, fill=(255, 255, 0, 255))
    d.line([(0, spec["ground_y"]), (base.shape[1], spec["ground_y"])], fill=(0, 255, 255, 255))
    (work / "02_pose").mkdir(exist_ok=True)
    overlay.convert("RGB").save(work / "02_pose" / "joints.png")


if __name__ == "__main__":
    main()
