#!/usr/bin/env python3
"""ST-19 當舖櫃臺的乾毛巾：畫一條摺好的毛巾（正面看，三層摺邊，兩端圓角，近兩端各一道細條紋）。

現有素材裡沒有能乾淨裁下的毛巾（船上的毯子被保溫瓶、外套與長凳蓋住），所以用和其他擺設相同的畫法自己畫：
深色描邊、兩階明暗、上緣受光，加一點毛圈布的顆粒。輸出是候選原圖，由 tools/assets/story_staging_art.py
照 assets_src/pipeline/story_staging_art.json 收進遊戲（補法線、對齊偶數邊）。

用法：python3 tools/assets/draw_folded_towel.py [輸出路徑]
同一個種子每次畫出一樣的圖（雜湊登記在清單裡）。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "assets_src/candidates/st19_towel/folded-towel-drawn.png"
WIDTH, HEIGHT = 480, 132
MARGIN = 6
SEED = 1906

BASE = np.array([226, 218, 202], float)      # 米白毛圈布
SHADE = np.array([178, 166, 150], float)     # 背光面
LIGHT = np.array([244, 238, 226], float)     # 上緣受光
STRIPE = np.array([92, 132, 138], float)     # 兩端的細條紋（灰青）
OUTLINE = np.array([58, 44, 36], float)      # 和其他擺設同色系的深褐描邊


def _shape(width: int, height: int) -> np.ndarray:
    """圓角長條：兩端是半徑約高度一半的圓，上緣略微鼓起（布摺好後中間比兩端厚一點）。"""
    y, x = np.mgrid[0:height, 0:width].astype(float)
    left, right = MARGIN, width - MARGIN
    top, bottom = MARGIN, height - MARGIN
    radius = (bottom - top) * 0.42
    bulge = 5.0 * np.sin(np.clip((x - left) / (right - left), 0, 1) * np.pi)
    inside = (x >= left) & (x <= right) & (y >= top - bulge + 6) & (y <= bottom)
    for cx in (left + radius, right - radius):
        cy = top + radius + 6
        corner = ((x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2)
        side = (x < left + radius) if cx < width / 2 else (x > right - radius)
        inside &= ~side | corner | (y > cy)
        # 底邊的角也稍微圓一點（布的厚度），不是方的切口。
        foot = 10.0
        fx = cx + (radius - foot) * (-1 if cx < width / 2 else 1)
        fy = bottom - foot
        beyond = (x < fx) if cx < width / 2 else (x > fx)
        inside &= ~(beyond & (y > fy)) | ((x - fx) ** 2 + (y - fy) ** 2 <= foot ** 2)
    return inside


def draw(out: Path) -> Path:
    rng = np.random.default_rng(SEED)
    mask = _shape(WIDTH, HEIGHT)
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH].astype(float)
    rows = np.where(mask.any(axis=1))[0]
    top, bottom = rows.min(), rows.max()
    t = (y - top) / max(1, bottom - top)  # 0 上緣 → 1 底邊

    color = BASE + (SHADE - BASE) * np.clip((t - 0.35) * 1.4, 0, 1)[..., None]
    color = np.where((t < 0.22)[..., None], LIGHT + (BASE - LIGHT) * (t / 0.22)[..., None], color)
    # 三層摺邊：每層下緣一道暗線、上緣一道亮線。
    for edge in (0.42, 0.64, 0.84):
        dark = np.exp(-((t - edge) / 0.018) ** 2)
        lit = np.exp(-((t - edge - 0.045) / 0.02) ** 2) * 0.6
        color = color * (1 - 0.45 * dark[..., None]) + LIGHT * (0.35 * lit[..., None])
    # 兩端的細條紋（摺疊後在正面看到的那一段）。
    for cx in (0.16, 0.84):
        band = np.exp(-(((x / WIDTH) - cx) / 0.012) ** 2)
        color = color * (1 - 0.75 * band[..., None]) + STRIPE * (0.75 * band[..., None])
    # 兩端圓弧暗一點，看得出布捲過去。
    ends = np.clip(1 - np.minimum(x - MARGIN, WIDTH - MARGIN - x) / 40.0, 0, 1)
    color *= (1 - 0.25 * ends ** 2)[..., None]
    # 毛圈布的顆粒。
    grain = rng.normal(0, 1, (HEIGHT, WIDTH))
    grain = np.array(Image.fromarray(((grain * 18) + 128).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), float) - 128
    color += grain[..., None] * 0.45

    # 描邊：外圍 3 像素深褐，內側 1 像素過渡。
    alpha = Image.fromarray((mask * 255).astype(np.uint8))
    eroded = np.array(alpha.filter(ImageFilter.MinFilter(7)), bool)
    soft = np.array(alpha.filter(ImageFilter.MinFilter(9)), bool)
    color = np.where((mask & ~eroded)[..., None], OUTLINE, color)
    color = np.where((eroded & ~soft)[..., None], color * 0.75 + OUTLINE * 0.25, color)

    rgba = np.dstack([color.clip(0, 255), mask * 255.0]).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA")
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    return out


def main(argv: list[str]) -> int:
    out = Path(argv[1]) if len(argv) > 1 else DEFAULT_OUT
    print(f"wrote {draw(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
