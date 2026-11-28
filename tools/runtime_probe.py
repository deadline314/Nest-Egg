"""Isolated, bounded Godot probe processes with strict diagnostics and owned cleanup."""

import json
from collections import Counter
import os
import re
import signal
import subprocess


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


# 探針的 log 上限與單行讀取上限（NE-431）：一直噴錯的 Godot 不能把 log 寫到幾 GB，掃 log 時也不把一整行超長內容讀進記憶體。
LOG_LIMIT_BYTES = 64 * 1024 * 1024
LINE_LIMIT = 64 * 1024


def stop_owned(process, force=False):
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL if force else signal.SIGTERM)
        else:
            # Windows 的 Godot_*_console.exe 會再開一個 Godot 程序；只停 console 那支會留下孤兒，所以停整棵樹。
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True)
            if force:
                process.kill()
    except (ProcessLookupError, OSError):
        pass


def _wait_bounded(process, timeout, log_path):
    """等程序結束；超時或 log 超過上限就停掉。回傳 (結束代碼, 原因或空字串)。"""
    import time
    deadline = time.monotonic() + timeout
    while True:
        try:
            return process.wait(timeout=1), ""
        except subprocess.TimeoutExpired:
            pass
        try:
            too_big = log_path.stat().st_size > LOG_LIMIT_BYTES
        except OSError:
            too_big = False
        if too_big or time.monotonic() >= deadline:
            reason = "log exceeded limit" if too_big else "timeout"
            stop_owned(process)
            try:
                return process.wait(timeout=10), reason
            except subprocess.TimeoutExpired:
                stop_owned(process, force=True)
                return process.wait(timeout=10), reason


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
            code, reason = _wait_bounded(process, timeout, output / (mode + ".log"))
            timed_out = reason != ""
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
        while True:
            line = log.readline(LINE_LIMIT)  # 單行最多讀這麼多；超長的一行分段讀，不整行進記憶體
            if not line:
                break
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
