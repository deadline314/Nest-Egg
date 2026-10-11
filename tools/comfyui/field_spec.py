"""Write the spec and the recipe of a character drawn by field_design.py (neutral standing side view, the far foot half a step ahead).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/field_spec.py --id sweeper --name 清掃兵 --height 56 --seed 21841 \
        [--glow head:c] [--portrait] [--far-tint 0.8] [--force]

Needs art_src/characters/<id>/base_rgba.png and 01_design/prompt.txt. Runs the pose model (GPU, a few seconds) when keypoints.json is
missing, then writes tools/comfyui/specs/<id>_side.json and recipes/<id>.json; an existing spec is kept unless --force.
What it decides, so that a plain humanoid needs no hand-written spec:
  joints   from the pose keypoints; the shoulder is moved down to the middle of the arm's top
  ground   hip + thigh + shin + (sole - ankle): how tall the figure stands with straight legs, not how tall it is mid-stride
  groups   near arm and far leg by SAM point prompts placed from the keypoints; a far hand that shows, and the head, by text; the body =
           everything else,
           completed from stage P (the same picture without the near arm); a wide ring around the arm is taken from stage P too, so no
           sliver of the hand stays on the thigh (it would show as a second hand once the arm moves)
  parts    pelvis / torso / thigh / shin / foot / upper arm / forearm / hand, with round joint caps at the hip and the ankle, hidden
           overlaps under the head and at the shoulder, and the armhole of stage P repainted in the colour of the clothes
Run it twice: once before the parts step, and again (with --force) after it, so that the elbow and wrist snap to the arm mask.
A character with layered clothes (a coat, an apron, something on the back) still needs its own groups and stages: start from this spec,
then split them the way egret_side.json and ali_side.json do. Look at 06_parts/ownership.png before going on.
"""
import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from fit_joints import fit  # noqa: E402

BONES = [{"name": "hip", "parent": "", "from": "ground_hip"}, {"name": "chest", "parent": "hip", "at": "waist"},
         {"name": "neck", "parent": "chest", "at": "neck"}, {"name": "head", "parent": "neck", "at": "head"},
         {"name": "arm_back_upper", "parent": "chest", "at": "shoulder", "dx": -0.6, "tip": "elbow"},
         {"name": "arm_back_lower", "parent": "arm_back_upper", "tip": "palm"}, {"name": "hand_back", "parent": "arm_back_lower", "tip": "fingertip"},
         {"name": "arm_front_upper", "parent": "chest", "at": "shoulder", "dx": 0.0, "tip": "elbow"},
         {"name": "arm_front_lower", "parent": "arm_front_upper", "tip": "palm"}, {"name": "hand_front", "parent": "arm_front_lower", "tip": "fingertip"},
         {"name": "leg_back_upper", "parent": "hip", "at": "hip", "dx": -0.7, "tip": "knee"}, {"name": "leg_back_lower", "parent": "leg_back_upper", "tip": "ankle"},
         {"name": "foot_back", "parent": "leg_back_lower"}, {"name": "leg_front_upper", "parent": "hip", "at": "hip", "dx": 0.0, "tip": "knee"},
         {"name": "leg_front_lower", "parent": "leg_front_upper", "tip": "ankle"}, {"name": "foot_front", "parent": "leg_front_lower"}]
STAGE_P = ("Remove the character's near-side arm entirely, from the shoulder to the fingertips, including its sleeve, its glove and anything it "
           "wears, so that a neat round armhole seam is left at the shoulder. The hand and all its fingers are removed too: nothing of the hand "
           "remains in front of the hip or the thigh. No arm, no hand and no skin are drawn there. Paint the side of the torso "
           "clothing, the belt, the hip and the thigh that were hidden behind the arm, in exactly the same art style and colors. Keep everything "
           "else exactly unchanged: the pose, the proportions, the position, the head, the legs and the clothes.")


def disc(cx: float, cy: float, r: float, n: int = 16) -> list:
    return [[round(cx + r * math.cos(i * 2 * math.pi / n)), round(cy + r * math.sin(i * 2 * math.pi / n))] for i in range(n)]


def half_width(alpha: np.ndarray, at, axis, limit: int = 140) -> float:
    """Half the limb's width at a point: the shorter of the two runs across the limb (the longer one may run into the other leg)."""
    normal = np.array([-axis[1], axis[0]])
    runs = []
    for side in (-1.0, 1.0):
        t = 0
        while t < limit:
            x, y = np.round(np.array(at) + normal * side * t).astype(int)
            if not (0 <= x < alpha.shape[1] and 0 <= y < alpha.shape[0]) or not alpha[y, x]:
                break
            t += 1
        runs.append(t)
    return float(min(runs))


def lerp(a, b, t: float) -> list:
    return [round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t)]


def unit(a, b) -> np.ndarray:
    d = np.array(b, float) - np.array(a, float)
    return d / max(np.linalg.norm(d), 1e-6)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--height", type=float, required=True, help="standing height in world pixels (the protagonist is about 63)")
    ap.add_argument("--seed", type=int, required=True, help="seed of the adopted design picture (recorded in the recipe)")
    ap.add_argument("--glow", action="append", default=[], help="part:letter, e.g. head:c (cyan), foot:m (magenta), torso:y (yellow)")
    ap.add_argument("--portrait", action="store_true", help="also cut art/portraits/<id>.png")
    ap.add_argument("--far-tint", type=float, default=0.8)
    ap.add_argument("--density", type=float, default=20.0,
                    help="texture pixels per world pixel (default 20: enough for 4K at twice the gameplay zoom; the protagonist keeps the source density)")
    ap.add_argument("--arm-text", action="store_true",
                    help="pick the near arm with the text prompt 'arm' instead of points (when the point mask comes out ragged or partial)")
    ap.add_argument("--trim-spikes", help="comma list of parts whose features thinner than 4 px are cut off (a toothpick, a lace end: on screen they "
                                          "are under a pixel wide and break into loose specks)")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    work = ROOT / "art_src/characters" / args.id
    spec_path = ROOT / "tools/comfyui/specs" / f"{args.id}_side.json"
    recipe_path = ROOT / "tools/comfyui/recipes" / f"{args.id}.json"
    if spec_path.exists() and not args.force:
        raise SystemExit(f"[field_spec] {spec_path} exists; edit it, or pass --force to write it again")
    base = work / "base_rgba.png"
    prompt = work / "01_design" / "prompt.txt"
    for needed in (base, prompt):
        if not needed.exists():
            raise SystemExit(f"[field_spec] {needed} is missing")
    rgba = Image.open(base).convert("RGBA")
    alpha = np.asarray(rgba)[:, :, 3] > 127
    (work / ".gdignore").touch()
    gitignore = work / ".gitignore"
    if not gitignore.exists():
        gitignore.write_text("# 06_parts 是從 sam／04_stages／05_groups 用 CPU 重建的中間層（build_character.py --from parts，不需要 GPU），不進版控。\n06_parts/\n", encoding="utf8")
    keypoints = work / "keypoints.json"
    if not keypoints.exists():
        grey = Image.new("RGBA", rgba.size, (128, 128, 128, 255))
        grey.alpha_composite(rgba)
        grey.convert("RGB").save(work / "base_grey.png")
        here = Path(__file__).parent
        subprocess.run([sys.executable, str(here / "gpu_lock.py"), "--", sys.executable, str(here / "pose_keypoints.py"),
                        "--image", str(work / "base_grey.png"), "--out", str(keypoints)], check=True)
    kp = json.loads(keypoints.read_text(encoding="utf8"))["points"]
    J = {k: [float(v[0]), float(v[1])] for k, v in fit({}, kp, np.asarray(rgba)[:, :, 3]).items()}
    upper_arm = math.dist(J["shoulder"], J["elbow"])
    J["shoulder"][1] += round(0.05 * upper_arm)  # the model puts it on the top edge of the shoulder; the arm turns a little below that
    thigh, shin = math.dist(J["hip"], J["knee"]), math.dist(J["knee"], J["ankle"])
    column = np.nonzero(alpha[:, int(np.clip(round(J["ankle"][0] + 0.3 * (J["toe"][0] - J["ankle"][0])), 0, alpha.shape[1] - 1))])[0]
    sole = float(column.max()) if len(column) else float(np.nonzero(alpha)[0].max())
    ground = round(J["hip"][1] + thigh + shin + max(8.0, sole - J["ankle"][1]))
    px_wp = round((ground - J["head_top"][1]) / args.height, 2)
    knee_w = max(18.0, half_width(alpha, J["knee"], unit(J["knee"], J["ankle"])))
    ankle_w = min(max(10.0, half_width(alpha, J["ankle"], unit(J["knee"], J["ankle"]))), 0.8 * knee_w)  # the run across an ankle often ends in the shoe
    # half the body's depth at the hip joint: a thigh cap larger than this is cut off by the silhouette and shows a flat edge when seated
    hip_w = max(knee_w, half_width(alpha, J["hip"], np.array([0.0, 1.0]), 220))
    J = {k: [round(v[0]), round(v[1])] for k, v in J.items()}
    # Once the arm mask exists (after the first parts step), run this tool again: the elbow and the wrist move onto the arm's centre line.
    # The pose model often puts them on the arm's edge, and then the wrist's centre is not covered by the forearm or the hand.
    arm_mask = work / "sam" / ("arm.png" if args.arm_text else "points_arm.png")
    if arm_mask.exists():
        mask = np.asarray(Image.open(arm_mask).convert("L").resize(rgba.size)) > 127
        for name in ("elbow", "palm"):
            x, y = J[name]
            xs = np.nonzero(mask[min(max(y, 0), mask.shape[0] - 1)])[0]
            xs = xs[np.abs(xs - x) < 90]
            if len(xs):
                J[name][0] = int(round((xs.min() + xs.max()) / 2))
    far = {name.replace("left_", ""): [round(v[0]), round(v[1])] for name, v in kp.items() if name.startswith("left_")}
    hand_tip = lerp(J["elbow"], J["palm"], 1.3)
    reach = max(40, round(0.45 * math.dist(J["elbow"], J["palm"])))
    hand_box = [min(J["palm"][0], hand_tip[0]) - reach, J["palm"][1], max(J["palm"][0], hand_tip[0]) + reach, max(J["palm"][1], hand_tip[1]) + reach]
    far_leg_points = [lerp(far["knee"], far["ankle"], 0.6), far["ankle"], lerp(far["heel"], far["big_toe"], 0.5)]
    if math.dist(far["knee"], J["knee"]) > 3.0 * knee_w:  # mid-stride source: the far thigh is in the open
        far_leg_points.insert(0, lerp(far["hip"], far["knee"], 0.75))
    groups = {
        "arm": {"sam": [], "points": {"pos": [lerp(J["shoulder"], J["elbow"], 0.5), lerp(J["elbow"], J["palm"], 0.5), hand_tip],
                                      "neg": [J["neck"], J["knee"]]}},  # not the hip or the far wrist: a hanging hand is often in front of them
        # what is left of "arm" and "hand" once the near arm is taken: the far hand when it shows in front of the body. Left in the body it
        # would be glued to the torso and read as an extra hand.
        "arm_far": {"sam": ["arm", "hand"]},
        # the far shin and shoe (the far foot stands half a step ahead); the far thigh only when it is clear of the near one
        # clipped below the hip joint: the mask must not bite a notch out of the pelvis
        "leg_far": {"sam": [], "y": [round(J["hip"][1] + 0.15 * thigh), rgba.size[1]],
                    "points": {"pos": far_leg_points, "neg": [J["knee"], J["ankle"], J["hip"], J["palm"]]}},
        "head": {"sam": ["head"]},
        "body": {"sam": [], "rest": True, "complete": {"stage": "P", "occluders": ["arm"], "near": 260, "trim": 20, "gap_grow": 30, "edge_trim": 1, "check_removed": hand_box, "keep_rim": True, "stage_silhouette": True}},
    }
    if args.arm_text:
        groups["arm"] = {"sam": ["arm"]}
        groups["arm_far"] = {"sam": ["hand"]}
    tint = args.far_tint

    def pair(name: str, z_back: int, z_front: int) -> list:
        return [{"name": f"{name.split('_')[0]}_back_{name.split('_')[1]}" if "_" in name else f"{name}_back", "bone": "", "z": z_back, "tint": tint},
                {"name": f"{name.split('_')[0]}_front_{name.split('_')[1]}" if "_" in name else f"{name}_front", "bone": "", "z": z_front}]

    def uses(name: str, z_back: int, z_front: int) -> list:
        out = pair(name, z_back, z_front)
        for use in out:
            use["bone"] = use["name"]
        return out

    hip, waist, knee, ankle, elbow, palm = J["hip"], J["waist"], J["knee"], J["ankle"], J["elbow"], J["palm"]
    parts = {
        "pelvis": {"group": "body", "from": "waist", "to": "hip", "mode": "upright", "pivot": "hip", "y": [waist[1] + 20, hip[1] - 12],
                   "caps": [{"joint": "hip", "radius": round(0.75 * hip_w), "feather": 1.5}], "uses": [{"name": "pelvis", "bone": "hip", "z": 0}]},
        "torso": {"group": "body", "from": "waist", "to": "neck", "mode": "upright", "pivot": "waist", "y": [0, waist[1] + 20], "uses": [{"name": "torso", "bone": "chest", "z": 1}]},
        "head": {"group": "head", "from": "head", "to": "head_top", "mode": "upright", "pivot": "head", "uses": [{"name": "head", "bone": "head", "z": 5}]},
        "leg_upper": {"group": "body", "from": "hip", "to": "knee", "mode": "bone", "y": [hip[1] + 20, knee[1]],
                      "caps": [{"joint": "hip", "radius": round(0.85 * hip_w), "feather": 10}], "uses": uses("leg_upper", -5, 3)},
        "leg_lower": {"group": "body", "from": "knee", "to": "ankle", "mode": "bone", "y": [knee[1], ankle[1] + 14],
                      "caps": [{"joint": "ankle", "radius": round(0.9 * ankle_w), "feather": 1.5}], "uses": uses("leg_lower", -5, 3)},
        "foot": {"group": "body", "from": "ankle", "to": "toe", "mode": "upright", "pivot": "ankle", "y": [ankle[1] - 8, 3000],
                 "caps": [{"joint": "ankle", "radius": round(1.35 * ankle_w), "feather": 6}],
                 "uses": [{"name": "foot_back", "bone": "foot_back", "z": -5, "tint": tint}, {"name": "foot_front", "bone": "foot_front", "z": 3}]},
        "arm_upper": {"group": "arm", "from": "shoulder", "to": "elbow", "mode": "bone", "y": [0, elbow[1]], "uses": uses("arm_upper", -7, 8)},
        "arm_lower": {"group": "arm", "from": "elbow", "to": "palm", "mode": "bone", "y": [elbow[1], palm[1]], "uses": uses("arm_lower", -7, 8)},
        "hand": {"group": "arm", "from": "palm", "to": "fingertip", "mode": "hand", "pivot": "palm", "y": [palm[1], 3000],
                 "uses": [{"name": "hand_back", "bone": "hand_back", "z": -6, "tint": tint}, {"name": "hand_front", "bone": "hand_front", "z": 10}]},
    }
    body_parts = [name for name in parts if name != "head"]
    nose = kp.get("nose", J["head"])
    spec = {
        "description": f"{args.name}（{args.id}）的分件規格，由 tools/comfyui/field_spec.py 依姿勢關鍵點產生（功能姿勢來源：自然走姿、四肢分開）。欄位說明同 rin_side.json；"
                       "做法見 .claude/skills/character-art-pipeline 的「功能姿勢來源與關節處理」。產生後的調整直接改這份檔案。",
        "id": args.id, "display_name": args.name, "scale": 1.0, "height": args.height, "seam": 12,
        "illustration_px_per_wp": px_wp, "tex_px_per_wp": min(px_wp, args.density), "ground_y": ground, "joints": J, "groups": groups, "parts": parts,
        "glow": dict(item.split(":", 1) for item in args.glow), "bones": BONES,
        "weapon_anchor": {"bone": "chest", "from": "waist", "to": "shoulder", "dx": 0.8, "dy": 0.6,
                          "reach": round(0.57 * (upper_arm + math.dist(J["elbow"], J["palm"])) / px_wp, 2)},
        "stages": [{"name": "P", "from": None, "seed": 54, "prompt": STAGE_P}],
        "refine": {"defringe": {"width": 2}, "speckle": 600, "smooth_alpha": {"parts": body_parts, "sigma": 1.0},
                   "fill_holes": {"parts": body_parts + ["head"], "max_area": 800}, "close_fill": {"parts": ["hand", "foot", "arm_lower", "arm_upper", "torso", "head", "pelvis", "leg_upper"], "radius": 4},
                   # stage P leaves a dark or skin-coloured armhole on the torso; it shows as a hole in the clothes once the arm swings away
                   "inpaint": [{"part": "torso", "poly": [[round(J["shoulder"][0] + 0.3 * upper_arm * math.cos(i * math.pi / 10)),
                                                           round(J["shoulder"][1] + 0.25 * upper_arm + 0.42 * upper_arm * math.sin(i * math.pi / 10))] for i in range(20)]}],
                   "underlap": [{"part": "torso", "under": "head", "poly": disc(J["neck"][0] + 0.3 * (nose[0] - J["neck"][0]), J["neck"][1] - 0.45 * (J["neck"][1] - nose[1]), 44)},
                                {"part": "torso", "under": "arm_upper", "poly": disc(J["shoulder"][0], J["shoulder"][1], 26)}]},
    }
    if args.trim_spikes:
        spec["refine"]["trim_spikes"] = {"parts": args.trim_spikes.split(","), "radius": 2}
    if args.portrait:
        top = J["head_top"]
        side = 1.4 * (J["neck"][1] - top[1])
        x0 = J["neck"][0] - side * 0.55
        spec["dialog_portrait"] = {"box": [round(x0), round(top[1] - 8), round(x0 + side), round(top[1] - 8 + side)], "out": f"art/portraits/{args.id}.png", "size": 256}
    spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    recipe = {"description": f"{args.name}（{args.id}）的建置配方。來源是功能姿勢的文生圖（art_src/characters/{args.id}/01_design/prompt.txt，seed {args.seed}）；建置從 parts 或之後的步驟開始。",
              "id": args.id, "name": args.name, "spec": f"tools/comfyui/specs/{args.id}_side.json", "rig": f"art/rigs/{args.id}.json",
              "work": f"art_src/characters/{args.id}", "design": {"size": list(rgba.size), "pick": args.seed, "prompt": prompt.read_text(encoding="utf8").strip()}}
    recipe_path.write_text(json.dumps(recipe, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"  wrote {spec_path.relative_to(ROOT)} and {recipe_path.relative_to(ROOT)}: ground_y {ground}, {px_wp} px per world px, knee half-width {knee_w:.0f}, ankle {ankle_w:.0f}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
