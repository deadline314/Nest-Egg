#!/usr/bin/env python3
"""第四章存檔鏈（NE-431）：在獨立的程序裡從新遊戲走到 Atropos 競技場並存檔退出（接線廊 → 工作帶 → 競技場），
再另開一個程序按「繼續遊戲」：要回到清理線安全臺，接著進原帳辦公室拿到原帳。兩個程序共用同一個存檔資料夾，
各自有獨立的使用者資料夾；每個程序都有時間與 log 上限，停掉時連子程序一起停（tools/runtime_probe.py）。
用法：python tools/run_ch4_save_chain.py --godot <Godot> --output <新資料夾>
這條鏈原本不在測試挑選與 CI 裡，地圖線曾在「冷啟動回到安全臺」這一步看到失敗（NE-431）。
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from runtime_probe import LINE_LIMIT, _wait_bounded, stop_owned

PROJECT = Path(__file__).resolve().parents[1]
CASES = [
    ("write", "res://tools/ch4_atropos_probe.tscn", 1500),
    ("continue", "res://tools/ch4_ledger_probe.tscn", 900),
]
BAD = re.compile(r"^FAIL |SCRIPT ERROR|^ERROR:|Parse Error|handle_crash:|Program crashed")
DONE = re.compile(r"^RESUME_PROBE \S+ mode=(\w+) failures=(\d+)")


def run(mode, scene, timeout, engine, output, slot):
    profile = output / (mode + "-profile")
    environment = os.environ.copy()
    environment.update(XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile))
    command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(PROJECT), scene, "--",
               "--mode=" + mode, "--save-dir=" + str(slot), "--out=" + str(output / mode)]
    log_path = output / (mode + ".log")
    with log_path.open("w") as log:
        process = subprocess.Popen(command, cwd=PROJECT, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code, reason = _wait_bounded(process, timeout, log_path)
        finally:
            if process.poll() is None:
                stop_owned(process, force=True)
    problems, finished = [], None
    with log_path.open(errors="replace") as log:
        while True:
            line = log.readline(LINE_LIMIT)
            if not line:
                break
            if BAD.search(line) and len(problems) < 20:
                problems.append(line.strip()[:300])
            match = DONE.search(line)
            if match:
                finished = int(match.group(2))
    passed = code == 0 and not reason and finished == 0 and not problems
    return {"mode": mode, "scene": scene, "exit": code, "stopped": reason, "probe_failures": finished,
            "problems": problems, "passed": passed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / ".gdignore").touch()
    slot = output / "slot"
    slot.mkdir()
    cases = []
    for mode, scene, timeout in CASES:
        case = run(mode, scene, timeout, args.godot.resolve(), output, slot)
        cases.append(case)
        print(f"{mode}: {'PASS' if case['passed'] else 'FAIL'} exit={case['exit']} probe_failures={case['probe_failures']}"
              + (f" stopped={case['stopped']}" if case["stopped"] else ""))
        for problem in case["problems"]:
            print("  " + problem)
        if not case["passed"]:
            break
    (output / "receipt.json").write_text(json.dumps({"cases": cases}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if len(cases) == len(CASES) and all(case["passed"] for case in cases) else 1


if __name__ == "__main__":
    sys.exit(main())
