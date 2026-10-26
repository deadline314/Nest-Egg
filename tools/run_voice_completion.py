#!/usr/bin/env python3
"""Real Main voice continuation, exact pending-primary cold reads and default recovery."""

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import time

from runtime_probe import run_case, write_json

PROJECT = pathlib.Path(__file__).resolve().parents[1]
MODES = ["write", "completed_read", "choice_read", "first_read", "second_read", "repeat",
         "skip_active", "later_read", "skip_early", "skip_auto", "return", "unheard",
         "cancel", "cancel_read", "invalid", "invalid_skip", "return_then_ask"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=pathlib.Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    if not 30 <= args.timeout <= 900:
        parser.error("timeout must be 30..900 seconds per process")
    output, engine = args.output.resolve(), args.godot.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["autoload/story.gd", "game/main.gd", "game/story_result_completion.gd",
                 "game/story_result_sources.gd", "game/cutscene/cutscene_player.gd",
                 "core/story_outcomes.gd", "data/story/ch1_kasa.json",
                 "tests/helpers/voice_completion_base.gd", "tests/probes/voice_completion.gd",
                 "tests/probes/voice_completion.tscn", "tools/run_save_probe.gd",
                 "tools/runtime_probe.py", "tools/run_voice_completion.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    print("VOICE_ENGINE_SHA256", engine_hash, flush=True)
    receipt = {"engine": str(engine), "engine_sha256": engine_hash, "source_sha256": sources,
               "cases": [], "original_pending_primaries": {}}
    started = time.monotonic()
    for mode in MODES:
        slot = output / ("write-slot" if mode == "completed_read" else
                         "skip_active-slot" if mode == "later_read" else
                         "cancel-slot" if mode == "cancel_read" else mode + "-slot")
        original_name = {"choice_read": "accepted-choice-primary.json",
                         "first_read": "first-reading-primary.json",
                         "second_read": "second-choice-primary.json"}.get(mode)
        if original_name:
            slot.mkdir(exist_ok=False)
            original = output / "write-slot" / original_name
            payload = original.read_bytes()
            shutil.copyfile(original, slot / "slot.json")
            if (slot / "slot.json").read_bytes() != payload:
                raise ValueError("pending continuation must use the exact original primary bytes")
            receipt["original_pending_primaries"][mode] = hashlib.sha256(payload).hexdigest()
        case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene="res://tests/probes/voice_completion.tscn", slot=slot)
        if mode == "write":
            rows = case.get("result", {}).get("publications", [])
            coherent = (isinstance(rows, list) and len(rows) == 3
                        and all(isinstance(row, dict) for row in rows)
                        and [row.get("flag") for row in rows] ==
                        ["ch1_voice_accepted", "ch1_lamp_voice_asked", "sq5_lamp_voice_noticed"]
                        and [row.get("pending") for row in rows] ==
                        ["ch1_t_lamp_voice_first", "ch1_t_lamp_voice_second_prompt", ""]
                        and [row.get("counts") for row in rows] == [[0, 0, 0], [0, 0, 0], [1, 1, 1]]
                        and [row.get("live") for row in rows] == [0, 0, 1]
                        and case.get("result", {}).get("wallet") == 120)
            case["passed"] = bool(case["passed"] and coherent)
        if mode == "repeat":
            rows = case.get("result", {}).get("settlements", [])
            case["passed"] = bool(case["passed"] and isinstance(rows, list) and len(rows) == 3
                                  and all(isinstance(row, dict) for row in rows)
                                  and [row.get("count") for row in rows] == [1, 2, 3]
                                  and [row.get("disk") for row in rows] == [[1, 1, 1], [2, 2, 2], [3, 3, 3]])
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "receipt.json", receipt)
        print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            print("raw diagnostics:", output / (mode + ".log"), flush=True)
            return 1
    print("real voice and cold-read evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Voice completion probe failed: {error}") from error
