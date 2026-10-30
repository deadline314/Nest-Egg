#!/usr/bin/env python3
"""Real confirmed prologue skips, refused writes, retry/cancellation and cold reads."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import time

from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
SCENE = "res://tests/probes/skip_completion.tscn"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing Godot engine")
    if not 60 <= args.timeout <= 900:
        parser.error("timeout must be 60..900 seconds per process")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    # Evidence contains source copies; keep them out of engine/Git discovery.
    (output / ".gdignore").touch()
    (output / ".gitignore").write_text("*\n")
    engine = args.godot.resolve()
    names = ["game/main.gd", "game/level/level.gd", "game/skip_completion.gd",
             "core/run_flag_commit.gd", "core/run_destination.gd", "game/training_completion.gd",
             "core/run_snapshot.gd", "core/run_save_store.gd", "core/run_save_codec.gd",
             "autoload/game_state.gd", "autoload/story.gd", "autoload/gameplay_lock.gd",
             "ui/radio_save_prompt.gd", "ui/pause_menu.gd", "data/levels/ch1_prologue.tres",
             "data/levels/ch1_prologue_map.json", "data/levels/ch1_pawnshop.tres",
             "data/story/ch1_kasa.json", "tools/prologue_play_probe.gd",
             "tests/probes/training_completion.gd", "tests/probes/skip_completion.gd",
             "tests/probes/skip_completion.tscn", "tools/run_skip_completion.py", "tools/runtime_probe.py"]
    sources = {}
    for name in names:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"source_sha256": sources, "engine_sha256": engine_sha,
               "cases": [], "cold_primary_sha256": {}}
    started = time.monotonic()

    def run(mode):
        slot = output / (mode + "-slot")
        slot.mkdir()
        return run_case(mode, engine, output, args.timeout, project=PROJECT, scene=SCENE, slot=slot)

    def record(case):
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "receipt.json", receipt)
        print(case["mode"], "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)

    # Each case owns its own Main, data profile and slot. Cold readers depend on
    # the exact primaries produced below and run only after all writers succeed.
    with ThreadPoolExecutor(max_workers=3) as executor:
        for case in executor.map(run, ["skip", "cancel", "stale", "trained"]):
            record(case)
    if any(not case["passed"] for case in receipt["cases"]):
        return 1
    for mode, primary in [("read", "skip-slot/result-primary.json"),
                          ("cancel_read", "cancel-slot/original-primary.json"),
                          ("trained_read", "trained-slot/result-primary.json")]:
        slot = output / (mode + "-slot")
        slot.mkdir()
        original = (output / primary).read_bytes()
        (slot / "slot.json").write_bytes(original)
        if (slot / "slot.json").read_bytes() != original:
            raise ValueError("cold reader must retain exact original primary bytes")
        receipt["cold_primary_sha256"][mode] = hashlib.sha256(original).hexdigest()
        case = run_case(mode, engine, output, args.timeout, project=PROJECT, scene=SCENE, slot=slot)
        record(case)
        if not case["passed"]:
            return 1
    print("skip result evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
