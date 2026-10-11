"""把選定的背包立繪放進遊戲（NE-243）。CPU，不需要模型。

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_inventory/publish.py

輸入 design_s24302.png（generate.py 的輸出，先核對雜湊）；輸出 art/portraits/rin_inventory.png：
清掉生成圖背景的低透明度霧（和零件精修同一個門檻），裁到人物外框加 16 像素留白，不縮放。
"""
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "design_s24302.png"
SOURCE_SHA256 = "e37feae6c7e6e27ff18a63f9c5f32c81f2f557284613260abee9cdf7554afdf9"
ALPHA_FLOOR = 40
MARGIN = 16

if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
    raise SystemExit(f"[rin_inventory] {SOURCE} 不是選定的那張，停止")
rgba = np.asarray(Image.open(SOURCE).convert("RGBA")).copy()
rgba[:, :, 3][rgba[:, :, 3] < ALPHA_FLOOR] = 0
rgba[rgba[:, :, 3] == 0] = 0
ys, xs = np.nonzero(rgba[:, :, 3])
x0, y0 = max(xs.min() - MARGIN, 0), max(ys.min() - MARGIN, 0)
x1, y1 = min(xs.max() + MARGIN + 1, rgba.shape[1]), min(ys.max() + MARGIN + 1, rgba.shape[0])
out = ROOT / "art/portraits/rin_inventory.png"
Image.fromarray(rgba[y0:y1, x0:x1]).save(out)
print(f"{out.relative_to(ROOT)} {x1 - x0}x{y1 - y0}")
