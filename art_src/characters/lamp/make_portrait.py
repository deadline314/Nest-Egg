"""燈的對話頭像：從立繪直接裁出頭與肩（他以通訊出現，沒有骨架零件）。CPU，不需要模型。

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/lamp/make_portrait.py

輸入 base_rgba.png（Qwen Image 2.1 文生圖，seed 21831，提示詞在 01_design/prompt.txt）；輸出 art/portraits/lamp.png（256×256，透明背景）。
"""
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE_SHA256 = "630d5b8d2bb20b05f3d5b3b4442b0a172dddad7dcdc5de54078639c2572504b7"
BOX = (401, 32, 681, 312)  # base_rgba.png 的像素：頭頂上方 8 px 起、寬高相同
ALPHA_FLOOR = 40  # 生成圖的背景有 alpha 1～3 的霧，和零件精修用同一個門檻
SIZE = 256

base = HERE / "base_rgba.png"
if hashlib.sha256(base.read_bytes()).hexdigest() != BASE_SHA256:
    raise SystemExit(f"[lamp] {base} 不是登記的那張立繪，停止")
rgba = np.asarray(Image.open(base).convert("RGBA")).copy()
rgba[:, :, 3][rgba[:, :, 3] < ALPHA_FLOOR] = 0
out = ROOT / "art/portraits/lamp.png"
Image.fromarray(rgba).crop(BOX).resize((SIZE, SIZE), Image.LANCZOS).save(out)
print(f"portrait {out.relative_to(ROOT)} {SIZE}x{SIZE}")
