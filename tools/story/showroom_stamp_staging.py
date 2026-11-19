"""晴岸接待桌沿用窗格、桌面與核閱文本，在櫃檯蓋收件章。"""
from __future__ import annotations

from build_ch1_story import actor, stage, wait
from rent_window_staging import ART, PAPER_PATH, PAPER_POINT, PAPER_STATE, STAMP_BASE, STAMP_GRIP

STAGE = "ch3_showroom_reception"
FLOOR = 285
SHOT = (325, 247, 1.25)
RIN_SCALE = 2.19
DESK_SCALE = 34.5 * RIN_SCALE / 276
DESK_POS = [300, FLOOR - 276 * DESK_SCALE]
TABLE_Y = DESK_POS[1] + 95 * DESK_SCALE
PAPER = "showroom_posted_notice"
STAMP = "showroom_receipt_stamp"
MARK = "showroom_receipt_mark"
PAPER_SCALE = 0.24
STAMP_SCALE = 0.38
PAPER_POS = [329, TABLE_Y - PAPER_STATE["material_bottom_pixel_centre"] * PAPER_SCALE]
STAMP_POS = [352 - STAMP_BASE[0] * STAMP_SCALE, TABLE_Y - STAMP_BASE[1] * STAMP_SCALE]
REST = [STAMP_POS[i] + STAMP_GRIP[i] * STAMP_SCALE for i in range(2)]
PRESS = [PAPER_POS[i] + PAPER_POINT[i] * PAPER_SCALE - (STAMP_BASE[i] - STAMP_GRIP[i]) * STAMP_SCALE for i in range(2)]
HOVER = [PRESS[0], PRESS[1] - 7]


def definition() -> dict:
    return {
        "camera": {"pos": list(SHOT[:2]), "zoom": SHOT[2]},
        "floor": FLOOR,
        "layers": [
            dict(kind="gradient", top="#254564", bottom="#385674"),
            *(dict(kind="sprite", path="res://art/environment/materials/glass_curtain_body.png", pos=[x, -3],
                   scale=0.8, source_width=384, filter="linear", modulate="#b3b7c0", glow=False)
              for x in (0, 307.2, 614.4)),
            dict(kind="rect", rect=[0, FLOOR, 940, 180], color="#465b71"),
            dict(kind="rect", rect=[0, FLOOR, 940, 3], color="#688293"),
            dict(kind="sprite", path="res://art/environment/scene_props/clearwater/clearwater__reception_desk.png",
                 pos=DESK_POS, scale=DESK_SCALE, source_width=320, filter="linear", depth="front", glow=False,
                 modulate="#c8c4ba"),
            dict(kind="sprite", id=PAPER, path=PAPER_PATH, pos=PAPER_POS, scale=PAPER_SCALE,
                 source_width=96, filter="linear", depth="front", glow=False, lighting="physical"),
            dict(kind="sprite", id=MARK, path=ART + "contract_mark.png", pos=[0, 0], scale=PAPER_SCALE,
                 source_width=96, filter="linear", depth="front", parent_prop=PAPER, anchor=[0, 0], visible=False),
            dict(kind="sprite", id=STAMP, path=ART + "stamp.png", pos=STAMP_POS, scale=STAMP_SCALE,
                 source_width=49, filter="linear", depth="front", glow=False, lighting="physical"),
        ],
    }


def steps() -> list[dict]:
    touch = dict(do="reach", id="lin", hand="front", contact=[86.5, 19.5], angle=2.1, time=0.33, wait=True)
    return [
        stage(STAGE, *SHOT, fade_in=0.25, feet=FLOOR),
        actor("rin", "rin", 267, FLOOR, facing=1, scale=RIN_SCALE),
        actor("lin", "lin", 351, FLOOR, facing=-1, scale=2.22),
        dict(touch, space="prop", prop=STAMP, to=STAMP_GRIP),
        dict(do="prop_hold", id=STAMP, actor="lin", hand="front", point=STAMP_GRIP),
        dict(touch, to=HOVER),
        dict(touch, to=PRESS, time=0.18),
        dict(do="sfx", id="mat_wood", volume=-12.0, jitter=0.0),
        dict(do="prop_visible", id=MARK, visible=True),
        wait(0.24),
        dict(touch, to=HOVER, time=0.18),
        dict(touch, to=REST),
        dict(do="prop_release", id=STAMP),
        dict(do="reach", id="lin", hand="front", release=True, time=0.31, wait=True),
    ]
