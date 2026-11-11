"""BG-54 native capture batch; run inside the shared GPU lock."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    args.out.mkdir(parents=True, exist_ok=True)
    stages = []
    files = {}
    for relative in ("tools/run_capture_precision.py", "tools/test_viewport_capture.gd", "tools/viewport_capture.gd"):
        data = (root / relative).read_bytes()
        name = "BG-54-" + relative.replace("/", "_") + ".txt"
        (args.out / name).write_bytes(data)
        files[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    for name, scene, extra in (
        ("gray", "test_viewport_capture", []),
        ("native-1280", "capture_precision_probe", ["--width=1280", "--height=720"]),
        ("native-1920", "capture_precision_probe", ["--width=1920", "--height=1080"]),
    ):
        if args.only and name not in args.only.split(","):
            continue
        directory = args.out / name
        directory.mkdir(exist_ok=True)
        resolution = "1920x1080" if name == "native-1920" else "1280x720"
        command = [args.godot, "--path", str(root), "--resolution", resolution, "--rendering-driver", "vulkan", "--rendering-method", "forward_plus", "--quit-after", "5000", f"res://tools/{scene}.tscn", "--", f"--out={directory}", *extra]
        with (directory / "console.log").open("wb") as output:
            result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
        log = (directory / "console.log").read_bytes()
        clean = result.returncode == 0 and b"SCRIPT ERROR" not in log and b"ERROR:" not in log
        stages.append({"stage": name, "exit_code": result.returncode, "no_errors": clean, "command": command})
        for member in directory.rglob("*"):
            if member.is_file():
                data = member.read_bytes()
                files[member.relative_to(args.out).as_posix()] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        print(json.dumps(stages[-1]), flush=True)
        (args.out / "native-manifest.json").write_text(json.dumps({"stages": stages, "files": files}, indent=2), encoding="utf-8", newline="\n")
        if not clean:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
