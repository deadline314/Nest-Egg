"""Scaffold a new humanoid character: a recipe and a spec made from a template; nothing else to write by hand.

    python tools/comfyui/new_character.py --id trooper --name 天穹保全 --height 54 --glow o --weapon smg \
        --appearance "a Skydome corporate security trooper in a grey-blue ..." \
        [--template armored|civilian] [--armor shoulder,forearm,knee,chest] [--glow-parts head,torso]

Writes   tools/comfyui/recipes/<id>.json     the look (Qwen prompt, seed) and where everything goes
         tools/comfyui/specs/<id>_side.json  groups, parts, bones - joints and scale numbers are empty (null) on purpose:
                                             build_character.py fills them from the picture after the pose step (fit_joints.py)
Then run  build_character.py --recipe tools/comfyui/recipes/<id>.json  (see design/03-art-pipeline/CHARACTER_PIPELINE.md).

Templates
  armored   a soldier: breakable armor plates (shoulder, forearm, knee, chest by default) that fly off one step at a time
  civilian  no armor, no breaking (NPCs)
The files are plain JSON: edit the SAM prompts, cut heights and so on afterwards; build_character.py never rewrites them
(except for the empty joints).
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STYLE = ("Anime cel-shaded character art in the style of Studio Trigger's Cyberpunk Edgerunners: flat colors, bold clean black outlines, "
         "hard-edged two-tone shading, saturated neon accents. Full body, strict side view facing right, standing upright with the arms "
         "relaxed at the sides and empty hands, the far-side leg hidden behind the near leg. ")
ARMOR_DEFAULTS = {
    "shoulder": {"sam": "shoulder armor pauldron", "order": 1},
    "forearm": {"sam": "forearm armor guard", "order": 2},
    "knee": {"sam": "knee armor pad", "order": 3},
    "chest": {"sam": "chest armor plate", "order": 4},
}
PEEL = ("Remove all the armor plates completely (the shoulder armor, the forearm guards, the knee pads and the chest plate) and paint the undersuit "
        "that was beneath them, in exactly the same art style and colors. Keep everything else exactly unchanged.")


def uses(name, bone, z, order=None, tint=None):
    u = {"name": name, "bone": bone, "z": z}
    if tint:
        u["tint"] = tint
    if order:
        u["armor_order"] = order
    return u


def build_spec(r: dict) -> dict:
    armor = [a for a in r.get("armor", []) if a in ARMOR_DEFAULTS] if r["template"] == "armored" else []
    orders = {a: i + 1 for i, a in enumerate(armor)}  # break order = the order listed
    armor_sam = {a: r.get("sam", {}).get(f"armor_{a}", ARMOR_DEFAULTS[a]["sam"]) for a in armor}
    sam = r.get("sam", {})
    groups = {"hand": {"sam": [sam.get("hand", "gloved hand")]}}
    for a in armor:
        groups[f"armor_{a}"] = {"sam": [armor_sam[a]]}
    arm_occ = ["hand"] + [f"armor_{a}" for a in armor if a in ("shoulder", "forearm")]
    body_occ = ["arm", "hand"] + [f"armor_{a}" for a in armor if a in ("chest", "knee", "shoulder", "forearm")]
    groups["arm"] = {"sam": [sam.get("arm", "arm sleeve")]}
    groups["boot"] = {"sam": [sam.get("boot", "boot")]}
    groups["head"] = {"sam": [sam.get("head", "head")]}
    groups["body"] = {"sam": sam.get("body", ["torso", "legs"])}
    if armor:
        groups["arm"]["complete"] = {"stage": "P", "occluders": [o for o in arm_occ], "near": 120}
        groups["body"]["complete"] = {"stage": "P", "occluders": body_occ, "near": 120}
    parts = {
        "pelvis": {"group": "body", "from": "waist", "to": "hip", "mode": "upright", "uses": [uses("pelvis", "hip", 0)], "y": ["@waist+20", "@hip+20"], "pivot": "hip"},
        "torso": {"group": "body", "from": "waist", "to": "neck", "mode": "upright", "uses": [uses("torso", "chest", 1)], "y": [0, "@waist+20"], "pivot": "waist"},
        "head": {"group": "head", "from": "head", "to": "head_top", "mode": "upright", "uses": [uses("head", "head", 5)], "pivot": "head"},
        "leg_upper": {"group": "body", "from": "hip", "to": "knee", "mode": "bone",
                      "uses": [uses("leg_back_upper", "leg_back_upper", -5, tint=0.62), uses("leg_front_upper", "leg_front_upper", 3)], "y": ["@hip+20", "@knee"]},
        "leg_lower": {"group": "body", "from": "knee", "to": "ankle", "mode": "bone",
                      "uses": [uses("leg_back_lower", "leg_back_lower", -5, tint=0.62), uses("leg_front_lower", "leg_front_lower", 3)], "y": ["@knee", 4000]},
        "foot": {"group": "boot", "from": "ankle", "to": "toe", "mode": "upright",
                 "uses": [uses("foot_back", "foot_back", -5, tint=0.62), uses("foot_front", "foot_front", 3)], "pivot": "ankle"},
        "arm_upper": {"group": "arm", "from": "shoulder", "to": "elbow", "mode": "bone",
                      "uses": [uses("arm_back_upper", "arm_back_upper", -7, tint=0.62), uses("arm_front_upper", "arm_front_upper", 8)], "y": [0, "@elbow"]},
        "arm_lower": {"group": "arm", "from": "elbow", "to": "palm", "mode": "bone",
                      "uses": [uses("arm_back_lower", "arm_back_lower", -7, tint=0.62), uses("arm_front_lower", "arm_front_lower", 8)], "y": ["@elbow", 4000]},
        "hand": {"group": "hand", "from": "palm", "to": "fingertip", "mode": "hand",
                 "uses": [uses("hand_back", "hand_back", -6, tint=0.62), uses("hand_front", "hand_front", 10)], "pivot": "palm"},
    }
    if "chest" in armor:
        parts["armor_chest"] = {"group": "armor_chest", "from": "waist", "to": "neck", "mode": "upright", "pivot": "waist",
                                "uses": [uses("armor_chest", "chest", 2, orders["chest"])]}
    if "shoulder" in armor:
        parts["armor_shoulder"] = {"group": "armor_shoulder", "from": "shoulder", "to": "elbow", "mode": "bone", "pivot": "shoulder",
                                   "uses": [uses("armor_shoulder_back", "arm_back_upper", -6, orders["shoulder"], 0.62), uses("armor_shoulder", "arm_front_upper", 9, orders["shoulder"])]}
    if "forearm" in armor:
        parts["armor_forearm"] = {"group": "armor_forearm", "from": "elbow", "to": "palm", "mode": "bone", "pivot": "elbow",
                                  "uses": [uses("armor_forearm_back", "arm_back_lower", -6, orders["forearm"], 0.62), uses("armor_forearm", "arm_front_lower", 9, orders["forearm"])]}
    if "knee" in armor:
        parts["armor_knee"] = {"group": "armor_knee", "from": "knee", "to": "ankle", "mode": "bone", "pivot": "knee",
                               "uses": [uses("armor_knee_back", "leg_back_lower", -4, orders["knee"], 0.62), uses("armor_knee", "leg_front_lower", 4, orders["knee"])]}
    body_parts = [p for p in parts if not p.startswith("armor_")]
    glow_kind = r.get("glow", "")
    glow = {p: glow_kind for p in r.get("glow_parts", ["head", "torso"])} if glow_kind else {}
    joints = {n: None for n in ["hip", "waist", "neck", "head", "head_top", "shoulder", "elbow", "palm", "fingertip", "knee", "ankle", "toe"]}
    bones = [
        {"name": "hip", "parent": "", "from": "ground_hip"},
        {"name": "chest", "parent": "hip", "at": "waist"},
        {"name": "neck", "parent": "chest", "at": "neck"},
        {"name": "head", "parent": "neck", "at": "head"},
        {"name": "arm_back_upper", "parent": "chest", "at": "shoulder", "dx": -0.6, "tip": "elbow"},
        {"name": "arm_back_lower", "parent": "arm_back_upper", "tip": "palm"},
        {"name": "hand_back", "parent": "arm_back_lower", "tip": "fingertip"},
        {"name": "arm_front_upper", "parent": "chest", "at": "shoulder", "dx": 0.0, "tip": "elbow"},
        {"name": "arm_front_lower", "parent": "arm_front_upper", "tip": "palm"},
        {"name": "hand_front", "parent": "arm_front_lower", "tip": "fingertip"},
        {"name": "leg_back_upper", "parent": "hip", "at": "hip", "dx": -0.7, "tip": "knee"},
        {"name": "leg_back_lower", "parent": "leg_back_upper", "tip": "ankle"},
        {"name": "foot_back", "parent": "leg_back_lower"},
        {"name": "leg_front_upper", "parent": "hip", "at": "hip", "dx": 0.0, "tip": "knee"},
        {"name": "leg_front_lower", "parent": "leg_front_upper", "tip": "ankle"},
        {"name": "foot_front", "parent": "leg_front_lower"},
    ]
    spec = {
        "description": f"{r['name']}（{r['id']}）的分件規格，由 tools/comfyui/new_character.py 的 {r['template']} 範本產生。groups：SAM 3.1 文字提示分出的群組（前面的優先）；"
                       "parts：把群組切成零件並指定掛載；y 是水平切線（像素）。joints 與縮放數字由 fit_joints.py 在 pose 步驟填入，手動填的不會被蓋掉。",
        "id": r["id"], "display_name": r["name"], "scale": r.get("scale", 1.0), "height": r["height"], "seam": 10,
        "illustration_px_per_wp": None, "tex_px_per_wp": 20, "ground_y": None,
        "joints": joints, "groups": groups, "parts": parts, "glow": glow, "bones": bones,
        "weapon_anchor": {"bone": "chest", "from": "waist", "to": "shoulder", "dx": 0.8, "dy": 0.6, "reach": None},
        "dialog_portrait": {"box": None, "out": f"art/portraits/{r['id']}.png"},
        "refine": {"defringe": {"width": 2}, "speckle": 30, "smooth_alpha": {"parts": body_parts + [p for p in parts if p.startswith("armor_")], "sigma": 1.0}},
    }
    if armor:
        spec["stages"] = [{"name": "P", "from": None, "seed": r.get("seeds", {}).get("peel", 51), "prompt": PEEL}]
    return spec


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True, help="display name")
    ap.add_argument("--height", type=float, required=True, help="standing height in world pixels (the player's collision box is 44; enemies are 54-60)")
    ap.add_argument("--appearance", required=True, help="English description of the look for the Qwen prompt")
    ap.add_argument("--template", choices=["armored", "civilian"], default="armored")
    ap.add_argument("--armor", default="shoulder,forearm,knee,chest", help="breakable armor pieces in break order (armored template only)")
    ap.add_argument("--glow", default="", help="glow colour letters for the glow layers: c m r o y g")
    ap.add_argument("--glow-parts", default="head,torso", help="parts that get a glow layer")
    ap.add_argument("--weapon", default="", help="the rig weapon id the character holds (for the preview)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--force", action="store_true", help="overwrite an existing recipe or spec")
    args = ap.parse_args()
    recipe_path = ROOT / "tools/comfyui/recipes" / f"{args.id}.json"
    spec_path = ROOT / "tools/comfyui/specs" / f"{args.id}_side.json"
    if (recipe_path.exists() or spec_path.exists()) and not args.force:
        raise SystemExit(f"[new_character] {recipe_path.name} or {spec_path.name} already exists (use --force to overwrite)")
    recipe = {
        "description": f"{args.name}（{args.id}）的建置配方：build_character.py 依這份檔案從頭產出角色。每個步驟的輸入輸出見 design/03-art-pipeline/CHARACTER_PIPELINE.md。",
        "id": args.id, "name": args.name, "template": args.template,
        "spec": f"tools/comfyui/specs/{args.id}_side.json", "rig": f"art/rigs/{args.id}.json", "work": f"art_src/characters/{args.id}",
        "height": args.height, "scale": 1.0, "weapon": args.weapon,
        "armor": [a for a in args.armor.split(",") if a] if args.template == "armored" else [],
        "glow": args.glow, "glow_parts": [p for p in args.glow_parts.split(",") if p],
        "design": {"size": [832, 1216], "pick": args.seed, "prompt": STYLE + args.appearance.strip()},
    }
    spec = build_spec(recipe)
    recipe_path.write_text(json.dumps(recipe, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"wrote {recipe_path.relative_to(ROOT)}\nwrote {spec_path.relative_to(ROOT)}")
    print(f"next: D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/{args.id}.json --to pose")


if __name__ == "__main__":
    main()
