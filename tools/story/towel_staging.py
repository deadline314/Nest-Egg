"""ST-19 S01 當舖櫃臺的乾毛巾：老 K 把毛巾沿櫃臺推給凜，凜拿起來按一下頭髮再放回櫃臺。

只是演出：毛巾是舞台上的一件擺設，不是物品，不影響結算。座標都是舞台座標（ch1_pawnshop_front 的櫃臺頂面 y=207），
握點是毛巾貼圖的原圖像素。重建舞台時毛巾回到老 K 手邊，接續的段落用 rest_steps() 把它直接放回凜那側。
兩人站得比早飯那場近（老 K 205、凜 325）：手臂只搆得到身前約 0.35 倍身高，站遠了推不過去、也接不到。
"""
from __future__ import annotations

TOWEL = "res://art/environment/scene_props/pawnshop_front_contacts/towel.png"
SOURCE = (480, 132)          # 毛巾原圖大小（像素）
WORLD_WIDTH = 11.0           # 摺好的毛巾寬約 30 公分（世界像素，主角身高 58）
ACTOR_SCALE = 3.5            # 老 K 3.6、凜 3.4，櫃臺上的東西用兩人之間的縮放
COUNTER_TOP = 207            # 舞台家具 shop_counter 的頂面
SCALE = round(ACTOR_SCALE * WORLD_WIDTH / SOURCE[0], 4)
HEIGHT = SOURCE[1] * SCALE
REST_Y = round(COUNTER_TOP - HEIGHT + 1.5, 1)   # 布底邊略壓在頂面上，不浮空
START_X = 215                # 毛巾一開始在老 K 手邊
PUSHED_X = 268               # 推過去以後
RETURNED_X = 274             # 凜擦完放回自己這側
K_GRIP = [80, 30]            # 老 K 的掌心按在毛巾左端
RIN_GRIP = [240, 30]         # 凜拿毛巾中間（按在頭頂時兩邊一樣長，蓋住頭髮而不是擋在臉前）
HAIR = [100, 35]             # 凜頭部貼圖上的頭頂側邊（head.png 168×199）
HAIR_RUB = [78, 48]


def layers() -> list[dict]:
    return [dict(kind="sprite", id="towel", path=TOWEL, pos=[START_X, REST_Y], scale=SCALE, source_width=SOURCE[0], filter="linear")]


def _stage_point(x: float, grip: list[int]) -> list[float]:
    return [round(x + grip[0] * SCALE, 1), round(REST_Y + grip[1] * SCALE, 1)]


def _reach(actor: str, **fields) -> dict:
    return dict(do="reach", id=actor, hand="front", **fields)


def push_steps() -> list[dict]:
    """老 K 張開手掌按在毛巾左端，毛巾沿櫃臺滑到凜那邊、掌心跟著走，再收手。
    他的骨架沒有握拳的手，所以不用拿起（prop_hold），而是讓手停在毛巾上（space=prop 的接觸會跟著擺設移動）。"""
    return [
        _reach("k", space="prop", prop="towel", to=K_GRIP, time=.4),
        dict(do="prop_move", id="towel", to=[PUSHED_X, REST_Y], time=.6, wait=True),
        _reach("k", release=True, time=.3),
    ]


def wipe_steps() -> list[dict]:
    """凜拿起毛巾，在頭髮上按兩下，放回自己這側的櫃臺。"""
    hair = dict(space="part", target_actor="rin", part="head")
    return [
        _reach("rin", space="prop", prop="towel", to=RIN_GRIP, time=.35, grip=True),
        dict(do="prop_hold", id="towel", actor="rin", hand="front", point=RIN_GRIP, follow_rotation=False),
        _reach("rin", to=HAIR, time=.45, **hair),
        _reach("rin", to=HAIR_RUB, time=.3, **hair),
        _reach("rin", to=HAIR, time=.3, **hair),
        dict(do="wait", time=.2),
        _reach("rin", to=_stage_point(RETURNED_X, RIN_GRIP), time=.45),
        dict(do="prop_release", id="towel"),
        _reach("rin", release=True, time=.3),
    ]


def rest_steps() -> list[dict]:
    """接續的段落：毛巾已經在凜那側。"""
    return [dict(do="prop_move", id="towel", to=[RETURNED_X, REST_Y], time=0, wait=True)]
