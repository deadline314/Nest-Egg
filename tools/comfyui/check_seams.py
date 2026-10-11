"""Find silhouette defects where body parts meet, before anyone has to spot them in a screenshot (NE-218).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/check_seams.py --recipe tools/comfyui/recipes/<id>.json [...more recipes] [--strict]
    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/check_seams.py --all            every recipe that has refined parts
    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/check_seams.py --self-test

Reads <work>/07_refined/<part>.png (full-canvas layers) and the spec's joints. CPU only, a second per character. Run it right after
the refine step; then still look at the legs-apart close-up (rig_preview --closeup) and one walk cycle (--gait).

The joint audit (tools/rig_joint_audit) counts holes between two parts. It cannot see these, which a player notices at once:
  overhang  below the hip joint the pelvis is wider than the thigh that hangs from it: the far thigh's strip stayed on the pelvis and
            sticks out under the hem as soon as the legs part ("a lump where the upper and lower body meet")
  ragged    the outline of a limb jumps in and out by several pixels: a mask stopped at a hand, a holster or a shadow and bit a
            notch out of the limb, or left a fringe ("torn")
  step      two parts of one limb do not have the same width where they meet (thigh / shin at the knee, upper arm / forearm)
A finding that is the drawing itself (hip armour that really is wider than the thigh) is listed in the spec with its reason:
    "seam_checks": {"allow": {"overhang": "tasset plates ride the pelvis"}}
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OVERHANG_PX, OVERHANG_BACK_PX, RAGGED_PX, STEP_SHARE = 7.0, 24.0, 7.0, 0.22  # the buttock is behind the thigh's line by nature
LIMBS = [("leg_upper", "leg_lower", "knee"), ("arm_upper", "arm_lower", "elbow")]


def edges(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Rows that hold pixels, and the first and last column of each."""
    rows = np.nonzero(mask.any(1))[0]
    return rows, mask[rows].argmax(1).astype(float), (mask.shape[1] - 1 - mask[rows, ::-1].argmax(1)).astype(float)


def overhang(pelvis: np.ndarray, thigh: np.ndarray, hip_y: int, knee_y: int) -> tuple[float, float]:
    """How far the pelvis reaches past the thigh's front and back edge below the hip joint (px; the thigh's edges are straight lines
    fitted to its middle, so a notch at its top does not hide the overhang)."""
    rows, first, last = edges(thigh)
    mid = (rows >= hip_y + 0.3 * (knee_y - hip_y)) & (rows <= hip_y + 0.75 * (knee_y - hip_y))
    if mid.sum() < 20:
        return 0.0, 0.0
    front, back = np.polyfit(rows[mid], last[mid], 1), np.polyfit(rows[mid], first[mid], 1)
    p_rows, p_first, p_last = edges(pelvis)
    below = p_rows >= hip_y + 4
    if below.sum() < 6:
        return 0.0, 0.0
    over_front = p_last[below] - np.polyval(front, p_rows[below])
    over_back = np.polyval(back, p_rows[below]) - p_first[below]
    # a few rows may stick out (the outline's corner): what counts is what most of the strip does
    return float(np.percentile(over_front, 60)), float(np.percentile(over_back, 60))


def ragged(mask: np.ndarray) -> float:
    """Largest jump of a limb's outline against its own smoothed course (px), ignoring the rounded ends."""
    rows, first, last = edges(mask)
    if len(rows) < 80:
        return 0.0
    keep = slice(len(rows) // 6, len(rows) - len(rows) // 6)
    worst = 0.0
    for edge in (first, last):
        smooth = ndimage.median_filter(edge, 41, mode="nearest")
        worst = max(worst, float(np.abs(edge - smooth)[keep].max()))
    return worst


def step(upper: np.ndarray, lower: np.ndarray, joint_y: int) -> float:
    """Relative width difference of two limb parts at the row they meet."""
    def width(mask: np.ndarray, lo: int, hi: int) -> float:
        rows = [np.nonzero(r)[0] for r in mask[max(lo, 0):hi] if r.any()]
        return float(np.median([r.max() - r.min() + 1 for r in rows])) if rows else 0.0
    a, b = width(upper, joint_y - 30, joint_y - 12), width(lower, joint_y + 12, joint_y + 30)
    return abs(a - b) / max(a, b) if a and b else 0.0


def check(recipe_path: Path) -> list[str]:
    recipe = json.loads(recipe_path.read_text(encoding="utf8"))
    spec = json.loads((ROOT / recipe["spec"]).read_text(encoding="utf8"))
    refined = ROOT / recipe["work"] / "07_refined"
    allow = spec.get("seam_checks", {}).get("allow", {})

    def layer(name: str) -> np.ndarray | None:
        path = refined / f"{name}.png"
        return np.array(Image.open(path).convert("RGBA"))[:, :, 3] > 127 if path.exists() else None

    found: list[str] = []
    joints = spec["joints"]
    pelvis, thigh = layer("pelvis"), layer("leg_upper")
    if pelvis is not None and thigh is not None and "overhang" not in allow:
        front, back = overhang(pelvis, thigh, int(joints["hip"][1]), int(joints["knee"][1]))
        for side, value, limit in (("front", front, OVERHANG_PX), ("back", back, OVERHANG_BACK_PX)):
            if value > limit and f"overhang:{side}" not in allow:
                found.append(f"overhang: below the hip the pelvis is {value:.0f} px wider than the thigh at the {side}")
    for upper_name, lower_name, joint in LIMBS:
        upper, lower = layer(upper_name), layer(lower_name)
        for name, mask in ((upper_name, upper), (lower_name, lower)):
            if mask is not None and f"ragged:{name}" not in allow:
                value = ragged(mask)
                if value > RAGGED_PX:
                    found.append(f"ragged: the outline of {name} jumps by {value:.0f} px")
        if upper is not None and lower is not None and joint in joints and f"step:{joint}" not in allow:
            value = step(upper, lower, int(joints[joint][1]))
            if value > STEP_SHARE:
                found.append(f"step: {upper_name} and {lower_name} differ in width by {value:.0%} at the {joint}")
    return found


def self_test() -> None:
    canvas = np.zeros((600, 400), bool)
    pelvis, thigh = canvas.copy(), canvas.copy()
    pelvis[100:230, 100:220] = True      # 120 wide down to 30 rows below the hip (y 200)
    thigh[200:500, 100:180] = True       # 80 wide: the pelvis sticks out 40 px at the front
    front, back = overhang(pelvis, thigh, 200, 500)
    assert front > 30 and back < 2, (front, back)
    pelvis[204:, 180:] = False
    assert overhang(pelvis, thigh, 200, 500)[0] < 2
    assert ragged(thigh) < 1
    thigh[300:320, 170:180] = False      # a notch bitten out of the front edge
    assert ragged(thigh) >= 9
    shin = canvas.copy()
    shin[500:590, 100:150] = True        # 50 wide under an 80-wide thigh
    assert step(thigh, shin, 500) > 0.3
    print("check_seams self-test: ok")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--recipe", action="append", default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--strict", action="store_true", help="exit 1 when anything is found")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    recipes = [Path(r) if Path(r).is_absolute() else ROOT / r for r in args.recipe]
    if args.all:
        recipes = sorted((ROOT / "tools/comfyui/recipes").glob("*.json"))
    total = 0
    for path in recipes:
        try:
            found = check(path)
        except (KeyError, FileNotFoundError):
            continue  # not a humanoid built from parts (a design-only recipe)
        total += len(found)
        for line in found:
            print(f"  WARN seam {path.stem}: {line}")
    print(f"check_seams: {len(recipes)} recipe(s), {total} finding(s)")
    if total and args.strict:
        raise SystemExit(1)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
