#!/usr/bin/env python3
"""Verify original terminal home ownership, refused writes, recovery and cold reads."""
import argparse
import hashlib
import os
import shutil
import subprocess
from pathlib import Path
from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
MODES = ("intact", "intact_read", "missing", "missing_read", "shifted", "shifted_read", "malformed", "malformed_read", "foreign", "foreign_read", "choice", "choice_read", "source", "source_read", "condition", "condition_read")
SOURCES = ["game/story_flag_sources.gd", "game/story_flag_completion.gd",
           "game/story_result_completion.gd", "game/main.gd", "game/level/level.gd",
           "data/story/ch1_kasa.json", "data/levels/ch1_pawnshop_dawn.tres",
           "tests/probes/home_completion.gd", "tests/probes/home_completion.tscn",
           "tools/run_home_completion.py", "tools/runtime_probe.py"]


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
    cases = []
    for mode in MODES:
        slot = output / (mode.removesuffix("_read") + "-slot")
        case = run_case(mode, args.godot.resolve(), output, 240, project=PROJECT,
                        scene="res://tests/probes/home_completion.tscn", slot=slot, verbose=True)
        data = case.get("result", {})
        publications = data.get("publications", [])
        coherent = (publications == [] if mode.endswith("_read") else
                    isinstance(publications, list) and len(publications) == 2
                    and {row.get("flag") for row in publications if isinstance(row, dict)}
                    == {"ch1_home_done", "ch1_complete"})
        case["passed"] = bool(case["passed"] and data.get("mode") == mode and coherent)
        cases.append(case)
        write_json(output / "receipt.json", {"engine_sha256": engine_hash,
                   "source_sha256": hashes, "cases": cases})
        print(mode, "PASS" if case["passed"] else "FAIL", "checks", data.get("checks"), flush=True)
        if not case["passed"]:
            print("diagnostics:", case["diagnostics"], "raw log:", output / (mode + ".log"), flush=True)
            return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Original home completion probe failed: {error}") from error
