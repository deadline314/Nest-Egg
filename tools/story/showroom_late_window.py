"""C16 晚窗：凜把座椅從西曬的光帶移到內側。"""
from __future__ import annotations

from build_ch1_story import actor, face, move, stage, wait

STAGE = "ch3_late_window"
FLOOR = 305
SHOT = (474, 242, 1.16)
ART = "res://art/environment/scene_props/clearwater/"
CHAIR = "late_window_chair"
CHAIR_SOURCE = "clearwater__window_chair.png"
CHAIR_WIDTH = 249
CHAIR_HEIGHT = 240
CHAIR_SCALE = 0.36
TABLE_POS = [383, FLOOR - 233 * CHAIR_SCALE]
TABLE_REGION = [0, 0, 82, CHAIR_HEIGHT]
CHAIR_REGION = [83, 0, CHAIR_WIDTH - 83, CHAIR_HEIGHT]
WINDOW_POS = [323, 156]
WINDOW_REGION = [0, 0, 522, 240]
WINDOW_SCALE = 0.33
CHAIR_REST = [452, FLOOR - CHAIR_HEIGHT * CHAIR_SCALE]
CHAIR_SHADE = [CHAIR_REST[0] + 27, CHAIR_REST[1]]
CHAIR_BACK = [234.5, 30.5]
RIN_REST_X = 523
RIN_FINISH_X = 547
PULL_TIME = 0.64


def _furniture(ident: str, kind: str, pos: list, scale: float, bounds: tuple[int, ...], **support) -> dict:
    # Bounds are visible alpha extents in the selected sprite region.
    left, top, right, bottom = bounds
    return dict(id=ident, kind=kind, **support,
                rect=[round(value, 3) for value in (pos[0] + left * scale, pos[1] + top * scale,
                                                   (right - left) * scale, (bottom - top) * scale)])


def definition() -> dict:
    return {
        "camera": {"pos": list(SHOT[:2]), "zoom": SHOT[2]},
        "floor": FLOOR,
        "furniture": [
            _furniture("late_window_frame", "residential_window", WINDOW_POS, WINDOW_SCALE,
                       (1, 1, 521, 240), support="固定在西側室內牆"),
            _furniture("late_window_side_table", "table", TABLE_POS, CHAIR_SCALE, (0, 64, 76, 233)),
            _furniture(CHAIR, "high_back_chair", CHAIR_REST, CHAIR_SCALE, (5, 0, 166, 240), plane="actor"),
        ],
        "layers": [
            dict(kind="gradient", top="#86818b", bottom="#b3a69b"),
            *(dict(kind="sprite", path="res://art/environment/scenes/clearwater.webp",
                   source_width=1536, region=[350, 181, 246, 258], pos=[x, 73],
                   scale=0.9, filter="linear", glow=False, modulate="#99949e")
              for x in (146, 367.4, 588.8)),
            dict(kind="rect", rect=[146, 296, 665, 9], color="#7d7380"),
            dict(kind="sprite", path="res://art/environment/scenes/clearwater.webp",
                 source_width=1536, region=[700, 797, 650, 65], pos=[146, FLOOR],
                 scale=1.03, filter="linear", glow=False, modulate="#a39a98"),
            dict(kind="poly", points=[[348, 305], [480, 305], [456, 361], [294, 361]],
                 color="#ffdfac", alpha=0.31),
            dict(kind="sprite", path=ART + "clearwater__late_window_shaded.png", source_width=522,
                 region=WINDOW_REGION, pos=WINDOW_POS, scale=WINDOW_SCALE, filter="linear", glow=False,
                 modulate="#e0d1b3", furniture_ref="late_window_frame"),
            dict(kind="sprite", path=ART + CHAIR_SOURCE, source_width=CHAIR_WIDTH,
                 region=TABLE_REGION, pos=TABLE_POS, scale=CHAIR_SCALE, filter="linear", glow=False,
                 modulate="#d2c1a5", furniture_ref="late_window_side_table"),
            dict(kind="sprite", id=CHAIR, path=ART + CHAIR_SOURCE, source_width=CHAIR_WIDTH,
                 region=CHAIR_REGION, pos=CHAIR_REST, scale=CHAIR_SCALE, filter="linear", depth="front",
                 glow=False, modulate="#d2c1a5", furniture_ref=CHAIR),
        ],
    }


def opening() -> list[dict]:
    return [
        stage(STAGE, *SHOT, fade_in=0.25, feet=FLOOR),
        actor("rin", "rin", RIN_REST_X, FLOOR, facing=-1, scale=2.4),
        actor("lin", "lin", 611, FLOOR, facing=-1, scale=2.26),
    ]


def move_chair() -> list[dict]:
    return [
        dict(do="reach", id="rin", hand="front", space="prop", prop=CHAIR, to=CHAIR_BACK,
             contact=[96.5, 37.5], angle=2.25, time=0.35, wait=True),
        dict(move("rin", RIN_FINISH_X, FLOOR, t=PULL_TIME, wait_for=False), wait=False),
        face("rin", -1),
        dict(do="prop_move", id=CHAIR, to=CHAIR_SHADE, time=PULL_TIME, wait=True),
        dict(do="sfx", id="mat_wood", volume=-18.0, jitter=0.0),
        wait(0.16),
        dict(do="reach", id="rin", hand="front", release=True, time=0.28, wait=True),
    ]
