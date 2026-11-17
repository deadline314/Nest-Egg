#!/usr/bin/env bash
# 只跑「有更動到的範圍」的測試（平常開發、每張票交付前用這個）。
# 用法：GODOT=/path/to/godot tools/run_tests_changed.sh [基準，預設 origin/main]
# 依 git 的更動（相對基準的提交、未提交的修改、新檔案）挑出受影響的測試套件（tools/select_tests.py），
# 再用 tools/run_tests_parallel.sh 平行跑。只改文件或票時沒有測試要跑。
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

if [ "$SELECTED" = "ALL" ]; then
	echo "改到整個專案或測試流程本身，跑全部測試。"
	exec tools/run_tests_parallel.sh
fi
if [ -z "$SELECTED" ]; then
	echo "沒有受影響的測試要跑（只改了文件、票或與遊戲無關的檔案）。"
	exit 0
fi
echo "受影響的測試：$SELECTED"
exec tools/run_tests_parallel.sh --only="$SELECTED"
