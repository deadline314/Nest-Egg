"""Run a command while no ComfyUI generation job is running (and none starts), so Godot and ComfyUI never use the GPU together.

Usage: python tools/comfyui/gpu_lock.py -- "<godot>" --path . res://tools/screenshot.tscn -- --out=...

Takes the same file lock comfy_api.run() takes around every job (comfy_guard.server_lock): it waits for the job in progress to
finish, holds the lock while the command runs (a generation client that wants the GPU waits meanwhile), then releases it.
ComfyUI itself stays loaded, so the next job starts immediately. The exit code is the command's.
Keep the commands short (screenshots, imports, tests); a long one holds up generation.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import comfy_guard  # noqa: E402


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        print(__doc__)
        return 2
    with comfy_guard.server_lock():
        return subprocess.call(argv)


if __name__ == "__main__":
    sys.exit(main())
