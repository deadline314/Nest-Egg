"""看門狗的底層圖：把四條腿拿掉、補出被腿擋住的身體（Qwen Image 2.1 參考編輯，固定種子；做過的工作會直接沿用）。

    D:/ComfyUI/.venv/Scripts/python.exe art_src/creatures/watchdog/parts/generate.py

輸入 ../design_21801/design_rgba.png（只讀）；輸出 raw/watchdog_nolegs_s21871_0.png。切零件由 build_parts.py 做。
"""
import hashlib
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DESIGN = HERE.parent / "design_21801" / "design_rgba.png"
DESIGN_SHA256 = "94c7378b622ff62edbe79fc69f59a4691dc01e77dd49c62aada8e944e018a2f7"
SEED = 21871
PROMPT = ("Remove all four legs of the robot dog completely: the round hip and shoulder axle discs, the upper and lower leg segments and the "
          "paws, on both the near side and the far side. Paint what was behind them: the underside of the torso and the side armor of the "
          "chest and the hindquarters, as one clean continuous hull, in exactly the same art style, line weight and colors. The torso, the neck, "
          "the head, the small turret on the back and the tail stay exactly unchanged at the same position and scale. No legs, no paws, no shadow.")

os.environ["OUT_DIR"] = str(HERE / "raw")
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from comfy_api import qwen  # noqa: E402

if hashlib.sha256(DESIGN.read_bytes()).hexdigest() != DESIGN_SHA256:
    raise SystemExit(f"[watchdog] {DESIGN} 不是登記的設計圖，停止")
made = qwen("This is an RGBA image with transparency. " + PROMPT + " The image has alpha channel and the background is transparent.",
            images=[str(DESIGN)], seed=SEED, resolution=1280, prefix=f"watchdog_nolegs_s{SEED}")[0]
print(made)
