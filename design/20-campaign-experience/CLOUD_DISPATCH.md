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

後續核對：官方狀態 revision 由 2 變為 5，再變為 7，回報 `running / connected`，網路政策就緒仍為 `unknown`。早先狀態變化後僅重試一次 fetch，仍 exit 128、相同 proxy 8080 錯誤；最新核對未再發網路命令。代理 TCP 檢查回報 `Operation not permitted`。原始 log 位於該雲端環境 `/workspace/Nest-Egg/work/bg25-network/fetch-origin-main.log`；舊 session 已停止 source 工作、保留環境，沒有任何 source 交付。這不能推論整個平台 Proxy 故障；`connected` 也不等於網路政策或 shell 權限已就緒。

## 權限比對與恢復

使用者手動建立的「盤點目前可見內容」（`01a12411-12a5-761f-a328-15abf29e409d`）在同一專案路徑及 remote，普通 `git ls-remote origin HEAD` exit 0、代理 TCP 8080 connected、GitHub HTTP 200；官方政策為 `unrestricted / enforced`。工作頁權限實際為 **Full access**。沒有向這個使用者 session 傳送任務或修改設定。

新建立的「雲端 A2：Nest-Egg 預檢與場景動態」（`01a12420-974e-73e7-8853-5ff215a3d0a7`）明確選擇 Cloud → Nest-Egg，使用與舊 A 相同的已發佈 config/version。確認 repo、remote、Godot 4.7.2，官方 `observations_current=true`、`running / connected`、`unrestricted / enforced`；但普通 sandbox 的 `ls-remote` 與 `fetch` 仍各 exit 128、連不上 proxy 8080。工作頁權限與舊 A 均為 **Approve for me**。

[官方 Permissions](https://learn.chatgpt.com/docs/permission-modes) 與 [Auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review) 說明：Approve for me 保留 workspace-write sandbox，改的是額外操作的審查者，不會自動開放網路。Full access 移除相應 sandbox 邊界。因此環境政策與實際 shell 執行權限必須分別核對，不能因為選到正確環境或政策 enforced 就當成普通 Git 已可連線。

在 A2 的既有正式單次命令審查通道，僅對該 repo 的 `git ls-remote origin HEAD` 與 `git fetch origin main` 提出正常 escalation 後，兩個命令均 exit 0。工具接受並執行，未回報拒絕；沒有另提供審查裁決內容，不能虛構 reviewer 的判斷。實際遠端及 fetch 後 `origin/main` 都為 `252d09e9853b1310be127bc37f9a03ea3a8436a3`，工作目錄乾淨。這支持 sandbox 執行權限是造成前後差異的關鍵；沒有證據斷定舊 A 的 unknown 狀態具有相同唯一根因。

未修改任何 session/global Full access、proxy、CA、network policy 或憑證。之後已授權的必要 Git 網路操作，沿用現有正式命令審查通道；工具不支援、權限政策不允許或審查拒絕時停止並保留錯誤，不繞過。新 session 派工門檻是正確 repo/引擎、當前官方政策，以及實際 Git 成功，不能只看狀態燈。

BG-25 的唯一雲端 owner 已轉交 A2；舊 A 已收到停止 source/Git mutation、保留診斷 log 的移交。A2 已收到完整票務、範圍、局部測試、截圖與逐票快轉推 main 的實作指令。連線恢復不是 BG-25 完成交付。

## B/C 平行派工預檢

2026-10-10 另建兩個獨立工作頁，送出前各自確認 `Cloud` → `Nest-Egg`，預檢完成後才送出正式實作任務。兩邊均沿既有正式單次命令審查通道，未調整持久權限或代理設定。

| 項目 | 雲端 B：武器與近戰連段 | 雲端 C：累積章節打包 |
|---|---|---|
| session / host | `01a12433-dc1b-73b7-9b03-7d75f9d78091` / `durable` | `01a12435-097e-7623-bbbb-df838dc7c0bc` / `durable` |
| 實際 hostname | `95f13671d68f` | `415f826d087f` |
| repo / remote | `/workspace/Nest-Egg` / `https://github.com/deadline314/Nest-Egg.git` | 同左，獨立環境與工作樹 |
| OS / Godot | Debian 13.6 / `4.7.2.stable.official.ed1daf0bf` | 同左 |
| 官方當前狀態 | `observations_current=true`、`running / connected`、`unrestricted / enforced` | 同左 |
| CPU / RAM 上限 | `cpu.max=400000 100000`（4 核）/ `memory.max=17179869184`（16 GiB） | 同左 |
| 預檢時磁碟可用 bytes | `32034643968` | `32032587776` |
| `git ls-remote origin HEAD` | exit 0 | exit 0 |
| `git fetch origin main` | exit 0 | exit 0 |
| fetch 後 `origin/main` / `FETCH_HEAD` | `b4c186ea401dfb29b92e28a0a9c8e7de46f604e3` | 同左 |

兩邊預檢時 source 工作樹乾淨，但環境快照的 HEAD 為 `7e05a6e78623e620482caa527d480cbc52b13a0c`，落後當時 main 32 個 commit；正式任務要求從重新 fetch 的最新 main 建 feature branch。以上 SHA 是預檢時觀測值，不是未來推送可沿用的固定基線。

B 已正式收到 NE-236、NE-237 與 NE-231 近戰成長範圍；C 已正式收到 NE-232 下一階段管線。兩邊正式實作採 GPT-6.1 Sol High，先核對現有資料與介面、列出檔案 ownership 再開始。NE-237 的存檔依賴與 NE-232 的真章節 readiness 尚未全部交付，不因環境連線或管線測試通過便勾完成。

## 分工

| 工作 | 票 | 範圍 | 實際派工狀態 |
|---|---|---|---|
| 雲端 A2：場景動態 | BG-25 | PropData/PropNode、局部動畫元件/shader、相關道具資料與測試；先做水管水流 | 已驗證正式單次 Git 命令通道並取得 main，已正式派工；尚未完成票 |
| 雲端 B：武器差異與連段 | NE-236、NE-237；NE-231 僅近戰部分 | MeleeSet/連段處理、Player 近戰與相應成長、測試；不碰角色基礎 rig、shared Fx 或故事存檔 | 獨立環境、引擎及兩個 Git 命令通過，已正式派工 |
| 雲端 C：累積章節打包 | NE-232 | 發行工具、真章節 readiness、產物清單/校驗、相關測試；不碰 Main/Story 或存檔 | 獨立環境、引擎及兩個 Git 命令通過，已正式派工；正式章節完成前不製造占位包 |

主 session 保留 ST-3/9 原子故事結果與世界存檔、第一章生成器、ST-10 構圖、ST-19 第二章候選與正式接線、本機 ComfyUI 及實體 GPU 驗收。另一台電腦保留 NE-222/221/218/79/80/81/90/224/242，以及 CharacterRig/HumanoidAnimator/RigInput/PlayerVisual；所有雲端任務都不得搶寫。

BG-26 海報補驗已由主 session 在 `5629471431e34f0f4e69bfa94ecd70335762b4db` 完成交付，與 BG-25 水流範圍不同。

## 各 session 的交付規則

先 fetch 最新 origin/main，讀完整 AGENTS.md、pm-ticket 與適用技能，用自己的 feature branch。作者及提交者皆 Stanley Li，email `stanley890314@gmail.com`。新票先按最新遠端的該專案最大編號加一，開完立即 commit 並 push，避免撞號。

每票受影響的局部測試全過（腳本錯誤也算失敗）後，保存真正遊戲截圖到 `pm/Nest-Egg/images/`，票上追加 Commit 與實際證據、逐項勾驗收；全部達成才改完成。框架或候選階段保留進行中。不可為過關而改測試選擇器、runner 或已知失敗清單；完整測試由 CI 處理。

每票分別 commit 並立即推送。推前 fetch/rebase 到最新 main，處理衝突及必要局部複驗；以 `git push origin HEAD:main` 快轉合入，不能 force main。確認本機 main/origin/main 同 SHA，僅移除自己的已合併工作分支。提交訊息沒有 AI/model 名稱或任何 co-author/session 署名。

軟 Vulkan 原生 Forward+ 證據不能當作實體 GPU、VRAM、HDR 峰值或人工手把驗收。ComfyUI 與大型生成模型留本機指定 owner，雲端保持少量必要素材與測試，不重複堆積全專案產物。
