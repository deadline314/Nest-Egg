# 2026-10-11 本機 Session 收尾交接

使用者要求把本輪做到一半的工作保存、整理偏好和紀錄、清掉無用途檔案，然後停止開發。永久要求見 [user_guide.md](user_guide.md)。**序章至第一章尚未完整通關，也没有正式累積單檔可交付。**新 Session 先讀本文件、相關票和最新 origin/main，再決定接手哪一部分。

## 最新接手與清理補充（2026-10-11）

使用者後續授權：同步最新 main，移除其他 worktree 和舊分支，下一個 Session 繼續把序章至第一章做成完整可玩。本機已快轉至 `4198f1f9fc19f9bb7e19694b07ce96336ad3357d`，含另一台電腦的角色交接；接手仍先 fetch 最新 main。可直接貼上的[新 Session 指令](NEXT_SESSION_PROMPT.md)和[分支／未提交候選封存與恢復方式](attachments/worktree-retirement-2026-10-11/README.md)優先於下文歷史「保留 worktree／分支」敘述。精確刪除結果以封存 manifest 為準。

舊 `codex/chapter2-layout`、`codex/stage-framing`、`codex/world-ui-clarity` 的提交已在 main；前兩者另有未提交候選，已保存原始 bytes、patch 和來源 HEAD。第一章 `a5f2a1ba` 與武器 `41f326ab` 未完成驗收，不直接合入 main；其提交歷史與其他雲端候選均在 Git bundle，重新 fetch 後可恢復成新審查分支。移除舊分支不抹掉候選、不表示整章通過。原三個 stash 仍保留，另見封存 manifest。

主工作区兩張票的既有未提交打勾（BG-17 暗場量測、ST-1 使用者確認）另存 `primary-unaccepted-ticket-edits.zip`；本次沒有新增證據支持這兩個勾選，不將其混入正式票狀態。檔案原始 hash 與 patch 都在封包。

最新記憶體偏好：**可以多用一些 RAM**，避免不必要的固定門檻；監看系統剩餘實體量、commit／pagefile、程序峰值及 VRAM，依實際占用控制模型和批次，避免耗盡、關機或重啟。不同電腦的 GPU／記憶體數字不能混用。

## 已交付與仍在分支的界線

| 範圍 | 精確狀態 |
|---|---|
| NE-247 真姿勢衝刺殘影 | 已完成並合入 main。以實際衣物／姿態／武器輪廓作低透明深灰短殘影、有界池與保存選項；不改衝刺判定。票內有原局部、本機原生及雲端測試證據。 |
| BG-31 貼圖載入／選單生命周期 | 本輪窄修補已推 main `1ade0c7fc3ed4545e737d07a611a2a838941088d`；原七套件2576/0、新局106/0與獨立程序冷讀96/0。票保留進行中。收尾提交結果見票的最新 Commit 段落。不能把這段原生 route 當作全部 NPC／重要通訊回歸。 |
| ST-9 正式第一章 producer／存檔框架、NE-246 重要通訊 | 保存在 `origin/codex/chapter-one-producers`，HEAD `a5f2a1ba9eb64233b56108c3e930c68bffa52158`，148 檔 WIP，**不在 main**。沒有通過原 selector 的完整範圍，不可直接整包合併。 |
| ST-16 序章 | 有 C:/tmp 候選，尚未採用；正式入口尚未證明從序章一路到第一章。新的 P06 負責開場，不能把已移除的舊 c01 強塞回故事目錄掩蓋缺口。 |
| NE-228 背景 tooltip 蓋住通訊 | 真原生截圖已發現。最小 HUD 候選只完成 CPU／grammar，**未採用、未跑 Godot／native**；票保持進行中。 |
| 武器／連段雲端候選 | `origin/codex/cloud-weapon-phone-context-review`，HEAD `41f326ab09060ebff2b58907ac50122926b9f17d`，尚未本機採用或實體手把驗收。 |
| NE-232／233 發行 | 工具進行中／整章驗收待辦。readiness 不成立，禁止把 probe 匯出或工具成功稱為正式第一章單檔。 |

NE-225、NE-226、NE-227、NE-238、NE-245、BG-23、BG-24、BG-26 目前票標完成；不因本次交接宣稱全部環境與 UI 已完工。BG-27 持續噪點、BG-28 高低背景、BG-29 影子、BG-30 光影層級、NE-243／244 中性背包仍有待辦。ST-18／20 劇本完成不等於 ST-19／21 關卡落地。

## NE-246 已有證據，不能擴大解讀

在第一章私人 worktree `C:/Users/stanl/.codex/worktrees/chapter-one-runtime/Nest-Egg`，使用真 Main 新局、世界入口、Source、固定檔案寫入器，七種正常／保存拒絕重試／取消／記錄／新 OS 程序 Continue 路徑共 **528/0**；全部自然 exit0、原生 SCRIPT／Parse／Compile／ERROR0、來源零漂移。這是 a5f2 所屬來源，不是最新 main 或整章完整路線；工具安排進入倉庫，沒有替代宵夜／brief 的自然主線路徑。

補強的真射擊閱讀路徑：`C:/tmp/ne246-combat-native-4/`，PID32956，**97/0**、自然 exit0、raw0、來源零漂移。玩家真的扣彈並射出右向子彈，先有兩次飛行觀測；閱讀、開 Pause、返回閱讀各保留**同一子彈、7 敵人與 3.80650633333332 秒時鐘**。觀察的程序 private bytes 峰值 1,237,848,064；沒有 VRAM 測量。

![原生重要通訊；背景任務 tooltip 遮住講者，是待修缺陷](Nest-Egg/images/NE-246-handoff-reading-tooltip.png)

![通訊上開 Pause；世界保持凍結，背景 tooltip 仍遮住頂部](Nest-Egg/images/NE-246-handoff-pause-tooltip.png)

圖只是已測來源與缺陷基準，不是 HUD 修復後畫面。完整原始 log、來源／PID／slot 摘要及未採用候選的保存位置見 [收尾證據索引](attachments/session-close-2026-10-11/index.json)。舊 normal7 的 ALWAYS 祖先問題、initial-retry2／3 退出資源錯誤、combat1～3 前提錯誤均拒收，不能用其中的行為檢查數冒充通過。

冷續玩會重播已保存的**當前段落起點**，没有永久逐句游標或跨多鏈未讀佇列保證。安排倉庫的 probe 未走 dinner／brief，HUD 顯示宵夜目標不能單憑這張圖判成自然主線 bug；NE-223／233 仍須真全路線驗證。

## 雲端原始 ALL 的紅色結果

`a5f2a1ba9eb64233b56108c3e930c68bffa52158` 的原始選擇器選 **ALL83 組**，自然 EOF **86,162 checks／126 new failures／0 known／exit1**。未改 selector、known failures 或 assertions。原始報告已從雲端 evidence HEAD `16d448d8ed10ae90ba1514c8aaeb942b218ebd2c` 精確保存到 [失敗索引](Nest-Egg/attachments/NE-246-story-cloud-evidence/cloud/failures.csv)及[原始報告](Nest-Egg/attachments/NE-246-story-cloud-evidence/cloud/README.md)。雲端初步分類87條故事／舊契約、39條產品行為，下游因果仍逐項核對；當前候選不能宣稱修好全部126項。

已定位三個 SCRIPT：

1. ChapterCutscenes 引用已移除的 `ch1_c01_open`，取得空 Dictionary 後讀 `steps`。
2. Story 正式結果包含合法字串，旗標投影先比字串與 bool，造成型別錯誤；窄 guard 應先核 TYPE_BOOL。
3. Pacing 仍引用舊 `ch1_c01_open` 與 budget 契約，正式 compiler 已將 opening 交 ST-16 P06。

未完成遷移還有 Continuity 的 once dinner／bare death、Chapter1Map 的直接 formal flag／waiter false success／bare terminal walkthrough、Pacing 正式 dispatch 對話估計。歷史測試保留獨立 legacy fixture，新正式流程驗真 owner／receipt；不能回填舊 opening、直接授旗標或假造 producer。

## 已凍結候選與接手順序

精選候選已封存到本文件的 attachments；**解壓不代表可直接 apply**。每包保留原 bytes、來源 SHA、README 和未完成界線。

| 候選 | 前提與限制 |
|---|---|
| `story-contract-migration.zip` | 7檔未完成 WIP，freeze `da1981120159dfe450e98966253c018a318de47e3a5e8db0d5d761414e02509e`；CPU34/0、grammar0，無引擎證據，不可整包採用。 |
| `story-typed-flag-review.zip` | 初始更窄 typed flag／mixed-result／CombatHud catalog conservation 候選，freeze `a33ae04426a833a810bb592de01a23f6bd659dee7c121e0cac66c8e8768fe68d`；只供獨立審查，不能替代大範圍遷移。 |
| `st16-unapplied-source-bundle.zip` | 未採用序章、窄合成、revision3/4/5與精準 staged driver；全部舊前提，重新比對 actual Main 後才能使用。 |
| `hud-hover-modal-candidate.zip` | HUD＋獨立 helper，freeze `618f31b025c077c3a26e827bc05275318b7ed978abb3a9470491d96965252bb4`；CPU14/0、grammar0，29個 authored assertions 未執行。 |

需要接手時：先保護私人 Source／Snapshot／Port、對照 actual preimage → 分別完成 Story contract 遷移與 HUD tooltip → semantic import → 原相關 suites → 原 selector 選出的 ALL → 同源真 Main／活子彈／保存拒絕／冷續玩 Forward+ → 才分票交付。之後才做 ST-16 真序章與 NE-233 全路線；最後交 NE-232 雲端正式打包。這個 Session 不會自動執行上述下一步。

私人重要來源 raw SHA：

- `core/story_run_source.gd`：`cf1e279f486d0e9497150d9ff3639f651960db70b5ce4f4e307a21f9037b80e4`
- `core/run_snapshot.gd`：`78eaaed37e0f473a5ce0c864ce579ae5604ebc9bfe2806bfa998e421f00e469c`
- 正式保存 Port：`a10fa32095196f7f3e719587386482cac12b59b48525bb5e3e917e16e1365148`（實際路徑以來源 manifest 為準）。

這些只是接手前核對，不禁止合理新修補；任何新更動都要另列 exact diff 與相關證據，不弱化嚴格 Snapshot 或正式結果授權。

## 工程調查中有用的資訊

- Godot4.7.2 的 Window `get_mouse_position` 會讀 OS 游標。只注入 InputMouseMotion 没改 OS 位置，曾造成實際槍口往左；combat4 使用真 `Viewport.warp_mouse` 修正測試前提，没有修改產品瞄準或生成假子彈。
- HUD 繼承 pausable，不能只在 `_process` 檢查「剛暫停」；暫停後已停止 process。候選考慮 PAUSED／UNPAUSED 通知。
- Godot4.7.2 `mouse_behavior_recursive=DISABLED` 會退出 hover，但不保證取消已顯示或等待中的 tooltip。`Viewport::cancel_tooltip` 是 C++ 內部方法，沒有 GDScript 綁定；不能照 latest 文件猜存在的 API。候選只處理 HUD-owned 控制／TooltipPanel，需驗 pending timer、舊 popup、Pause／Radio 的輸入與恢復。
- BG-31 對照支持「CanvasTexture＋並发 texture creation」相關，沒有確定 RID owner 的 native stack。產品保留 Canvas 法線／HDR，用主執行緒分批載入；單一 load 不可搶占，2ms 是 soft 預算。快取估算128MiB不是整個程序 RAM／VRAM上限。
- 武器候選處理射擊拒絕前不扣彈／冷卻／發效果，以及已付費終段耗能與完整收招重新驗證；不改27個平衡數值。原雲端83447/0但 raw 有負測與退出 ERROR 的分類，不可寫成 raw ERROR0；Phone 初始紅色不冒稱已修。

## 分支、現場與清理

未合併的 `codex/chapter-one-producers` 和雲端武器候選保留，不刪、不 force main。私人 worktree 保留其他來源與原始 stash；Primary 的 BG-17、ST-1 是外部正在修改的檔案，不隨本次清理帶進提交。其他 Session 的 chapter2-layout、stage-framing 等未確認所有權的 worktree 不動。

本次只清本 Session 已確認無用且已存入證據封包的18個私人獨立診斷／UID／場景及47個重複歷史／生成檔案，並移除已合併的自有工作分支；不執行全域 git clean 或掃整個專案刪圖片。實際清理清單、提交與 main 同步結果放收尾索引。BG31-render-fix 舊保存位置已封存為 bg31-historical-evidence.zip，原 hash 與相對路徑留在封包；自動匯入 CSV 的 translation／import 不是證據，列為刪除。候選和失敗證據只存一次，避免在 runtime tools／正式包放多份大圖或臨時 probe。

`pm/.gdignore` 排除票據圖片和 raw CSV 的 Godot 資源匯入，避免再生無用翻譯／匯入 metadata；已搜尋正式來源，沒有從 pm 載入遊戲資源。65檔清理都在明确白名單内、逐檔驗hash、不刪外部工作。私人18個 untracked probe 移到封包後是新的完整來源 inventory，旧native仍僅屬原清單；接手重驗時先建立新manifest。

原派工 chat：**雲端 B：武器與近戰連段** `01a12433-dc1b-73b7-9b03-7d75f9d78091`；**雲端 C：累積章節打包** `01a12435-097e-7623-bbbb-df838dc7c0bc`。先核真 Nest-Egg 與 Git fetch 成功，不以 runtime connected 代替。收尾不新開 Session、不啟動更多模型／引擎／章節工作。
