#!/usr/bin/env python3
"""First-clinic original IO refusal, genuine recovery, skip and exact pending cold reads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
PHASES = ["wake", "tray", "look", "decide", "take", "leave", "missing"]
ORIGINAL = ["wake", "look", "take", "pending_write", "pending_read"]
POSITIVE = (["retry_" + p for p in ["wake", "look", "take", "leave"]]
            + ["normal_take", "normal_leave", "skip_wake", "skip_look", "cancel_wake", "cancel_take"]
            + [action + "_" + p for p in PHASES for action in ["write", "read"]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    if not 30 <= args.timeout <= 900:
        parser.error("timeout must be 30..900 seconds per process")
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    engine = args.godot.resolve()
    seed = PROJECT / "tests/fixtures/clinic_tray_pending.json"
    provenance = json.loads(seed.with_suffix(".provenance.json").read_text())
    if hashlib.sha256(seed.read_bytes()).hexdigest() != provenance["seed_sha256"]:
        raise ValueError("original pending first-clinic bytes differ from producer provenance")
    sources = {}
    for name in ["autoload/story.gd", "core/story_outcomes.gd", "game/main.gd",
                 "game/level/level.gd", "game/story_result_clinic.gd",
                 "game/story_result_sources.gd", "game/story_result_completion.gd",
                 "data/story/ch1_kasa.json", "tests/helpers/clinic_source_checks.gd",
                 "tests/probes/clinic_original.gd", "tests/probes/clinic_original.tscn",
                 "tests/probes/clinic_completion.gd", "tests/probes/clinic_completion.tscn",
                 "tests/fixtures/clinic_tray_pending.json", "tests/fixtures/clinic_tray_pending.provenance.json",
                 "tools/run_save_probe.gd", "tools/runtime_probe.py", "tools/run_clinic_completion.py"]:
        dest = output / "source" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, dest)
        sources[name] = hashlib.sha256(dest.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256":engine_sha, "source_sha256":sources,
               "seed_provenance":provenance, "original_pending_primaries":{}, "cases":[]}
    start = time.monotonic()
    for original, modes in [(True, ORIGINAL), (False, POSITIVE)]:
        for mode in modes:
            name = ("original_" if original else "") + mode
            slot = output / (name + "-slot")
            slot.mkdir()
            source = None
            if original and mode == "pending_read":
                source = seed
            elif not original and mode.startswith("read_"):
                source = output / (mode.replace("read_", "write_", 1) + "-slot/pending-primary.json")
            if source is not None:
                payload = source.read_bytes()
                shutil.copyfile(source, slot / "slot.json")
                if (slot / "slot.json").read_bytes() != payload:
                    raise ValueError("cold reader must use exact produced pending bytes")
                receipt["original_pending_primaries"][name] = hashlib.sha256(payload).hexdigest()
            # run_case uses mode for both CLI and output; original names are isolated
            # in their own folder so the immutable original command modes remain.
            dest = output / "original" if original else output
            dest.mkdir(exist_ok=True)
            case = run_case(mode, engine, dest, args.timeout, project=PROJECT,
                            scene="res://tests/probes/clinic_original.tscn" if original
                                  else "res://tests/probes/clinic_completion.tscn", slot=slot)
            case["label"] = name
            receipt["cases"].append(case)
            receipt["wall_seconds"] = round(time.monotonic() - start, 3)
            write_json(output / "receipt.json", receipt)
            print(name, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
                  "checks", case.get("result", {}).get("checks"), flush=True)
            if not case["passed"]:
                print("raw diagnostics:", dest / (mode + ".log"), flush=True)
                return 1
    print("original first-clinic completion and cold reads:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Clinic completion probe failed: {error}") from error
