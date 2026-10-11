"""看門狗（四足機械犬）的零件與生物定義。CPU，不需要模型；輸入都先核對。

    D:/ComfyUI/.venv/Scripts/python.exe art_src/creatures/watchdog/parts/build_parts.py

輸入  ../design_21801/design_rgba.png          設計圖（四條腿都看得到的側面站姿）
      raw/watchdog_nolegs_s21871_0.png         同一張圖拿掉四條腿的底層（generate.py）
      sam/<名稱>.png                            SAM 3.1 遮罩：head、tail、gun_turret 用文字提示，front_leg、rear_leg 用點提示（SAM_POINTS）
輸出  art/creatures/watchdog/<零件>.png         原尺寸裁切，不縮放
      art/creatures/watchdog.json              PartCreature 的定義（零件、步態、各狀態）
做法  身體取底層圖，頭、尾、砲塔、腿取設計圖的原像素。腿依關節折線分段；每一段在自己的關節各多留一個圓盤，
      關節轉動時兩段互相蓋住。身體在頭、尾、砲塔的接點各留一小塊被蓋住的底，轉動時不露縫。
      遠側的兩條腿沿用近側的貼圖，壓暗、往前錯開，步態相位相反。
法線圖由 tools/art/paint_normals（--only=creatures）產生。改了關節或狀態就重跑這支腳本，再跑法線與匯入。
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / "art/creatures/watchdog"
DESIGN = HERE.parent / "design_21801" / "design_rgba.png"
NOLEGS = HERE / "raw" / "watchdog_nolegs_s21871_0.png"
INPUTS = {DESIGN: "94c7378b622ff62edbe79fc69f59a4691dc01e77dd49c62aada8e944e018a2f7", NOLEGS: "eedbca4126dc08349df6462c57762b7064734decb545c39012f9c38911fb283d"}
# 重新分割時用的點（設計圖像素）；遮罩已存在 sam/，平常不需要再跑模型。
SAM_POINTS = {"front_leg": {"pos": [[890, 470], [840, 690], [880, 850]], "neg": [[960, 690], [1040, 840], [700, 400], [1000, 300]]},
              "rear_leg": {"pos": [[490, 480], [370, 610], [280, 720], [290, 840]], "neg": [[420, 720], [450, 840], [650, 380], [370, 420]]}}
SCALE = 0.08          # 世界像素／貼圖像素：耳尖離地約 66，全長約 82
ORIGIN = (640, 880)   # 設計圖上對應敵人腳底中心的點（四隻腳掌之間、腳底的那一列）
ALPHA_FLOOR = 40
WHITE_KNEE = 150.0    # 亮度（RGB 最大值）超過這裡的部分減半
JOINT_DISC = 34       # 每段腿在關節多留的圓盤半徑（設計圖像素），比關節的圓軸大一點
BODY_PIVOT = (700, 400)
HEAD_PIVOT, TAIL_PIVOT, TURRET_PIVOT, MUZZLE = (1140, 228), (430, 353), (927, 205), (1048, 157)
FRONT = [("front_upper", (947, 402)), ("front_lower", (845, 571)), ("front_paw", (835, 797)), (None, (900, 880))]
REAR = [("rear_thigh", (494, 410)), ("rear_shank", (430, 579)), ("rear_meta", (319, 643)), ("rear_paw", (256, 790)), (None, (300, 880))]
FAR_SHIFT = {"front": (34, -4), "rear": (40, -4)}  # 遠側腿的根部比近側往前、往上一點
FAR_TINT = 0.55


def load_mask(name: str, shape: tuple[int, int]) -> np.ndarray:
    return np.asarray(Image.open(HERE / "sam" / f"{name}.png").convert("L").resize((shape[1], shape[0]))) > 127


def grow(mask: np.ndarray, r: int) -> np.ndarray:
    return cv2.dilate(mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))) > 0


def disc(shape: tuple[int, int], centre, radius: float) -> np.ndarray:
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return np.hypot(xx - centre[0], yy - centre[1]) <= radius


def segment_distance(shape: tuple[int, int], a, b) -> np.ndarray:
    """每個像素到線段 a-b 的距離。"""
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    a, b = np.array(a, float), np.array(b, float)
    d = b - a
    t = np.clip(((xx - a[0]) * d[0] + (yy - a[1]) * d[1]) / max(float(d @ d), 1e-6), 0.0, 1.0)
    return np.hypot(xx - (a[0] + t * d[0]), yy - (a[1] + t * d[1]))


def save_part(name: str, rgba: np.ndarray, keep: np.ndarray, pivot) -> dict:
    """裁出零件、存檔，回傳貼圖上的支點。"""
    layer = rgba.copy()
    layer[:, :, 3][~keep] = 0
    ys, xs = np.nonzero(layer[:, :, 3] > 0)
    if len(ys) == 0:
        raise SystemExit(f"[watchdog] 零件 {name} 是空的：檢查遮罩與關節")
    x0, y0, x1, y1 = max(xs.min() - 2, 0), max(ys.min() - 2, 0), xs.max() + 3, ys.max() + 3
    Image.fromarray(layer[y0:y1, x0:x1]).save(OUT / f"{name}.png")
    return {"file": f"{name}.png", "pivot": [int(pivot[0] - x0), int(pivot[1] - y0)]}


def world(a, b) -> list:
    """設計圖上 a 相對 b 的位移，換成世界像素。"""
    return [round((a[0] - b[0]) * SCALE, 2), round((a[1] - b[1]) * SCALE, 2)]


def leg_parts(design: np.ndarray, mask: np.ndarray, chain: list) -> dict:
    """依關節折線把一條腿分段：像素歸給最近的那一段，再加上兩端關節的圓盤。"""
    shape = mask.shape
    joints = [point for _, point in chain]
    distance = np.stack([segment_distance(shape, joints[i], joints[i + 1]) for i in range(len(joints) - 1)])
    nearest = distance.argmin(0)
    out = {}
    for i, (name, joint) in enumerate(chain[:-1]):
        keep = mask & ((nearest == i) | disc(shape, joint, JOINT_DISC) | (disc(shape, joints[i + 1], JOINT_DISC) if i + 1 < len(chain) - 1 else False))
        out[name] = save_part(name, design, keep, joint)
    return out


def states() -> dict:
    """每個狀態的姿勢（角度是弧度，正的是順時針；腿往下垂，所以負的往前擺）。狀態名稱對應看門狗的行為狀態。"""
    def ch(part, prop, base=0.0, amp=0.0, freq=1.0):
        return {"part": part, "prop": prop, "base": base, "amp": amp, "freq": freq}
    return {
        "idle": {"root": {"bob_amp": 0.25, "bob_freq": 0.5}, "channels": [ch("head", "rot", 0.0, 0.03, 0.3), ch("tail", "rot", 0.0, 0.12, 0.8), ch("body", "sy", 0.0, 0.008, 0.5)]},
        "dormant": {"root": {"bob_amp": 0.12, "bob_freq": 0.25}, "channels": [ch("head", "rot", 0.5, 0.01, 0.25), ch("tail", "rot", 0.45, 0.0, 1.0), ch("turret", "rot", 0.35, 0.0, 1.0)]},
        "intro": {"root": {"bob_amp": 0.4, "bob_freq": 2.0}, "channels": [ch("head", "rot", -0.18, 0.06, 3.0), ch("tail", "rot", -0.2, 0.3, 4.0), ch("body", "sx", 0.02, 0.01, 3.0)]},
        "burst_windup": {"root": {"bob_amp": 0.0, "bob_freq": 1.0}, "channels": [ch("body", "x", -1.5), ch("head", "rot", 0.14), ch("tail", "rot", -0.4, 0.04, 9.0), ch("front_upper", "rot", -0.1), ch("far_front_upper", "rot", -0.1)]},
        "burst": {"root": {"bob_amp": 0.0, "bob_freq": 1.0}, "channels": [ch("body", "x", -1.0, 0.5, 14.0), ch("head", "rot", 0.12), ch("tail", "rot", -0.4, 0.06, 12.0)]},
        "leap_windup": {"root": {"bob_amp": 0.0, "bob_freq": 1.0}, "channels": [ch("body", "sy", -0.08), ch("body", "y", 3.0), ch("body", "rot", 0.05), ch("head", "rot", 0.2), ch("tail", "rot", -0.5, 0.05, 10.0)]},
        "leap": {"root": {"bob_amp": 0.0, "bob_freq": 1.0}, "channels": [ch("body", "rot", -0.18), ch("body", "sx", 0.05), ch("head", "rot", 0.1), ch("tail", "rot", 0.5),
                                                                       ch("front_upper", "rot", -0.38), ch("far_front_upper", "rot", -0.46), ch("front_lower", "rot", 0.35), ch("far_front_lower", "rot", 0.35),
                                                                       ch("rear_thigh", "rot", 0.4), ch("far_rear_thigh", "rot", 0.32), ch("rear_meta", "rot", 0.3), ch("far_rear_meta", "rot", 0.3)]},
        "fan_windup": {"root": {"bob_amp": 0.0, "bob_freq": 1.0}, "channels": [ch("head", "rot", -0.32, 0.03, 8.0), ch("tail", "rot", -0.6, 0.05, 10.0), ch("body", "sy", 0.02, 0.012, 8.0)]},
        "phase_shift": {"root": {"bob_amp": 0.3, "bob_freq": 6.0}, "channels": [ch("body", "x", 0.0, 0.8, 16.0), ch("head", "rot", -0.1, 0.2, 6.0), ch("tail", "rot", 0.0, 0.5, 7.0)]},
    }


def main() -> None:
    for path, want in INPUTS.items():
        got = hashlib.sha256(path.read_bytes()).hexdigest()
        if got != want:
            raise SystemExit(f"[watchdog] {path.name} 的雜湊 {got[:12]} 不是登記的那張（{want[:12]}），停止")
    design = np.asarray(Image.open(DESIGN).convert("RGBA")).copy()
    shape = design.shape[:2]
    hull = np.asarray(Image.open(NOLEGS).convert("RGBA").resize((shape[1], shape[0]), Image.LANCZOS)).copy()
    for picture in (design, hull):
        picture[:, :, 3][picture[:, :, 3] < ALPHA_FLOOR] = 0
        # 米白色的裝甲在場景燈下會整片變成純白、看不到分片線：把亮部壓一半（150 以上的亮度減半，最亮約 200）
        rgb = picture[:, :, :3].astype(np.float32)
        peak = rgb.max(2, keepdims=True)
        picture[:, :, :3] = (rgb * np.where(peak > WHITE_KNEE, (WHITE_KNEE + (peak - WHITE_KNEE) * 0.5) / np.maximum(peak, 1.0), 1.0)).round().astype(np.uint8)
    solid = design[:, :, 3] > 0
    head, tail, turret = (grow(load_mask(name, shape), 2) & solid for name in ("head", "tail", "gun_turret"))
    legs = {name: ndimage.binary_fill_holes(grow(load_mask(name, shape), 2)) & solid for name in ("front_leg", "rear_leg")}
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    textures = {}
    # 身體：底層圖去掉頭、尾、砲塔，但在各自的接點留一小塊被蓋住的底
    keep = hull[:, :, 3] > 0
    keep &= ~(grow(head, 3) & ~disc(shape, HEAD_PIVOT, 42)) & ~(grow(tail, 3) & ~disc(shape, TAIL_PIVOT, 22)) & ~(grow(turret, 3) & ~disc(shape, TURRET_PIVOT, 16))
    labels, count = ndimage.label(keep)
    if count > 1:  # 底層圖偶爾留下的游離小塊
        keep = labels == (1 + int(np.argmax(ndimage.sum(keep, labels, range(1, count + 1)))))
    textures["body"] = save_part("body", hull, keep, BODY_PIVOT)
    textures["head"] = save_part("head", design, head, HEAD_PIVOT)
    textures["tail"] = save_part("tail", design, tail, TAIL_PIVOT)
    textures["turret"] = save_part("turret", design, turret, TURRET_PIVOT)
    textures.update(leg_parts(design, legs["front_leg"], FRONT))
    textures.update(leg_parts(design, legs["rear_leg"], REAR))

    parts = [{"name": "body", **textures["body"], "pos": world(BODY_PIVOT, ORIGIN), "z": 0}]

    def add_leg(prefix: str, chain: list, shift, z: int, tint: float | None) -> None:
        parent, parent_joint = "body", BODY_PIVOT
        for i, (name, joint) in enumerate(chain[:-1]):
            at = (joint[0] + shift[0], joint[1] + shift[1]) if i == 0 else joint
            entry = {"name": prefix + name, **textures[name], "pos": world(at, parent_joint), "parent": parent, "z": z if i == 0 else (-1 if i < len(chain) - 2 else 0)}
            if tint is not None:
                entry["tint"] = tint
            parts.append(entry)
            parent, parent_joint = prefix + name, joint

    add_leg("far_", FRONT, FAR_SHIFT["front"], -3, FAR_TINT)
    add_leg("far_", REAR, FAR_SHIFT["rear"], -3, FAR_TINT)
    parts.append({"name": "tail", **textures["tail"], "pos": world(TAIL_PIVOT, BODY_PIVOT), "parent": "body", "z": -1})
    parts.append({"name": "turret", **textures["turret"], "pos": world(TURRET_PIVOT, BODY_PIVOT), "parent": "body", "z": 1, "aim": 1.0,
                  "recoil": [-1.2, 0.0], "muzzle": world(MUZZLE, TURRET_PIVOT)})
    parts.append({"name": "head", **textures["head"], "pos": world(HEAD_PIVOT, BODY_PIVOT), "parent": "body", "z": 2})
    add_leg("", FRONT, (0, 0), 3, None)
    add_leg("", REAR, (0, 0), 3, None)
    definition = {
        "description": "看門狗（PartCreature，NE-218）：四足機械犬，背上一座小砲塔。小跑時對角的腿同步，砲塔跟著瞄準方向轉；睡著時低頭垂尾，"
                       "連射前後坐、撲擊前壓低再伸展、扇形彈幕前仰頭。零件與這份檔案由 art_src/creatures/watchdog/parts/build_parts.py 產生，不要手改。",
        "dir": "res://art/creatures/watchdog/", "texture_scale": SCALE, "parts": parts,
        "gait": {"stride": 44, "full_speed": 60, "hop": 0.9, "legs": [
            {"part": "front_upper", "phase": 0.0, "swing": 0.3, "lift": 1.0}, {"part": "front_lower", "phase": 0.6, "swing": 0.2, "lift": 0.0},
            {"part": "far_front_upper", "phase": math.pi, "swing": 0.3, "lift": 1.0}, {"part": "far_front_lower", "phase": math.pi + 0.6, "swing": 0.2, "lift": 0.0},
            {"part": "rear_thigh", "phase": math.pi, "swing": 0.26, "lift": 1.0}, {"part": "rear_shank", "phase": math.pi + 0.6, "swing": 0.16, "lift": 0.0},
            {"part": "far_rear_thigh", "phase": 0.0, "swing": 0.26, "lift": 1.0}, {"part": "far_rear_shank", "phase": 0.6, "swing": 0.16, "lift": 0.0}]},
        "states": states(),
    }
    (ROOT / "art/creatures/watchdog.json").write_text(json.dumps(definition, ensure_ascii=False, indent=1) + "\n", encoding="utf8")
    print(f"watchdog: {len(textures)} 張貼圖、{len(parts)} 個零件；耳尖離地 {round((ORIGIN[1] - np.nonzero(solid)[0].min()) * SCALE, 1)} 世界像素")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
