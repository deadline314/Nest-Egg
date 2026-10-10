"""Regenerate the rin_field source: Qwen Image 2.1 reference edit of the approved s33 side view (identity reference only).

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_field/01_design/generate.py

Same prompt, seed, resolution and reference give the same job key, so a finished job is reused, not generated again.
The approved s33 picture is only read. Output: design_s22401.png next to this file (1056x1536 RGBA).
"""
import hashlib
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SEED = 22401
RESOLUTION = 1280
REFERENCE = ROOT / "art_src/characters/rin2/base_rgba.png"
REFERENCE_SHA256 = "401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9"

sys.path.insert(0, str(ROOT / "tools/comfyui"))
os.environ.setdefault("OUT_DIR", str(ROOT / "tools/comfyui/out"))
from comfy_api import qwen  # noqa: E402

if hashlib.sha256(REFERENCE.read_bytes()).hexdigest() != REFERENCE_SHA256:
    raise SystemExit(f"[rin_field] {REFERENCE} is not the approved s33 picture any more; stop")
prompt = (HERE / "prompt.txt").read_text(encoding="utf-8").strip()
made = qwen("This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent.",
            images=[str(REFERENCE)], seed=SEED, resolution=RESOLUTION, prefix=f"rin_walk_s{SEED}_r{RESOLUTION}")[0]
shutil.copy(made, HERE / f"design_s{SEED}.png")
print(f"design_s{SEED}.png <- {made}")
