# 雲端派工與環境核對（2026-10-10）

雲端工作必須從工作頁的環境選單明確選擇既有 `Nest-Egg`。只建立一般 cloud chat，不會自動帶入這個環境。三個早先一般工作區的任務已在環境檢查停止：Ubuntu 24.04、空白 `/workspace/scratch/`，沒有專案或 Godot，沒有修改、commit 或 push；不能算已派到正式開發環境。

## 已選定的環境

- 工作頁已選擇 `Cloud` → `Nest-Egg`。
- 真正 session：`01a12412-cd59-74f3-9f7d-fe7d5356e098`，雲端執行主機 `durable`。
- 實際工作路徑 `/workspace/Nest-Egg`，fetch/push remote 均為 `https://github.com/deadline314/Nest-Egg.git`。
- 實際系統 Debian 13.6、Xeon Platinum 8573C，5 個可見邏輯核心；不能把可見核心數當 CPU 配額。
- 啟用既有專案環境後為 Godot `4.7.2.stable.official.ed1daf0bf`。未啟用前 PATH 的 4.6.3 不能用於本專案驗收。
- 此次命令回報約 17 GiB RAM、16 GiB 可用，磁碟約 32G、30G 可用；不同於先前列出的 32 GiB 上限，不按舊容量安排負載。
- 截至首次核對，環境已提供 shell，但 `git fetch origin main` 失敗：`Failed to connect to proxy port 8080 after 0 ms: Could not connect to server`。尚未取得最新 main，沒有開始 source 實作或交付測試。

已請同一 session 透過既有 Cloud Environment 官方能力檢查網路就緒與正常等待／重連入口，只在狀態變化後有限重試一次 fetch。不能停用或繞過代理、網路政策，不能取出憑證，不能用另一份 clone 冒充設定好的環境。這個錯誤不是 remote 403；真正權限拒絕仍不重試或繞過。

後續核對：官方狀態 revision 由 2 變為 5，回報 `running / connected`，網路政策就緒仍為 `unknown`。狀態變化後僅重試一次 fetch，仍 exit 128、相同 proxy 8080 錯誤。代理 TCP 檢查回報 `Operation not permitted`，官方能力沒有 reconnect 入口，因此沒有继续重試或繞過。原始 log 位於該雲端環境 `/workspace/Nest-Egg/work/bg25-network/fetch-origin-main.log`；session 已停止 source 工作、保留環境，BG-25 尚未實作，B/C 尚未派到正確環境。這是環境連線阻擋，不能誤稱任務已在背景開發。

## 分工

| 工作 | 票 | 範圍 | 實際派工狀態 |
|---|---|---|---|
| 雲端 A：場景動態 | BG-25 | PropData/PropNode、局部動畫元件/shader、相關道具資料與測試；先做水管水流 | 已進入正確環境，等網路同步最新 main |
| 雲端 B：武器差異與連段 | NE-236、NE-237；NE-231 僅近戰部分 | MeleeSet/連段處理、Player 近戰與相應成長、測試；不碰角色基礎 rig 或故事存檔 | 待 A 完成連線核對後，另建明確選環境的 session；尚未開始 |
| 雲端 C：累積章節打包 | NE-232 | 發行工具、真章節 readiness、產物清單/校驗、相關測試 | 待 A 完成連線核對後另建；尚未開始，不製造三份相同占位包 |

主 session 保留 ST-3/9 原子故事結果與世界存檔、第一章生成器、ST-10 構圖、ST-19 第二章候選與正式接線、本機 ComfyUI 及實體 GPU 驗收。另一台電腦保留 NE-222/221/218/79/80/81/90/224/242，以及 CharacterRig/HumanoidAnimator/RigInput/PlayerVisual；所有雲端任務都不得搶寫。

BG-26 海報補驗已由主 session 在 `5629471431e34f0f4e69bfa94ecd70335762b4db` 完成交付，與 BG-25 水流範圍不同。

## 各 session 的交付規則

先 fetch 最新 origin/main，讀完整 AGENTS.md、pm-ticket 與適用技能，用自己的 feature branch。作者及提交者皆 Stanley Li，email `stanley890314@gmail.com`。新票先按最新遠端的該專案最大編號加一，開完立即 commit 並 push，避免撞號。

每票受影響的局部測試全過（腳本錯誤也算失敗）後，保存真正遊戲截圖到 `pm/Nest-Egg/images/`，票上追加 Commit 與實際證據、逐項勾驗收；全部達成才改完成。框架或候選階段保留進行中。不可為過關而改測試選擇器、runner 或已知失敗清單；完整測試由 CI 處理。

每票分別 commit 並立即推送。推前 fetch/rebase 到最新 main，處理衝突及必要局部複驗；以 `git push origin HEAD:main` 快轉合入，不能 force main。確認本機 main/origin/main 同 SHA，僅移除自己的已合併工作分支。提交訊息沒有 AI/model 名稱或任何 co-author/session 署名。

軟 Vulkan 原生 Forward+ 證據不能當作實體 GPU、VRAM、HDR 峰值或人工手把驗收。ComfyUI 與大型生成模型留本機指定 owner，雲端保持少量必要素材與測試，不重複堆積全專案產物。
