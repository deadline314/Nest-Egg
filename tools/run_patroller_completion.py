#!/usr/bin/env python3
"""Exercise the original chapter-two gate dialogue under real Main and IO refusal."""
import argparse
import hashlib
import os
import shutil
import subprocess
from pathlib import Path

from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
CASES = [("accepted", "accepted"), ("accepted_read", "accepted"),
         ("cancel", "cancel"), ("cancel_read", "cancel"),
         ("direct", "direct"), ("duplicate", "duplicate"), ("contract", "contract"), ("choice", "choice")]
SOURCES = ["game/story_result_ch2.gd", "game/story_result_sources.gd",
           "game/story_result_completion.gd", "game/level/level.gd",
           "data/story/ch2_heron.json", "data/npcs/ch2_patroller.tres",
           "tests/probes/patroller_completion.gd", "tests/probes/patroller_completion.tscn",
           "tools/run_patroller_completion.py", "tools/runtime_probe.py"]
SOURCES += ['core/story_result_catalog.gd', 'data/story_contracts/catalog.json', 'data/story_contracts/ch1.json', 'data/story_contracts/ch2.json', 'data/story_contracts/migration-5a.json']


# Deliberate live-content mutations; full independent error lines, once each.
EXPECTED_DIAGNOSTICS = {
    'contract': ('ERROR: [StoryContracts] res://data/story/ch2_heron.json/scenes/ch2_t_s05_gate: live content differs from independent contract',),
    'choice': ('ERROR: [StoryContracts] res://data/story/ch2_heron.json/scenes/ch2_t_s05_gate: live content differs from independent contract',),
}


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
    for mode, slot in CASES:
        case = run_case(mode, args.godot.resolve(), output, 240, project=PROJECT,
                        scene="res://tests/probes/patroller_completion.tscn",
                        slot=output / slot, verbose=True,
                        expected_diagnostics=EXPECTED_DIAGNOSTICS.get(mode, ()))
        cases.append(case)
        write_json(output / "receipt.json", {"engine_sha256": engine_hash,
                   "source_sha256": hashes, "cases": cases})
        print(mode, "PASS" if case["passed"] else "FAIL", case.get("result"), flush=True)
        if not case["passed"]:
            print("diagnostics:", case["diagnostics"], "raw log:", output / (mode + ".log"), flush=True)
            return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Patroller completion probe failed: {error}") from error
