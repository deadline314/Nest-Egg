# 第一章正式來源接線清單

2026-10-10；來源 owner 工作樹 `codex/ch1-formal-story`，作者初版基線 `53664537`，根代理目前已同步整合基線 `c744a44f2d7b87a345a0a883cae3f1df0efe8f51`。本輪以已放行的 [CH01_CLOSURE_SCRIPT.md](../13-story-v2/CH01_CLOSURE_SCRIPT.md) 為最高製作稿。這是來源實作與串行移交清單。資料已接受局部引擎測試；新稿沒有正式 JSON、可達或退出讀檔驗收通過的宣稱，完整紀錄見下方。

唯讀主checkout的已合main `90e5997f` [PROLOGUE_SCRIPT.md](../13-story-v2/PROLOGUE_SCRIPT.md)及`PROLOGUE_REVIEW.json`：正式順序是P06安全出口→這次免費晚飯→屋頂真簡報。來源ENTRY_CONTRACT保留此順序，未虛構序章完成flag或新runtime ID；序章執行期尚未接。合成base排除舊`ch1_c01_open`的重複試槍／世界說明；27,400只歷史紙本存款，不能補進可花現金。

## 已讀接口與所有權

已完整讀基線 `autoload/story.gd`、`game/npc/npc_actor.gd`、`data/scripts/npc_data.gd`／`npc_talk.gd`、`autoload/story_items.gd`、`data/scripts/story_item_data.gd`、`core/navigation/quest_catalog.gd`、`core/story_rules.gd`、`game/cutscene/cutscene_player.gd`、`core/continuity_audit.gd`，並核對 `CutsceneChecker`、既有生成器、實盤拾取／機關頻道入口。

作者初版唯讀 ST-22 的凍結接口：`Story.play_and_wait(id, once, context) -> bool` 使用 request handle；`NpcActor._present_talk` 只在 `completed` 時累計並發獎；`presentation_cancelled` 與 Main 的入口 snapshot 提供未完成段恢復。根代理同步 `3c053d31` 後這些接點已在本工作樹可用，不重新實作其已交付修正。ST-22 保留舊 skip/default 代選語義，新的明確選擇仍需下一個串行 owner 接線。

已完整核對 NE-231 `StoryTransactionData`、`StoryTransactionLedger`、Progression 三個故事事務 API 與七筆資源；它們已在 `d68ddb79a` 合入本工作樹。來源只登記 canonical 資源引用，不複製金額、錢包、收據或帳本實作。已刪除的交易工作樹不是執行期依賴。

本 owner 可寫：本清單、`tools/story/build_ch1_story.py`、`tools/story/ch1_closure.py`、新增回執／摘要／餐酒帳／欠條資源、接口真的到位後生成 `data/story/ch1_kasa.json`。本輪不寫 ST-22 的 Story/Main/Level/Npc/CutscenePlayer/HUD/Portal/level_generator，不寫 NE-231 的交易／Progression 服務，不寫 PM、角色美術或骨架。

## 最小正式契約

來源 helper 保留完整台詞、原有合法演出步驟、場景前置、互動綁定、段尾結果與 producer 索引。**作者來源規格不是已支援的 runtime JSON**：新增契約由正式 backend 明確轉譯，未綁定條件、交易、物件或選擇能力時，正式 export 必須列精確缺口並拒絕寫檔；不得靠未知 handler 被略過後仍完成。每個段落的不可逆結果只在本段成功完成後，同一份整輪快照保存；前段已完成保持，當前段未完成只撤回自身入口。

| 接點／下一 owner | 精確需要與禁止的捷徑 |
|---|---|
| Story `play`／`_enqueue_request`，StoryRules／NpcData 條件 | 開始前與完成前驗證旗標、實物、帳目狀態與選擇值。單個 `requires_flag` 不能把 `ch1_supper_choice="leave"/"stay"` 當等值判斷；來源先保留 `all/any/not/flag-equals/item` 條件，backend 不支援就拒絕輸出。普通復原經歷讀實際服務事件，不由 death_count≥2 猜在亭醒過 |
| CutscenePlayer `skip`／`_do_choice`、Story `_start_cinematic`／`apply_default_choices` | 本稿交盤、點餐、去留、付帳、欠條、接受招待、拿灰布均需明確確認。取消可返回且不完成；auto-skip/設定skip只能略資訊，停在未決選項。保留舊場景 default 規則，新明確場景另標政策。購買選項不得以 `set_flags` 當交易成功。route旗標初始unset，缺值只投影為unset；不得每次回訪重置已選route |
| ST-22完成入口 → NE-231交易服務 | 完成先執行具ID、可拒絕、冪等的正式事務，成功才 `scene_finished`／完成旗標／物品／下一段／導航保存；不足200回有完整臺詞的支付選擇。未知交易拒絕本段。訂單 `none→open200`、離開 `open→paid/owed`、留下 `open→gifted`互斥。欠條200不與720/40/私帳相抵；本章不發720 |
| StoryItems acquire／snapshot／restore（待串行 ownership） | 實盤拾取既有 `StoryItems.acquire`；取得歷史與目前持有分開。收盤須正式 remove/transfer，現服務只有 acquire，不能用 delivered旗標掩蓋盤仍持有；收盤成功且回執存在後不得保險箱再生。回執／摘要／餐帳／欠條全部 MANUAL，交易與完成端明確發放，不綁 scene_finished 自動發假物。灰布的item_acquire明列source_binding=first_clinic，必須真托盤尚有布、持有與world空側同存；舞臺回放不算真物件 |
| Level `_spawn` pickup／`_on_channel_toggled`、真互動物件與門（待owner） | 盤只真保險箱格 `[40,16]` 拾取生產；看門狗、清路、水閘讀持久機關事件。來源不把進vault或聽radio當拾取／開閘。交接櫃 `[8,19]` 仍是室內候選：補館外入口與櫃實體後才能接受它的 binding。四標籤要四個真正不同互動物件，讀完成各seen，不累加同一物四次 |
| QuestCatalog／ContinuityAudit（待串行ownership） | 現catalog僅完成flag＋真level/cell；title≤16、step title≤28。來源保留11語義，export只可發布producer與真互動binding已驗證的任務。灰布是診間stage-only，**無真地圖location**；次晨二章未有正式location；兩者保留語義與完整腳本但不能塞亭格或一章dawn當假目的地。需允許「無地圖標的當前場內互動／章末待下章」目標類型，或待實地接好再發布。新增條件／結果／選項／紙物producer要被掃描，不能只掃最外層set_flags |

### 唯一帳務引用與失敗處理

| Canonical ID | 正式資源（均在data/story_transactions） | 本稿呼叫 |
|---|---|---|
| `ch1.daily_dinner` | `ch1_daily_dinner.tres` | `ch1_b_dinner_food`段尾，免收、真0收據與吃飯flag同存；目前只是待接契約，既有flag不能冒充收據 |
| `ch1.revival_meal.order` | `ch1_revival_meal_order.tres` | 明確點餐完成才建立，未點不生成 |
| `ch1.revival_meal.paid` | `ch1_revival_meal_paid.tres` | 離開路明確付200；只有insufficient_credits進缺錢完整選擇 |
| `ch1.revival_meal.tab` | `ch1_revival_meal_tab.tres` | 明確保留200欠條，與其他帳分開 |
| `ch1.revival_meal.gift` | `ch1_revival_meal_gift.tres` | 留下路明確接受阿梨今晚招待，無退現金 |
| `ch1.revival_meal.later_pay` | `ch1_revival_meal_later_pay.tres` | 登記供後續主動付欠條，本章不呼叫 |
| `ch1.commission.settled` | `ch1_commission_settled.tres` | 只有二章次晨呼叫一次；`ch2_previous_job_settled`來自其recorded收據，本章不付720 |

接線以 `Progression.story_transaction_status(StoryTransactionData)` 做唯讀預檢、`story_receipt_status(id)` 查正式證據。單筆 `apply_story_transaction` 會立即發送錢包及交易事件，不能先呼叫它再逐步改道具、世界或完成旗標，否則訂閱者可看到半完成段落。整段結果 owner 必須先在獨立草稿驗入口條件、全部動作與結果，不碰 live services；所有 owner 先準備好可直接安裝的完整狀態；依整輪真實狀態組成候選存檔，成功提交到磁碟後才靜默安裝，接著發布事件。提交前任何失敗均保留原狀態，不能先發交易事件；保留 guard 至事件發布與其後新鮮狀態的必要保存完成。回呼中的合法普通消費不能被舊候選覆蓋。完整提交順序見 [整段安裝方案](STORY_ATOMIC_INSTALL_PLAN.md)。不可在 order／paid 已改變草稿帳目後重新用原 open／none 入口條件否決自己。任何未知、busy、ledger_locked、definition_changed或其他拒絕不給完成旗標／紙物／出口；保留原始進度，顯示服務的一句提示並允許返回。收據與world／item／旗標整轮snapshot由Main串行owner保存；不能只存flag而遺漏NE-231帳本。

`account(none/open200/paid200/owed200/gifted200)`及ordered/tab-settled均為 canonical receipt 的唯讀投影，來源 `ACCOUNT_RECEIPTS` 只說明查詢規則，不存另一份帳。只取五筆餐帳收據子集，合法集合精確為none{}／open{order}／paid{order,paid}或{order,tab,later_pay}／owed{order,tab}／gifted{order,gift}；其他組合一律拒絕，不能依first-match或缺單洗成none。daily_dinner與commission收據不影響此子集；untrusted或目前定義指紋不符先拒絕。晚飯40舊氣泡由免收段覆寫，沒有新債、退款、存款補錢或未來收40承諾。

## 段落、唯一生產者與續段

| 文稿 | 正式來源段／生產者 | 入口與結果 |
|---|---|---|
| 晚飯、F01 | `ch1_b_dinner`→`ch1_b_dinner_food`、`ch1_t_egret_1` | 免收晚飯；food段的真0收據與dinner同存，完整簡報才brief完成，不給現金 |
| F02 | 真 `ch1_data_disk` pickup；`ch1_g10_disk`僅取後radio | 拾取事件同存world空槽與held/history；radio不給盤、不給券或錢 |
| F03 | `ch1_t_handoff_accept`、`ch1_t_handoff_receipt`、`ch1_t_handoff_summary` | 三個不同完成場景；收盤→取紙→存摘要，任一中斷不撤回前段；回訪精確指下一段；與二章S00共用同實體交付事實 |
| F04 | 阿梨首見 clinic-only／booth／no-death／unknown 四變體；點餐或只坐的獨立确认 | 實際服務事實選問候；兩百公開且明確點才成立。未點none，不能有付款200UI |
| F05–F07 | 甜湯／只坐，下班；明確去留；paid／owed／no-order 三種告別 | 接待與晚間完成分開，route意圖不開門。現金不足有欠條／留下／返回，完成結果才supper_done |
| F08 | host、meal、address 三個完成場景 | 招待無現金增減；接受麵→吃麵→夜話實際說出地址，拍7段尾保存地址與SQ。未知地址不靠場景ID猜真 |
| F09 | `ch1_c14_home` | 爐關、壺有水未沸、老K忘記已回來；同章末結果，不給720、不跳舊level02 |
| O01–O04 | Sunday；四label；voice heard→問一次→問二次；真灰布交互 | 每項可選、可返回，無本章新增現金/XP；灰布在真初次建檔舞臺交互前不發布假地圖目標，不要求重覆死亡 |

初次死亡流程在真正`ch1_c09_wake`完成後、離診間與返回存檔前，需綁O04托盤選單及可選登記追問；回放不進此真物件選單。`ch1_recording_heard`只由真錄音播放完成生產，不能因建檔wake段存在就假設已聽亭錄音。所有Npc/物件續段按尚缺的已提交拍優先：order/sit已完成但name未完時續name；晚間談話完成後續close；host→meal→address分拍續接。來源各拍前置排除已完成或不符路線；不要用seen當完成。

## CPU交付與後續驗收

來源 helper 可先編譯／檢查：13段涵蓋、全11任務語義、每flag/item/交易producer可追跡、選項與revisit臺詞齊全、合法演出步驟與字數預算、無無條件主線實物發放、資源220字上限、任務短標題限制、未綁定位置保留none。CPU schema檢查不能替代引擎測試。

四份紙物由來源`render_document_resource`一致產生，category=KEY_ITEM、trigger=MANUAL、無自動發放或虛增探索總數；內文依序102／127／79／79字。完整正式來源目前81個presentation/decision段，16個明確選擇段。`build()`及預設CLI保持既有已發布36場與SCENES API，可依原規範重建；不默默套新稿。`build_production_source()`另回完整新稿，只有明確`--production`才嘗試新backend合成，該合成排除本稿覆寫的舊線性段與`ch1_c01_open`、`ch1_t_ali_2/3`。新稿沒有真backend時先拒絕，不觸碰JSON或舞臺；沒有capability強制開關或fixture位置。

本階段 `--check-closure-source` 只檢查並報告綁定缺口，不寫已載入JSON或舞臺；`--production`的新稿正式生成等 ST-22合入、NE-231 transaction API及串行最小接點接好才開。預設CLI仍重建舊已發布稿，這不代表新稿接線完成。屆時跑正式Story/Cutscene/Continuity/QuestMap與changed suites，再走M01–M35真退出讀檔及no-order/paid/owed/stay完整路。最後是真Forward+ HDR畫面、手把、物件接觸／音訊驗收；這份來源未替那些工作蓋章。

ST-10構圖尚待修：root在ST-22的`ST-22-16x9-home-movie.png`實際重現舊廚房SCALE=3.8/4.2與只限制feet的camera讓角色頭部超出上緣。本稿沿用的stage／scale／座標只是演出候選，不能算通過；ST-10須用`CharacterRig.visual_bounds`（`game/rig/character_rig.gd:238`）配合21:9可見區與對話safeRect同時驗頭、腳、家具與支撐接觸，不改NE-222等角色材質／rig。

### 本階段CPU驗證紀錄

使用Python 3.12、`-X utf8 -B`，無Godot。從`git show 53664537:tools/story/build_ch1_story.py`唯讀取得原產生器，與本版各自指向經確認的臨時OUT/STAGE_DIR；只唯讀主checkout現有麵攤PNG尺寸。預設兩版生成的36場完整JSON（結構、臺詞、旗標、death/respawn規則）及6份舞臺JSON完全一致，`build()`仍回None並填SCENES。臨時結果已清除，正式檔未寫。

新來源檢查exit=0、81段、16選擇段、6主線＋5支線；七筆canonical ID與NE-231資源一致，四份紙物與來源渲染完全一致。`--production`exit=2明確拒絕，`--check-closure-source`不寫檔；已載入JSON＋17份舞臺的18份內容SHA保持。七類不合法作者資料（未知handler、劇情送盤、假交易、缺producer、假收據、灰布無真托盤、選項直接送物）均被拒絕。五筆餐帳的32個子集只接受6個合法集合，26個拒絕；加入daily/commission不改判定。這是作者規則CPU驗證，沒有測試或取代runtime錢包、帳本、存檔。

最高稿SHA256=`7eb5272fea09329fa42c23d97163514834a5f0e28931b721d98b7397b7acdd0c`；未生成的正式`ch1_kasa.json`SHA256=`6d020b5940b96a08a318687bbd6ab0329576bae8a5b54666d22d929f7b2197b4`。作者初版未跑引擎；根代理局部驗證與完整重驗記錄如下。M01–M35尚無實際走查，任務語義尚未發布成正式quest資料；ST-22／NE-231／ST-16／ST-10接線與驗收維持前述界線。

獨立來源通讀補正：取灰布時不假定已持有交盤回執；聲音首問支援真亭與診間錄音；首次復原出口不假定已到倉庫。欠條結清只投影真later_pay收據，直接付款／招待不表示曾有欠條。以上沒有更動目前載入的36場舊稿。

### 根代理來源與引擎驗證（2026-10-10）

最早完整驗證在四份新增紙物缺圖示、探索總數斷言及市場摘要首句超限上失敗。紙物現在使用實際既有文件圖示；市場摘要分成完整句子、200／20／120及附件缺失的意義不變。局部 main／StoryLintSuite／StoryContentSuite 通過2486檢查，0新增失敗、0已知失敗；Godot自然退出0，無 SCRIPT ERROR／Parse Error／Compile Error。

a52e57ea基線原始 changed selector 依 smoke_test 修改選出全80組，54245檢查、1新增失敗「ducking recovers smoothly afterwards」，自然退出1。保留失敗原始輸出，不更改 selector、已知失敗或音效程式。原樣單獨重跑 FeelSuite 為644檢查／0失敗、自然退出0；不能因此宣稱整合全部通過。工作樹 rebase 至 d68ddb79a 後，匯入自然退出0且無腳本／匯入 ERROR；原 selector 選出的80組重驗54352項／0新失敗／0已知失敗，1190秒，自然退出0。隨後 rebase 至 c744a44f2，匯入自然退出0，全檔無 SCRIPT／Parse／Compile／ERROR；main、Collectibles、RunSave、StoryLint、StoryContent、Economy 六組接合3438項全過，105秒，自然退出0。兩輪測試 raw 保留原負向案例及引擎診斷，無 SCRIPT／Parse／Compile；未刪輸出或改過濾規則。80組結果對應 d68 基線，c744 接合結果另列，不混稱同一輪。

獨立CPU複核81段、16個明確選擇、6主線＋5支線；32個餐費子集接受6／拒絕26；四份紙物與來源渲染相同。預設36場JSON及6舞臺與原已發布生成結果相同，目前載入的18份JSON／舞臺SHA未變。production仍拒絕10項未提供能力，不把底層框架存在視為正式接線已完成。
