# 開發規範與逐票交付

> 來源：2026-10-06，使用者要求共用專案規範能由不同開發工具讀取，每完成一張票都要 commit 並立即 push；同步最新 main，必要時 rebase，使用指定作者並移除舊分支。

- 專案規範同時保留 `AGENTS.md` 與 `CLAUDE.md`；技能同時保留 `.agents/skills/` 與 `.claude/skills/`，共用內容需同步更新。
- 工作開始先讀取專案規範；依任務完整讀取對應技能，票券、音訊素材與場景素材各依既有規範處理。
- 每張票完成驗收後，單獨 commit 並立刻 push 到 remote main。commit 作者與提交者使用 Stanley Li，email 為 `stanley890314@gmail.com`。
- commit 訊息只描述需求與交付，不包含 AI 工具、模型名稱或共同作者署名。
- 每次 push 前 fetch 最新 main；有新提交時 rebase，解決衝突並重新驗證受影響範圍。remote main 僅允許快轉推送。
- 推送成功後確認本機 main 與 origin/main 一致；只刪除已合併的工作分支。遠端拒絕操作時不重試、不繞過，直接回報。

## 受影響測試工具的日誌編碼（NE-263，2026-10-30）

Bash 呼叫測試挑選工具時，在該 Python 子程序內指定 UTF-8 標準輸出與錯誤輸出。中文說明及進入 main 前的未捕捉例外都必須與 shell 日誌使用同一編碼；使用者不必設定環境變數，不更動系統 locale 或檔案編碼。

工具錯誤仍以非零結束，不能執行測試或回報「沒有受影響的測試」。測試以嚴格 UTF-8 讀取實際 pipe bytes，另用遵守 Python IO 設定的 cp950 例外樣本重現 Windows 邊界，不用替代字元掩蓋亂碼。
