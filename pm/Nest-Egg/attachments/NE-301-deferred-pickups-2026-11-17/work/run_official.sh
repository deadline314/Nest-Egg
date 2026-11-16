#!/usr/bin/env bash
set -uo pipefail
export PATH="/usr/bin:/mingw64/bin:$PATH"
python3() { "/c/Users/stanl/AppData/Local/Programs/Python/Python313/python.exe" "$@"; }
export -f python3
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
export GODOT="/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
export SHARDS=2
export LOG_DIR="D:/NestEggVerification/evidence-20261117/ne301/official-aae"
cd /c/NE/bg32-20261117
mkdir -p "$LOG_DIR"
git rev-parse HEAD > "$LOG_DIR/base.txt"
tools/run_tests_changed.sh aae101cfc85b192af9558d5b38d250aea4f1e726 > "$LOG_DIR/console.log" 2>&1
ne301_status=$?
printf '%s\n' "$ne301_status" > "$LOG_DIR/exit.txt"
exit "$ne301_status"
