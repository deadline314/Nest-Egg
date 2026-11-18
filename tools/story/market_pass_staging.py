"""S05 市集入口，沿原查核證來源呈現出示、確認與讓路。"""
from __future__ import annotations

from math import pi

PASS = "public_aisle_pass"
FLOOR = 330.0
ACTOR_SCALE = 2.2
PASS_SCALE = 0.052
PASS_POS = [312.0, 244.0]
RIN_EDGE = [138.5, 287.5]
PATROLLER_EDGE = [246.5, 264.5]
RIN_HAND = [96.5, 37.5]
PATROLLER_HAND = [72.5, 47.5]


def layer() -> dict:
    return dict(kind="sprite", id=PASS, path="res://art/items/icons/doc_stub_hd.png",
                source_width=384, pos=PASS_POS, scale=PASS_SCALE, filter="linear", depth="front",
                glow=False, visible=False, support="凜出示的查核證由手掌持握")


def _hand(actor: str, point: list[float], *, contact: list[float], on_pass=False, angle=0.0) -> dict:
    reach = dict(do="reach", id=actor, hand="front", to=point, contact=contact, angle=angle, time=0.38, wait=True)
    if on_pass:
        reach.update(space="prop", prop=PASS)
    return reach


def _release(actor: str) -> dict:
    return dict(do="reach", id=actor, hand="front", release=True, time=0.3, wait=True)


def inspect_steps() -> tuple[dict, ...]:
    """卡片由凜一直持有。巡帳員摸卡邊看清楚後收手。"""
    return (
        _hand("rin", RIN_EDGE, contact=RIN_HAND, on_pass=True),
        dict(do="prop_visible", id=PASS, visible=True),
        dict(do="prop_hold", id=PASS, actor="rin", hand="front", point=RIN_EDGE, follow_rotation=False),
        _hand("rin", [322, 253], contact=RIN_HAND),
        _hand("patroller", PATROLLER_EDGE, contact=PATROLLER_HAND, on_pass=True, angle=pi),
        dict(do="wait", time=0.4),
        _release("patroller"),
    )


def clear_steps() -> tuple[dict, ...]:
    return (
        _hand("rin", [315, 253], contact=RIN_HAND),
        dict(do="prop_visible", id=PASS, visible=False),
        dict(do="prop_release", id=PASS),
        _release("rin"),
        dict(do="move", id="patroller", to=[424, FLOOR], time=1.55, pose="walk", then="idle", wait=True),
        dict(do="face", id="patroller", dir=-1),
    )
