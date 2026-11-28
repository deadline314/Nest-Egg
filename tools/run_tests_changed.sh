#!/usr/bin/env bash
# 只跑「有更動到的範圍」的測試（平常開發、每張票交付前用這個）。
# 用法：GODOT=/path/to/godot tools/run_tests_changed.sh [基準，預設 origin/main]
# 依 git 的更動（相對基準的提交、未提交的修改、新檔案）挑出受影響的測試套件（tools/select_tests.py），
# 再用 tools/run_tests_parallel.sh 平行跑；受影響的探針（tools/run_*.py，CI 的真實流程檢查）也一起跑（PROBE_JOBS 個同時，預設 4）。只改文件或票時沒有測試要跑。
# 挑選工具出錯（git 失敗、基準不存在、Python 當掉）時以失敗結束，不會當成「沒有測試要跑」。
# 完整測試由 CI 負責（每小時＋每次推送，見 .github/workflows/tests.yml），也可以隨時用 tools/run_tests_parallel.sh 跑全部。
set -uo pipefail
cd "$(dirname "$0")/.."

fail() {
	echo "run_tests_changed.sh：$1" >&2
	echo "沒有跑任何測試；修正上面的問題，或改用 tools/run_tests_parallel.sh 跑全部。" >&2
	exit 2
}

# Windows 的 python3 可能是只會開商店的空殼，先確認真的能執行。
PYTHON=""
for candidate in python3 python; do
	if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >/dev/null 2>&1; then
		PYTHON="$candidate"
		break
	fi
done
[ -n "$PYTHON" ] || fail "找不到可用的 Python 3.8 以上（試過 python3、python）。"

if [ $# -ge 1 ]; then
	BASE="$1"
	git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || fail "找不到基準「$BASE」（不是這個 repo 裡的 commit 或分支）。"
else
	BASE="origin/main"
	if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
		BASE="HEAD~1"
		echo "找不到 origin/main，改用 HEAD~1 當基準。" >&2
	fi
fi

# Python 與 Bash 的共同日誌使用 UTF-8；包含尚未進入 main() 的未捕捉例外。
SELECTED="$(PYTHONIOENCODING=utf-8 "$PYTHON" tools/select_tests.py --base "$BASE")"
STATUS=$?
[ "$STATUS" -eq 0 ] || fail "挑選受影響測試的工具出錯（tools/select_tests.py 結束代碼 $STATUS，原因見上方）。"
SELECTED="${SELECTED//$'\r'/}"  # Windows 的 Python 以 CRLF 換行

# 本機已發布的重複證據到期後清理，結果不影響測試退出狀態。
if ! PYTHONIOENCODING=utf-8 "$PYTHON" tools/evidence_retention.py --apply; then
	echo "舊證據清理有錯誤，繼續執行受影響測試。" >&2
fi

PROBES="$(PYTHONIOENCODING=utf-8 "$PYTHON" tools/select_tests.py --base "$BASE" --probes)"
STATUS=$?
[ "$STATUS" -eq 0 ] || fail "挑選受影響探針的工具出錯（tools/select_tests.py --probes 結束代碼 $STATUS，原因見上方）。"
PROBES="${PROBES//$'
'/}"
if [ -n "$PROBES" ] && [ -z "${GODOT:-}" ]; then
	fail "要跑探針（$PROBES）但沒有設定 GODOT。"
fi

SUITE_STATUS=0
if [ "$SELECTED" = "ALL" ]; then
	echo "改到整個專案或測試流程本身，跑全部測試。"
	tools/run_tests_parallel.sh || SUITE_STATUS=$?
elif [ -n "$SELECTED" ]; then
	echo "受影響的測試：$SELECTED"
	tools/run_tests_parallel.sh --only="$SELECTED" || SUITE_STATUS=$?
fi

# 探針（tools/run_*.py）各自用獨立的設定檔與存檔資料夾跑一段真實流程，可以平行；CI 會逐一再跑一次。
PROBE_STATUS=0
source tools/bounded_run.sh
# 被中斷時連同探針與 Godot 一起停掉（NE-431）。
trap 'for job in $(jobs -p); do kill_tree "$job"; done; stop_bounded_children; exit 130' INT TERM HUP
if [ -n "$PROBES" ]; then
	PROBE_DIR="$(mktemp -d)"
	JOBS="${PROBE_JOBS:-4}"
	echo "受影響的探針（$JOBS 個同時跑，紀錄在 $PROBE_DIR）：$PROBES"
	run_probe() {
		local runner="$1" name
		name="$(basename "$runner" .py)"
		if run_bounded "$PROBE_DIR/$name.txt" "$PYTHON" "$runner" --godot "$GODOT" --output "$PROBE_DIR/$name"; then
			echo "探針通過：$runner"
		else
			echo "探針失敗：$runner（紀錄：$PROBE_DIR/$name.txt）"
			: >"$PROBE_DIR/$name.failed"
		fi
	}
	for runner in ${PROBES//,/ }; do
		while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
		run_probe "$runner" &
	done
	wait
	if compgen -G "$PROBE_DIR/*.failed" >/dev/null; then
		PROBE_STATUS=1
	fi
fi

if [ "$SELECTED" != "ALL" ] && [ -z "$SELECTED" ] && [ -z "$PROBES" ]; then
	echo "沒有受影響的測試要跑（只改了文件、票或與遊戲無關的檔案）。"
fi
[ "$SUITE_STATUS" -eq 0 ] && [ "$PROBE_STATUS" -eq 0 ]
