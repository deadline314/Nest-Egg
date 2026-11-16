#!/usr/bin/env bash
set -uo pipefail
export PATH="/usr/bin:/mingw64/bin:$PATH"
python3() { "/c/Users/stanl/AppData/Local/Programs/Python/Python313/python.exe" "$@"; }
export -f python3
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
export GODOT="/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
export SHARDS=2
export LOG_DIR="C:/NE/evidence-20261117/bg32/official-3713"
cd /c/NE/bg32-20261117
mkdir -p "$LOG_DIR"
git rev-parse HEAD > "$LOG_DIR/base.txt"
tools/run_tests_changed.sh 3713db51062b14ed33ab61488559109fc41e2bfd > "$LOG_DIR/console.log" 2>&1
bg32_status=$?
printf '%s\n' "$bg32_status" > "$LOG_DIR/exit.txt"
exit "$bg32_status"
