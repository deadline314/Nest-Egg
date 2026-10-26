#!/usr/bin/env python3
"""Repeat a genuine rechoose reply through the original stall NPC twice."""
import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
from runtime_probe import run_case, write_json

PROJECT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=pathlib.Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["tests/probes/supper_repeat.gd", "tests/probes/supper_repeat.tscn",
                 "tests/probes/supper_completion.gd", "tests/helpers/supper_completion_base.gd",
                 "game/story_result_completion.gd", "game/story_result_sources.gd",
                 "game/story_result_supper.gd", "autoload/story.gd", "data/story/ch1_kasa.json",
                 "tools/run_supper_repeat.py", "tools/runtime_probe.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    case = run_case("repeat_return", args.godot.resolve(), output, 240, project=PROJECT,
                    scene="res://tests/probes/supper_repeat.tscn", slot=output / "slot")
    data = case.get("result", {})
    case["passed"] = bool(case["passed"] and data.get("talks") == 2 and data.get("wallet") == 231
                          and data.get("spends") == 2 and data.get("flags", {}).get("ch1_supper_choice") == "unset")
    write_json(output / "receipt.json", {"source_sha256": sources, "cases": [case]})
    print("repeat original rechoose", "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
          "checks", data.get("checks"), flush=True)
    return 0 if case["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Supper repeat probe failed: {error}") from error
