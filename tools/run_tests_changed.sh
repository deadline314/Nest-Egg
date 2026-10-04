#!/usr/bin/env bash
# 只跑「有更動到的範圍」的測試（平常開發、每張票交付前用這個）。
# 用法：GODOT=/path/to/godot tools/run_tests_changed.sh [基準分支，預設 origin/main]
# 依 git 的更動（相對基準分支的提交、未提交的修改、新檔案）挑出受影響的測試套件（tools/select_tests.py），
# 再用 tools/run_tests_parallel.sh 平行跑。只改文件或票時沒有測試要跑。
# 完整測試由 CI 負責（每小時＋每次推送，見 .github/workflows/tests.yml），也可以隨時用 tools/run_tests_parallel.sh 跑全部。
set -uo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-origin/main}"
git rev-parse --verify --quiet "$BASE" >/dev/null || BASE="HEAD~1"
SELECTED="$(python3 tools/select_tests.py --base "$BASE" 2>/dev/null || python tools/select_tests.py --base "$BASE")"
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
