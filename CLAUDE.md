# Nest Egg — 開發守則

## 1. 品質要求（每張票的前提，不另外寫進票）

- 程式碼與架構好維護：命名清楚、職責單一、做好抽象化，可重用的部分抽成框架或共用類別
- 高擴充性：新增內容（武器、敵人、關卡、角色外觀）以資料為主，盡量不改程式
- 高穩定性與高容錯：資源遺失或資料損毀時記錄錯誤並退回安全預設值，不讓遊戲崩潰；錯誤訊息要指出具體位置
- 高效能、低記憶體：避免每影格配置、可重用的物件走物件池，大量繪製分塊或合併
- 合適的功能引導與說明：選單與 HUD 的 tooltip、遊戲內提示一句講重點，不寫廢話
- 不破壞任何原有功能：交付前「有更動到的範圍」的測試必須全過（`tools/run_tests_changed.sh`）；完整測試由 CI 負責（每次推送、每個 PR、每小時一次且程式有更動才跑），CI 紅了優先處理

## 2. 環境

- 引擎：Godot 4.7（Forward+、HDR 2D）
- 測試（無頭冒煙測試，輸出有腳本錯誤也算失敗）：
  - 平常用：`GODOT=/path/to/godot tools/run_tests_changed.sh`——依 git 更動挑出受影響的測試套件（`tools/select_tests.py`）再平行跑；只改文件或票就不跑
  - 完整平行：`GODOT=/path/to/godot tools/run_tests_parallel.sh`（核心數 + 2 個程序，約 4 分鐘）；`--only=套件1,套件2` 指定套件
  - 循序跑全部：`GODOT=/path/to/godot tools/run_tests.sh`
  - 已知失敗清單在 `tests/known_failures.txt`：只有「新的失敗」讓平行測試與 CI 不通過；修好一項就從清單刪掉
- 截圖：`godot --path . res://tools/screenshot.tscn -- --out=<絕對路徑> [--scenario=<名稱>]`

## 3. 工作流程

- 需求先整理進 `design/`，再依 `pm-ticket` skill 在 `pm/Nest-Egg/` 開票
- 一張票完成：受影響範圍的測試全過 → 截圖存到 `pm/Nest-Egg/images/` → 在票上加 Commit 段落、狀態改「完成」、驗收條件打勾 → commit 一次

## 4. Git 流程

- 每做完一張票，**各自 commit 並立刻 push 到 remote 的 main**；不把多張已完成的票累積成一次提交或推送
- push 之前先 `git fetch origin main`，確認 main 是最新；main 有新的 commit 就 rebase 到最新 main 上，解完衝突再 push（只能快轉，不用 force 推 main）
- 在本機分支上做，push 用 `git push origin HEAD:main`。推完確認本機 `main` 與 `origin/main` 指向同一個 commit，再移除已合併的本機工作分支與遠端舊功能分支；未合併的分支先保留並回報，不直接刪除
- commit 作者用 `Stanley Li <stanley890314@gmail.com>`
- commit 的作者與提交者都使用 `Stanley Li <stanley890314@gmail.com>`。commit 訊息不得出現 Claude、GPT、GPT-6、Codex 等 AI 名稱或模型署名，也不得加入任何 `Co-Authored-By`、`Claude-Session` 或類似的署名行
- 遠端拒絕操作（例如刪分支回 403）時，不重試、不繞過，回報使用者
