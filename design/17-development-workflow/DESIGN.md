# 開發規範與逐票交付

> 來源：2026-10-06，使用者要求共用專案規範能由不同開發工具讀取，每完成一張票都要 commit 並立即 push；同步最新 main，必要時 rebase，使用指定作者並移除舊分支。

- 專案規範同時保留 `AGENTS.md` 與 `CLAUDE.md`；技能同時保留 `.agents/skills/` 與 `.claude/skills/`，共用內容需同步更新。
- 工作開始先讀取專案規範；依任務完整讀取對應技能，票券、音訊素材與場景素材各依既有規範處理。
- 每張票完成驗收後，單獨 commit 並立刻 push 到 remote main。commit 作者與提交者使用 Stanley Li，email 為 `stanley890314@gmail.com`。
- commit 訊息只描述需求與交付，不包含 AI 工具、模型名稱或共同作者署名。
- 每次 push 前 fetch 最新 main；有新提交時 rebase，解決衝突並重新驗證受影響範圍。remote main 僅允許快轉推送。
- 推送成功後確認本機 main 與 origin/main 一致；只刪除已合併的工作分支。遠端拒絕操作時不重試、不繞過，直接回報。
