# 故事結果批次規劃契約

2026-10-10。此階段只有 `StoryResultPlan.plan(results, snapshot, context)` 的有界、純資料預演，以及既有 EconomySuite 的回歸案例。尚未修改 Story、GameState、Progression、StoryItems、RunSnapshot、正式來源、JSON、任務、UI、關卡或保存接線；不能把它列成十項 production capabilities 的完成，也不能稱第一章已交付。

已讀 AGENTS、continuity-qa、chapter-design、pm-ticket 與既有服務。唯讀作者來源為 `C:/tmp/Nest-Egg-ch1-formal-story/tools/story/ch1_closure.py`、`CH1_PRODUCTION_INTEGRATION.md`；唯讀物品來源為 custody owner 的 StoryItems／RunSnapshot／STORY_ITEM_CUSTODY；條件來源為 condition owner 的 STORY_CONDITION_CONTRACT。此分工不寫 PM、Git、不啟動引擎或 GPU。

## 依賴與來源責任

必須先整合經引擎驗證的 `core/story_condition_tree.gd`，含根代理核准的公開 `verify_ledger(facts, context)`，才能對 planner 做引擎驗證。planner 共用條件器的條件真相與完整 canonical 帳本驗證，不重寫 exact meal subset 或維護另一份帳目狀態。局部 `StoryTransactionLedger` 只在已驗證的獨立快照上预演正式交易，採用現行 StoryTransactionData 描述與同一套前置／排斥／錢包規則。

純函式不能認證呼叫者。context 必須由實際 owner 收集現行資源、完整來源 scene registry 和已接入的 producer registry，不可由選項、玩家 JSON 或作者的候選 binding 填入；`trusted=true` 不算證據。不存在正式世界／角色能力時必须拒絕，不可把候選格、旗標或「來源 path 看起來對」當作已實作 producer。測試 registry 明確是 fixtures，不能發布成正式 producer。

## 輸入與輸出

snapshot 是既有服務的同步投影，並非另一份可落盤的 save schema：

```text
flags       = GameState.world_flags
items       = StoryItems.snapshot(): owned/unseen/custody_version=1/held/transferred
credits     = Progression.snapshot().credits
ledger      = Progression.snapshot().story_transactions
area_states = GameState.area_states: area_id -> {consumed, damage, world}
completed   = Story.progress_snapshot(): completed scene ids (不是播放中的 seen)
```

外層只接受上述六欄。缺漏、損毀、未知旗標、錯型別、非當前 custody 格式均拒絕；legacy 必須先走 owner 的遷移，不能由 planner 猜交盤狀態。custody 保留完整取得史与 NEW，owned 必須恰在 held／transferred 一側，unseen 必須為 owned 子集。StringName item／completed id 與 JSON 版本數字沿既有 service 邊界接受；context id／registry key 必須 plain String。

context 外層只接受以下欄位：

| 欄位 | owner 供給的資料 |
|---|---|
| scene_id、replay | 正式完成單位 ID 與實際 presentation mode；memory replay 一律不能結果提交 |
| scenes | 已載入的全部 scene id -> `{once:bool,condition:tree,results:Array}`；傳入 results 必須完全等於本段註冊內容 |
| flag_defaults | 所有已知 flag 的正式 scalar defaults；known missing 依 default 投影，未知不補 false |
| item_definitions | 實際 StoryItemData 目錄投影：id -> `{trigger:int}` |
| transaction_definitions | 七份正式 StoryTransactionData.descriptor()；金額／指紋不寫死在 planner |
| producers | `kind:id` -> 具體 producer entries；每段恰一筆匹配；見下節 |
| ledger_locked | 實際帳本鎖定狀態；同時必須驗現行 descriptor 與每張收據，bool 本身不是認證 |

所有旗標值須符合 default 的**確切型別**，不把 bool、String、int、float 互轉。snapshot 缺已宣告旗標會在 next.flags 補 default（目前作者字串選路值是 unset）；整合 owner 若從 JSON 接入，需先依自己明確遷移規則還原 canonical type。不得每次入場把已選 route 重置。

成功回 `{valid:true,status:"planned",error:"",next:完整投影,events:通知資料清單}`；失敗回 `{valid:false,status:具體拒絕碼,error:帶欄位位置的診斷}`，沒有 next 或 events。所有輸入、另一份 proposal 與回傳分支均無可寫 alias。events 只是資料，不會被此 class 執行。

## 支援結果與 producer

作者格式沿 `ch1_closure.py`：`flag(id,value)`、`transaction(id)`、`item_acquire(id[,source_binding])`、`item_transfer(id,destination)`。未知 kind／額外欄位均拒絕；沒有 raw cash、handler、Callable、world gate、companion 或自訂 dispatch。

每筆 producer 有 `{scene_id,source,capability}`；source 為 owner 實際 project source path。capability 只接受下列明確契約，额外 trusted 或別名不被接受。

| capability | 附加欄位與用途 |
|---|---|
| scene_completion | 只寫已宣告 flag 或執行 canonical transaction |
| scene_manual_item | 無附加欄位；只發真正 scene completion 生產的 MANUAL 紙物；不接受 source_binding |
| item_transfer | 附加 destination，與作者 destination 完全一致；實際交接 binding 已存在才由 owner 註冊；只准 held 原件交出一次 |
| consumed_pickup | 附加 binding、area_id、slot；作者 source_binding 必須相同；area 必須已存在，slot 必須由實際 Level._spawn_key 生產且屬該 item（`item_id@x,y`） |

world pickup 只預演既有 `area_states[area_id].consumed[slot]=true` 與 item owned／held／unseen 同時變更；不合成 area、座標、world gate 或人物事實。registry 必須由 actual spawn／resource／persistent area 產生，不能把作者候選位置塞入。即使真保險箱 pickup 具有此形狀，仍需 adapter 接線與跨程序保存驗收才算已安裝。

灰布是 first_clinic 舞臺物件，沒有既有 area_states 可表達的正式托盤快照。`stage_tray` 等尚未定義的 capability 明確拒絕；不能把灰布降格為普通 scene_manual_item，或借亭格當 world marker。資料盤同樣只能由真 pickup 生產，不能註冊成 scene grant。這些是 context owner 的語義責任；純函式驗 schema 與 registry 匹配，不宣稱能證明 `.gd` path 已運行或物件真的存在。

## 原子、重播與順序

先有限驗全部 input tree、服務投影與當前 canonical 帳本，再在**開始快照**上求值本段 condition。開始帳本即使本段只寫 flag，也必須驗指紋、delta、前置、互斥與 exact meal receipt set；腐敗不能洗成 none。

之後才深複製 bounded snapshot，在局部資料與局部 ledger 上依作者順序預演整份結果。order→paid 可建立本批前置收據；paid→order 不會自動重排。任何一筆失敗就只回 error，先前預演 flag／item／world／receipt／wallet 全部丟棄。最後完整驗 canonical 帳本，再追加本段 completed 與 scene_completed 事件。不以已改變的帳目重跑開始 condition；none 入場的 order 或 open 入場的 paid 不會自我否決。

同定義既有 receipt 允許 incomplete segment 續接，不重扣款、不重產 transaction event；金額或指紋不同拒絕。0 元也生成真收據與一次 transaction event。已完成相同 scene id 一律 `already_completed`，沒有任何新結果；先前完成段完整保留。此 planner 是一次不可逆完成單位，`once=false` 只保留資料來源政策，不能使已完成段重領；repeatable presentation 應走 presentation-only 路徑。replay mode 即使 empty results 也拒絕新 completion。

## 有界資料與後续 coordinator

每份 input tree ≤32768 nodes，沿 RunSaveCodec 深度16、文字1024与 plain-data 限制，先驗再复制；result list ≤64，registry／flags／items／completed／area map 各 ≤1024，producer candidates ≤16，error ≤512字元。world/damage 的未知純資料只保持既有快照；結果不修改它們。能力擴充需明確版本與 owner schema，不能靜默略過。

後續 runtime coordinator 必須在同一同步 guard 內取同步快照、重驗現況、規劃整批、使用各 owner 新增的**silent install APIs** 同時安裝旗標、custody、credits、receipt ledger、world markers、completed，並把全輪 canonical snapshot 寫入保存邊界。現有 Progression.apply_story_transaction、StoryItems.acquire／transfer 都會各自通知或保存，不能逐筆呼叫它們假裝整批原子。

guard 必須持續到所有保存安排、完成通知與事件發布結束，避免回呼重入再完成。通知發出前任何 listener 都只能看見整份新狀態；通知後的合法 ordinary spending 不能由舊 proposal 再覆蓋。失敗不得 scene_finished／自動發紙物／保存半份狀態／排下一段／改導航。planner 沒有把 proposal 安裝成 runtime 成功，呼叫端不能以 valid 代稱已保存。

## 驗證狀態

CPU gdparse 僅確認三份 GDScript grammar，沒有引擎 semantic 或 runtime pass 宣稱。新 helper 在既有 EconomySuite invocation 中執行，保留所有原始測試及 smoke registry；covers 199不足整批、order先後、paid＋gift、wallet overflow、0收據、canonical漂移／delta／locked／未知／前置缺失、held vs history、一次 transfer／manual grant、world item同批、未知scene producer／action／item／flag／能力、typeddefault、replay、completed、bounded tree、cycle與回傳alias。

一般拒絕案例逐個比對所有輸入 JSON bytes 不變且無 partial next/events；Object／cycle 不能合法 stringify，另驗原參照保持且沒有 handlers 執行。正式資源僅由測試 load 後 descriptor 提供，不複製 canonical 金額與指紋。根代理先整合 verified condition helper，再執行 EconomySuite／tools/run_tests_changed.sh；fixtures 不表示 formal JSON、實際互動、退出讀檔、HUD、畫面或遊測已完成。

### 原生 headless 驗證紀錄（2026-10-10）

根代理在條件公開 proof 與 custody 合入後，將本工作樹 rebase 至 `109f2ea30`，明確授權此分工使用一個 headless engine slot。上文的「尚未啟動引擎／CPU grammar only」是初次 CPU 凍結時的紀錄；以下是依新授權執行的補驗，沒有修改 shared services 或 frozen planner/helper 程式，沒有開 native GUI、GPU 或截圖，也沒有改 selectors、filters、known_failures 或 smoke registry。

引擎：`C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`，版本 `4.7.2.stable.official.ed1daf0bf`。依授權只複製已停止 condition 工作樹的 `.godot/imported`、global_script_class_cache.cfg 和 uid_cache.bin，沒有複製任何 versioned source。匯入与兩次測試嚴格循序；每個程序 EOF 後才開始下一個。

| 執行 | 實際結果 |
|---|---|
| 獨立 `--headless --editor --quit` 匯入 | EOF exit 0；完整3271行 log 已掃描並檢查所有非進度內容，SCRIPT ERROR／Parse Error／Compile Error／ERROR matches 0 |
| 原本 `tools/run_tests_parallel.sh --only=EconomySuite`，SHARDS=1 | EOF exit 0；278 checks、0 new failures、0 known failures；包含所有原始 Economy 測試及新 planner helper |
| 原本 `tools/run_tests_changed.sh`，預設基準與 SHARDS=1 | 原 selector 選中 EconomySuite；EOF exit 0；1組／278 checks、0 new failures、0 known failures，wall time 8s |

兩份原始測試 log 都完整檢查：沒有 SCRIPT ERROR／Parse Error／Compile Error／ERROR；保留既有 StoryTransaction 故意餵入錯誤定義／損毀快照產生的 WARNING 及 backtrace。這是本次選中的測試輸出，不表示其他測試／正式章節的 raw log 全球沒有 ERROR。原 filters／known_failures 未更動。

原始證據在 `C:/tmp/st9-result-plan-evidence`；`.exit` 檔都為0。內容 SHA256：

| 檔案 | SHA256 |
|---|---|
| import-01.log | `794dc1dcf1e4c732adab1294014540298e150f571ce0c7aca5022ff43a090074` |
| economy-01.runner.log | `42bd293b6da6c4a57c97bd438b8c3ff1bd2e2e8c947133ea075cb35a888fb468` |
| economy-01/shard_0.log | `998383ae9480333089f344f8850928575712ad146cfd7eee350c9cb77411f540` |
| changed-01.runner.log | `5a85e2b5b0ea7794005e14beeb36c3fb96ce511be4b256bddcb2ae953db2c5f9` |
| changed-01/shard_0.log | `998383ae9480333089f344f8850928575712ad146cfd7eee350c9cb77411f540` |

沒有語意或執行錯誤需要修正，所以 core/story_result_plan.gd、tests/helpers/story_result_plan_checks.gd、tests/suite/test_economy.gd 保持 CPU 凍結 SHA，只有本文追加 EOF 後實際證據。引擎產生的本分工兩份 UID 與外來 UID 另外交根代理決定整合，不在此分工做 Git 操作或刪除。所有已啟動程序已 EOF，engine slot 已釋放。

這次通過的是純 planner 的原生回歸與受影響範圍測試。STORY_ATOMIC_INSTALL_PLAN 的 silent owner API、coordinator、真 world producer、保存接線與正式 production scene／choice／quest 仍是待串行實作方案；不能由278 checks 宣稱第一章或十項 production capabilities 已完成。
