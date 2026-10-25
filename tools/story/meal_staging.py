"""ST-10 meal geometry and a finite, presentation-only eating beat.

All points address the immutable source art. Story remains the sole owner of
items, money and completion; rebuilding a stage always restores resting props.
"""
from math import cos, sin

BENCH_X = 307
BENCH_WIDTH = 30
RIN_X = BENCH_X + BENCH_WIDTH / 2
SEAT_Y = 276.4
TABLE_X = 330
TABLE_WIDTH = 40
TABLE_HEIGHT = 25.5 * TABLE_WIDTH / 30.4
TABLE_SOURCE_WIDTH = 304
BOWL = (85, 55)
GRIP = [310, 481]
TIP = [1110, 503]
TIP_OFFSET = (10, .275)
FEED_ANGLE = -2.8
LIPS = [152, 145]
UTENSIL_SCALE = .0125
ATLAS = "res://art/environment/scene_props/dawn_noodle_stall_contacts/utensil_atlas.png"


def pickup(floor, actor_scale):
    table_y = round(floor - TABLE_HEIGHT * actor_scale, 1)
    table_scale = round(actor_scale * TABLE_WIDTH / TABLE_SOURCE_WIDTH, 4)
    return [TABLE_X + BOWL[0] * table_scale - TIP_OFFSET[0],
            table_y + BOWL[1] * table_scale - TIP_OFFSET[1]]


def layers(floor, actor_scale):
    return [dict(kind="sprite", id="meal_chopsticks", path=ATLAS,
                 pos=pickup(floor, actor_scale), region=[40, 444, 1088, 116],
                 pivot=[270, 37], scale=UTENSIL_SCALE, source_width=1536,
                 filter="linear"),
            dict(kind="sprite", id="meal_noodles", path=ATLAS, pos=[0, 0],
                 region=[1304, 334, 166, 380], pivot=[81, 16],
                 scale=UTENSIL_SCALE, source_width=1536, filter="linear",
                 parent_prop="meal_chopsticks", anchor=TIP, visible=False)]


def actions(floor, actor_scale):
    palm = pickup(floor, actor_scale)
    above = [palm[0], palm[1] - 15]
    dx, dy = TIP_OFFSET
    mouth_offset = [-dx * cos(FEED_ANGLE) + dy * sin(FEED_ANGLE),
                    -dx * sin(FEED_ANGLE) - dy * cos(FEED_ANGLE)]

    def reach(**fields):
        return dict(do="reach", id="rin", hand="front", **fields)

    return [
        reach(space="prop", prop="meal_chopsticks", to=GRIP, time=.35, grip=True),
        dict(do="prop_hold", id="meal_chopsticks", actor="rin", hand="front",
             point=GRIP, follow_rotation=True),
        dict(do="prop_visible", id="meal_noodles", visible=True),
        reach(to=above, time=.4),
        dict(do="prop_move", id="meal_noodles", angle=-FEED_ANGLE, time=.45, wait=False),
        reach(space="part", target_actor="rin", part="head", to=LIPS,
              offset=mouth_offset, angle=FEED_ANGLE, time=.45),
        dict(do="wait", time=.35),
        dict(do="prop_visible", id="meal_noodles", visible=False),
        dict(do="prop_move", id="meal_noodles", angle=0, time=.4, wait=False),
        reach(to=above, time=.4),
        reach(to=palm, time=.35),
        dict(do="prop_release", id="meal_chopsticks"),
        reach(release=True, time=.3),
        dict(do="wait", time=.35),
    ]
