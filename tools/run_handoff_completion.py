#!/usr/bin/env python3
"""Verify real Main handoff completion and a fresh-process read, with isolated saves."""

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import time

PROJECT = pathlib.Path(__file__).resolve().parents[1]


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def stop_owned(process, force=False):
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL if force else signal.SIGTERM)
        elif force:
            process.kill()
        else:
            process.terminate()
    except ProcessLookupError:
        pass


def run_case(mode, engine, output, timeout):
    profile = output / (mode + "-profile")
    environment = os.environ.copy()
    environment.update(XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile))
    command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(PROJECT),
               "res://tests/probes/handoff_completion.tscn", "--", "--mode=" + mode,
               "--save-dir=" + str(output / "slot"), "--out=" + str(output / mode)]
    timed_out = False
    with (output / (mode + ".log")).open("w") as log:
        process = subprocess.Popen(command, cwd=PROJECT, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            write_json(output / (mode + "-process.json"), {"pid": process.pid, "command": command})
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_owned(process)
                try:
                    code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    stop_owned(process, force=True)
                    code = process.wait(timeout=10)
        finally:
            if process.poll() is None:
                stop_owned(process)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    stop_owned(process, force=True)
                    process.wait(timeout=10)
    (output / (mode + ".exit")).write_text(str(code) + "\n")
    bad_line = re.compile(r"^ERROR:|SCRIPT ERROR|Parse Error|^FAIL(?:\s|:)|handle_crash:|"
                          r"Program crashed|leaked at exit|resources still in use")
    diagnostics, diagnostic_count = [], 0
    with (output / (mode + ".log")).open(errors="replace") as log:
        for line in log:
            if bad_line.search(line):
                diagnostic_count += 1
                if len(diagnostics) < 32:
                    diagnostics.append(line.strip()[:512])
    case = {"mode": mode, "exit": code, "timeout": timed_out,
            "diagnostics": diagnostics, "diagnostic_count": diagnostic_count}
    result = output / mode / "result.json"
    try:
        if result.stat().st_size > 1024 * 1024:
            raise ValueError("probe result exceeds 1 MiB")
        case["result"] = json.loads(result.read_text())
    except (OSError, ValueError) as error:
        case["result_error"] = str(error)
    data = case.get("result", {})
    if not isinstance(data, dict):
        case["result_error"] = "probe result is not an object"
        data = {}
        case["result"] = data
    case["passed"] = (code == 0 and not timed_out and not diagnostics
                      and type(data.get("checks")) is int and data["checks"] > 0
                      and data.get("failures") == [])
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
    return case


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
                 "tests/probes/handoff_completion.tscn", "tools/run_save_probe.gd", "tools/run_handoff_completion.py"]:
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
        case = run_case(mode, engine, output, args.timeout)
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
