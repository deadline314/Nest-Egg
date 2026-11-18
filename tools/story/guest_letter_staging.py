"""S20's writing beat on the existing guest-room table."""
from math import cos, pi, sin

TABLE = 180.0
PEN = "hong_pen"
LETTER = "hong_letter"
ENVELOPE = "hong_envelope"
INK = "hong_letter_ink"
ATLAS = "res://art/environment/scene_props/guest_book_contacts/hong_stationery.png"
SCALE = .25
PEN_GRIP = [22.5, 23.5]
PEN_TIP = [5.5, 32.5]
ALI_FINGERS = [80.5, 24.5]
HONG_FINGERS = [96.5, 34.5]
PEN_START = [271.5, TABLE - PEN_TIP[1] * SCALE]
PEN_END = [360.0, PEN_START[1]]
PEN_REST = [369.0, 177.75]
PEN_FLAT_ANGLE = .49
ENVELOPE_FIRST_GRIP = [15.5, 56.5]
ENVELOPE_LAST_GRIP = [67.5, 55.5]
LETTER_GRIP = [115.5, 22.5]


def layers():
    def stationery(ident, region, x, bottom):
        return dict(kind="sprite", id=ident, path=ATLAS, source_width=128, region=region,
                    pos=[x, TABLE - bottom * SCALE], scale=SCALE, filter="linear", depth="front", visible=False)

    return (
        stationery(PEN, [0, 0, 64, 36], PEN_START[0], PEN_TIP[1]),
        stationery(LETTER, [64, 0, 64, 34], 353.0, 30.5),
        stationery(ENVELOPE, [0, 36, 80, 28], 270.5, 25.5),
        stationery(INK, [88, 36, 40, 14], 358.0, 22.0),
    )


def initial(*, response=False):
    return {LETTER: {"visible": True}, PEN: {"visible": response}, ENVELOPE: {"visible": response}}


def exchange():
    ali_release = [PEN_START[0] + PEN_GRIP[0] * SCALE + 4, PEN_START[1] + PEN_GRIP[1] * SCALE]
    tip_x, tip_y = PEN_TIP
    c, s = cos(PEN_FLAT_ANGLE), sin(PEN_FLAT_ANGLE)
    flat = [362.75 - (tip_x * c - tip_y * s) * SCALE, 179.25 - (tip_x * s + tip_y * c) * SCALE]
    seated = dict(do="pose", id="hong", pose="sit", pose_reason="坐著寫給朋友的信。",
                  pose_support="右椅座面 y=209，雙腳落在地板 y=265.5。")
    return (
        dict(do="camera", pos=[320, 216], zoom=1.02, time=.45, wait=True),
        dict(do="reach", id="ali", hand="front", space="prop", prop=PEN, to=PEN_GRIP,
             contact=ALI_FINGERS, angle=0, time=.35, wait=True),
        dict(do="prop_hold", id=PEN, actor="ali", hand="front", point=PEN_GRIP, follow_rotation=False),
        dict(do="reach", id="ali", hand="front", to=ali_release, contact=ALI_FINGERS, angle=0, time=.35, wait=True),
        dict(do="prop_release", id=PEN),
        dict(do="reach", id="ali", hand="front", release=True, time=.26, wait=False),
        dict(do="prop_move", id=PEN, to=PEN_END, time=.45, wait=True),
        dict(do="reach", id="hong", hand="front", space="prop", prop=PEN, to=PEN_GRIP,
             contact=HONG_FINGERS, angle=pi, time=.35, wait=True),
        dict(do="prop_hold", id=PEN, actor="hong", hand="front", point=PEN_GRIP, follow_rotation=False),
        dict(seated, loop="writing"),
        dict(do="reach", id="hong", hand="front", to=[362.25, 174.25], contact=HONG_FINGERS,
             angle=pi, time=.3, wait=True),
        dict(do="reach", id="hong", hand="front", to=[369.25, 174.25], contact=HONG_FINGERS,
             angle=pi, time=.55, wait=True),
        dict(do="prop_visible", id=INK, visible=True),
        dict(do="reach", id="hong", hand="front", to=PEN_REST, contact=HONG_FINGERS,
             angle=pi, time=.4, wait=True),
        dict(do="prop_release", id=PEN),
        dict(do="prop_move", id=PEN, to=flat, angle=PEN_FLAT_ANGLE, time=.2, wait=True),
        dict(do="reach", id="hong", hand="front", release=True, time=.32, wait=True),
        dict(seated, loop=""),
    )


def offer_envelope():
    return (
        dict(do="reach", id="ali", hand="front", space="prop", prop=ENVELOPE, to=ENVELOPE_FIRST_GRIP,
             contact=ALI_FINGERS, angle=0, time=.35, wait=True),
        dict(do="prop_move", id=ENVELOPE, to=[275.0, TABLE - 25.5 * SCALE], time=.35, wait=True),
        dict(do="reach", id="ali", hand="front", release=True, time=.3, wait=False),
        dict(do="prop_move", id=ENVELOPE, to=[348.5, TABLE - 25.5 * SCALE], time=.45, wait=True),
        dict(do="camera", pos=[320, 206.3], zoom=.84, time=.45, wait=True),
    )


def collect_letter():
    return (
        dict(do="reach", id="hong", hand="front", space="prop", prop=LETTER, to=LETTER_GRIP,
             contact=HONG_FINGERS, angle=pi, time=.29, wait=True),
        dict(do="prop_hold", id=LETTER, actor="hong", hand="front", point=LETTER_GRIP, follow_rotation=False),
        dict(do="prop_visible", id=INK, visible=False),
        dict(do="reach", id="hong", hand="front", to=[364, 176.75], contact=HONG_FINGERS, angle=pi, time=.35, wait=True),
        dict(do="prop_visible", id=LETTER, visible=False),
        dict(do="prop_release", id=LETTER),
        dict(do="reach", id="hong", hand="front", space="prop", prop=ENVELOPE, to=ENVELOPE_LAST_GRIP,
             contact=HONG_FINGERS, angle=pi, time=.2, wait=True),
        dict(do="prop_hold", id=ENVELOPE, actor="hong", hand="front", point=ENVELOPE_LAST_GRIP, follow_rotation=False),
        dict(do="reach", id="hong", hand="front", space="actor", to=[0, -96], contact=HONG_FINGERS,
             angle=pi / 2, time=.28, wait=True),
    )
