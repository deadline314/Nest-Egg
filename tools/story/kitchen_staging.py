"""Kitchen source-space anchors shared by stage construction and choreography.

Atlas regions keep the urn body fixed and the kettle lid on a physical hinge.
Coordinates refer to the padded source canvas, before Godot import reduction.
"""
from math import pi

PROP_DIR = "res://art/environment/scene_props/pawnshop_kitchen_contacts/"
KETTLE_SCALE = 50.0 / 823.0
URN_SCALE = 192.0 / 1248.0
BACKGROUND = dict(path="pawnshop_kitchen_contacts.png", pos=[-313.75, -176], width=1672, scale=.75)


def background_point(x, y):
    return [BACKGROUND["pos"][0] + x * BACKGROUND["scale"],
            BACKGROUND["pos"][1] + y * BACKGROUND["scale"]]


def background_rect(x, y, width, height):
    return background_point(x, y) + [width * BACKGROUND["scale"], height * BACKGROUND["scale"]]


# Baked surfaces measured in the immutable background source canvas.
FURNITURE = [
    dict(id="dining_table", kind="table", rect=background_rect(685, 489, 201, 146)),
    dict(id="dining_chair", kind="seat", rect=background_rect(638.75, 552, 75, 83)),
    dict(id="kitchen_door", kind="door", rect=background_rect(1126.25, 283.75, 100, 362.5)),
]
MAT = background_point(754 + 1 / 3, 489)  # Clear table surface, left of the baked mug.
STOVE = background_point(548.75, 467.5)
DIAL = background_point(546, 486)
URN_POS = [470, 304]
OUTLET = [URN_POS[0] + (60 - 500) * URN_SCALE, URN_POS[1] + (700 - 1269) * URN_SCALE]
FILL_ACTOR_X = 365
KETTLE_GRIP = [350, 200]
LID_GRIP = [1380, 430]
LEVER_GRIP = [1091, 340]
LID_OPEN = 1.2
DIAL_OFF = .85
FILL_FOOT = [OUTLET[0] - (630 - 628) * KETTLE_SCALE, OUTLET[1] + 8 + (879 - 430) * KETTLE_SCALE]


def layers():
    def sprite(id, atlas, region, pivot, pos, scale, **extra):
        return dict(kind="sprite", id=id, path=PROP_DIR + atlas + ".png",
                    region=region, pivot=pivot, pos=pos, scale=scale,
                    source_width=1700 if atlas == "kettle_atlas" else 1180,
                    filter="linear", **extra)
    return [
        {"kind": "rect", "id": "kettle_mat", "rect": [MAT[0] - 29, MAT[1], 58, 2.7], "color": "#343a31"},
        sprite("water_urn", "urn_atlas", [26, 18, 866, 1254], [474, 1251], URN_POS, URN_SCALE),
        sprite("urn_lever", "urn_atlas", [1048, 250, 84, 204], [43, 162], [0, 0], URN_SCALE,
               parent_prop="water_urn", anchor=[130, 582], angle=-pi / 2),
        sprite("kettle", "kettle_atlas", [36, 54, 1004, 828], [592, 825], MAT, KETTLE_SCALE,
               states={"filled": {"path": PROP_DIR + "kettle_atlas.png"}}, initial_state="filled"),
        sprite("kettle_lid", "kettle_atlas", [1122, 408, 560, 218], [535, 146], [0, 0], KETTLE_SCALE * .944,
               parent_prop="kettle", anchor=[900, 385]),
        {"kind": "dial", "id": "stove_dial", "pos": DIAL, "radius": 5,
         "color": "#222a25", "pointer": "#d4ceb4", "angle": DIAL_OFF},
        {"kind": "rain", "id": "tap_water", "area": [OUTLET[0] - .3, OUTLET[1] + .5, .6, 5.2],
         "speed": [24, 36], "length": [2, 3], "count": 8, "wind": 0,
         "opacity": .8, "visible": False},
        {"kind": "poly", "id": "kettle_water", "points": [[OUTLET[0] + x, OUTLET[1] + 8 + y] for x, y in [(-8, 0), (-5, -1.3), (5, -1.3), (8, 0), (5, 1.2), (-5, 1.2)]], "color": "#829995", "visible": False},
        {"kind": "glow", "id": "stove_heat", "pos": STOVE, "radius": 17,
         "color": "#e3b16c", "intensity": .5, "alpha": .25, "visible": False},
        {"kind": "poly", "id": "stove_flame", "points": [[STOVE[0] + x, STOVE[1] + y] for x, y in [(-21, 0), (-18, -5), (-15, -1), (-10, -6), (-6, -1), (0, -6), (4, -1), (10, -5), (14, 0)]],
         "color": "#7ba6bd", "visible": False},
    ]


def reach(actor, hand, prop=None, point=None, **extra):
    result = dict(do="reach", id=actor, hand=hand, time=.35,
                  contact=([73, 40] if actor == "rin" else [64, 39]), angle=pi / 2)
    if prop:
        result.update(space="prop", prop=prop, to=point)
    return result | extra


def release(actor, hand):
    return dict(do="reach", id=actor, hand=hand, release=True, time=.25)


def close_stove():
    return [
        dict(do="move", id="k", to=[320, 304], time=1.5, wait=False, then="idle"),
        dict(do="move", id="rin", to=[110, 304], time=1.5, wait=True, then="idle"),
        reach("rin", "front", "stove_dial", [0, 0], follow_rotation=True),
        dict(do="prop_move", id="stove_dial", angle=DIAL_OFF, time=.3),
        dict(do="sfx", id="switch", volume=-10),
        dict(do="prop_visible", id="stove_flame", visible=False),
        dict(do="prop_visible", id="stove_heat", visible=False),
        release("rin", "front"),
        dict(do="move", id="rin", to=[290, 304], time=1.8, wait=False, then="idle"),
    ]


def fill_kettle():
    # Source grip is on the left side of the black carrying handle. The other
    # hand is free to lift the lid and operate the tap; no hand swaps mid-carry.
    fill_grip = [FILL_FOOT[0] + (KETTLE_GRIP[0] - 628) * KETTLE_SCALE,
                 FILL_FOOT[1] + (KETTLE_GRIP[1] - 879) * KETTLE_SCALE]
    mat_grip = [MAT[0] + (KETTLE_GRIP[0] - 628) * KETTLE_SCALE,
                MAT[1] + (KETTLE_GRIP[1] - 879) * KETTLE_SCALE]
    return [
        dict(do="face", id="rin", dir=-1),
        dict(do="move", id="k", to=[110, 304], time=1.4, wait=True, then="idle"),
        dict(do="face", id="k", dir=-1),
        reach("k", "front", "kettle", KETTLE_GRIP),
        dict(do="prop_hold", id="kettle", actor="k", hand="front", point=KETTLE_GRIP),
        reach("k", "front", space="actor", to=[-20, -195], time=.25),
        reach("k", "front", space="actor", to=[25, -170], time=.45),
        dict(do="face", id="k", dir=1),
        dict(do="move", id="k", to=[FILL_ACTOR_X, 304], time=1.8, wait=True, then="idle"),
        dict(do="face", id="rin", dir=1),
        dict(do="pose", id="k", pose="squat", pose_reason="蹲低以壺口對準水缸出水口", pose_support="雙腳仍在廚房地面304"),
        reach("k", "front", space="actor", to=[fill_grip[0] - FILL_ACTOR_X, fill_grip[1] - 304], time=.5),
        reach("k", "back", "kettle_lid", LID_GRIP, angle=0),
        dict(do="prop_move", id="kettle_lid", angle=LID_OPEN, time=.4),
        release("k", "back"),
        reach("k", "back", "urn_lever", LEVER_GRIP, angle=0),
        dict(do="prop_move", id="urn_lever", angle=0, time=.3),
        dict(do="prop_visible", id="tap_water", visible=True),
        dict(do="wait", time=1.4),
        dict(do="prop_visible", id="kettle_water", visible=True),
        dict(do="prop", id="kettle", state="filled"),
        dict(do="prop_visible", id="tap_water", visible=False),
        dict(do="prop_move", id="urn_lever", angle=-pi / 2, time=.3),
        release("k", "back"),
        reach("k", "back", "kettle_lid", LID_GRIP, angle=0),
        dict(do="prop_move", id="kettle_lid", angle=0, time=.4),
        dict(do="prop_visible", id="kettle_water", visible=False),
        release("k", "back"),
        dict(do="pose", id="k", pose="idle"),
        reach("k", "front", space="actor", to=[25, -170], time=1.2),
        dict(do="face", id="k", dir=-1),
        dict(do="move", id="k", to=[200, 304], time=1.1, wait=True, then="idle"),
        dict(do="face", id="k", dir=1),
        reach("k", "front", space="stage", to=mat_grip, time=.4),
        dict(do="prop_release", id="kettle"),
        release("k", "front"),
        dict(do="move", id="k", to=[190, 304], time=.5, wait=True, then="idle"),
        dict(do="face", id="k", dir=1),
        dict(do="face", id="rin", dir=-1),
        dict(do="wait", time=3.0),
    ]
