#!/usr/bin/env python3
"""Original actual-input prologue results, durable counter completion and cold reads."""
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
PHASES = ["fall", "clean", "call"]
ACTIONS = ["retry", "read", "pending", "pending_read", "cancel", "cancel_read", "skip", "normal"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    if not 60 <= args.timeout <= 900:
        parser.error("timeout must be 60..900 seconds per process")
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    engine = args.godot.resolve()
    fixtures = PROJECT / "tests/fixtures/prologue_counter"
    provenance = json.loads((fixtures / "provenance.json").read_text())
    for row in provenance:
        if hashlib.sha256((fixtures / row["file"]).read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError("original actual-training primary differs: " + row["file"])
    sources = {}
    names = ["autoload/story.gd", "core/story_outcomes.gd", "game/main.gd", "game/level/level.gd",
             "game/story_result_sources.gd", "game/story_result_completion.gd", "game/npc/npc_actor.gd",
             "data/story/ch1_kasa.json", "tools/story/prologue_source.py", "tools/story/ch1_runtime_backend.py",
             "tools/story/test_completion_policies.py", "tools/prologue_play_probe.gd",
             "tests/helpers/prologue_source_checks.gd", "tests/helpers/ali_completion_base.gd",
             "tests/probes/prologue_original.gd", "tests/probes/prologue_original.tscn",
             "tests/probes/prologue_completion.gd", "tests/probes/prologue_completion.tscn",
             "tools/run_save_probe.gd", "tools/runtime_probe.py", "tools/run_prologue_completion.py"]
    names += [str(p.relative_to(PROJECT)) for p in fixtures.iterdir() if p.is_file()]
    for name in names:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256":engine_sha, "source_sha256":sources,
               "seed_provenance":provenance, "original_pending_primaries":{}, "cases":[]}
    start = time.monotonic()
    cases = [(True, phase, "") for phase in PHASES]
    cases += [(False, phase, action) for phase in PHASES for action in ACTIONS]
    for original, phase, action in cases:
        mode = phase if original else phase + "_" + action
        label = "original_" + mode if original else mode
        slot = output / (label + "-slot")
        slot.mkdir()
        if not original:
            if action == "read":
                source = output / (phase + "_retry-slot/slot.json")
            elif action in ["pending_read", "cancel_read"]:
                source = output / (phase + "_" + action.removesuffix("_read") + "-slot/pending-primary.json")
            else:
                source = fixtures / (phase + ".json")
            payload = source.read_bytes()
            shutil.copyfile(source, slot / "slot.json")
            if (slot / "slot.json").read_bytes() != payload:
                raise ValueError("reader must retain exact original primary bytes")
            receipt["original_pending_primaries"][label] = hashlib.sha256(payload).hexdigest()
        dest = output / "original" if original else output
        dest.mkdir(exist_ok=True)
        case = run_case(mode, engine, dest, args.timeout, project=PROJECT,
                        scene="res://tests/probes/prologue_original.tscn" if original
                              else "res://tests/probes/prologue_completion.tscn", slot=slot)
        case["label"] = label
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - start, 3)
        write_json(output / "receipt.json", receipt)
        print(label, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
              "checks", case.get("result", {}).get("checks"), flush=True)
        if not case["passed"]:
            print("raw diagnostics:", dest / (mode + ".log"), flush=True)
            return 1
    print("original tutorial counter and cold reads:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Prologue completion probe failed: {error}") from error
