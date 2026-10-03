"""Check a character recipe and spec before any slow step runs; every problem is reported with its exact place.

    python tools/comfyui/check_spec.py --recipe tools/comfyui/recipes/trooper.json [--joints]

--joints also requires every joint and the scale numbers to be filled (the parts / textures steps need them).
Exit code 1 when there is at least one error; warnings never fail.
"""
import argparse
import json
import sys
from pathlib import Path

MODES = {"bone", "upright", "hand"}
REQUIRED_TOP = ["id", "display_name", "scale", "tex_px_per_wp", "joints", "groups", "parts", "bones", "weapon_anchor"]
REQUIRED_BONES = ["hip", "chest", "neck", "head", "arm_front_upper", "arm_front_lower", "hand_front",
                  "leg_front_upper", "leg_front_lower", "foot_front"]


def check(recipe: dict, spec: dict, need_joints: bool) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warns: list[str] = []

    def err(where: str, msg: str) -> None:
        errors.append(f"{where}: {msg}")

    for key in ["id", "spec", "rig", "work", "design"]:
        if key not in recipe:
            err(f"recipe.{key}", "missing")
    for key in REQUIRED_TOP:
        if key not in spec:
            err(f"spec.{key}", "missing")
    if errors:
        return errors, warns
    if spec["id"] != recipe["id"]:
        err("spec.id", f"is '{spec['id']}' but the recipe id is '{recipe['id']}'")
    joints = spec["joints"]
    for name, value in joints.items():
        if value is None:
            if need_joints:
                err(f"spec.joints.{name}", "is empty (run the pose step, or fill it by hand)")
        elif not (isinstance(value, list) and len(value) == 2 and all(isinstance(v, (int, float)) for v in value)):
            err(f"spec.joints.{name}", f"must be [x, y], got {value}")
    if need_joints:
        for key in ["ground_y", "illustration_px_per_wp"]:
            if spec.get(key) is None:
                err(f"spec.{key}", "is empty (run the pose step)")
        if spec["weapon_anchor"].get("reach") is None:
            err("spec.weapon_anchor.reach", "is empty (run the pose step)")
    known_joints = ", ".join(joints)

    def joint(where: str, name: str) -> None:
        if name not in joints:
            err(where, f"unknown joint '{name}' (known: {known_joints})")

    bone_names: list[str] = []
    for i, b in enumerate(spec["bones"]):
        where = f"spec.bones[{i}] ({b.get('name', '?')})"
        name = b.get("name")
        if not name:
            err(where, "has no name")
            continue
        if name in bone_names:
            err(where, "duplicate bone name")
        parent = b.get("parent", "")
        if parent and parent not in bone_names:
            err(where, f"parent '{parent}' must be defined before it")
        for key in ("at", "tip", "from"):
            if key in b and key != "from":
                joint(f"{where}.{key}", b[key])
        bone_names.append(name)
    for name in REQUIRED_BONES:
        if name not in bone_names:
            err("spec.bones", f"the rig needs a bone named '{name}'")
    anchor = spec["weapon_anchor"]
    if anchor.get("bone") not in bone_names:
        err("spec.weapon_anchor.bone", f"unknown bone '{anchor.get('bone')}'")
    for key in ("from", "to"):
        joint(f"spec.weapon_anchor.{key}", anchor.get(key, ""))

    stages = {s["name"] for s in spec.get("stages", [])}
    for i, s in enumerate(spec.get("stages", [])):
        if s.get("from") is not None and s["from"] not in stages:
            err(f"spec.stages[{i}].from", f"unknown stage '{s['from']}'")
    for gname, g in spec["groups"].items():
        where = f"spec.groups.{gname}"
        if not g.get("sam"):
            err(f"{where}.sam", "needs at least one SAM text prompt")
        c = g.get("complete")
        if c:
            for o in c.get("occluders", []):
                if o not in spec["groups"]:
                    err(f"{where}.complete.occluders", f"unknown group '{o}'")
            if "stage" in c and c["stage"] not in stages:
                err(f"{where}.complete.stage", f"unknown stage '{c['stage']}' (stages: {', '.join(sorted(stages)) or 'none'})")
    uses_names: list[str] = []
    orders: dict[int, list[str]] = {}
    for pname, p in spec["parts"].items():
        where = f"spec.parts.{pname}"
        if "damage_of" in p:
            if p["damage_of"] not in spec["parts"]:
                err(f"{where}.damage_of", f"unknown part '{p['damage_of']}'")
            continue
        if p.get("group") not in spec["groups"]:
            err(f"{where}.group", f"unknown group '{p.get('group')}'")
        if p.get("mode") not in MODES:
            err(f"{where}.mode", f"must be one of {sorted(MODES)}, got '{p.get('mode')}'")
        for key in ("from", "to"):
            joint(f"{where}.{key}", p.get(key, ""))
        if "pivot" in p:
            joint(f"{where}.pivot", p["pivot"])
        if "y" in p and not (isinstance(p["y"], list) and len(p["y"]) == 2):
            err(f"{where}.y", "must be [low, high]")
        elif "y" in p and need_joints and any(isinstance(v, str) for v in p["y"]):
            err(f"{where}.y", f"{p['y']} still has an unresolved '@joint' (run the pose step)")
        if not p.get("uses"):
            err(f"{where}.uses", "needs at least one use (name, bone, z)")
        for u in p.get("uses", []):
            if u.get("bone") not in bone_names:
                err(f"{where}.uses.{u.get('name')}.bone", f"unknown bone '{u.get('bone')}'")
            if not isinstance(u.get("z"), int):
                err(f"{where}.uses.{u.get('name')}.z", "must be an integer")
            if u.get("name") in uses_names:
                err(f"{where}.uses.{u.get('name')}", "duplicate use name")
            uses_names.append(u.get("name"))
            if "armor_order" in u:
                if not (isinstance(u["armor_order"], int) and u["armor_order"] > 0):
                    err(f"{where}.uses.{u.get('name')}.armor_order", "must be a positive integer")
                else:
                    orders.setdefault(u["armor_order"], []).append(u["name"])
    for part in spec.get("glow", {}):
        if part not in spec["parts"]:
            err(f"spec.glow.{part}", "is not a part")
    blink = spec.get("blink")
    if blink and blink.get("part") not in spec["parts"]:
        err("spec.blink.part", f"unknown part '{blink.get('part')}'")
    if orders:
        steps = sorted(orders)
        if steps != list(range(1, len(steps) + 1)):
            warns.append(f"spec armor_order values {steps} are not 1..{len(steps)} without gaps (still works, steps keep their order)")
    return errors, warns


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--recipe", required=True)
    ap.add_argument("--joints", action="store_true")
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        recipe = json.loads(Path(args.recipe).read_text(encoding="utf8"))
        spec_path = root / recipe["spec"]
        spec = json.loads(spec_path.read_text(encoding="utf8"))
    except (OSError, ValueError, KeyError) as e:
        print(f"ERROR {args.recipe}: cannot read the recipe or its spec: {e}")
        sys.exit(1)
    errors, warns = check(recipe, spec, args.joints)
    for w in warns:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"check_spec {recipe.get('id')}: {len(errors)} error(s), {len(warns)} warning(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
