"""S14: 鷺在電話亭候位椅起身，拿回 S13 搬送的破傘和裝備袋。"""
from math import pi

from build_ch1_story import actor
from medic_transport_staging import BAG, SCALE as TRANSPORT_SCALE, UMBRELLA, UMBRELLA_GRIP, UMBRELLA_SCALE, reach, sprite

FLOOR = 292
SCALE = 2.0
SEAT = dict(id="booth_bench_seat", kind="seat", rect=[218, 265, 76, 27], plane="back")
PALM = [75.5, 36.5]
BAG_GRIP = [38.5, 10.5]
BAG_SCALE = 0.2 * SCALE / TRANSPORT_SCALE
EGRET_UMBRELLA_GRIP = [177.5, 240.5]
UMBRELLA_ANGLE = -1.03
UMBRELLA_IN_HAND = [285, 220]
BAG_IN_HAND = [258, 224]


def layers():
    bag = sprite("equipment_bag", BAG, [261, 243.5], BAG_SCALE, front=True)
    bag["support"] = "市集亭候位椅"
    return (bag, sprite("broken_umbrella", UMBRELLA, [293, 265], UMBRELLA_SCALE * SCALE / TRANSPORT_SCALE,
                        pivot=EGRET_UMBRELLA_GRIP, support="破傘斜靠候位椅的右緣"))


def cast(*, opening):
    egret = actor("egret", "egret", 235 if opening else 270, FLOOR, facing=1, scale=SCALE,
                  speaker="egret", weapon="", pose="sit" if opening else "idle",
                  pose_reason="鷺復原後先在亭邊坐穩。" if opening else None,
                  pose_support="骨盆落在候位椅座面，雙腳踩地。" if opening else None)
    if opening:
        egret["seat_sag"] = 0.57
    others = (
        actor("rin", "rin", 309, FLOOR, facing=-1, scale=SCALE, speaker="rin", weapon=""),
        actor("banyan", "banyan", 400, FLOOR, facing=-1, scale=SCALE, speaker="banyan", weapon=""),
        actor("resident_side", "resident", 457, FLOOR, facing=-1, scale=SCALE, weapon=""),
        actor("worker_side", "night_worker", 499, FLOOR, facing=-1, scale=SCALE, weapon=""),
    )
    # 兩位旁觀者在各自位置旁觀，動作範圍不相交。
    others[-1]["layer"] = 3
    return (egret, *others)


def initial(*, opening):
    umbrella = {"angle": UMBRELLA_ANGLE}
    if opening:
        return {UMBRELLA: umbrella}
    umbrella["pos"] = UMBRELLA_IN_HAND
    bag_pos = [coord - grip * BAG_SCALE for coord, grip in zip(BAG_IN_HAND, BAG_GRIP)]
    return {UMBRELLA: umbrella, BAG: {"pos": bag_pos}}


def _egret_reach(point, *, prop=None, hand="front", time=0.45):
    step = dict(do="reach", id="egret", hand=hand, to=point, time=time, wait=True,
                contact=PALM, angle=0)
    if prop:
        step.update(space="prop", prop=prop)
    return step


def _hold(prop, actor_id, point, hand="front"):
    return dict(do="prop_hold", id=prop, actor=actor_id, hand=hand,
                point=point, follow_rotation=False)


def _release_hand(actor_id, hand="front"):
    return dict(do="reach", id=actor_id, hand=hand, release=True, time=0.35, wait=True)


def _wait(seconds):
    return dict(do="wait", time=seconds)


def opening():
    return (dict(do="sfx", id="beep", volume=-13, jitter=0),
            _egret_reach([224, 248], hand="back", time=0.32))


def rise():
    return (_wait(0.2), _release_hand("egret", "back"),
            dict(do="pose", id="egret", pose="idle"), _wait(0.86),
            dict(do="move", id="egret", to=[270, FLOOR], time=0.85, pose="walk", then="idle"))


def _bend(actor_id, pose):
    return dict(do="pose", id=actor_id, pose=pose, pose_reason="彎膝從候位椅拿隨身物件。",
                pose_support="雙腳踩在亭邊地面。")


def return_equipment():
    return (
        _bend("rin", "crouch"), _wait(0.45),
        reach("rin", "rin", prop=UMBRELLA, to=UMBRELLA_GRIP, angle=pi),
        _hold(UMBRELLA, "rin", UMBRELLA_GRIP),
        reach("rin", "rin", to=[300, 226], angle=pi),
        dict(do="pose", id="rin", pose="idle"),
        reach("rin", "rin", to=[295, 216], angle=pi, time=0.4),
        _egret_reach(EGRET_UMBRELLA_GRIP, prop=UMBRELLA), _wait(0.35),
        dict(do="prop_release", id=UMBRELLA),
        _hold(UMBRELLA, "egret", EGRET_UMBRELLA_GRIP),
        _egret_reach(UMBRELLA_IN_HAND), _release_hand("rin"),
        _bend("egret", "squat"), _wait(0.66),
        _egret_reach(BAG_GRIP, prop=BAG, hand="back"),
        _hold(BAG, "egret", BAG_GRIP, "back"),
        _egret_reach(BAG_IN_HAND, hand="back"),
        dict(do="pose", id="egret", pose="idle"), _wait(0.9),
    )


def resume_equipment():
    return (_egret_reach(EGRET_UMBRELLA_GRIP, prop=UMBRELLA, time=0.1),
            _hold(UMBRELLA, "egret", EGRET_UMBRELLA_GRIP),
            _egret_reach(BAG_GRIP, prop=BAG, hand="back", time=0.1),
            _hold(BAG, "egret", BAG_GRIP, "back"))


def laugh(*actors, duration):
    return (*(dict(do="pose", id=actor_id, pose="idle", loop="booth_laugh") for actor_id in actors),
            _wait(duration),
            *(dict(do="pose", id=actor_id, pose="idle", loop="") for actor_id in actors))
