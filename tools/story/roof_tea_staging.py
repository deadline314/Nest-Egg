"""第二章屋頂的傘、茶箱、兩只杯子與凜的最後一口。"""
from math import pi

import market_pass_staging
from booth_return_staging import PALM as EGRET_PALM
from medic_transport_staging import reach

STAGE = "ch2_rooftop_tea"
ART = "res://art/environment/scene_props/rooftop/rooftop__torn_umbrella_tea.png"
FLOOR = 262.0
SCALE = 0.49
LEFT = 320.0 - 182.0 * SCALE
TOP = FLOOR - 352.0 * SCALE
CUP = "rin_roof_cup"
CUP_REGION = (123, 203, 35, 47)
CUP_GRIP = [126, 234]
CUP_SLIDE = 16
SIP = [273.0, 154.0]
CARRY = [280.0, 184.0]
CARD = market_pass_staging.PASS
EGRET_EDGE = market_pass_staging.PATROLLER_EDGE
RIN_EDGE = market_pass_staging.RIN_EDGE
CARD_SHOW = [339.0, 179.0]


def stage_point(x: float, y: float) -> list[float]:
    return [round(LEFT + x * SCALE, 3), round(TOP + y * SCALE, 3)]


def layers() -> tuple[dict, ...]:
    # 只把左杯拆成四周的原貼圖片段。杯子拿起時，桌面與另一杯仍留在原位。
    bands = ((0, 0, 364, 203), (0, 203, 123, 47), (158, 203, 206, 47), (0, 250, 364, 110))
    pieces = tuple(dict(kind="sprite", path=ART, source_width=364, region=list(region),
                        pos=stage_point(*region[:2]), scale=SCALE, filter="linear", modulate="#bdcbd9",
                        furniture_ref="rooftop_tea_table")
                   for region in bands)
    cup = dict(kind="sprite", id=CUP, path=ART, source_width=364, region=list(CUP_REGION),
               pos=stage_point(*CUP_REGION[:2]), scale=SCALE, filter="linear",
               modulate="#bdcbd9", depth="front", support="rooftop_tea_table", furniture_ref=CUP)
    table_under_cup = dict(kind="sprite", path=ART, source_width=364, region=[123, 251, 35, 3],
                           pos=stage_point(123, 247), scale=SCALE, filter="linear",
                           modulate="#bdcbd9", furniture_ref="rooftop_tea_table")
    card = market_pass_staging.layer()
    card["pos"] = [round(point - edge * card["scale"], 3) for point, edge in zip(CARD_SHOW, EGRET_EDGE)]
    card["support"] = "鷺與凜交接查核證時，以手掌持握。"
    return pieces + (table_under_cup, cup, card)


def furniture() -> tuple[dict, ...]:
    def measured(ident, kind, x0, y0, x1, y1, **support):
        return dict(id=ident, kind=kind, rect=stage_point(x0, y0) + [round((x1-x0)*SCALE,3), round((y1-y0)*SCALE,3)], **support)
    return (
        measured("rooftop_tea_table", "table", 96, 247, 262, 350),
        measured("roof_left_stool", "seat", 35, 285, 99, 351),
        measured("roof_right_stool", "seat", 250, 285, 322, 351),
        measured(CUP, "cup", 123, 224, 157, 250, support="rooftop_tea_table"),
        measured("egret_roof_cup", "cup", 188, 224, 214, 249, support="rooftop_tea_table"),
    )


def drink_and_set_down() -> list[dict]:
    home = stage_point(*CUP_GRIP)
    bend = dict(do="pose", id="rin", pose="crouch", pose_reason="彎膝拿放在茶箱上的杯子。",
                pose_support="雙腳踩在屋頂地面。")
    stand = dict(do="pose", id="rin", pose="idle")
    pause = dict(do="wait", time=0.44)
    pickup = reach("rin", "rin", prop=CUP, to=CUP_GRIP, angle=pi/4, time=0.32)
    carry = reach("rin", "rin", to=CARRY, angle=pi/4, time=0.32)
    return [bend, pause, pickup,
            dict(do="prop_hold", id=CUP, actor="rin", hand="front", point=CUP_GRIP, follow_rotation=False),
            carry, stand, pause, reach("rin", "rin", to=SIP, angle=pi/4, time=0.42), pause,
            carry, bend, pause, reach("rin", "rin", to=home, angle=pi/4, time=0.38),
            dict(do="prop_release", id=CUP), dict(do="sfx", id="ch2_roof_cup", volume=-2.0),
            reach("rin", "rin", release=True, time=0.3), stand, pause]


def briefing_props() -> dict:
    x, y = CUP_REGION[:2]
    return {CUP: {"pos": stage_point(x + CUP_SLIDE, y)}}


def slide_cup() -> list[dict]:
    # The cup stays on the tabletop and clears the umbrella pole at its new position.
    grip_end = stage_point(CUP_GRIP[0] + CUP_SLIDE, CUP_GRIP[1])
    return [
        dict(do="move", id="egret", to=[330, FLOOR], time=0.52, pose="walk", then="squat", wait=True,
             pose_reason="屈膝夠到矮茶箱上的杯子。", pose_support="雙腳留在屋頂地面。"),
        dict(do="wait", time=0.55),
        _roof_reach("egret", CUP_GRIP, prop=CUP),
        dict(do="prop_hold", id=CUP, actor="egret", hand="front", point=CUP_GRIP, follow_rotation=False),
        _roof_reach("egret", grip_end),
        dict(do="prop_release", id=CUP),
        reach("egret", "egret", release=True, time=0.3),
        dict(do="move", id="egret", to=[372, FLOOR], time=0.52, pose="walk", then="idle", wait=True),
        dict(do="face", id="egret", dir=-1),
    ]


def _roof_reach(actor: str, point: list[float], *, prop: str | None = None) -> dict:
    contact = EGRET_PALM if actor == "egret" else market_pass_staging.RIN_HAND
    step = dict(do="reach", id=actor, hand="front", to=point, contact=contact,
                angle=pi if actor == "egret" else 0.0, time=0.42, wait=True)
    if prop is not None:
        step.update(space="prop", prop=prop)
    return step


def show_check_card() -> list[dict]:
    return [
        dict(do="move", id="egret", to=[349, FLOOR], time=0.48, pose="walk", then="idle", wait=False),
        dict(do="move", id="rin", to=[302, FLOOR], time=0.48, pose="walk", then="idle", wait=True),
        _roof_reach("egret", EGRET_EDGE, prop=CARD),
        dict(do="prop_visible", id=CARD, visible=True),
        dict(do="prop_hold", id=CARD, actor="egret", hand="front", point=EGRET_EDGE, follow_rotation=False),
    ]


def pass_check_card() -> list[dict]:
    # Both palms touch opposite edges before ownership transfers.
    return [
        _roof_reach("egret", [324.0, 176.0]),
        _roof_reach("rin", RIN_EDGE, prop=CARD),
        dict(do="prop_release", id=CARD),
        dict(do="prop_hold", id=CARD, actor="rin", hand="front", point=RIN_EDGE, follow_rotation=False),
        reach("egret", "egret", release=True, time=0.3, wait=False),
        _roof_reach("rin", [310.0, 181.0]),
        dict(do="prop_visible", id=CARD, visible=False),
        dict(do="prop_release", id=CARD),
        reach("rin", "rin", release=True, time=0.3),
        dict(do="move", id="egret", to=[372, FLOOR], time=0.48, pose="walk", then="idle", wait=False),
        dict(do="move", id="rin", to=[268, FLOOR], time=0.48, pose="walk", then="idle", wait=True),
    ]
