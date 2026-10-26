#!/usr/bin/env python3
"""Original Ali interaction: a departed source cannot keep its real entry greeting."""

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess

from runtime_probe import run_case, write_json
from run_ali_completion import coherent

PROJECT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=pathlib.Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    if not 30 <= args.timeout <= 900:
        parser.error("timeout must be 30..900 seconds")
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["autoload/story.gd", "game/level/map_bubbles.gd", "game/level/level.gd",
                 "game/npc/npc_actor.gd", "data/story/ch1_kasa.json",
                 "tests/probes/bubble_source.gd", "tests/probes/bubble_source.tscn",
                 "tests/probes/ali_completion.gd", "tests/helpers/ali_completion_base.gd",
                 "tests/fixtures/ali_handoff_seed.json", "tools/run_save_probe.gd",
                 "tools/runtime_probe.py", "tools/run_ali_completion.py", "tools/run_bubble_source.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    case = run_case("evening_ordered", engine, output, args.timeout, project=PROJECT,
                    scene="res://tests/probes/bubble_source.tscn", slot=output / "slot")
    case["passed"] = bool(case["passed"] and coherent("evening_ordered", case.get("result", {})))
    write_json(output / "receipt.json", {"engine_sha256": engine_hash,
                                       "source_sha256": sources, "cases": [case]})
    print("original greeting source", "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
          "checks", case.get("result", {}).get("checks"), flush=True)
    if not case["passed"]:
        print("raw diagnostics:", output / "evening_ordered.log", flush=True)
    return 0 if case["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Bubble source probe failed: {error}") from error
