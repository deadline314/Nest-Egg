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
  block     just above the hip joint the pelvis reaches well in front of the thigh: the front of the far hip was left on it as a
            block, which stands out as a lump whenever the far leg is not exactly under it
  front     at the knee the front edges of thigh and shin do not meet (a seam grown back over a cut, a shin cut along another line):
            a flap or a ledge when the knee bends
  detached  a limb part begins far from the joint it turns on (a far forearm of which only the cuff was drawn): when the limb is
            raised, the hand floats in the air
  spur      a long sliver a few pixels wide hangs off a part (a cut outline left the edge of the neighbouring sleeve on a jacket
            panel): on screen it is thinner than a pixel, a hairline next to the body that breaks into loose specks when it turns
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
DETACHED_PX = 14.0
BLOCK_PX, FRONT_PX = 12.0, 9.0  # the shin may leave the line by 6 px over these 12 rows (make_parts ramp)
OVERHANG_PX, OVERHANG_BACK_PX, RAGGED_PX, STEP_SHARE = 7.0, 24.0, 7.0, 0.22  # the buttock is behind the thigh's line by nature
SPUR_WIDTH_PX, SPUR_LENGTH_PX = 7, 30  # hair is thin by nature: hair and head parts are not checked
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


def block(pelvis: np.ndarray, thigh: np.ndarray, hip_y: int, knee_y: int) -> float:
    """How far the pelvis is in front of the thigh's front line in the rows just above the hip joint (px)."""
    rows, _, last = edges(thigh)
    mid = (rows >= hip_y + 0.3 * (knee_y - hip_y)) & (rows <= hip_y + 0.75 * (knee_y - hip_y))
    p_rows, _, p_last = edges(pelvis)
    above = (p_rows >= hip_y - 14) & (p_rows <= hip_y - 4)
    if mid.sum() < 20 or above.sum() < 6:
        return 0.0
    return float(np.median(p_last[above]) - np.polyval(np.polyfit(rows[mid], last[mid], 1), hip_y))


def front_step(upper: np.ndarray, lower: np.ndarray, joint_y: int) -> float:
    """How far apart the front edges of the two parts are, 12 px either side of the joint (px)."""
    a, b = np.nonzero(upper[joint_y - 12])[0], np.nonzero(lower[joint_y + 12])[0]
    return float(abs(int(a.max()) - int(b.max()))) if len(a) and len(b) else 0.0


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
    if pelvis is not None and thigh is not None and "block" not in allow:
        value = block(pelvis, thigh, int(joints["hip"][1]), int(joints["knee"][1]))
        if value > BLOCK_PX:
            found.append(f"block: just above the hip the pelvis is {value:.0f} px in front of the thigh (the far hip left on it: a lump when the far leg moves)")
    shin = layer("leg_lower")
    if thigh is not None and shin is not None and "front:knee" not in allow:
        value = front_step(thigh, shin, int(joints["knee"][1]))
        if value > FRONT_PX:
            found.append(f"front: at the knee the front edges of thigh and shin are {value:.0f} px apart (a flap or a ledge when the knee bends)")
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
    if pelvis is not None and thigh is not None and "hip_gap" not in allow:
        rows, first, last = edges(thigh)
        top = int(rows[0])
        lo, hi = int(np.median(first[:10])), int(np.median(last[:10]))
        band = pelvis[int(joints["hip"][1]):top, lo:hi + 1]
        if band.shape[0] > 6 and band.shape[1] > 0:
            covered = float(band.any(1).mean()) if band.size else 1.0
            share = float(band.mean())
            if share < 0.7:
                found.append(f"hip_gap: between the hip joint and the top of the thigh ({band.shape[0]} px) the pelvis covers only {share:.0%} of the thigh's width (a gap opens there when the leg turns)")
    for name, pdef in spec["parts"].items():  # detached: a limb part whose pixels begin far from the joint it turns on
        joint = pdef.get("pivot") or pdef.get("from")
        core = name.startswith(("arm_", "leg_", "jacket_sleeve", "sleeve")) and name != "leg_upper" and not name.endswith("_dmg")  # plates and holsters sit away from joints by design; the thigh has its own check
        mask = layer(name) if core and pdef.get("mode") == "bone" and joint in joints and f"detached:{name}" not in allow else None
        if mask is not None and mask.any():
            gap = detached(mask, joints[joint])
            if gap > DETACHED_PX:
                found.append(f"detached: {name} begins {gap:.0f} px away from its joint {joint} (nothing is drawn between them when the limb is raised)")
    for name in spec["parts"]:
        if name.startswith(("hair", "head")) or name.endswith("_dmg") or f"spur:{name}" in allow:
            continue
        mask = layer(name)
        if mask is not None and mask.any():
            length, x, y = spur(mask)
            if length >= SPUR_LENGTH_PX:
                found.append(f"spur: a sliver {length} px long and under {SPUR_WIDTH_PX} px wide hangs off {name} at ({x}, {y}) (a hairline that breaks into specks; refine.erase)")
    return found


def spur(mask: np.ndarray) -> tuple[int, int, int]:
    """Longest piece of the part that is thinner than SPUR_WIDTH_PX: (its length, x, y of its bounding box), (0, 0, 0) if there is none."""
    yy, xx = np.ogrid[-3:4, -3:4]
    thin = mask & ~ndimage.binary_opening(mask, structure=xx * xx + yy * yy <= 9)
    labels, count = ndimage.label(thin, np.ones((3, 3)))
    best = (0, 0, 0)
    for i, box in enumerate(ndimage.find_objects(labels), 1):
        length = max(box[0].stop - box[0].start, box[1].stop - box[1].start)
        if length > best[0] and int((labels[box] == i).sum()) <= length * SPUR_WIDTH_PX:  # a sliver, not a ragged fringe along an edge
            best = (length, box[1].start, box[0].start)
    return best


def detached(mask: np.ndarray, joint: list[float]) -> float:
    """Distance from a joint to the nearest pixel of the part that turns on it."""
    ys, xs = np.nonzero(mask)
    return float(np.sqrt((xs - joint[0]) ** 2 + (ys - joint[1]) ** 2).min())


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
    pelvis[100:200, 100:220] = True      # the block above the hip is still there
    thigh[300:320, 170:180] = True
    assert block(pelvis, thigh, 200, 500) > 30
    pelvis[150:200, 185:] = False
    assert block(pelvis, thigh, 200, 500) < 6
    assert front_step(thigh, shin, 500) > 25 and front_step(shin, shin, 520) == 0
    assert detached(shin, [125, 500]) < 1 and detached(shin, [125, 420]) > 70
    assert spur(shin)[0] < 10             # only the rounded-off corners
    shin[440:500, 100:104] = True        # a 4 px wide sliver hanging 60 px above the shin's corner
    assert spur(shin)[0] >= 55, spur(shin)
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
