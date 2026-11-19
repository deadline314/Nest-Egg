"""第二章屋頂的傘、茶箱、兩只杯子與凜的最後一口。"""
from math import pi

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
SIP = [273.0, 154.0]
CARRY = [280.0, 184.0]


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
    return pieces + (table_under_cup, cup)


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
