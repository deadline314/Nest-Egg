"""S22 的原屋頂遠景。雨傘及門框都直接取現有貼圖區域。"""
from __future__ import annotations

from math import pi

from build_ch1_story import actor, stage

STAGE = "ch2_rooftop_watcher"
WATCHER = "greycoat"
UMBRELLA = "watcher_black_umbrella"
CLOSED = "watcher_closed_umbrella"
FLOOR = 140.0
SCALE = 0.6
START_X = 521.0
DOOR_X = 569.0
FOLD_X = 550.0
SHOT = (526, 152, 1.8)
GRIP = [158.5, 171.5]
HAND = [75.5, 48.5]
LOCAL_HAND = [0.0, -22.0]
CLOSED_HAND = [0.0, -20.0]
CLOSED_GRIP = [54.5, 53.5]


def layers() -> tuple[dict, ...]:
    canopy_scale = 0.14
    exit_scale = 0.168
    exit_art = "res://art/environment/scene_props/rooftop/rooftop__stairwell_hut.png"
    exit_left = 530
    exit_top = FLOOR - 432 * exit_scale
    closed_scale = 0.07
    return (
        dict(kind="sprite", id="opposite_stairwell", path=exit_art,
             source_width=422, region=[0, 0, 422, 432], pos=[exit_left, exit_top], scale=exit_scale,
             filter="linear", modulate="#4c6077", support="對面屋頂梯間承重於遠景女兒牆後方"),
        dict(kind="sprite", id=UMBRELLA, path="res://art/environment/scene_props/suo_boat/suo_boat__boat_umbrella.png",
             source_width=324, region=[0, 0, 324, 188],
             pos=[START_X - GRIP[0] * canopy_scale, FLOOR + LOCAL_HAND[1] - GRIP[1] * canopy_scale],
             scale=canopy_scale, filter="linear", modulate="#6a7387", visible=False, depth="front",
             support="灰衣人扶在真實傘柄上的掌心"),
        dict(kind="sprite", id=CLOSED,
             path="res://art/environment/scene_props/ending_a_stall/ending_a_stall__wet_umbrella_hung.png",
             source_width=109, region=[0, 0, 109, 331],
             pos=[FOLD_X - CLOSED_GRIP[0] * closed_scale, FLOOR + CLOSED_HAND[1] - CLOSED_GRIP[1] * closed_scale],
             scale=closed_scale, filter="linear", modulate="#242b40", visible=False, depth="front",
             support="收起後仍由灰衣人手中提著"),
        dict(kind="sprite", id="opposite_door_leaf", path=exit_art,
             source_width=422, region=[181, 166, 94, 266], pos=[exit_left + 181 * exit_scale, exit_top + 166 * exit_scale],
             scale=exit_scale, filter="linear", modulate="#4c6077", depth="front", support="同一梯間的前方門扇"),
    )


def reveal_and_retreat() -> list[dict]:
    return [
        stage(STAGE, x=SHOT[0], y=SHOT[1], zoom=SHOT[2], fade_in=0.25, feet=FLOOR),
        dict(actor(WATCHER, "ch2_greycoat", START_X, FLOOR, facing=-1, scale=SCALE, speaker="", weapon=""),
             shade=0.42, backdrop=True),
        dict(do="reach", id=WATCHER, hand="front", space="prop", prop=UMBRELLA, to=GRIP,
             contact=HAND, angle=pi / 2, time=0.25, wait=True),
        dict(do="prop_visible", id=UMBRELLA, visible=True),
        dict(do="prop_hold", id=UMBRELLA, actor=WATCHER, hand="front", point=GRIP, follow_rotation=False),
        dict(do="reach", id=WATCHER, hand="front", space="actor", to=LOCAL_HAND,
             contact=HAND, angle=pi / 2, time=0.2, wait=True),
        dict(do="wait", time=0.6),
        dict(do="move", id=WATCHER, to=[FOLD_X, FLOOR], time=1.3, pose="walk", then="idle", wait=True),
        dict(do="reach", id=WATCHER, hand="front", space="actor", to=CLOSED_HAND,
             contact=HAND, angle=pi / 2, time=0.25, wait=True),
        dict(do="prop_visible", id=UMBRELLA, visible=False),
        dict(do="prop_release", id=UMBRELLA),
        dict(do="reach", id=WATCHER, hand="front", space="prop", prop=CLOSED, to=CLOSED_GRIP,
             contact=HAND, angle=pi / 2, time=0.12, wait=True),
        dict(do="prop_visible", id=CLOSED, visible=True),
        dict(do="prop_hold", id=CLOSED, actor=WATCHER, hand="front", point=CLOSED_GRIP, follow_rotation=False),
        dict(do="reach", id=WATCHER, hand="front", space="actor", to=CLOSED_HAND,
             contact=HAND, angle=pi / 2, time=0.1, wait=True),
        dict(do="move", id=WATCHER, to=[DOOR_X, FLOOR], time=0.85, pose="walk", then="idle", wait=True),
        dict(do="prop_visible", id=CLOSED, visible=False),
        dict(do="remove", id=WATCHER),
        dict(do="wait", time=0.15),
    ]
