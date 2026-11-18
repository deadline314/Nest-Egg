"""S19's already accepted coat and soup request."""
from math import pi

TABLE = 180.0
COAT = "chen_raincoat"
HOOD = "chen_rainhood"
BOWL = "chen_pear_soup"
ATLAS = "res://art/environment/scene_props/guest_book_contacts/chen_soup_props.png"
HOOD_GRIP = [96.5, 15.5]
BOWL_GRIP = [34.5, 77.5]
ALI_FINGERS = [80.5, 24.5]
BOWL_SCALE = .34
BOWL_START = [267.0, TABLE - (91.5 - 48) * BOWL_SCALE]
BOWL_END = [343.0, BOWL_START[1]]


def layers():
    return (
        dict(kind="sprite", id=COAT, path=ATLAS, source_width=128, region=[0, 0, 82, 48], scale=.30,
             pos=[270.0, TABLE - 43.5 * .30], filter="linear", depth="front", visible=False),
        dict(kind="sprite", id=HOOD, path=ATLAS, source_width=128, region=[84, 0, 44, 44], scale=.31,
             pos=[0, 0], pivot=[25, 34], parent_prop=COAT, anchor=[38, 25],
             filter="linear", depth="front"),
        dict(kind="sprite", id=BOWL, path=ATLAS, source_width=128, region=[0, 48, 84, 48], scale=BOWL_SCALE,
             pos=BOWL_START, filter="linear", depth="front", visible=False),
    )


def initial():
    return {COAT: {"visible": True}}


def fulfill():
    palm_y = BOWL_START[1] + (BOWL_GRIP[1] - 48) * BOWL_SCALE
    coat_grip = [25.5, 33.5]
    return (
        dict(do="camera", pos=[320, 216], zoom=1.02, time=.45, wait=True),
        dict(do="reach", id="ali", hand="front", space="prop", prop=HOOD, to=HOOD_GRIP,
             contact=ALI_FINGERS, angle=0, time=.33, wait=True),
        dict(do="prop_move", id=HOOD, angle=.9, time=.52, wait=True),
        dict(do="reach", id="ali", hand="front", release=True, time=.3, wait=True),
        dict(do="reach", id="ali", hand="front", space="prop", prop=COAT, to=coat_grip,
             contact=ALI_FINGERS, angle=0, time=.25, wait=True),
        dict(do="prop_hold", id=COAT, actor="ali", hand="front", point=coat_grip, follow_rotation=False),
        dict(do="reach", id="ali", hand="front", to=[250.0, 191.0], contact=ALI_FINGERS, angle=0, time=.4, wait=True),
        dict(do="prop_release", id=COAT),
        dict(do="reach", id="ali", hand="front", release=True, time=.25, wait=True),
        dict(do="reach", id="ali", hand="front", space="prop", prop=BOWL, to=BOWL_GRIP,
             contact=ALI_FINGERS, angle=0, time=.35, wait=True),
        dict(do="prop_visible", id=BOWL, visible=True),
        dict(do="prop_hold", id=BOWL, actor="ali", hand="front", point=BOWL_GRIP, follow_rotation=False),
        dict(do="reach", id="ali", hand="front", to=[280.0, palm_y - 13.0], contact=ALI_FINGERS, angle=0, time=.33, wait=True),
        dict(do="reach", id="ali", hand="front", to=[280.0, palm_y], contact=ALI_FINGERS, angle=0, time=.35, wait=True),
        dict(do="prop_release", id=BOWL),
        dict(do="reach", id="ali", hand="front", release=True, time=.28, wait=False),
        dict(do="prop_move", id=BOWL, to=BOWL_END, time=.65, wait=True),
        dict(do="camera", pos=[320, 206.3], zoom=.84, time=.45, wait=True),
    )
