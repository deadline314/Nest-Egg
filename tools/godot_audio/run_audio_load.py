#!/usr/bin/env python3
"""Run independent, bounded audio-mixing probes and preserve each raw result."""

import argparse
import concurrent.futures
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import time


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def run_case(index, engine, project, output, seconds):
    name = "case-" + str(index)
    environment = os.environ.copy()
    profile = str(output / ("profile-" + str(index)))
    environment.update(XDG_DATA_HOME=profile, APPDATA=profile, LOCALAPPDATA=profile)
    command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(project),
               "--", "--seconds=" + str(seconds), "--out=" + str(output / (name + ".json"))]
    timed_out = False
    with (output / (name + ".log")).open("w") as log:
        process = subprocess.Popen(command, cwd=project, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        write_json(output / (name + "-process.json"), {"pid": process.pid, "command": command})
        try:
            code = process.wait(timeout=seconds * 3 + 30)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Only this newly created process group belongs to this probe.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                code = process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=10)
    (output / (name + ".exit")).write_text(str(code) + "\n")
    raw = (output / (name + ".log")).read_text(errors="replace")
    result = {"case": index, "exit": code, "timeout": timed_out,
              "crashed": "handle_crash:" in raw, "script_error": "SCRIPT ERROR:" in raw,
              "leaks": "leaked at exit" in raw or "resources still in use" in raw,
              "error": bool(re.search(r"^ERROR:", raw, re.MULTILINE))}
    recorded = output / (name + ".json")
    if recorded.exists():
        try:
            result["result"] = json.loads(recorded.read_text())
        except (ValueError, OSError) as error:
            result["result_error"] = str(error)
    return result


def passed(case):
    return (case["exit"] == 0
            and not any(case[key] for key in ["timeout", "crashed", "script_error", "leaks", "error"])
            and case.get("result", {}).get("audio_active")
            and case["result"].get("shutdown_mixed")
            and case["result"].get("audio_behavior"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=pathlib.Path)
    parser.add_argument("--project", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent / "probes")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--cases", type=int, default=8)
    parser.add_argument("--seconds", type=int, default=12)
    args = parser.parse_args()
    if not 1 <= args.cases <= 32 or not 1 <= args.seconds <= 60:
        parser.error("cases must be 1..32 and seconds must be 1..60")
    engine, project, output = args.engine.resolve(), args.project.resolve(), args.output.resolve()
    if not engine.is_file():
        parser.error("engine does not exist")
    for name in ["project.godot", "main.tscn", "main.gd"]:
        if not (project / name).is_file():
            parser.error("probe source is missing: " + name)
    output.mkdir(exist_ok=False)
    (output / "source").mkdir()
    sources = {}
    for name in ["project.godot", "main.tscn", "main.gd"]:
        shutil.copyfile(project / name, output / "source" / name)
        sources[name] = hashlib.sha256((project / name).read_bytes()).hexdigest()
    write_json(output / "source.json", sources)
    with engine.open("rb") as stream:
        engine_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.cases) as pool:
        futures = [pool.submit(run_case, index, engine, project, output, args.seconds)
                   for index in range(args.cases)]
        results = [future.result() for future in futures]
    receipt = {"engine": str(engine), "engine_sha256": engine_hash, "cases": args.cases,
               "seconds_per_case": args.seconds, "wall_seconds": round(time.monotonic() - started, 3),
               "results": results}
    write_json(output / "results.json", receipt)
    for case in results:
        print("case", case["case"], "PASS" if passed(case) else "FAIL", "exit", case["exit"])
    print("raw results:", output / "results.json")
    return 0 if all(passed(case) for case in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
