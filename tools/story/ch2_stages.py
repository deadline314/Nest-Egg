"""第二章的正式過場舞台（ST-19）：帳房、市集電話亭、代收處。

每個舞台是一張既有的場景立繪（1536×864 縮 0.5，鋪滿舞台 -64..704 × -36..396），需要時再疊上關卡裡同一件場景擺設的貼圖。
擺設的大小讀自它的 PropData（data/environment/scene_props/<場景>/<id>.tres），乘上這個舞台的演員縮放，和關卡裡的比例一致。
舞台檔由 build_ch2_story.py 寫到 data/cutscene/stages/<id>.json；劇本只用 frame() 把演員與鏡頭接到段落前面。
量測都在舞台座標（立繪預覽 768×432 的座標減 (64, 36)）。
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

import towel_staging
from build_ch1_story import actor as stage_actor, stage as stage_scene

ROOT = Path(__file__).resolve().parents[2]
SCENE_ART = "res://art/environment/scenes/%s.webp"
PROP_ART = "res://art/environment/scene_props/%s/%s.png"
PROP_DATA = ROOT / "data/environment/scene_props"
STAGE_DATA = ROOT / "data/cutscene/stages"
_SIZE = re.compile(r"size\s*=\s*Vector2\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)")


def _res_path(path: str) -> Path:
    return ROOT / path.removeprefix("res://")


def prop_size(scene: str, prop_id: str) -> tuple[float, float]:
    """擺設的世界大小（PropData.size）；檔案缺了或格式不對就直接報錯，指出是哪個擺設。"""
    path = PROP_DATA / scene / f"{prop_id}.tres"
    match = _SIZE.search(path.read_text(encoding="utf-8")) if path.exists() else None
    if not match:
        raise ValueError(f"讀不到擺設 {prop_id} 的大小（{path}）")
    return float(match.group(1)), float(match.group(2))


def background(scene: str, modulate: str | None = None) -> dict:
    layer = {"kind": "sprite", "path": SCENE_ART % scene, "pos": [-64, -36.0], "scale": 0.5, "filter": "linear", "source_width": 1536}
    if modulate:
        layer["modulate"] = modulate
    return layer


def prop_layer(scene: str, prop_id: str, x: float, floor: float, scale: float, *, front: bool = False, glow: bool = False) -> dict:
    """關卡擺設貼在舞台上：左緣 x、底邊落在 floor；縮放＝演員縮放 × 世界寬 ÷ 貼圖寬（StageFitAudit 依此核對）。"""
    width, height = prop_size(scene, prop_id)
    path = PROP_ART % (scene, prop_id)
    tex_w = Image.open(_res_path(path)).size[0]
    layer = {"kind": "sprite", "path": path, "pos": [round(x, 1), round(floor - height * scale, 1)],
             "scale": round(scale * width / tex_w, 4), "filter": "linear", "source_width": tex_w}
    if glow:
        layer["glow"] = True
    if front:
        layer["depth"] = "front"
    return layer


@dataclass(frozen=True)
class Cast:
    """一位演員：id、骨架種類、位置、面向；可選姿勢要附上原因與支撐（劇本檢查要求每個非站姿都說清楚）。"""
    ident: str
    x: float
    facing: int
    kind: str = ""
    floor: float | None = None
    pose: str | None = None
    pose_reason: str | None = None
    pose_support: str | None = None
    scale: float | None = None   # 沒給就用舞台的演員縮放（同一舞台身高不同的人才另外給）


@dataclass(frozen=True)
class Stage:
    ident: str
    floor: float
    scale: float
    shot: tuple[float, float, float]
    layers: tuple[dict, ...]
    furniture: tuple[dict, ...] = ()
    floors: tuple[float, ...] = ()

    def definition(self) -> dict:
        data = {"camera": {"pos": list(self.shot[:2]), "zoom": self.shot[2]}, "floor": self.floor,
                "layers": [dict(layer) for layer in self.layers]}
        if self.floors:
            data["floors"] = list(self.floors)
        if self.furniture:
            data["furniture"] = [dict(item) for item in self.furniture]
        return data

    def frame(self, cast: tuple[Cast, ...], opening: bool = False) -> list[dict]:
        """段落開頭的舞台與演員；接續的段落只用很短的淡入，畫面不跳。"""
        x, y, zoom = self.shot
        steps = [stage_scene(self.ident, x=x, y=y, zoom=zoom, fade_in=0.8 if opening else 0.25, feet=self.floor)]
        for member in cast:
            kind = member.kind or member.ident
            ground = self.floor if member.floor is None else member.floor
            scale = self.scale if member.scale is None else member.scale
            steps.append(stage_actor(member.ident, kind, member.x, ground, facing=member.facing, scale=scale,
                                     speaker=kind, pose=member.pose, weapon="", pose_reason=member.pose_reason,
                                     pose_support=member.pose_support))
        return steps


# --- 帳房（S13）：art/environment/scenes/yong_hideout.webp ---------------------------------------------
# 量自立繪：辦公桌正面 x 217～382、桌面 y≈215、桌腳落地 y≈284（高 69）；木地板前緣 y≈311，演員站在 296。
# 縮放照桌高定：桌高 69 是身高的 0.63（高辦公桌，比例表 counter 0.6～0.64）→ 58 × 1.9 ≈ 110。
LEDGER = Stage(
    "ch2_ledger_office", floor=296, scale=1.9, shot=(320, 200, 1.2),
    layers=({"kind": "gradient", "top": "#120808", "bottom": "#2a1410", "parallax": 0.0},
            background("yong_hideout"),
            {"kind": "glow", "pos": [310, 160], "radius": 150, "color": "#ffd08a", "intensity": 0.6, "additive": True, "alpha": 0.3,
             "pulse": 0.05, "pulse_depth": 0.2}),
    furniture=({"id": "ledger_desk", "kind": "counter", "rect": [217, 215, 165, 69]},))

# --- 市集電話亭（S14）：art/environment/scenes/anchor_phone_booth.webp，疊上關卡裡同一座電話亭 --------------
# 量自立繪：人行道從牆腳 y≈249 到路緣 y≈304，演員與電話亭都站在 292。捲門高約 180（1.5 身高，車庫門），縮放 2.0。
BOOTH_FLOOR = 292
BOOTH = Stage(
    "ch2_phone_booth", floor=BOOTH_FLOOR, scale=2.0, shot=(300, 196, 1.15),
    layers=({"kind": "gradient", "top": "#05080c", "bottom": "#0c141a", "parallax": 0.0},
            background("anchor_phone_booth", modulate="#c8d2dc"),
            prop_layer("anchor_phone_booth", "anchor_phone_booth__phone_booth", 150, BOOTH_FLOOR, 2.0, glow=True),
            {"kind": "glow", "pos": [174, 190], "radius": 140, "color": "#7fe0c8", "intensity": 0.8, "additive": True, "alpha": 0.35,
             "pulse": 0.08, "pulse_depth": 0.25},
            {"kind": "rain", "depth": "front", "opacity": 0.3}))

# --- 代收處（S06）：art/environment/scenes/neon_market.webp，疊上關卡裡同一張收款桌 -------------------------
# 量自立繪：攤位在水面倒影後方，前景濕路面 y≈304～354；演員站在 330，利息站在收款桌後一點（322），桌子畫在他前面。
COLLECTION_FLOOR = 330
COLLECTION_BEHIND = 322
COLLECTION = Stage(
    "ch2_collection_desk", floor=COLLECTION_FLOOR, scale=2.0, shot=(330, 226, 1.2), floors=(COLLECTION_BEHIND,),
    layers=({"kind": "gradient", "top": "#0a0614", "bottom": "#1a1024", "parallax": 0.0},
            background("neon_market", modulate="#c8c0d0"),
            {"kind": "glow", "pos": [420, 250], "radius": 160, "color": "#ff8a6a", "intensity": 0.6, "additive": True, "alpha": 0.25,
             "pulse": 0.06, "pulse_depth": 0.2},
            prop_layer("neon_market", "neon_market__debt_desk", 380, COLLECTION_FLOOR, 2.0, front=True)))



def derived(ident: str, base: str, extra: tuple[dict, ...], scale: float, shot: tuple[float, float, float]) -> Stage:
    """沿用既有舞台（立繪、家具、地面線）再加幾件擺設；原舞台檔不動，加的東西畫在原本的圖層之後。"""
    data = json.loads((STAGE_DATA / f"{base}.json").read_text(encoding="utf-8"))
    return Stage(ident, floor=data["floor"], scale=scale, shot=shot, layers=tuple(data["layers"]) + extra,
                 furniture=tuple(data.get("furniture", ())), floors=tuple(data.get("floors", ())))


# --- 當舖櫃臺（S01）：沿用第一章的 ch1_pawnshop_front，櫃臺上多一條乾毛巾（tools/story/towel_staging.py） ---------
PAWNSHOP = derived("ch2_pawnshop_counter", "ch1_pawnshop_front", tuple(towel_staging.layers()), scale=3.5, shot=(300, 290, 0.88))

STAGES = (LEDGER, BOOTH, COLLECTION, PAWNSHOP)
