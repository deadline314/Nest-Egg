"""S08租攤視窗：沿用窗口原圖、職員及紙張，真正持章、觸紙、放回與收手。"""
from __future__ import annotations

import json
import math
from pathlib import Path

from build_ch1_story import actor

ROOT = Path(__file__).resolve().parents[2]
ART = "res://art/environment/scene_props/rent_window_contacts/"
FLOOR = 340.0
ACTOR_SCALE = 2.4
WINDOW_X = 350.0
WINDOW_SCALE = ACTOR_SCALE * 38.4 / 308
WINDOW_Y = FLOOR - 504 * WINDOW_SCALE
COUNTER_Y = WINDOW_Y + 324.5 * WINDOW_SCALE
CLERK_X = 399.0
CLERK_SAG = .33
CHAIR_SCALE = 24.5 * ACTOR_SCALE / 245
CHAIR_POS = [CLERK_X - 38.0, FLOOR - 33 * ACTOR_SCALE]
SEAT_SOURCE_POINT = [158.5, 163.5]  # 245×330原圖中已核對的實際椅墊上表面像素中心，alpha245
SEAT_Y = CHAIR_POS[1] + SEAT_SOURCE_POINT[1] * CHAIR_SCALE
HAND_POINT = [68.5, 22.5]
STAMP_GRIP = [23.5, 12.5]
STAMP_BASE = [23.5, 50.5]
STAMP_REST = [WINDOW_X + 35 * WINDOW_SCALE, WINDOW_Y + 274 * WINDOW_SCALE]
PAPER_SCALE = ACTOR_SCALE * 9.0 / 96.0
PAPER_X = 368.0
PAPER_POINT = [48.0, 43.0]
PAPER_STATE = json.loads((ROOT / "assets_src/pipeline/guest_book_contacts-receipt.json").read_text(encoding="utf-8"))["states"][-1]
PAPER_PATH = "res://" + PAPER_STATE["path"]
PAPER_POS = [PAPER_X, COUNTER_Y - PAPER_STATE["material_bottom_pixel_centre"] * PAPER_SCALE]
STAMP = "rent_contract_stamp"
PAPER = "rent_contract_copy"
MARK = "rent_contract_mark"


def _point(pos, point, scale):
    return [pos[0] + point[0] * scale, pos[1] + point[1] * scale]


STAMP_REST_GRIP = _point(STAMP_REST, STAMP_GRIP, WINDOW_SCALE)
PAPER_CONTACT = _point(PAPER_POS, PAPER_POINT, PAPER_SCALE)
PRESS_GRIP = [PAPER_CONTACT[i] - (STAMP_BASE[i] - STAMP_GRIP[i]) * WINDOW_SCALE for i in range(2)]


def layers():
    return (
        dict(kind="sprite", path=ART + "window_clean.png", pos=[WINDOW_X, WINDOW_Y], scale=WINDOW_SCALE,
             source_width=308, filter="linear", glow=False),
        # 椅面約為H的0.27；沿用正常尺寸辦公椅，不把原小藍凳硬放大。
        dict(kind="sprite", id="rent_clerk_chair", path="res://art/environment/scene_props/control_room/control_room__control_chair.png",
             pos=CHAIR_POS, scale=CHAIR_SCALE,
             source_width=245, filter="linear", glow=False),
        dict(kind="sprite", path=ART + "window_front.png", pos=[WINDOW_X, WINDOW_Y], scale=WINDOW_SCALE,
             source_width=308, filter="linear", depth="front"),
        dict(kind="sprite", id=PAPER, path=PAPER_PATH, pos=PAPER_POS, scale=PAPER_SCALE,
             source_width=96, filter="linear", visible=False, glow=False, depth="front", lighting="physical"),
        dict(kind="sprite", id=MARK, path=ART + "contract_mark.png", pos=[0, 0], scale=PAPER_SCALE,
             source_width=96, filter="linear", visible=False, glow=False, depth="front", parent_prop=PAPER, anchor=[0, 0]),
        dict(kind="sprite", id=STAMP, path=ART + "stamp.png", pos=STAMP_REST, scale=WINDOW_SCALE,
             source_width=49, filter="linear", glow=False, depth="front", lighting="physical"),
    )


def furniture():
    return (
        dict(id="rent_counter", kind="table", rect=[WINDOW_X, COUNTER_Y, 308 * WINDOW_SCALE, FLOOR - COUNTER_Y], plane="back"),
        dict(id="rent_clerk_seat", kind="seat", rect=[CLERK_X - 15, SEAT_Y, 35, FLOOR - SEAT_Y], plane="actor"),
    )


def opening_steps(*, revisit=False):
    clerk = actor("window_clerk", "ch2_window_clerk", CLERK_X, FLOOR, facing=-1, scale=ACTOR_SCALE,
                  speaker="window_clerk", pose="sit", weapon="", pose_reason="職員坐在租攤窗口內核對合約。",
                  pose_support=f"辦公椅座面 x=384～419、y={SEAT_Y:.1f}；雙腳以地板 y=340 支撐。")
    clerk["seat_sag"] = CLERK_SAG
    return (clerk, dict(do="prop_visible", id=PAPER, visible=not revisit),
            dict(do="prop_visible", id=MARK, visible=False), dict(do="wait", time=.65))


def _reach(to=None, **fields):
    step = dict(do="reach", id="window_clerk", hand="front", time=.4, wait=True, **fields)
    if to is not None:
        step.update(to=to, contact=HAND_POINT, angle=math.pi)
    return step


def stamp_steps():
    hover = [PRESS_GRIP[0], PRESS_GRIP[1] - 9]
    return (
        _reach(STAMP_REST_GRIP),
        dict(do="prop_hold", id=STAMP, actor="window_clerk", hand="front", point=STAMP_GRIP, follow_rotation=False),
        _reach(hover),
        _reach(PRESS_GRIP),
        dict(do="sfx", id="mat_wood", volume=-12.0, jitter=0.0),
        dict(do="prop_visible", id=MARK, visible=True),
        dict(do="wait", time=.18),
        _reach(hover),
        _reach(STAMP_REST_GRIP),
        dict(do="prop_release", id=STAMP),
        _reach(release=True),
        dict(do="wait", time=.2),
    )
