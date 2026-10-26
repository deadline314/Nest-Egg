#!/usr/bin/env python3
"""Independent single/four-worker texture allocation, readback and strict shutdown."""
import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
from runtime_probe import run_case, write_json

PROJECT = pathlib.Path(__file__).resolve().parents[1]
PROBE = PROJECT / "tools/godot_audio/texture_probe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=pathlib.Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["tools/godot_audio/texture_probe/project.godot", "tools/godot_audio/texture_probe/main.tscn",
                 "tools/godot_audio/texture_probe/main.gd", "tools/godot_audio/manifest.json",
                 "tools/godot_audio/dummy-texture-threads.patch", "tools/godot_audio/audio-bus-lifetime.patch",
                 "tools/godot_audio/build.py", "tools/godot_audio/test_build.py",
                 "tools/run_texture_threads.py", "tools/runtime_probe.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256": engine_hash, "source_sha256": sources, "cases": []}
    for mode, workers in [("single", 1), ("four", 4)]:
        case = run_case(mode, engine, output, 60, project=PROBE,
                        scene="res://main.tscn", slot=output / "unused-slot")
        data = case.get("result", {})
        case["passed"] = bool(case["passed"] and data.get("workers") == workers
                              and data.get("created") == data.get("released") == 8192)
        receipt["cases"].append(case)
        write_json(output / "receipt.json", receipt)
        print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"], "checks", data.get("checks"), flush=True)
        if not case["passed"]:
            print("raw diagnostics:", output / (mode + ".log"), flush=True)
            return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Texture worker probe failed: {error}") from error
