# 序章→第一章真實可玩閉環：CPU 審查

審查範圍是 `C:/Users/stanl/.codex/worktrees/chapter-one-runtime/Nest-Egg` 當下正式來源，非 UI worktree。僅讀取；未啟動 Godot，未改 repo／作者來源／旗標／PM／Git。89 份來源的 byte 與 LF SHA-256 在 `freeze-manifest.json`，正式 115 場景、11 任務及選項／入口摘要在 `formal-scene-index.json`。不要把這個報告或 arranged Ali probe 當完整玩家通關證據。已排除 Root 正在修的 clinic cold 與 cancel。

目前可靜態追到：新遊戲當舖 → 廚房 dinner 觸發 → 屋頂真鷺 NPC → 前門 → 街道／可選電話亭巷 → 倉庫看門狗／水閘 → vault 真盤 pickup → 上層回程 → 館外真交接櫃三次選擇 → 館內真 Ali → 宵夜選擇 → 回家電影 → 結算。來源已補交盤、回執、摘要、點餐／只坐、付清／欠條／招待／無單離開等契約；票上舊「正式任務 0」不是目前事實。

## 阻斷通關／發行閉環（2 項）

### 1. P1 整體閉環缺口：序章正式入口和六項實作教學皆未接入

重現入口：主選單「開始」 → `Main._on_start_requested` → `res://data/levels/ch1_pawnshop.tres`。Main 第一關仍固定當舖（`game/main.gd:6,147`）。正式當舖沒有 intro_scene；`tools/level/ch1_production_bindings.py:81` 主動清空開場，`tools/story/build_ch1_story.py:548–552` 移除 `ch1_c01_open`，註明等待 ST-16 P06，卻沒有正式 P01–P06 場景或序章區域。當舖 `hints`（`data/levels/ch1_pawnshop.tres:82`；生成器 `tools/level/build_ch1.py:422–448`）是走近顯示，沒有六操作依次各做一次的進度門。

影響：角色與世界介紹、住宅存款動機、完整／長按略過、復原練習和序章存續都無實際入口。這是 ST-16／序章至第一章發行阻擋，不等同斷言現有第一章本身一定無法完成。ST-16 驗收 `pm/ST/[ST-16]加入序章補上遊戲開頭.md:19–32`；設計 `design/13-story-v2/PROLOGUE.md:8–27`。

窄處理方向：由序章 owner 提供正式 start／safe P06 handoff，維持首次真死亡服務的唯一真相，再以新遊戲完整與略過兩條路實測；不要恢復舊試槍電影或給假的序章完成旗標。

### 2. P1 跨章閉環缺口：章末 Continue 回結算，沒有下一章入口；終端畫面也沒有版本界線

正式入口：麵攤 `stall_home` → `ch1_pawnshop_dawn` intro `ch1_c14_home`（`data/levels/ch1_stall.tres:12–18`；`ch1_pawnshop_dawn.tres:82–84`）。該關 complete_after_intro=true，next_level 沒指定；`Level._begin_intro:323–326` 走 `_run_ending`，Main `game/main.gd:298–313` 保存 chapter_complete 後到 Victory。Continue `main.gd:177–183` 見 chapter_complete 又到 Victory。

`ch1_next_morning` 正式任務存在，但 `next_morning` 是 chapter_handoff／location=null（`data/story/ch1_kasa.json:9265–9271,9843–9874`），沒有 S01 的真地圖入口／互動者。第二章舊 Demo 不可當新版「鷺」。這是下一章銜接未實作，非第一章內門條件循環。

獨立第一章包可合理在此結束，但 closure 文稿要求明確「第二章尚未包含、第一章進度已保存」（`design/13-story-v2/CH01_CLOSURE_SCRIPT.md:229,297`）。目前 Victory 只有「下一章 鷺」及再玩／主選單（`ui/victory_screen.gd:38–61`），不顯示任務中的版本說明；玩家看不到未提供章節的原因。完整版需要真 S01，階段包至少在正式終端畫面清楚標示已保存與版本範圍，不能接舊 level_02 或先發720。

## 劇情連續性（2 項）

### 3. P2 真機關已完成，主線仍指向第一個未接生產者的路障

任務 `ch1_take_disk` 前三步讀 `ch1_street_route_open`、`watchdog_defeated`、`ch1_flood_gate_open`（`tools/story/ch1_closure.py:718–721`；正式 JSON `9560–9613`），三值預設 false（JSON `9024–9026`）。目前 runtime `.gd` 中沒有這三值的寫入或可信投影。遭遇清除只有 `EventBus.mechanism_toggled.emit(channel,false)`（`game/props/encounter_zone.gd:136–138`），看門狗隔牆／水閘使用真 channel 開門（`game/props/gate.gd:66–76`、`game/props/flood_pit.gd:106–112`），不產生上述任務旗標。

可重現的正常路線：聽完鷺 → 清完 `arena_street_blockade` → 打倒看門狗開 `watchdog_gate` → 踩踏板開 `flood_c`。`QuestCatalog.current_step` 取第一個未完成步驟（`core/navigation/quest_catalog.gd:333–339`），因此取得資料盤前仍導回街道路障；取盤後頂層 complete=ledger_disk_obtained 會把整項任務完成，掩蓋三個始終 false 的步驟。這是指引錯誤，不是已證實通路阻塞。

窄處理：從實際持久 encounter／gate／flood 狀態投影到同一任務真相，或由唯一機關 owner 在真正完成事件原子保存相應值；不要 radio／到達座標／看場景代寫。NE-223 的可達完成旗標、HUD 與讀檔驗收目前不能勾。

### 4. P2 聲線支線有台詞和任務，真電話亭沒有啟動這條支線的入口

正式物件：`ch1_booth_alley` C `[26,19]`，binding `voice` 在 `[25,19]`；scene `ch1_dispatch_voice`／`ch1_t_lamp_voice_prompt` → first → second prompt。作者要求 `ch1_recording_heard`（`ch1_closure.py:666–684,737–739`）。正式 binding 明寫 source_handler_pending=true（`data/story/ch1_kasa.json:9250–9263`；生成器 `ch1_production_backend.py:120`）。

正常互動 `Checkpoint.start_call` → `_tick_call` 在 T_VOICE 只播 phone_voice、吐標語（`game/level/checkpoint.gd:162–165`），完成只補彈與 set_checkpoint（`:181–192`）。沒有 recording completion 事實寫入；也沒有在 checkpoint 建立 NPC/entry Source 或顯示 voice optional_topics 的合法入口。`NpcActor` 話題框架能讀 NPC dispatcher 的 optional_interactions，但這個 Checkpoint 不走 NpcActor。即使舊檔手動旗標為 true，仍不能拿它當真電話亭入口證明。

影響：無死玩家可以備份，卻無法按設計在安全亭追問燈；SQ5 不可由正常路線完成。修真正錄音完成 owner 與互動授權／選項入口，不強迫多死、不呼叫 Story.play 冒充 NPC。clinic cold/cancel 不在此項範圍。

## 表現改善（3 項）

### 5. P2 作者動作需求尚未進正式可播放步驟，F09 壺／爐結果尤其缺失

正式 `ch1_c14_home`（JSON `3946–4134`）只有背景、actor move／face、say、switch SFX、fade／title；結果只有 home_done／complete。沒有移動壺、關爐、裝水或保存其狀態。廚房 stage 為單張 kitchen.webp 背景（`data/cutscene/stages/ch1_pawnshop_kitchen.json:17–27`），没有可獨立操作的爐／壺層。作者 `ch1_closure.py:623` 明記「此prop結果待舞臺/world owner」；製作稿 `CH01_CLOSURE_SCRIPT.md:223–229` 要凜真關火、老 K裝水、結束同狀態。不能把播放 switch 音效算成完成物件演出。

同類差距在交盤插槽／出紙與麵攤坐下吃麵：作者 staging 在 `ch1_closure.py:348,358,549–550,565`，translator `ch1_production_backend.py:170–180` 只複製 steps，不編譯 staging；一般 dialogue 段只有 say／wait。實際物品和交易原子結果已存在，此處指出 ST-9／ST-10 的演出交付缺口，不撤回合法交盤／付帳契約。

先讓 stage/world owner 提供必要真道具及支撐，再做原生畫面核對；本輪沒有判斷圖片上的人物比例／接縫是否合格。

### 6. P2 章末同一張卡連播兩次後再出結算标题

正常入口同第2項。`ch1_c14_home` 最後已播放 title「第一章 傘 完」2.5s（作者 `ch1_closure.py:618–619`；JSON `4127–4133`）。隨後 `_run_ending` 又讀 chapter.end_title 並顯示另一張2.8s卡（`game/level/level.gd:1119–1123`）；Victory 再把 end_title 顯示為面板標題（`ui/victory_screen.gd:38–40`）。重複的是前兩段全屏卡，結算標題本身可保留。

窄處理：明確指定章末卡唯一 owner，保留完成／儲存及次晨提示；以真回家路線與 Continue 驗證不重播，勿減弱 existing once/result assertions。

### 7. P3 玩家提示暴露製作語言，後半段「明早對錢／把紙記好」重複可收斂

確定正式 UI 文案：`stall_home` prompt「回家後播放劇情。」（`data/levels/ch1_stall.tres:17`；authority `tools/level/build_ch1.py:92`）。提示應說人物目的，如「回當舖」，電影預告由既有 cinematic_preview_scene 處理。其他提示「阿梨…說完才出得去／說完才能回家」（生成器 `build_ch1.py:811,833`）偏機制說明；應指明尚未處理的去留或帳，依真缺條件給原因。

編輯建議（不是通關故障）：正常必經 `ch1_t_egret_1`、`ch1_g10_disk_return`、`ch1_t_handoff_receipt`、`ch1_t_handoff_summary`、`ch1_c14_home` 都重述次晨算錢／收紙（authority `ch1_closure.py:313–331,353–377,606–618`）。首次簡報及單據可清楚說一次；後段用紙濕、碗的位置、等人等具體動作承接，讓凜、鷺、燈、老 K分別說自己的需要，減少角色都在解釋提交與記錄。保留必要金額／債務辨識與選項結果，不刪讀檔／回訪必要提醒。steps 與 lines 在 JSON 中的同句複本並非播放兩遍，未把它們計入重複量。

## 已排除的誤報與剩餘驗收

- 鷺 Sunday 可由真 NPC main dispatcher進 `ch1_t_egret_sunday_prompt`，不是缺少 optional_topics 就不可達；四張獨立標籤的 OBJECT dispatcher已有真地圖字形與唯一資源。Ali 點餐A→姓名B、只坐、宵夜離開／留下都已有合法資料路由；不要求先知道地址才回家。餐酒200是明確訂單後的帳，order不扣wallet；沒有章末提前720的結果。
- `ch1_g10_disk_unclaimed` 目前沒有 inbound trigger，且依賴第3項未接的 flood flag；可作導航補句但不應拿它當真盤 pickup 證據。真盘槽是 `ch1_data_disk@40,16`。
- multilingual 尚非每句三欄（ST-2），屬明確未交付能力；此報告未用語言缺欄斷言中文版不可通關。
- 未跑引擎。仍需新遊戲完整／略過序章、正式 Input 通路、每個機關死亡保存、交盤各提交邊界、Ali／宵夜全合法分支、實際退出新process Continue、兩種難度以上及手把、場景比例／支撐／遮擋／時間量測。已安排的 Ali probe只證明其局部真NPC及存檔契約，不證明玩家从開始走到那裡。
- 第2項的次晨「當舖結算，再上屋頂談附件」在 SCRIPT_CH02 中有不同事件，未把兩個位置誤報為矛盾。沒有把未出生的紙盤、未播放錄音、訓練死亡或作者 readiness descriptor當真事實。

來源檢查可重現：以 `freeze-manifest.json`核對每個path的LF SHA，再搜尋 `ch1_street_route_open|watchdog_defeated|ch1_flood_gate_open|ch1_recording_heard`於 `game/core/autoload/**/*.gd`。目前前四值無runtime生產者；scene索引只讀目前正式JSON、不 import generator、不呼叫生成器 main。
