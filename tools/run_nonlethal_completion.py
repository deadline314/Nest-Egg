#!/usr/bin/env python3
"""Verify original nonlethal boss actions, refused writes and exact cold reads."""
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
SCENE = "res://tests/probes/nonlethal_completion.tscn"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boss", choices=("yong", "janus"), default="yong")
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing Godot engine")
    if not 60 <= args.timeout <= 900:
        parser.error("timeout must be 60..900 seconds per process")
    engine, output = args.godot.resolve(), args.output.resolve()
    scene = SCENE if args.boss == "yong" else "res://tests/probes/janus_completion.tscn"
    output.mkdir(parents=True, exist_ok=False)
    (output / ".gdignore").touch()
    (output / ".gitignore").write_text("*\n")
    names = ["game/main.gd", "game/channel_completion.gd", "game/level/level.gd",
             "game/enemies/enemy.gd", "game/enemies/boss/pattern_boss.gd",
             "game/enemies/yong_boss.gd", "game/enemies/boss/boss_hold_point.gd",
             "core/run_flag_commit.gd", "core/run_snapshot.gd", "core/run_save_store.gd",
             "core/run_save_codec.gd", "core/story_install_bundle.gd",
             "autoload/game_state.gd", "autoload/story.gd", "autoload/gameplay_lock.gd",
             "data/scripts/level_data.gd", "data/levels/ch2_ledger_office.tres",
             "data/levels/ch2_ledger_office_map.json", "data/enemies/yong.tres", "data/bosses/yong.json",
             "ui/radio_save_prompt.gd", "tests/probes/nonlethal_completion.gd",
             "tests/probes/nonlethal_completion.tscn", "tests/probes/channel_completion.gd",
             "tests/probes/training_completion.gd", "tools/prologue_play_probe.gd",
             "tools/runtime_probe.py", "tools/run_nonlethal_completion.py", "ui/hud.gd", "ui/boss_bar.gd",
             "tools/level/build_ch1.py", "tools/level/build_ch2.py", "tools/level/build_ch3.py",
             "tools/level/check_channel_generation.py", "game/enemies/janus_boss.gd",
             "tests/probes/janus_completion.gd", "tests/probes/janus_completion.tscn",
             "data/levels/ch3_gate_hall.tres", "data/levels/ch3_gate_hall_map.json",
             "data/enemies/janus.tres", "data/bosses/janus.json"]
    sources = {}
    for name in names:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"boss": args.boss, "source_sha256": sources, "engine_sha256": engine_sha,
               "cases": [], "cold_primary_sha256": {}}
    started = time.monotonic()

    def run(mode):
        slot = output / (mode + "-slot")
        slot.mkdir()
        return run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene=scene, slot=slot, verbose=True)

    def record(case):
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "receipt.json", receipt)
        print(case["mode"], "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            for diagnostic in case["diagnostics"]:
                print(diagnostic, flush=True)

    with ThreadPoolExecutor(max_workers=3) as executor:
        for case in executor.map(run, [args.boss, "cancel", "death", "stale", "forged"]):
            record(case)
    if any(not case["passed"] for case in receipt["cases"]):
        return 1
    for mode, primary in [("accepted_read", args.boss + "-slot/result-primary.json"),
                          ("cancel_read", "cancel-slot/original-primary.json")]:
        slot = output / (mode + "-slot")
        slot.mkdir()
        original = (output / primary).read_bytes()
        (slot / "slot.json").write_bytes(original)
        if (slot / "slot.json").read_bytes() != original:
            raise ValueError("cold reader must retain exact original primary bytes")
        receipt["cold_primary_sha256"][mode] = hashlib.sha256(original).hexdigest()
        case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene=scene, slot=slot, verbose=True)
        record(case)
        if not case["passed"]:
            return 1
    print("nonlethal result evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
