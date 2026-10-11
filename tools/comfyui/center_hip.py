"""Give a character cut the old way (near leg = its own SAM group, pelvis and thigh cut by a row) a round hip, without cutting its parts
again (that would run SAM again and lose the reviewed masks): the hip joint moves to the middle of the thigh's top, and the refine step
continues the thigh up to that joint in a round cap (`extend`; where the pelvis part is drawn there - a hem over the hip - the cap
shows the same pixels) and gives the pelvis a disc of the thigh's cloth around it (`cap_from`).
Without it the pelvis has a flat lower edge and the thigh a flat top, which show as boxes as soon as the thigh turns (sitting, squatting).
New characters get the same from field_spec.py (center_hip).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/center_hip.py <id> [<id> ...]     then: build_character.py --from refine --to import
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def center(cid: str) -> str:
    recipe = json.loads((ROOT / f"tools/comfyui/recipes/{cid}.json").read_text(encoding="utf8"))
    path = ROOT / recipe["spec"]
    spec = json.loads(path.read_text(encoding="utf8"))
    thigh = np.array(Image.open(ROOT / recipe["work"] / "06_parts" / "leg_upper.png").convert("RGBA"))[:, :, 3] > 127
    hip_y, knee_y = int(spec["joints"]["hip"][1]), int(spec["joints"]["knee"][1])
    widths = thigh.sum(1)
    full = np.nonzero(widths >= 0.6 * np.median(widths[widths > 0]))[0]  # a jacket over the hip leaves only a sliver of the thigh's first rows
    if not len(full):
        return f"{cid}: no thigh to measure"
    top = max(hip_y, int(full.min()))
    rows = [np.nonzero(r)[0] for r in thigh[top + 8:top + 8 + (knee_y - hip_y) // 4] if r.any()]
    back, front = float(np.median([r.min() for r in rows])), float(np.median([r.max() for r in rows]))
    radius = (front - back) / 2
    old_x = spec["joints"]["hip"][0]
    spec["joints"]["hip"][0] = round((front + back) / 2)
    refine = spec.setdefault("refine", {})

    def front_z(name: str) -> int:
        return max(int(u.get("z", 0)) for u in spec["parts"][name]["uses"])
    # what is drawn between the body and the near thigh (pelvis, torso, a jacket's hem), back to front: the thigh's cap shows the same
    behind = sorted((n for n, p in spec["parts"].items() if "damage_of" not in p and n != "leg_upper" and 0 <= front_z(n) < front_z("leg_upper")), key=front_z)
    refine["extend"] = [e for e in refine.get("extend", []) if e.get("part") != "leg_upper"] + [{"part": "leg_upper", "joint": "hip", "to": "knee", "drop_rim": 14, "like": behind}]
    refine["cap_from"] = [e for e in refine.get("cap_from", []) if e.get("part") != "pelvis"] + [{"part": "pelvis", "from": "leg_upper", "joint": "hip", "to": "knee", "radius": round(radius)}]
    path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    return f"{cid}: hip x {old_x} -> {spec['joints']['hip'][0]}, radius {radius:.0f}"


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    for name in sys.argv[1:]:
        print(center(name))
