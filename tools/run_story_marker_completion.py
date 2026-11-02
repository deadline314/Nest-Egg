#!/usr/bin/env python3
"""Verify finite story ownership under damaged policy metadata, recovery and cold reads."""
import argparse
import hashlib
import os
import shutil
import subprocess
from pathlib import Path
from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
PRODUCERS = ("label", "gate", "item")
MODES = ("missing", "missing_read", "shifted", "shifted_read", "malformed", "malformed_read", "missing_choice", "missing_choice_read", "intact", "intact_read")
SOURCES = ["game/story_result_ch2.gd", "game/story_result_sources.gd",
           "game/story_result_completion.gd", "game/level/level.gd",
           "data/story/ch2_heron.json", "data/npcs/ch1_label_watch.tres", "data/npcs/ch2_patroller.tres",
           "data/npcs/ch2_rent_window.tres", "data/story/ch1_kasa.json", "tests/probes/story_marker_completion.gd",
           "tests/probes/story_marker_completion.tscn", "tools/run_story_marker_completion.py",
           "tools/runtime_probe.py", "tests/probes/story_contract_audit.gd",
           "tests/probes/story_contract_audit.tscn"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    hashes = {}
    for name in SOURCES:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with args.godot.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    audit = run_case("contracts", args.godot.resolve(), output, 60, project=PROJECT,
                     scene="res://tests/probes/story_contract_audit.tscn", slot=output / "audit-slot")
    cases = [audit]
    write_json(output / "receipt.json", {"engine_sha256": engine_hash,
               "source_sha256": hashes, "cases": cases})
    if not audit["passed"]:
        print("Authored ownership audit failed:", audit, flush=True)
        return 1
    print("contracts PASS checks", audit["result"]["checks"], flush=True)
    for producer in PRODUCERS:
        for mode in MODES:
            slot = output / producer / mode.removesuffix("_read")
            case = run_case(producer + "--" + mode, args.godot.resolve(), output, 240,
                            project=PROJECT, scene="res://tests/probes/story_marker_completion.tscn",
                            slot=slot, verbose=True)
            data = case.get("result", {})
            publications = data.get("publications", [])
            coherent = (isinstance(publications, list)
                        and ((not mode.endswith("_read") and len(publications) == (2 if producer == "item" else 1)
                              and {row.get("event") for row in publications if isinstance(row, dict)} == ({"item", "flag"} if producer == "item" else {"flag"})
                              and all(isinstance(row, dict) and row.get("talks") == 1
                                      and row.get("world_counts") == [1, 1, 1] for row in publications))
                             or (mode.endswith("_read") and publications == [])))
            case["passed"] = bool(case["passed"] and data.get("producer") == producer
                                  and data.get("mode") == mode and coherent)
            cases.append(case)
            write_json(output / "receipt.json", {"engine_sha256": engine_hash,
                       "source_sha256": hashes, "cases": cases})
            print(producer, mode, "PASS" if case["passed"] else "FAIL",
                  "checks", data.get("checks"), flush=True)
            if not case["passed"]:
                print("diagnostics:", case["diagnostics"], "raw log:", output / (producer + "--" + mode + ".log"), flush=True)
                return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Story marker completion probe failed: {error}") from error
