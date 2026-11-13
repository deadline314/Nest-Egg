"""S18's restaurant slip: reuse the existing plain paper art, with real hand and table contact.

The original document artwork and its Qwen source are unchanged. This is a visual
paper prop, not an inventory item; the abstract bars do not introduce new dialogue.
All points use the original 96-pixel image, never an imported texture's dimensions.
"""
from __future__ import annotations

import math
import json
from pathlib import Path

PROP = "zheng_meal_slip"
PATH = "res://art/items/world/document.png"
ROOT = Path(__file__).resolve().parents[2]
SOURCE_WIDTH = 96
SCALE = 3.7 * 5.0 / SOURCE_WIDTH  # a 5-world-pixel paper, about 15 cm, relative to H=56
PAPER_POINT = [72, 42]
HAND_POINT = json.loads((ROOT / "art_src/characters/guest_zheng/hand_contact.json").read_text(encoding="utf8"))["runtime_point"]
START = [379.0, 153.0]
REST = [360.0, 180.0 - 87.5 * SCALE]  # paper wholly inside x=271.25..377.25; within the guest's real arm reach
STATES = json.loads((ROOT / "assets_src/pipeline/guest_book_contacts-receipt.json").read_text(encoding="utf8"))["states"]


def validate_states(states):
    if not isinstance(states, list) or not 1 <= len(states) <= 8:
        raise ValueError("guest paper requires 1..8 states, matching the existing stage contract")
    for state in states:
        path = state.get("path", "")
        if "\\" in path or not path.startswith("art/") or ".." in path.split("/"):
            raise ValueError("guest paper state paths must be relative POSIX art paths, including on Windows")


validate_states(STATES)
FLAT_REST = [REST[0], 180.0 - STATES[-1]["material_bottom_pixel_centre"] * SCALE]


def layer():
    return dict(kind="sprite", id=PROP, path=PATH, pos=REST, scale=SCALE,
                source_width=SOURCE_WIDTH, filter="linear", glow=False, visible=False, depth="front",
                states={s["id"]: dict(path="res://" + s["path"]) for s in STATES})


def initial(*, placing=False):
    return {PROP: dict(pos=START if placing else FLAT_REST, angle=0.0, visible=not placing,
                       state="default" if placing else STATES[-1]["id"])}


def _contact(pos):
    return [pos[0] + PAPER_POINT[0] * SCALE, pos[1] + PAPER_POINT[1] * SCALE]


def place_steps():
    # First establish physical contact with the hidden slip, then reveal it in his
    # fingers. The hold follows that same contact while the real hand moves to the table.
    begin = (
        dict(do="reach", id="zheng", hand="front", to=_contact(START), contact=HAND_POINT,
             angle=math.pi, time=.45, wait=True),
        dict(do="prop_visible", id=PROP, visible=True),
        dict(do="prop_hold", id=PROP, actor="zheng", hand="front", point=PAPER_POINT, follow_rotation=False),
        dict(do="reach", id="zheng", hand="front", to=_contact(REST), contact=HAND_POINT,
             angle=math.pi, time=.65, wait=True),
    )
    lay_down = []
    for state in STATES:
        # The same source coordinate stays on opaque paper in every geometric
        # state; the hold binding remains valid throughout the tilt. Keep each
        # state's real material bottom on the table as the wrist descends.
        target = [_contact(REST)[0], 180 - (state["material_bottom_pixel_centre"] - PAPER_POINT[1]) * SCALE]
        lay_down += [dict(do="prop", id=PROP, state=state["id"]),
                     dict(do="reach", id="zheng", hand="front", to=target, contact=HAND_POINT,
                          angle=math.pi, time=.07, wait=True)]
    return begin + tuple(lay_down) + (
        dict(do="prop_release", id=PROP),
        dict(do="reach", id="zheng", hand="front", release=True, time=.4, wait=True),
    )
