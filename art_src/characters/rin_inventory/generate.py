"""凜的中性背包立繪（NE-243）：Qwen Image 2.1 參考編輯，s33 定稿當身份參照；做過的工作會直接沿用。

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_inventory/generate.py [種子，預設 24301]

輸出 design_s<種子>.png（原生 RGBA）。定稿只讀不寫；選定的那張由 publish.py 清掉背景霧後放到 art/portraits/rin_inventory.png。
"""
import hashlib
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REFERENCE = ROOT / "art_src/characters/rin2/base_rgba.png"
REFERENCE_SHA256 = "401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9"
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 24301

sys.path.insert(0, str(ROOT / "tools/comfyui"))
os.environ.setdefault("OUT_DIR", str(ROOT / "tools/comfyui/out"))
from comfy_api import qwen  # noqa: E402

if hashlib.sha256(REFERENCE.read_bytes()).hexdigest() != REFERENCE_SHA256:
    raise SystemExit(f"[rin_inventory] {REFERENCE} 不是已同意的 s33 定稿，停止")
prompt = (HERE / "prompt.txt").read_text(encoding="utf-8").strip()
made = qwen("This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent.",
            images=[str(REFERENCE)], seed=SEED, resolution=1280, prefix=f"rin_inventory_s{SEED}")[0]
shutil.copy(made, HERE / f"design_s{SEED}.png")
print(f"design_s{SEED}.png <- {made}")
