# 有上限地執行一個 Godot（或任何）程序：輸出只寫檔、檔案大小與執行時間都有上限、超過就連同子程序一起停掉（用 source 載入）。
# 2026-11-28 一支 grep 讀一份沒有上限的 log、吃掉 14.5 GB 記憶體；同一天一輪測試在 session 被終止後還留著 Godot 一直跑（NE-431）。
# Windows 的 Godot_*_console.exe 會再開一個 Godot 程序：只停掉 console 那支，另一支會留下來，所以一律停整棵程序樹。
#
# 用法：
#   source tools/bounded_run.sh
#   run_bounded <log 檔> <命令...>     # 回傳命令的結束代碼；超時或 log 太大時回傳 124，並在 log 最後寫一行 BOUNDED_RUN: 說明
#   stop_bounded_children              # 停掉這個 shell 用 run_bounded 開的、還在跑的程序（給 trap 用）
# 上限可用環境變數調整：BOUNDED_SECONDS（預設 3600 秒）、BOUNDED_LOG_MB（預設 64 MB）。

BOUNDED_SECONDS="${BOUNDED_SECONDS:-3600}"
BOUNDED_LOG_MB="${BOUNDED_LOG_MB:-64}"
BOUNDED_PIDS=()

# 列出一個程序底下所有的子孫程序（不含自己）。Linux 用 ps -o；Git Bash 的 ps 沒有 -o，改讀它固定的欄位（PID PPID ...）。
descendants_of() {
	local table
	table="$(ps -A -o pid= -o ppid= 2>/dev/null || ps -e 2>/dev/null | awk 'NR > 1 { print $1, $2 }')"
	awk -v root="$1" '
		{ parent[$1] = $2 }
		END {
			found[root] = 1
			changed = 1
			while (changed) {
				changed = 0
				for (pid in parent) if (!(pid in found) && (parent[pid] in found)) { found[pid] = 1; changed = 1 }
			}
			for (pid in found) if (pid != root) print pid
		}' <<< "$table"
}

# 停掉一個程序與它開的所有子孫程序。Windows（Git Bash）另外用 taskkill /T 停掉 Godot 自己開的原生子程序。
kill_tree() {
	local pid="$1" child
	local family
	family="$(descendants_of "$pid") $pid"
	for child in $family; do
		if [ -r "/proc/$child/winpid" ] && command -v taskkill >/dev/null 2>&1; then
			taskkill //T //F //PID "$(cat "/proc/$child/winpid")" >/dev/null 2>&1
		fi
		kill -TERM "$child" 2>/dev/null
	done
	sleep 1
	for child in $family; do
		kill -KILL "$child" 2>/dev/null
	done
	return 0
}

run_bounded() {
	local log="$1"
	shift
	local max_bytes=$((BOUNDED_LOG_MB * 1024 * 1024))
	"$@" > "$log" 2>&1 &
	local pid=$!
	BOUNDED_PIDS+=("$pid")
	local waited=0 reason=""
	while kill -0 "$pid" 2>/dev/null; do
		sleep 2
		waited=$((waited + 2))
		local size
		size=$(stat -c %s "$log" 2>/dev/null || echo 0)
		if [ "$size" -gt "$max_bytes" ]; then
			reason="log exceeded ${BOUNDED_LOG_MB} MB"
		elif [ "$waited" -ge "$BOUNDED_SECONDS" ]; then
			reason="still running after ${BOUNDED_SECONDS} s"
		fi
		if [ -n "$reason" ]; then
			kill_tree "$pid"
			break
		fi
	done
	wait "$pid" 2>/dev/null
	local status=$?
	if [ -n "$reason" ]; then
		# 太大的 log 截掉，只留頭尾，後面的讀取（grep）不會再吃到一整份超大檔案。
		if [ "$(stat -c %s "$log" 2>/dev/null || echo 0)" -gt "$max_bytes" ]; then
			local keep=$((max_bytes / 2))
			{ head -c "$keep" "$log"; printf '\n...[truncated]...\n'; tail -c "$keep" "$log"; } > "$log.cut" && mv "$log.cut" "$log"
		fi
		printf '\nBOUNDED_RUN: stopped (%s): %s\n' "$reason" "$*" >> "$log"
		return 124
	fi
	return "$status"
}

stop_bounded_children() {
	local pid
	for pid in "${BOUNDED_PIDS[@]}"; do
		kill -0 "$pid" 2>/dev/null && kill_tree "$pid"
	done
	return 0
}
