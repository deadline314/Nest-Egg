#!/usr/bin/env python3
"""Actual stall source, material options/results and exact pending-primary cold reads."""

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
ACTIONS = ["pay", "tab", "host", "host_none", "meal", "address", "leave_none", "return",
           "choice_leave", "choice_stay", "choice_host", "choice_tab", "insufficient", "cancel_host",
           "normal_pay", "normal_host", "normal_meal"]
PENDING = set(ACTIONS) - {"address", "leave_none", "return", "cancel_host"}


def action_of(mode):
    return mode.removesuffix("_pending_read").removesuffix("_read").removeprefix("normal_")


def coherent(mode, data, expected_wallet=None):
    action = action_of(mode)
    cancelled = mode == "cancel_host"
    complete = action != "return" and not cancelled
    stays = action in {"host", "host_none", "meal", "address", "choice_stay", "choice_host", "cancel_host"}
    flags = data.get("flags", {})
    progression = data.get("progression", {})
    if not isinstance(flags, dict) or not isinstance(progression, dict):
        return False
    if (data.get("talks") != (0 if cancelled else 1)
            or flags.get("ch1_supper_done") is not complete
            or flags.get("knows_ali_address") is not (stays and not cancelled)
            or flags.get("ch1_supper_meal_done") is not (stays and not cancelled)
            or progression.get("credits") != data.get("wallet")):
        return False
    receipts = progression.get("story_transactions", {}).get("receipts", {})
    if not isinstance(receipts, dict):
        return False
    short = {key.removeprefix("ch1.revival_meal.") for key in receipts
             if key.startswith("ch1.revival_meal.")}
    no_order = action in {"host_none", "choice_stay", "leave_none"}
    expected = set() if no_order else {"order"}
    if action == "pay":
        expected.add("paid")
    elif action in {"tab", "choice_leave", "choice_tab", "insufficient"}:
        expected.add("tab")
    elif stays and not no_order:
        expected.add("gift")
    if short != expected:
        return False
    rows = data.get("publications", [])
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        return False
    if mode.endswith("read"):
        return not rows and data.get("wallet") == expected_wallet
    if not rows or type(data.get("spends")) is not int or data["spends"] < 1:
        return False
    if data.get("wallet") != (193 if action == "insufficient" else 233) - (200 if action == "pay" else 0) - data["spends"]:
        return False
    for row in rows:
        expected_count = 0 if row.get("pending") else 1
        if row.get("counts") != [expected_count] * 3 or row.get("live") != expected_count:
            return False
    return True


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
    provenance = json.loads((PROJECT / "tests/fixtures/supper_evening.provenance.json").read_text())
    for row in provenance:
        seed = PROJECT / ("tests/fixtures/supper_evening_" + row["kind"] + ".json")
        if hashlib.sha256(seed.read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError("original evening seed bytes differ from producer provenance")
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False)
    sources = {}
    for name in ["autoload/story.gd", "game/main.gd", "game/npc/npc_actor.gd",
                 "game/story_result_completion.gd", "game/story_result_sources.gd", "game/story_result_supper.gd",
                 "data/story/ch1_kasa.json", "tests/helpers/supper_completion_base.gd",
                 "tests/probes/supper_completion.gd", "tests/probes/supper_completion.tscn",
                 "tests/fixtures/supper_evening_ordered.json", "tests/fixtures/supper_evening_none.json",
                 "tests/fixtures/supper_evening.provenance.json", "tools/run_save_probe.gd",
                 "tools/runtime_probe.py", "tools/run_supper_completion.py"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256": engine_hash, "source_sha256": sources,
               "seed_provenance": provenance, "original_pending_primaries": {}, "cases": []}
    started = time.monotonic()
    for action in ACTIONS:
        modes = [action] + ([action + "_pending_read"] if action in PENDING else []) + [action + "_read"]
        for mode in modes:
            pending = mode.endswith("_pending_read")
            slot = output / ((mode if pending else action) + "-slot")
            expected_wallet = None
            if pending:
                source = output / (action + "-slot") / "pending-primary.json"
                payload = source.read_bytes()
                slot.mkdir(exist_ok=False)
                shutil.copyfile(source, slot / "slot.json")
                if (slot / "slot.json").read_bytes() != payload:
                    raise ValueError("cold source must retain exact original pending-primary bytes")
                receipt["original_pending_primaries"][mode] = hashlib.sha256(payload).hexdigest()
            if mode.endswith("read"):
                envelope = json.loads((slot / "slot.json").read_text())
                expected_wallet = json.loads(envelope["payload"])["progression"]["credits"]
            case = run_case(mode, engine, output, args.timeout, project=PROJECT,
                            scene="res://tests/probes/supper_completion.tscn", slot=slot)
            case["passed"] = bool(case["passed"] and coherent(mode, case.get("result", {}), expected_wallet))
            receipt["cases"].append(case)
            receipt["wall_seconds"] = round(time.monotonic() - started, 3)
            write_json(output / "receipt.json", receipt)
            print(mode, "PASS" if case["passed"] else "FAIL", "exit", case["exit"],
                  "checks", case.get("result", {}).get("checks"), flush=True)
            if not case["passed"]:
                print("raw diagnostics:", output / (mode + ".log"), flush=True)
                return 1
    print("real supper results and cold-read evidence:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Supper completion probe failed: {error}") from error
