#!/usr/bin/env bash
# 執行無頭冒煙測試。用法：GODOT=/path/to/godot tools/run_tests.sh
# 除了測試本身的斷言，也會把輸出中的腳本錯誤視為失敗。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

if [ ! -d .godot ]; then
	echo "Importing project..."
	"$GODOT" --headless --editor --quit >/dev/null 2>&1
fi

LOG="$(mktemp)"
"$GODOT" --headless res://tests/smoke_test.tscn 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}

source tools/test_filters.sh
if has_unexpected_errors "$LOG"; then
	echo "Detected script errors in output." >&2
	STATUS=1
fi
rm -f "$LOG"
exit "$STATUS"
