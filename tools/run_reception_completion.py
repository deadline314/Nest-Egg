#!/usr/bin/env python3
"""Original Ali reception: atomic bill, original pending-name cold reads and cancellation."""

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
MODES = ["reception_" + prefix + suffix for prefix in ["ordered", "sit"]
         for suffix in ["", "_pending_read", "_read", "_cancel", "_cancel_read"]]


def coherent(mode, data):
    ordered = "ordered" in mode
    return (data.get("selected") is True and data.get("bill") is ordered
            and data.get("wallet") == 234
            and data.get("met") is (not mode.endswith("_cancel"))
            and data.get("talks") == (0 if mode.endswith("_cancel") else 1)
            and data.get("publications") == ([] if mode.endswith("read") else
                                              ["transaction", "item", "flag"] if ordered else ["flag"]))


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
    seed = PROJECT / "tests/fixtures/ali_handoff_seed.json"
    provenance = json.loads(seed.with_suffix(".provenance.json").read_text())
    if hashlib.sha256(seed.read_bytes()).hexdigest() != provenance["seed_sha256"]:
        raise ValueError("original handoff seed bytes differ from the producer provenance")
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["core/story_outcomes.gd", "autoload/story.gd", "game/main.gd",
                 "game/story_result_completion.gd", "game/story_result_sources.gd",
                 "game/npc/npc_actor.gd", "data/story/ch1_kasa.json",
                 "tests/helpers/reception_completion_base.gd", "tests/probes/reception_completion.gd",
                 "tests/probes/reception_completion.tscn", "tests/fixtures/ali_handoff_seed.json",
                 "tests/fixtures/ali_handoff_seed.provenance.json", "tools/run_save_probe.gd",
                 "tools/runtime_probe.py", "tools/run_reception_completion.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256": engine_hash, "source_sha256": sources,
               "seed_provenance": provenance, "original_pending_primaries": {}, "cases": []}
    started = time.monotonic()
    for mode in MODES:
        pending = mode.endswith("_pending_read")
        writer = mode.removesuffix("_pending_read") if pending else mode.removesuffix("_read")
        slot = output / ((mode if pending else writer) + "-slot")
        if pending:
            source = output / (writer + "-slot") / "pending-primary.json"
            payload = source.read_bytes()
            slot.mkdir(exist_ok=False)
            shutil.copyfile(source, slot / "slot.json")
            if (slot / "slot.json").read_bytes() != payload:
                raise ValueError("cold source must keep the exact original pending-primary bytes")
            receipt["original_pending_primaries"][mode] = hashlib.sha256(payload).hexdigest()
        case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                        scene="res://tests/probes/reception_completion.tscn", slot=slot)
        case["passed"] = bool(case["passed"] and coherent(mode, case.get("result", {})))
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - started, 3)
        write_json(output / "receipt.json", receipt)
        print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            print("raw diagnostics:", output / (mode + ".log"), flush=True)
            return 1
    print("real reception results and cold-read evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Reception completion probe failed: {error}") from error
