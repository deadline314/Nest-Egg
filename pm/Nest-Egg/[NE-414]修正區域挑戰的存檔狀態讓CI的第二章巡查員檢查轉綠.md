# [NE-414] 修正區域挑戰的存檔狀態讓 CI 的第二章巡查員檢查轉綠

> 狀態：完成

## 內文

### 需求
main 的 CI 從 NE-410 起每次都紅：`tests` 的 `full` 工作在「Check chapter-two patroller results and cold reads」失敗，後面的檢查全部沒跑。找出根因修掉（不放寬檢查），並讓推送前跑的「受影響範圍測試」也會跑到這類檢查，以後不會再漏。

### 來源
2026-11-28，主 session 轉達：main 的 CI 從 86dd56598（NE-410）起都是紅的，請先修、bisect 確認、說明為什麼受影響範圍的測試沒抓到，挑選規則漏了就補進 `tools/select_tests.py`。

### 驗收條件
- [x] 本機重現 CI 的失敗，並用 bisect 確認是哪一個 commit 造成
- [x] 修掉根因；檢查腳本不改
- [x] 第二章巡查員檢查八種情況全過；CI 原本被跳過的其他探針檢查也在本機跑過（Windows 上 `controller_storage` 本來就跑不起來，見測試結果）
- [x] 存檔時世界狀態格式不對（物件、文字）不會讓整份存檔出錯，退回安全預設值
- [x] 有自動測試把區域挑戰的狀態實際送過存檔清理
- [x] `tools/select_tests.py` 會挑出受影響的探針檢查，`tools/run_tests_changed.sh` 推送前就會跑
- [ ] 推送後 CI 轉綠

### 測試流程
1. 執行 `python tools/run_patroller_completion.py --godot <godot> --output <新資料夾>`，預期八種情況都 PASS、沒有腳本錯誤
2. 執行 `python tools/select_tests.py --probes --explain --files data/levels/ch2_market_gate.tres`，預期列出 `tools/run_patroller_completion.py` 與挑中的原因
3. 進第二章市集入口，用電纜電倒一名敵人後存檔、讀檔，預期挑戰進度還在

---

# 跟其他票的關係

- Blocks：無
- Blocked by：無
- Related：NE-410、NE-411

---

# Commit-1

## 內文

NE-410 讓區域挑戰把進度存成一個物件（`{progress, done, failed}`）放進世界狀態；但存檔時清理世界狀態的 `RunSnapshot._world` 只認得開關，對每個值做 `value == true`。Godot 4.7 裡物件和布林比較是執行錯誤，整段清理中斷，第二章市集入口（有第一個區域挑戰）一存檔就壞掉，巡查員檢查的「重試成功後只結算一次」等三項因此失敗。
bisect：35e0dea57（NE-409）八種情況全過；86dd56598（NE-410）`accepted` 失敗，錯誤一模一樣。
現在存檔清理認得 `challenge@` 開頭的鍵，把進度夾在 0–1000、完成與失敗只收布林；其餘鍵只收布林，物件或文字一律當成 false，不會再讓比較出錯。
為什麼推送前沒抓到：受影響範圍的測試只挑 `tests/suite/` 的測試套件，CI 另外跑的 24 個探針檢查（`tools/run_*.py` 跑 `tests/probes/` 的真實流程）完全不在挑選範圍內；區域挑戰的測試只在記憶體裡來回存取狀態，沒有經過存檔清理。現在 `select_tests.py --probes` 會沿著相依關係挑出受影響的探針（例：改 `ch2_market_gate.tres` 會挑到巡查員檢查），`run_tests_changed.sh` 跑完套件後接著跑它們（預設 4 個同時）；區域挑戰的測試也把狀態實際送過存檔清理。

### 測試結果

| 項目 | 結果 |
|---|---|
| 第二章巡查員檢查 | 修正前：`accepted` 失敗（三項）；修正後八種情況全過 |
| 全部探針檢查（本機，CI 原本被跳過的也包含） | 24 個中 23 個通過；`controller_storage` 在 Windows 上不修改也一樣失敗（它比對隔離設定檔路徑的寫法只在 Linux 成立，CI 在 Linux 上通過），與這張票無關 |
| 測試套件（改到 `select_tests.py`，全部跑） | 通過 107748 / 107748（89 個套件），用新的 `run_tests_changed.sh` 跑，套件之後接著跑探針 |
| 腳本錯誤 | 0 |
| 自動檢查 | 挑戰狀態送過存檔清理後不變、可以還原；格式不對的挑戰狀態退回未開始，物件形式的開關當成 false |
| CI | 推送後確認，結果補在下方 |
