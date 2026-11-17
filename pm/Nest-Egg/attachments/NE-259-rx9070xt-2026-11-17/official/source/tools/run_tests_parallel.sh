#!/usr/bin/env bash
# 平行執行完整測試：把測試套件分成幾組，各組用獨立的 Godot 程序同時跑，總時間約等於最慢的那一組。
# 用法：GODOT=/path/to/godot tools/run_tests_parallel.sh [--only=套件1,套件2,...] [組數]
#   不給 --only 就跑全部；main 是開頭那一大段流程測試。平常開發用 tools/run_tests_changed.sh（只跑有更動到的範圍）。
#   組數預設是 CPU 核心數 + 2（測試大多在等遊戲時間，不吃滿 CPU）；也可以用環境變數 SHARDS 指定。
# 每組用自己的使用者資料夾（XDG_DATA_HOME／APPDATA），不會互相覆蓋存檔；套件的耗時記在 .godot/suite_times.txt，
# 下次依耗時平均分組（第一次用預設估計）。輸出判斷與 run_tests.sh 相同（tools/test_filters.sh）。
# 結果：每組的完整輸出在 $LOG_DIR（預設暫存資料夾）；最後列出總檢查數、失敗項目與腳本錯誤，有任何失敗就以非零代碼結束。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
source tools/test_filters.sh

ONLY=""
POSITIONAL=()
for arg in "$@"; do
	case "$arg" in
		--only=*) ONLY="${arg#--only=}" ;;
		*) POSITIONAL+=("$arg") ;;
	esac
done
CORES="$(nproc 2>/dev/null || echo 4)"
SHARDS="${POSITIONAL[0]:-${SHARDS:-$((CORES + 2))}}"
TIMES_FILE=".godot/suite_times.txt"
DEFAULT_SECONDS=25
DEFAULT_MAIN_SECONDS=240
LOG_DIR="${LOG_DIR:-$(mktemp -d)}"

if [ ! -d .godot ]; then
	echo "Importing project..."
	"$GODOT" --headless --editor --quit >/dev/null 2>&1
fi

if [ -n "$ONLY" ]; then
	SUITE_LIST="$ONLY"
else
	SUITE_LIST="main,$("$GODOT" --headless res://tests/smoke_test.tscn -- --only=list 2>/dev/null | sed -n 's/^SUITES: //p')"
	if [ "$SUITE_LIST" = "main," ]; then
		echo "Could not list the test suites (script error?). Run tools/run_tests.sh to see the output." >&2
		exit 1
	fi
fi

declare -A SECONDS_OF
if [ -f "$TIMES_FILE" ]; then
	while read -r name seconds; do
		[ -n "${name:-}" ] && SECONDS_OF["$name"]="${seconds%.*}"
	done < "$TIMES_FILE"
fi

# 依耗時由長到短，每次放進目前總時間最短的那一組。
ITEMS=($(echo "$SUITE_LIST" | tr ',' ' '))
SORTED="$(for name in "${ITEMS[@]}"; do
	fallback=$DEFAULT_SECONDS
	[ "$name" = "main" ] && fallback=$DEFAULT_MAIN_SECONDS
	echo "${SECONDS_OF[$name]:-$fallback} $name"
done | sort -nr)"
[ "$SHARDS" -gt "${#ITEMS[@]}" ] && SHARDS=${#ITEMS[@]}
declare -a LOAD ASSIGNED
for ((i = 0; i < SHARDS; i++)); do LOAD[$i]=0; ASSIGNED[$i]=""; done
while read -r seconds name; do
	best=0
	for ((i = 1; i < SHARDS; i++)); do
		if [ "${LOAD[$i]}" -lt "${LOAD[$best]}" ]; then best=$i; fi
	done
	LOAD[$best]=$((LOAD[$best] + seconds))
	ASSIGNED[$best]="${ASSIGNED[$best]:+${ASSIGNED[$best]},}$name"
done <<< "$SORTED"

echo "Running ${#ITEMS[@]} groups in $SHARDS processes (logs: $LOG_DIR)"
START=$SECONDS
PIDS=()
for ((i = 0; i < SHARDS; i++)); do
	[ -z "${ASSIGNED[$i]}" ] && continue
	DATA_HOME="$LOG_DIR/data_$i"
	mkdir -p "$DATA_HOME"
	(
		export XDG_DATA_HOME="$DATA_HOME" APPDATA="$DATA_HOME" LOCALAPPDATA="$DATA_HOME"
		"$GODOT" --headless res://tests/smoke_test.tscn -- --only="${ASSIGNED[$i]}" > "$LOG_DIR/shard_$i.log" 2>&1
	) &
	PIDS+=($!)
	echo "  process $i (estimated ${LOAD[$i]} s): ${ASSIGNED[$i]}"
done
for pid in "${PIDS[@]}"; do wait "$pid"; done

CHECKS=0
FAILURES=0
KNOWN=0
STATUS=0
: > "$TIMES_FILE.new"
for ((i = 0; i < SHARDS; i++)); do
	LOG="$LOG_DIR/shard_$i.log"
	[ -f "$LOG" ] || continue
	line="$(grep -E '^checks: [0-9]+, failures: [0-9]+' "$LOG" | tail -1)"
	if [ -z "$line" ]; then
		echo "Process $i did not finish (no result line): $LOG" >&2
		STATUS=1
		continue
	fi
	checks="$(echo "$line" | sed -E 's/checks: ([0-9]+), failures: ([0-9]+)/\1/')"
	CHECKS=$((CHECKS + checks))
	while IFS= read -r failure; do
		message="${failure#FAIL: }"
		if is_known_failure "$message"; then
			KNOWN=$((KNOWN + 1))
			echo "[process $i] known failure: $message"
		else
			FAILURES=$((FAILURES + 1))
			echo "[process $i] NEW FAILURE: $message"
		fi
	done < <(grep -E '^FAIL: ' "$LOG")
	if has_unexpected_errors "$LOG"; then
		echo "Detected script errors in output of process $i: $LOG" >&2
		STATUS=1
	fi
	sed -n 's/^SUITE_TIME //p' "$LOG" >> "$TIMES_FILE.new"
done
# 只跑一部分時，保留沒跑到的套件原本的耗時紀錄。
if [ -s "$TIMES_FILE.new" ]; then
	if [ -f "$TIMES_FILE" ]; then
		awk 'NR==FNR { fresh[$1]=1; next } !($1 in fresh)' "$TIMES_FILE.new" "$TIMES_FILE" >> "$TIMES_FILE.new"
	fi
	mv "$TIMES_FILE.new" "$TIMES_FILE"
else
	rm -f "$TIMES_FILE.new"
fi
echo "checks: $CHECKS, new failures: $FAILURES, known failures (tests/known_failures.txt): $KNOWN  (wall time $((SECONDS - START)) s)"
[ "$FAILURES" -gt 0 ] && STATUS=1
exit $STATUS
