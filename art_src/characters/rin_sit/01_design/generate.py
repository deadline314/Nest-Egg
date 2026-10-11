"""Seated source for rin (NE-222): Qwen Image 2.1 reference edit of the adopted rin_field source, for pose-specific hip and thigh parts.

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_sit/01_design/generate.py [--seed N]

Same prompt, seed, resolution and reference give the same job key, so a finished job is reused, not generated again.
The rin_field picture is only read. Output: design_s<seed>.png next to this file. One picture per run.
"""
import argparse
import hashlib
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RESOLUTION = 1280
REFERENCE = ROOT / "art_src/characters/rin_field/base_rgba.png"
REFERENCE_SHA256 = "49ee8e60b3082c075f30891f54d20260c8234a339568cb795587be75ba8b963f"

sys.path.insert(0, str(ROOT / "tools/comfyui"))
os.environ.setdefault("OUT_DIR", str(ROOT / "tools/comfyui/out"))
from comfy_api import qwen  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=22501)
seed = ap.parse_args().seed
if hashlib.sha256(REFERENCE.read_bytes()).hexdigest() != REFERENCE_SHA256:
    raise SystemExit(f"[rin_sit] {REFERENCE} is not the adopted rin_field source any more; stop")
prompt = (HERE / "prompt.txt").read_text(encoding="utf-8").strip()
made = qwen("This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent.",
            images=[str(REFERENCE)], seed=seed, resolution=RESOLUTION, prefix=f"rin_sit_s{seed}_r{RESOLUTION}")[0]
shutil.copy(made, HERE / f"design_s{seed}.png")
print(f"design_s{seed}.png <- {made}")
