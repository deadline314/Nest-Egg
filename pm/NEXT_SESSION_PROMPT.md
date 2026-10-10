# 新 Session 接手指令：序章至第一章完整可玩

以下內容可直接貼到 Nest-Egg 的新 Session。

```text
請接手 Nest-Egg（Godot 4.7.2，Forward+／HDR 2D），先同步最新 origin/main，再從最新 main 建 codex/ feature branch。先完整讀 AGENTS.md、.agents/skills/pm-ticket/SKILL.md、pm/user_guide.md、pm/SESSION_HANDOFF_2026-10-11.md、pm/attachments/worktree-retirement-2026-10-11/README.md，以及相關章節、連續性、佈景與原生畫面驗證 skills。另讀 pm/handoff/character-art-2026-10-11.md，避免重做另一台電腦的角色票。

先盤點目前票狀態與未勾驗收，不只沿用舊摘要。優先核對 ST-16、ST-2、ST-9、ST-10、NE-178、NE-223、NE-228、NE-230、NE-246、BG-31、NE-233；打包為 NE-232。NE-247 已合入 main，不重新做。核对保留候選、原始失敗、來源 SHA 和 stash。舊 worktree／分支已依使用者要求封存清理，請以 retirement manifest 的最新結果為準，不假設那些路徑／remote branch 還存在。

未完成來源在 pm/attachments/worktree-retirement-2026-10-11/preserved-branches.bundle。先 git bundle verify 和 list-heads，再依 README 將舊章節來源 a5f2a1ba9eb64233b56108c3e930c68bffa52158、武器候選 41f326ab09060ebff2b58907ac50122926b9f17d 恢復到各自新審查分支；不要整包盲合或覆蓋最新 main。第二章布局和 ST-10 舞台未提交來源另有 ZIP、patch 和 manifest；故事、序章、tooltip 的其他未採用 ZIP 在 pm/attachments/session-close-2026-10-11/。先比對前提，只採必要且通過驗證的部分。

舊第一章 WIP 的原始 selector 選 ALL83：86,162 checks、126 new failures、0 known、3 SCRIPT、exit1。原報告與 failures.csv 在 pm/Nest-Egg/attachments/NE-246-story-cloud-evidence/cloud/。這是舊 a5f2 的結果，不是最新 main 的測試結果；Story 型別、舊 opening／Pacing／Continuity 契約、正式 producer／旗標與取消結算仍需逐項核對。不能改 selector、加 known failure、刪斷言、假造 owner／receipt、直接送旗標來變綠。舊真 Main 的 528/0 和真子彈閱讀 97/0 只證明安排的局部路線，不能宣稱整章完成。HUD tooltip 蓋住通訊仍未正式修入；原截圖在交接文件。

主要目標是從正式新遊戲入口，依自然劇情完成序章→第一章→章末，包含合理劇本、可玩教學、NPC／通訊、主支線與 HUD／地圖、必要戰鬥、過場、機關、存檔、死亡重試和關閉程序後續玩。每場先審劇本的動機、因果、資訊量與演出，再落地；不要以跳關 probe／單場景／大綱冒充完整可玩。普通路線不封牆強迫戰鬥。場景物件的大小、位置、支撐、背景高低覆蓋與角色頭腳構圖都要實際看；一般畫面持續雜訊、tooltip 遮擋和 UI 可讀性按相關票處理。重要通訊可停世界、玩家確認前進，閱讀上開 Pause／返回仍保持原暫停責任。全流程考慮鍵鼠與手把，合成輸入不能稱實體手把驗收。

每張票按 AGENTS.md 交付：固定記下本票開始 SHA，原 tools/run_tests_changed.sh <固定基準SHA> 選出的受影響範圍全過（含腳本／編譯錯誤檢查）→ 同源 Forward+ 真實截圖存 pm/Nest-Egg/images/（BG／ST依專案規則）→ 票加 Commit 段落、只勾真正通過項，整票全部達成才改完成 → 各自 commit 並立刻 push。一般不額外跑完整測試，完整 CI 由既有排程負責；若原 selector 因框架修改選 ALL，不能自行縮小。rebase 若改動來源／行為要重驗相關範圍，不拿舊結果證明新來源。

每次 push 前 git fetch origin main，必要時 rebase 最新 main 並處理衝突；用 git push origin HEAD:main，只能快轉，禁止 force main。作者與提交者均 Stanley Li <stanley890314@gmail.com>，commit 訊息不得有 AI／模型名稱、Co-Authored-By 或類似署名。每張票完成後確認本機 main＝origin/main，移除已合併工作分支；遠端拒絕不要重試或繞過。若要新票，先 fetch、按該 pm 專案資料夾最大號＋1，開完立即 commit＋push，避免撞號。未完成結果保留原始失敗與可恢復來源，不提早結案。

記憶體方面，使用者允許多用一些 RAM，不要套用過度保守的固定剩餘門檻；持續量測可用實體 RAM、系統 commit／pagefile 餘量、程序峰值與實際 VRAM，避免耗盡導致 OOM、關機／重啟。ComfyUI 和 Godot 可在資源足夠時一起跑，模型／圖片用適當小批，完成回收，不在已滿時繼續堆。GPU 依實際電腦和現有共享鎖協調；Intel Arc 沒有 nvidia-smi 不代表 VRAM 為零。雲端先確認真的選 Nest-Egg、實際 Git fetch 成功、Godot 和 cgroup／磁碟額度，不能只看 connected。

可平行做互不改同檔的 CPU／邏輯任務，复杂用 6.1 Sol、簡單盤點用 Luna，由主 Session 驗收；生成和本機 GPU 驗收由指定 Session 協調。一般設計已授權自行決定，不必再問。先完成序章至第一章，通過真自然路線、死亡重試、保存與冷續玩，再交雲端按 NE-232 製作獨立 Windows「序章至第一章」單檔並回本機真啟動驗收；probe 包或 readiness 工具成功不能當正式交付。完成這個目標前不擴張第二章開發。
```
