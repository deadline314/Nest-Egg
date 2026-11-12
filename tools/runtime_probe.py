"""Isolated, bounded Godot probe processes with strict diagnostics and owned cleanup."""

import json
from collections import Counter
import os
import re
import signal
import subprocess


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


def run_case(mode, engine, output, timeout, *, project, scene, slot, verbose=False,
             expected_diagnostics=()):
    # Only the trusted caller declares exact intentional errors. The probe's
    # result cannot authorize diagnostics, and no pattern/summary is matched.
    if not isinstance(expected_diagnostics, tuple) or any(
            not isinstance(line, str) or not line.startswith("ERROR: ")
            or "\n" in line or "\r" in line or "SCRIPT ERROR" in line
            or "Parse Error" in line for line in expected_diagnostics):
        raise ValueError("expected_diagnostics must be exact ERROR lines in a tuple")
    expected = Counter(expected_diagnostics)
    observed_expected = Counter()

    profile = output / (mode + "-profile")
    environment = os.environ.copy()
    environment.update(XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile))
    command = [str(engine), "--headless", *(["--verbose"] if verbose else []),
               "--audio-driver", "Dummy", "--path", str(project),
               scene, "--", "--mode=" + mode,
               "--save-dir=" + str(slot), "--out=" + str(output / mode)]
    timed_out = False
    with (output / (mode + ".log")).open("w") as log:
        process = subprocess.Popen(command, cwd=project, env=environment, stdout=log,
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
                          r"Program crashed|leaked at exit|resources still in use|"
                          r"Leaked instance:|Resource still in use:")
    diagnostics, diagnostic_count = [], 0
    unexpected_diagnostics, unexpected_diagnostic_count = [], 0
    with (output / (mode + ".log")).open(errors="replace") as log:
        for line in log:
            if bad_line.search(line):
                diagnostic_count += 1
                complete_line = line.strip()
                if len(diagnostics) < 32:
                    diagnostics.append(complete_line[:512])
                if observed_expected[complete_line] < expected[complete_line]:
                    observed_expected[complete_line] += 1
                else:
                    unexpected_diagnostic_count += 1
                    if len(unexpected_diagnostics) < 32:
                        unexpected_diagnostics.append(complete_line[:512])
    case = {"mode": mode, "exit": code, "timeout": timed_out,
            "diagnostics": diagnostics, "diagnostic_count": diagnostic_count,
            "expected_diagnostics": dict(expected),
            "observed_expected_diagnostics": dict(observed_expected),
            "missing_expected_diagnostics": dict(expected - observed_expected),
            "unexpected_diagnostics": unexpected_diagnostics,
            "unexpected_diagnostic_count": unexpected_diagnostic_count}
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
    case["passed"] = (code == 0 and not timed_out
                      and diagnostic_count == sum(expected.values())
                      and observed_expected == expected and not unexpected_diagnostic_count
                      and type(data.get("checks")) is int and data["checks"] > 0
                      and data.get("failures") == [])
    return case
