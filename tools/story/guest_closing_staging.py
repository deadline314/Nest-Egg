"""S21: Ali takes a pear from her apron and drops it into the existing soup pot."""
from guest_soup_staging import ALI_FINGERS

PEAR = "ali_closing_pear"
STOVE = "ali_closing_stove"
FLOOR = 265.5
ALI_X = 128
# The original 36-world-pixel stove uses the same scale as the 3.9× actor.
STOVE_SCALE = 36 * 3.9 / 287
STOVE_ORIGIN = [135.0, FLOOR - 287 * STOVE_SCALE]
GRIP = [14.5, 50.5]
APRON = [149, 148]
RIM = [STOVE_ORIGIN[0] + 90 * STOVE_SCALE, STOVE_ORIGIN[1] + 19 * STOVE_SCALE]


def layers():
    return (
        dict(kind="sprite", id=PEAR, path=f"res://art/environment/scene_props/guest_book_contacts/{PEAR}.png",
             source_width=60, scale=.14, pos=APRON, pivot=GRIP, filter="linear", depth="front", visible=False),
        dict(kind="sprite", id=STOVE,
             path="res://art/environment/scene_props/ali_kitchen/ali_kitchen__soup_stove.png",
             source_width=181, scale=STOVE_SCALE, pos=STOVE_ORIGIN,
             modulate=[.83, .74, .68, 1.0], filter="linear", depth="front", visible=False),
    )


def add_pear():
    return (
        dict(do="camera", pos=[247, 207], zoom=.86, time=.39, wait=True),
        dict(do="reach", id="ali", hand="front", space="prop", prop=PEAR, to=GRIP,
             contact=ALI_FINGERS, angle=0, time=.29, wait=True),
        dict(do="prop_hold", id=PEAR, actor="ali", hand="front", point=GRIP, follow_rotation=False),
        dict(do="prop_visible", id=PEAR, visible=True),
        dict(do="reach", id="ali", hand="front", to=[RIM[0] - 2.3, RIM[1] - 17],
             contact=ALI_FINGERS, angle=0, time=.42, wait=True),
        dict(do="wait", time=.22),
        dict(do="reach", id="ali", hand="front", to=[RIM[0] - 2.3, RIM[1] - 8.5],
             contact=ALI_FINGERS, angle=.15, time=.27, wait=True),
        dict(do="prop_release", id=PEAR),
        dict(do="prop_move", id=PEAR, to=[RIM[0] - 2.3, RIM[1] + 8.5], time=.20, wait=True),
        dict(do="prop_visible", id=PEAR, visible=False),
        dict(do="reach", id="ali", hand="front", release=True, time=.30, wait=True),
    )
