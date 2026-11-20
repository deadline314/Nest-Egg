"""第二章的正式過場舞台（ST-19）：帳房、市集電話亭、代收處。

每個舞台是一張既有的場景立繪（1536×864 縮 0.5，鋪滿舞台 -64..704 × -36..396），需要時再疊上關卡裡同一件場景擺設的貼圖。
擺設的大小讀自它的 PropData（data/environment/scene_props/<場景>/<id>.tres），乘上這個舞台的演員縮放，和關卡裡的比例一致。
舞台檔由 build_ch2_story.py 寫到 data/cutscene/stages/<id>.json；劇本只用 frame() 把演員與鏡頭接到段落前面。
量測都在舞台座標（立繪預覽 768×432 的座標減 (64, 36)）。
"""
from __future__ import annotations

import json
import re
import struct
from dataclasses import dataclass, replace
from pathlib import Path

import towel_staging
import rent_window_staging
import ledger_dispute_staging
import medic_transport_staging
import booth_return_staging
import market_pass_staging
import roof_watcher_staging
import roof_tea_staging
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


def png_width(path: Path) -> int:
    """PNG 貼圖的寬（讀檔頭的 IHDR，不依賴影像套件；CI 的劇本檢查沒有安裝 Pillow）。"""
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} 不是有效的 PNG，讀不到寬度")
    return struct.unpack(">I", header[16:20])[0]


def background(scene: str, modulate: str | None = None) -> dict:
    layer = {"kind": "sprite", "path": SCENE_ART % scene, "pos": [-64, -36.0], "scale": 0.5, "filter": "linear", "source_width": 1536}
    if modulate:
        layer["modulate"] = modulate
    return layer


def prop_layer(scene: str, prop_id: str, x: float, floor: float, scale: float, *, front: bool = False, glow: bool = False) -> dict:
    """關卡擺設貼在舞台上：左緣 x、底邊落在 floor；縮放＝演員縮放 × 世界寬 ÷ 貼圖寬（StageFitAudit 依此核對）。"""
    width, height = prop_size(scene, prop_id)
    path = PROP_ART % (scene, prop_id)
    tex_w = png_width(_res_path(path))
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

LEDGER_DISPUTE = replace(LEDGER, ident="ch2_ledger_dispute", shot=(300, 216, 1.22),
                         layers=LEDGER.layers + ledger_dispute_staging.layers())

# S11：在原帳房立繪的高臺上沿用正式關卡的小薇座椅與黃傘。
_XIAOWEI_PLATFORM = 223.0
_XIAOWEI_FOOTREST = 219.4
_XIAOWEI_CHAIR_X = 451.0
_XIAOWEI_CHAIR = prop_layer("yong_hideout", "yong_hideout__xiaowei_chair_umbrella",
                            _XIAOWEI_CHAIR_X, _XIAOWEI_PLATFORM, LEDGER.scale)
_XIAOWEI_CHAIR["support_rect"] = [411, _XIAOWEI_PLATFORM, 103, 4]
_XIAOWEI_CHAIR_SCALE = _XIAOWEI_CHAIR["scale"]
_XIAOWEI_SEAT_Y = _XIAOWEI_CHAIR["pos"][1] + 63.5 * _XIAOWEI_CHAIR_SCALE
_XIAOWEI_SEAT_X = (_XIAOWEI_CHAIR_X + 40.0 * _XIAOWEI_CHAIR_SCALE,
                   _XIAOWEI_CHAIR_X + 99.0 * _XIAOWEI_CHAIR_SCALE)
LEDGER_XIAOWEI = replace(
    LEDGER, ident="ch2_ledger_xiaowei", shot=(350, 252, 1.13), floors=(_XIAOWEI_PLATFORM,_XIAOWEI_FOOTREST),
    furniture=LEDGER.furniture + (
        dict(id="xiaowei_safety_seat", kind="seat", plane="actor", support="platform",
             rect=[_XIAOWEI_SEAT_X[0], _XIAOWEI_SEAT_Y, _XIAOWEI_SEAT_X[1] - _XIAOWEI_SEAT_X[0],
                   _XIAOWEI_PLATFORM - _XIAOWEI_SEAT_Y]),),
    layers=LEDGER.layers + (
        _XIAOWEI_CHAIR,
        dict(kind="rect", rect=[456, _XIAOWEI_FOOTREST,22, 1.3], color="#806052"),
        dict(kind="rect", rect=[456.8, _XIAOWEI_FOOTREST+1.3, 20, 1.7], color="#503c35"),
        dict(kind="rect", rect=[458.4, _XIAOWEI_FOOTREST+2.6, 1.7, 1.0], color="#443430"),
        dict(kind="rect", rect=[473.0, _XIAOWEI_FOOTREST+2.6, 1.7, 1.0], color="#443430"),
        # 玻璃沿原門框構圖。低亮度反射留出臉部與黃傘的輪廓。
        dict(kind="rect", rect=[411, 115, 103, 108], color="#4b5c67", alpha=0.14, depth="front"),
        dict(kind="rect", rect=[411, 115, 1.4, 108], color="#6b5150", alpha=0.72, depth="front"),
        dict(kind="rect", rect=[512, 115, 2, 108], color="#392a2b", alpha=0.75, depth="front"),
        dict(kind="rect", rect=[411, 221.6, 103, 1.4], color="#5a413e", alpha=0.75, depth="front"),
        dict(kind="poly", points=[[413, 120],[470, 120],[421, 177],[413, 177]], color="#fff2d3", alpha=0.12, depth="front"),
        dict(kind="poly", points=[[503, 123],[509, 123],[476, 162],[470, 162]], color="#fff2e0", alpha=0.12, depth="front"),
    ))


def ledger_xiaowei_actor() -> dict:
    seated = stage_actor("xiaowei", "xiaowei", 483, _XIAOWEI_FOOTREST, facing=-1, scale=LEDGER_XIAOWEI.scale,
                         speaker="xiaowei", pose="sit", loop="glance", weapon="",
                         pose_reason="坐在高臺的安全座位，問父親傘要放在何處。",
                         pose_support=f"椅面 x={_XIAOWEI_SEAT_X[0]:.1f}～{_XIAOWEI_SEAT_X[1]:.1f}、y={_XIAOWEI_SEAT_Y:.1f}；"
                                      f"雙腳落在椅前腳踏 y={_XIAOWEI_FOOTREST:.1f}。")
    seated["seat_sag"] = 0.45
    return seated


# 主箱、主機與維修側箱安在高臺下的同一組牆架。主箱沿用戰鬥外觀的青燈和橫把手。
LEDGER_CONTROLS = replace(
    LEDGER_XIAOWEI, ident="ch2_ledger_controls", shot=(386, 253, 1.15),
    layers=LEDGER_XIAOWEI.layers + (
        dict(kind="poly", points=[[432, 281], [521, 281], [535, 289], [514, 294], [436, 294], [426, 290]],
             color="#160f12", alpha=0.58),
        dict(kind="poly", points=[[432, 239], [446, 231], [506, 231], [520, 239], [508, 246], [432, 246]],
             color="#534648"),
        dict(kind="poly", points=[[432, 239], [505, 239], [520, 232], [520, 282], [505, 290], [432, 290]],
             color="#2e2428"),
        dict(kind="poly", points=[[505, 239], [520, 232], [520, 282], [505, 290]], color="#211b21"),
        dict(kind="rect", rect=[433, 286, 71, 3], color="#5a4545"),
        dict(kind="rect", rect=[438, 242, 29, 39], color="#655e62"),
        dict(kind="rect", rect=[439.3, 243.3, 26.4, 36.4], color="#2f2b32"),
        dict(kind="rect", rect=[443, 259, 16, 3.5], color="#838388"),
        dict(kind="rect", rect=[448.5, 246, 5, 5], color="#9ae5f0"),
        dict(kind="rect", rect=[481, 248, 23, 26], color="#1d2029"),
        dict(kind="rect", rect=[483, 250, 19, 21], color="#3b4449"),
        dict(kind="rect", rect=[486, 252, 14, 8], color="#8fced1"),
        dict(kind="rect", rect=[489, 264, 9, 1.6], color="#a1a2a0"),
        dict(kind="rect", rect=[510, 208, 26, 62], color="#31252a"),
        dict(kind="rect", rect=[508, 260, 29, 3.5], color="#574345"),
        medic_transport_staging.sprite("pause_box", "medic_side_box", medic_transport_staging.BOX_POS,
                                      medic_transport_staging.BOX_SCALE),
        dict(kind="poly", points=[[512, 211], [533, 209], [537, 214], [537, 250], [512, 252]], color="#363039"),
        dict(kind="poly", points=[[514, 213], [531, 211], [535, 215], [535, 247], [514, 249]], color="#565059"),
        dict(kind="rect", rect=[518, 219, 12, 1.5], color="#ddae69"),
        dict(kind="rect", rect=[518, 221.5, 12, 1.5], color="#ddae69"),
        dict(kind="rect", rect=[515, 244, 2, 2], color="#93818a"),
        dict(kind="rect", rect=[532, 243, 2, 2], color="#93818a"),
    ))


# --- 市集電話亭（S14）：art/environment/scenes/anchor_phone_booth.webp，疊上關卡裡同一座電話亭 --------------
# 量自立繪：人行道從牆腳 y≈249 到路緣 y≈304，演員與電話亭都站在 292。捲門高約 180（1.5 身高，車庫門），縮放 2.0。
BOOTH_FLOOR = booth_return_staging.FLOOR
BOOTH = Stage(
    "ch2_phone_booth", floor=BOOTH_FLOOR, scale=booth_return_staging.SCALE, shot=(300, 196, 1.15),
    layers=({"kind": "gradient", "top": "#05080c", "bottom": "#0c141a", "parallax": 0.0},
            background("anchor_phone_booth", modulate="#c8d2dc"),
            prop_layer("anchor_phone_booth", "anchor_phone_booth__phone_booth", 150, BOOTH_FLOOR, 2.0, glow=True),
            {"kind": "glow", "pos": [174, 190], "radius": 140, "color": "#7fe0c8", "intensity": 0.8, "additive": True, "alpha": 0.35,
             "pulse": 0.08, "pulse_depth": 0.25},
            {"kind": "rain", "depth": "front", "opacity": 0.3},
            prop_layer("night_harbor", "night_harbor__harbor_bench_wet", 205, BOOTH_FLOOR, booth_return_staging.SCALE))
           + booth_return_staging.layers(),
    furniture=(booth_return_staging.SEAT,))

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

RENT_WINDOW = Stage(
    "ch2_rent_window", floor=rent_window_staging.FLOOR, scale=rent_window_staging.ACTOR_SCALE,
    shot=(350, 294, 1.15),
    layers=({"kind": "gradient", "top": "#0a0614", "bottom": "#1a1024", "parallax": 0.0},
            background("neon_market", modulate="#c8c0d0")) + rent_window_staging.layers(),
    furniture=rent_window_staging.furniture())

MEDIC_LEDGER = Stage(
    "ch2_medic_transport", floor=296, scale=1.9, shot=(370,256,1.1),
    layers=LEDGER.layers + medic_transport_staging.layers(), furniture=LEDGER.furniture)

# S05 查核證在市集濕路面上出示；背景中間的公眾攤道保持可見。
MARKET_PASS = Stage(
    "ch2_market_pass", floor=market_pass_staging.FLOOR, scale=market_pass_staging.ACTOR_SCALE, shot=(337, 243, 1.14),
    layers=({"kind": "gradient", "top": "#0a0614", "bottom": "#1a1024", "parallax": 0.0},
            background("neon_market", modulate="#b8b0c3"),
            {"kind": "glow", "pos": [325, 235], "radius": 160, "color": "#f9c28c", "intensity": 0.52,
             "additive": True, "alpha": 0.28, "pulse": 0.04, "pulse_depth": 0.12},
            market_pass_staging.layer(), {"kind": "rain", "depth": "front", "opacity": 0.28}))

# S22 沿用同一屋頂景色，換成遠樓的落腳高度。
ROOF_WATCHER = replace(derived(
    roof_watcher_staging.STAGE, "ch1_rooftop", roof_watcher_staging.layers(),
    scale=roof_watcher_staging.SCALE, shot=roof_watcher_staging.SHOT), floor=roof_watcher_staging.FLOOR)

ROOF_TEA = replace(derived(roof_tea_staging.STAGE, "ch1_rooftop", roof_tea_staging.layers(), scale=2.2, shot=(320, 200, 1.0)),
                   furniture=roof_tea_staging.furniture())

STAGES = (LEDGER, LEDGER_DISPUTE, LEDGER_XIAOWEI, LEDGER_CONTROLS, BOOTH, COLLECTION, PAWNSHOP, RENT_WINDOW, MEDIC_LEDGER, MARKET_PASS, ROOF_WATCHER, ROOF_TEA)
