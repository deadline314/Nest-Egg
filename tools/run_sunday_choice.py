#!/usr/bin/env python3
"""Real Main optional-choice IO refusal, cold continuation, reset and safe defaults."""

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import time

from runtime_probe import run_case, write_json

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
        parser.error("timeout must be 30..900 seconds per process")
    output, engine = args.output.resolve(), args.godot.resolve()
    output.mkdir(exist_ok=False)
    source_hashes = {}
    for name in ["autoload/story.gd", "game/main.gd", "game/story_result_completion.gd",
                 "game/cutscene/cutscene_player.gd", "data/story/ch1_kasa.json",
                 "tests/probes/sunday_choice.gd", "tests/probes/sunday_choice.tscn",
                 "tools/run_save_probe.gd", "tools/runtime_probe.py", "tools/run_sunday_choice.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        source_hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    print("SUNDAY_ENGINE_SHA256", engine_hash, flush=True)
    started = time.monotonic()
    receipt = {"engine": str(engine), "engine_sha256": engine_hash,
               "source_sha256": source_hashes, "cases": []}
    for mode in ["write", "read", "pending_read", "reset", "return", "skip", "observer_reset", "accepted_read"]:
        slot = output / ("slot" if mode in ["write", "read"] else "observer_reset-slot" if mode == "accepted_read" else mode + "-slot")
        if mode == "pending_read":
            slot.mkdir()
            original = output / "slot" / "pending-primary.json"
            payload = original.read_bytes()
            shutil.copyfile(original, slot / "slot.json")
            receipt["pending_original_sha256"] = hashlib.sha256(payload).hexdigest()
            if (slot / "slot.json").read_bytes() != payload:
                raise ValueError("pending continuation must use the exact original primary bytes")
        case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene="res://tests/probes/sunday_choice.tscn", slot=slot)
        if mode == "write":
            rows = case.get("result", {}).get("publications", [])
            coherent = (isinstance(rows, list) and len(rows) == 2
                        and all(isinstance(row, dict) for row in rows)
                        and rows[0].get("flag") == "ch1_sunday_accepted"
                        and rows[0].get("counts") == [0, 0, 0] and rows[0].get("live") == 0
                        and rows[0].get("pending") == "ch1_t_egret_sunday"
                        and rows[1].get("flag") == "asked_egret_sunday"
                        and rows[1].get("counts") == [1, 1, 1] and rows[1].get("live") == 1
                        and rows[1].get("pending") == "")
            case["passed"] = bool(case["passed"] and coherent)
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "receipt.json", receipt)
        print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            print("raw diagnostics:", output / (mode + ".log"), flush=True)
            return 1
    print("real choice and cold-read evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Sunday choice probe failed: {error}") from error
