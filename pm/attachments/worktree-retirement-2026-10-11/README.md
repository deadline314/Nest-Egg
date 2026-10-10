# 2026-10-11 舊 worktree 與分支封存

使用者明確要求同步最新 main、移除其他 worktree 和舊分支，並讓新 Session 接續。盤點基準 main 為 `4198f1f9fc19f9bb7e19694b07ce96336ad3357d`。本資料夾保存未發布候選；**封存不是程式合併、測試通過或票完成**。刪除／保留的實際結果見 [manifest.json](manifest.json)。

## 哪些已合入，哪些只能保留

- `codex/chapter2-layout`、`codex/stage-framing`、`codex/world-ui-clarity` 的既有提交均已是 main 祖先，無需再合併。第二章 worktree 43 個未提交檔與舞台 worktree 21 個檔（含兩個 tracked 修改）另有原始 ZIP／patch。
- `codex/chapter-one-producers` 的 `a5f2a1ba` 包含 148 檔故事／通訊 WIP；原 ALL83 有 126 新失敗與三個 SCRIPT，依 AGENTS.md 受影響測試先過的要求不能直接合入 main。
- 雲端武器 `41f326ab` 及其多個較早審查分支是候選／證據歷史；尚未完成本機、操作和整票验收，不以舊雲端綠色結果替代最新整合。
- 雲端 NE-245／246 evidence 分支的有效原始證據已有主線票據保存；bundle 另保留完整提交，避免整個 evidence 分支帶回舊程式。

沒有為「把所有分支合掉」將紅色程式發布、採空內容合併假稱完成或回填舊開場。下一個 Session 應恢復候選、逐項修復與驗收，再按票合入最新 main。

## 恢復提交歷史

`preserved-branches.bundle` 保存 manifest 中 16 個當時的 branch／remote ref，包含其未合併歷史；不複製 main 已有的全部歷史，因此需要完整 main 歷史。淺 clone 先補齊 main 歷史。所有 hash 與原始 ref 名稱見 manifest。驗證和取出只會建立新審查分支，不改 main。

```bash
git fetch origin main
git bundle verify pm/attachments/worktree-retirement-2026-10-11/preserved-branches.bundle
git bundle list-heads pm/attachments/worktree-retirement-2026-10-11/preserved-branches.bundle
git fetch pm/attachments/worktree-retirement-2026-10-11/preserved-branches.bundle refs/heads/codex/chapter-one-producers:refs/heads/codex/review-ch1-preserved
git fetch pm/attachments/worktree-retirement-2026-10-11/preserved-branches.bundle refs/remotes/origin/codex/cloud-weapon-phone-context-review:refs/heads/codex/review-weapons-preserved
```

從最新 main 建實作分支，將必要候選逐段審查、整合，處理最新 main 的貼圖／角色修正，先過相關測試再發布；不要在舊候選 HEAD 直接開發後覆蓋 main。bundle 內是 Git 物件；LFS 素材仍須原 remote 的實際 LFS 物件，不宣稱這是自足的遊戲發布包。

## 恢復未提交檔案

各 `*-uncommitted.zip` 有原 HEAD、原始檔 bytes、SHA256、tracked-change.patch 和 manifest。`stage-framing` 的 patch 只對舊來源 HEAD 適用，新 main 先比對或用三方審查，不能盲解壓覆蓋正式來源。`chapter2-layout` 是未採用新版第二章候選，不在本輪第一章開發目標。

第一章和 contextual UI 的 ZIP 只保存自然生成 UID；數千個可重建 `.import` 與 translation 不重複保存。各 worktree 的 `.godot` 匯入快取及 Python bytecode 可重建；沒有其他 ignored 原始來源。managed worktree 另以 app 歸檔機制保存可恢復快照，實際結果見 manifest。

主 checkout 的兩個既有驗收打勾另存 `primary-unaccepted-ticket-edits.zip`，只是原始現場；沒有新增證據支持 BG-17 暗場量測、ST-1 使用者確認，不能把這兩個修改當作本輪已驗收。原三個 stash 保留在本機 Git，不清空、不自動套入新分支；其 ref SHA 記在 manifest，若需要先逐檔核對內容。

## 本次檢查範圍

這次更新交接、同步 main 和移除已封存 checkout，沒有修改正式 runtime 或啟動模型／Godot。檢查 bundle verify、ZIP CRC／原始 SHA、刪除前的來源前提、文件連結、Git 同步及作者資訊。快轉時短暫出現舊 pack index 不可用訊息，之後 Git connectivity fsck 自然 exit0；舊 pack 已由 Git 維護替換，沒有自行刪或改 Git 物件。
