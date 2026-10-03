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

# 測試刻意觸發的錯誤（驗證缺圖／缺定義時的容錯）不算失敗。
EXPECTED_ERRORS="missing_part|no_such_character|test_catalog|no_such_icon|起點 987654|test_bad_cutscene|no_such_stage|no_such_sfx|test_missing_prop|test_npc_bad"
if grep -E "SCRIPT ERROR|^ERROR:|Parse Error" "$LOG" | grep -vqE "$EXPECTED_ERRORS"; then
	echo "Detected script errors in output." >&2
	STATUS=1
fi
rm -f "$LOG"
exit "$STATUS"
