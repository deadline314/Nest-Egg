#!/usr/bin/env python3
"""Verify real Main handoff completion and a fresh-process read, with isolated saves."""

import argparse
import hashlib
import json
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
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    if not 30 <= args.timeout <= 900:
        parser.error("timeout must be 30..900 seconds per process")
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False)
    (output / "source").mkdir()
    sources = {}
    for name in ["game/story_result_completion.gd", "tests/probes/handoff_completion.gd",
                 "tests/probes/handoff_completion.tscn", "tools/run_save_probe.gd", "tools/run_handoff_completion.py", "tools/runtime_probe.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    print("HANDOFF_ENGINE_SHA256", engine_hash, flush=True)
    print("HANDOFF_SOURCE_SHA256", json.dumps(sources), flush=True)
    started = time.monotonic()
    cases = []
    for mode in ["write", "read"]:
        case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene="res://tests/probes/handoff_completion.tscn", slot=output / "slot", verbose=True)
        data = case.get("result", {})
        if mode == "write":
            expected = {"ch1_t_handoff_accept": 1, "ch1_t_handoff_receipt": 2, "ch1_t_handoff_summary": 3}
            rows = data.get("counter_publications", [])
            coherent = (isinstance(rows, list) and len(rows) == 3
                        and all(isinstance(row, dict) and isinstance(row.get("scene"), str) for row in rows)
                        and {row.get("scene") for row in rows} == set(expected)
                        and all(row.get("live_count") == expected[row["scene"]]
                                and row.get("world_counts") == [expected[row["scene"]]] * 3
                                and row.get("durable") is True and row.get("talking") is True for row in rows))
            case["passed"] = bool(case["passed"] and coherent)
        cases.append(case)
        receipt = {"engine": str(engine), "engine_sha256": engine_hash, "source_sha256": sources,
                   "wall_seconds": round(time.monotonic() - started, 3), "cases": cases}
        write_json(output / "receipt.json", receipt)
        print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            for diagnostic in case["diagnostics"]:
                print(diagnostic, flush=True)
            print("raw diagnostics:", output / (mode + ".log"), flush=True)
            return 1
        if mode == "write":
            print("COUNTER_PUBLICATIONS", json.dumps(case["result"]["counter_publications"]), flush=True)
    print("real publication and cold-read evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Handoff completion probe failed: {error}") from error
