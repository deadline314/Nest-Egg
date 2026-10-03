# Nest Egg — 開發守則

## 1. 品質要求（每張票的前提，不另外寫進票）

- 程式碼與架構好維護：命名清楚、職責單一、做好抽象化，可重用的部分抽成框架或共用類別
- 高擴充性：新增內容（武器、敵人、關卡、角色外觀）以資料為主，盡量不改程式
- 高穩定性與高容錯：資源遺失或資料損毀時記錄錯誤並退回安全預設值，不讓遊戲崩潰；錯誤訊息要指出具體位置
- 高效能、低記憶體：避免每影格配置、可重用的物件走物件池，大量繪製分塊或合併
- 合適的功能引導與說明：選單與 HUD 的 tooltip、遊戲內提示一句講重點，不寫廢話
- 不破壞任何原有功能：每次交付前完整測試套件必須全數通過

## 2. 環境

- 引擎：Godot 4.7（Forward+、HDR 2D）
- 測試：`GODOT=/path/to/godot tools/run_tests.sh`（無頭冒煙測試，輸出有腳本錯誤也算失敗）
- 截圖：`godot --path . res://tools/screenshot.tscn -- --out=<絕對路徑> [--scenario=<名稱>]`

## 3. 工作流程

- 需求先整理進 `design/`，再依 `pm-ticket` skill 在 `pm/Nest-Egg/` 開票
- 一張票完成：測試全過 → 截圖存到 `pm/Nest-Egg/images/` → 在票上加 Commit 段落、狀態改「完成」、驗收條件打勾 → commit 一次

## 4. Git 流程

- 一張票 commit 之後，**立刻 push 到 remote 的 main**，不留到之後一起推
- push 之前先 `git fetch origin main`，確認 main 是最新；main 有新的 commit 就 rebase 到最新 main 上，解完衝突再 push（只能快轉，不用 force 推 main）
- 在本機分支上做，push 用 `git push origin HEAD:main`，推完刪掉本機分支。不在 remote 留功能分支，所以不會有舊分支要清
- commit 作者用 `Stanley Li <stanley890314@gmail.com>`
- commit 訊息**不得出現 Claude 等 AI 字樣**，也不得有 `Co-Authored-By`、`Claude-Session` 之類的行
- 遠端拒絕操作（例如刪分支回 403）時，不重試、不繞過，回報使用者
