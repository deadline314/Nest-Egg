"""Check that the ComfyUI start script and the hang recovery in comfy_api.py work, with small fast images.

Usage:
  python tools/comfyui/selftest.py                      # 12 images, no trouble: checks the batch completes
  python tools/comfyui/selftest.py --kill-at 4          # kills the server while image 4 renders
  python tools/comfyui/selftest.py --freeze-at 4 --stall-s 25   # freezes it (queue says "running" forever)
  python tools/comfyui/selftest.py --kill-at 3 --retries 0      # no retries: must stop with ComfyFailure and log the job
Run it twice in a row to see already finished images being reused instead of generated again.
Output (not imported by Godot): assets_src/work/comfy_selftest/. Exit code 0 = every image exists and is not black.
"""
from __future__ import annotations

import argparse
import ctypes
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument("--count", type=int, default=12)
ap.add_argument("--kill-at", type=int, default=-1, help="kill the server while this image (0-based) renders")
ap.add_argument("--freeze-at", type=int, default=-1, help="freeze the server while this image renders")
ap.add_argument("--delay", type=float, default=5.0, help="seconds after the image starts before the trouble")
ap.add_argument("--stall-s", type=float, default=0, help="override COMFY_STALL_S (use ~25 with --freeze-at)")
ap.add_argument("--retries", type=int, default=-1, help="override COMFY_MAX_RETRIES")
ap.add_argument("--fresh", action="store_true", help="delete earlier selftest images first")
args = ap.parse_args()

os.environ["OUT_DIR"] = str(ROOT / "assets_src" / "work" / "comfy_selftest")
os.environ["COMFY_FAIL_LOG"] = str(ROOT / "assets_src" / "work" / "comfy_selftest" / "failures.log")
if args.stall_s:
    os.environ["COMFY_STALL_S"] = str(args.stall_s)
if args.retries >= 0:
    os.environ["COMFY_MAX_RETRIES"] = str(args.retries)
sys.path.insert(0, str(Path(__file__).parent))
import comfy_api  # noqa: E402
import comfy_guard  # noqa: E402
from PIL import Image  # noqa: E402

OUT = Path(os.environ["OUT_DIR"])
OUT.mkdir(parents=True, exist_ok=True)
if args.fresh:
    for f in OUT.glob("selftest_*"):
        f.unlink()

current = {"i": -1}
fired = set()


def saboteur() -> None:
    """Breaks the server once, `delay` seconds after the chosen image starts."""
    while True:
        i = current["i"]
        if i in (args.kill_at, args.freeze_at) and i not in fired:
            time.sleep(args.delay)
            if current["i"] != i:
                continue
            fired.add(i)
            pid = comfy_guard.server_pid()
            if pid is None:
                print(f"[selftest] no server to break at image {i}", flush=True)
                continue
            if i == args.freeze_at:
                h = ctypes.windll.kernel32.OpenProcess(0x800, False, pid)  # PROCESS_SUSPEND_RESUME
                ctypes.windll.ntdll.NtSuspendProcess(h)
                print(f"[selftest] froze server pid {pid} during image {i}", flush=True)
            else:
                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
                print(f"[selftest] killed server pid {pid} during image {i}", flush=True)
        time.sleep(0.5)


threading.Thread(target=saboteur, daemon=True).start()

t0 = time.time()
bad = []
try:
    for i in range(args.count):
        current["i"] = i
        t = time.time()
        paths = comfy_api.qwen(f"A flat cel-shaded sticker of a small potted plant number {i}, dark outline", w=512, h=512, steps=8,
                               seed=1000 + i, prefix=f"selftest_{i:02d}")
        im = Image.open(paths[0])
        black = im.getextrema()[0] == (0, 0)
        print(f"[selftest] image {i:2d}: {time.time() - t:5.1f}s  {'BLACK' if black else 'ok'}", flush=True)
        if black:
            bad.append(i)
except comfy_api.ComfyFailure as ex:
    print(f"[selftest] STOPPED with ComfyFailure: {ex}", flush=True)
    log = Path(os.environ["COMFY_FAIL_LOG"])
    print(f"[selftest] failure log: {log.read_text(encoding='utf-8').strip().splitlines()[-1] if log.exists() else 'MISSING'}", flush=True)
    sys.exit(3)
finally:
    current["i"] = -1

done = len(list(OUT.glob("selftest_*_0.png")))
print(f"[selftest] {args.count} images in {time.time() - t0:.0f}s, files present: {done}, black: {len(bad)}")
sys.exit(0 if not bad and done >= args.count else 1)
