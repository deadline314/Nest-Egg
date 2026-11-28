#!/usr/bin/env bash
# 執行無頭冒煙測試。用法：GODOT=/path/to/godot tools/run_tests.sh
# 除了測試本身的斷言，也會把輸出中的腳本錯誤視為失敗。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

source tools/test_filters.sh
source tools/bounded_run.sh
LOG="$(mktemp)"
trap 'stop_bounded_children; exit 130' INT TERM HUP

if [ ! -d .godot ]; then
	echo "Importing project..."
	run_bounded "$LOG" "$GODOT" --headless --editor --quit
fi

# 輸出寫進檔案（有大小與時間上限），結束時只印失敗與結果（NE-431）。完整輸出留在 KEEP_LOG 指定的檔案裡。
run_bounded "$LOG" "$GODOT" --headless res://tests/smoke_test.tscn
STATUS=$?
grep -m 200 -E '^FAIL: |^BOUNDED_RUN: ' "$LOG"
grep -E '^checks: [0-9]+, failures: [0-9]+' "$LOG" | tail -n 1
if has_unexpected_errors "$LOG"; then
	echo "Detected script errors in output:" >&2
	grep -m 20 -E "SCRIPT ERROR|^ERROR:|Parse Error" "$LOG" >&2
	STATUS=1
fi
if [ -n "${KEEP_LOG:-}" ]; then
	mv "$LOG" "$KEEP_LOG"
	echo "Full output: $KEEP_LOG"
else
	rm -f "$LOG"
fi
exit "$STATUS"
