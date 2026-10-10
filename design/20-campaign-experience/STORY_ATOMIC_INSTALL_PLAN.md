# 故事結果原子安裝的串行實作方案

2026-10-10。此文件是根代理後續串行實作的具體方案，沒有修改服務、正式資料、PM、Git，也沒有啟動引擎。本階段 frozen planner 四份檔案維持原樣。以下新增方法名稱是**待實作契約**，不是已存在或已通過的 API。

## 目前真正的接點

以分工基線 `d68ddb79a041d8d76ffb076ce48fb0b38c5834ba` 唯讀檢查 Story、GameState、Progression、Main、Level、NpcActor、RunSnapshot、RunSaveStore，以及 custody owner 的 StoryItems／RunSnapshot 草案。

根代理已告知 custody 經42組／9005 checks、0失敗後合入 main `ea48f8c6e`；本文再次唯讀 `C:/Github/Nest-Egg` 的已合 StoryItems／RunSnapshot，將它們視為正式依賴。原 custody 臨時工作樹已讀完，不需保留。其他 API 位置以本分工 d68 檢查內容為準；條件公開 proof 仍由根代理完成整合與引擎驗證，本文不代稱其已交付。

| 現在的方法／行為 | 原子接線要解決的原因 |
|---|---|
| Story `_on_cinematic_finished` | 先清 current、釋放 framing、`_queue_chained_scene`，再發 scene_finished；新結果拒絕時已太晚，不能先排下一段 |
| Story `_on_passive_finished` | 移除 passive request 後立刻 scene_finished；bubbles／radio 同樣需先結算 |
| Story `_complete_request(request, completed)` | 實際 ST-22 結算方法；此基線**沒有** `_settle_request`。先填 `_request_results`，再發 request_settled；awaited NPC 可能同步恢復執行 |
| Story `_ready` 的 scene_finished listeners | 一個 `_apply_scene_flags`；另一個寫 `_completed` 並 request_story_save。新批次已安裝這些狀態，不能再寫一次 |
| custody StoryItems `_on_scene_finished` | 自動 `_grant(SCENE_FINISHED, id)`；新紙物 MANUAL，production scene 必須排除舊的自動獎勵路徑，不能依信號順序碰碰運氣 |
| Progression `apply_story_transaction` | 只在單筆 `_story_transaction_busy` 內同步 wallet／receipt，再發 credits_changed 與 transaction_committed；不能逐筆套它完成整段原子 |
| custody StoryItems `acquire`／`transfer` | 修改 custody 後立即 request_story_save、發通知；不能在多 owner 的中途呼叫 |
| Main `_save_run` | cinematic 活躍時用 `_cinematic_entry` 取代捕捉的整輪現況；成功批次若走此方法會保存舊帳本／舊 held／未完成旗標 |
| Main `_on_scene_finished` | 依 finished request 清 `_cinematic*`，再 queue save；新批次需先由 coordinator 清除／換成下一段保存 metadata，listener 只安排現況補存 |
| Level `_area` | GameState.area_state 回傳的共享 Dictionary；把 GameState.area_states 整個替換後，Level 仍可能抓著舊 `_area`，下一個 run_snapshot／死亡／換區會蓋回舊標記 |
| RunSnapshot `_apply_components`／`rollback_presentation` | 先 Progression.restore 發全部進度通知，再 GameState.restore_story_progress，內含 Story.restore_progress→reset_active_presentation；觀察者會看到半份還原，並可能重入取消／保存 |
| Level `_ready`／Main `_on_retry_requested` 的 non-persistent 分支 | 還原 checkpoint_progress／level_start_progress 會包含舊 story receipt 和 wallet，而 Story completed／custody 已保留，可能把已付錢或已領款回溯成另一份狀態 |

目前 `RunSaveStore.write` 透過 `.tmp`、驗證、正常主檔／`.bak` 輪替及 rename 寫完整整輪；正式進度不另寫舊 `story_progress.json`。validator 是 Main 指定的 `RunSnapshot.prepare`，不是作者 handlers。story 新結果不能用單獨 flags 檔案補救保存。

## 唯一 coordinator 與作用範圍

由 Main 擁有一個 `StoryResultCoordinator`，用強型別 owner 參照與直接方法連接。Main 初始化完成、真 Level 存在後才把 coordinator 登記到 Story；沒有 coordinator 的 atomic scene 回 `backend_unavailable`，不能降級成 legacy 完成。不要用任意 Callable、未知信號 handler、作者提供方法名稱做安裝 dispatch。

新場景由正式 compiler 明確標記 `results_policy="atomic_v1"`，並提供已驗證 condition、results、producer registry。只有這個政策走新 coordinator；舊场景保留原 scene_finished／set_flags／SCENE_FINISHED grants／NPC reward 及 skip-default 語义，不把整個已发布 chapter 自動改成新模式。此 schema 只是待 backend 實作欄位，能力未接好前仍拒絕 production export。

coordinator 狀態是 `IDLE → PREPARING → DURABLE_COMMIT → INSTALLING → PUBLISHING → IDLE`，並有單調遞增 run generation、presentation generation、operation serial。guard 不是帳務信任旗標，不能從作者資料取得；只有 owner 建立的 scope。guard 的有效期包含保存、silent installation、所有通知、`_complete_request` 的同步 listener，直到重入回呼全部返回。

`complete_segment(scene_id:StringName, request:int, presentation_generation:int, presentation_context:Dictionary) -> Dictionary`：只接受 Story 正在結束的真 handle／generation／來源。回 `{status:"committed", completed:true, operation_serial:int}` 或 `{status:具體拒絕,completed:false,error:String}`。結果碼 `busy`、`stale_request`、`backend_unavailable`、`save_failed`、`already_completed` 與 planner 原碼分開；此方法不能直接接受外部 planner 的任意 next。

內部流程不 await、不 deferred、不發 scene signal、不移除目前 request；資源／目錄／registry 在進入同步 guard 前暖好。coordinator 在 guard 內從現況重新 capture 並 plan，不接受幾秒前選項 UI 預檢的 proposal。UI 的 can-pay 只是提示。

## silent preparation／installation 方法

準備與安裝分開。準備可拒絕並回具體 error；準備完成前不改 live fields。安裝只接 owner 建立的 typed prepared object，內容已完成 bounded validation、StringName 集合轉換、資源引用解決、所有 allocation；安裝階段是 infallible assignments，沒有 load、查目錄、callback、await、警告、保存或 signal。普通 gameplay 不能取得這個 prepared object／scope。

| owner／待新增契約 | 完整責任与限制 |
|---|---|
| Progression `prepare_story_install(credits:int, ledger:Dictionary) -> prepared/error` | 共用 canonical verify_ledger，再以已驗 snapshot 準備獨立 StoryTransactionLedger 實例；只涵蓋 credits／story ledger，保留 upgrades、abilities、equipped、pawned。沒有 receipts 舊檔由既有 owner 遷移後進入，不能洗掉 locked evidence |
| Progression `_install_story_prepared(prepared) -> void` | 同步替換 credits 與 `_story_transactions`；不走 restore／spend／add_credits／apply_story_transaction；不發四種全量 restore 通知 |
| Progression `_publish_story_install(before_credits:int, applied_ids:Array[StringName], scope) -> void` | 只在 installation 全部完成後，由 coordinator 呼叫。先發一次 aggregate credits_changed（非零 delta），再依 author order 發 applied canonical IDs 的 story_transaction_committed；0 交易也要發 transaction notice。already_recorded 不再發 |
| StoryItems `prepare_snapshot` 與 `prepare_story_install(raw) -> prepared/error` | custody 草案已有前者；後者把 data 轉成四份独立 typed id 集合，先解決 notification 所需 StoryItemData。不能從 flag 猜 held 或轉移 |
| StoryItems `_install_story_prepared(prepared) -> void` | 同步替換 owned／unseen／held／transferred；不走 acquire／transfer，不保存、不通知 |
| StoryItems `_publish_story_install(events, scope) -> void` | 依已 committed 的 item_acquire／item_transfer event 發 acquired／transferred；提示文字依當前完整狀態計算。先完成全部 state 再發任何 item／toast。scope 擋重入 acquire／transfer；mark_seen 可在 PUBLISHING 修改 NEW 並標 dirty，不得被舊 prepared 再覆蓋 |
| GameState `prepare_story_install(flags:Dictionary, area_states:Dictionary) -> prepared/error` | exact defaults/types 與既有完整 area map；準備獨立資料。只涵蓋這兩個 owner fields，不回復死亡計數、時間、checkpoint、run stats 或 ordinary loadout |
| GameState `_install_story_prepared(prepared) -> void` | 一次替換 world_flags／area_states；不 set_flag、不 request_story_save。area 的 live alias 由下列 Level 步驟同時修正 |
| Level `prepare_story_area_install(next_area_states, world_events) -> prepared/error` | 以真 data.id、persistent_world 與 `_tracked` 找當前 area，校驗 item key／resource／Node 身分與真 pickup 尚在；stage tray 不支援就拒絕。準備新 `_area` 參照及 world projection，不能合成座標 |
| Level `_install_story_area_prepared(prepared) -> void` | `_area` 重新指向 GameState 已安裝的同一 area Dictionary；更新 world runtime 的 consumed view。consumed pickup 對象先無通知地停用互動／碰撞／繪製，保留 Node 到發布後才 queue_free，避免 tree_exiting observers 在半份 state 中執行。Level.run_snapshot 不得把 old consumed 蓋回 |
| Story `prepare_completion_install(completed:Array, scene_id, request, generation) -> prepared/error` | 核對真 request／generation、全部已知 completion id；準備 `_completed`，以及 `_seen` 保留 pending 但包含 completed 的集合。不是把 `_seen` 清成 completed；其餘排隊／passive handles 完整保留 |
| Story `_install_completion_prepared(prepared) -> void` | 同步安裝完成紀錄、當前 segment 的 committed serial。演出 handle 仍保留到發通知；不 reset_active_presentation、不結算 waiter、不啟動 then |
| Main `prepare_story_commit_snapshot(proposal, scope) -> prepared/error` | 真 current runtime capture + proposal overlay 成唯一完整整輪 candidate，見保存順序；確認 RunSnapshot.prepare／Codec 有界有效，不觸發入口替代 |
| Main `write_story_commit(prepared_snapshot, scope) -> durable_result` | 直接對 `_run_store` 寫 candidate；不走 `_save_run`，不引用 `_cinematic_entry`，不發 toast。回 outcome 語義见下节 |
| Main `_install_story_presentation_prepared(metadata) -> void` | 成功後清舊 cinematic entry/request 或原子改成已 committed 下一段的入口；不 queue_save，不呼叫外部 listener |

`Progression._story_transaction_busy` 可與 scope 的 `blocks_story_mutations()` 合併為 guard 判定，不在每張交易間放掉。全 owner 同步簽到同一 scope，不能只鎖錢包而讓 acquired callback 又移盤。PREPARING／INSTALLING 禁止其他 gameplay mutation；這兩段本來就不能有可恢復腳本回呼。PUBLISHING 只禁止新的故事 transaction／atomic result／custody acquire-transfer／Story progress reset或新 request／route/load，普通 spend/add_credits 仍合法。新 run／quit／死亡／route 等生命周期要求記錄到 bounded pending action，guard 結束後依真 generation 處理，不能中途拆換 owner。

## 精確執行順序：先保存可安裝完整候選，再 silent 安裝

選擇 durable-first，避免 IO 失敗後玩家已看到成功，再試圖退款／還盤。保存前允許的工作都是準備與校驗；保存成功後不安排任何仍可能拒絕的動作。

1. 檢查 IDLE、active run、Level instance／path／persistent producer、真 presentation handle／generation、非 replay；取得 scope。取消／換區已發生則 stale，不触發故事通知。
2. 捕捉 `Level.run_snapshot()` **在前**，因為它會 merge `_area`；再從同一現況捕捉服務投影與完整 RunSnapshot，確保 projection 的 area_states 與 runtime.area 同拍。檢查 save 不處在 `.newrun` 尚未恢復或 unknown version 保護狀態。
3. 以載入的真 context 跑 planner。再按上節準備全部 owner、真 world object、Story handle、導航投影／續段 metadata，最後 recheck source/generation 與 live projection bytes／revision 未變。所有任意資源或 validator 可能失敗的步驟必須留在這裡。
4. Compose 完整 candidate：`progression.credits/story_transactions`；`story.flags/items/seen`（seen 存的是已完成史）；`state.area_states`；當前 `runtime.area` 與 `runtime.world` 的相應一致世界；其他 progression／checkpoint／stats／loadout／navigation 沿同拍現況保留。world consumed 成功後 pending pickup 在 candidate 不再可生成。導航要先取得合法新狀態或保留現況；不能在安裝後才讓 required backend 拒絕。
5. 候選的 cinematic metadata 必須不再是**當前已完成段**。沒有合法已綁定 continuation 則 cinematic=""／context={}，下一次真互動由 loaded continuation registry 接缺拍。若當前正式 backend 有完整 then 契約，可先以 proposal.next 對下一段资格及真來源做唯讀驗證，candidate 保存 `cinematic=next_id` 和 sanitized 原來源 context，並把下一段 entry 定義為本份 committed candidate。這是在保存前規劃續段，還沒把 next 寫入 Story queue／_seen 或启动。不能猜不存在的二章／stage location。
6. 直接保存這份 candidate。保存失敗：所有 live owner／原段 handle／NPC 次數／world Node 保持，沒有任何通知或 completion；scope 释放後顯示一句既有服務提示。保留 Store diagnostics／原件／tmp／bak 的恢復證據，不能以另一份 flags save 掩蓋。
7. 保存明確 committed 後，以同一 scope 安裝 Progression→StoryItems→GameState→Level area rebind→Story completion→Main presentation metadata。順序本身不對外可見；此段沒有 callback、await、deferred、injection hook 或可拒絕的 validator，最後核對 prepared 引用已一次安裝。切勿再呼叫 prepare、restore 或 apply_story_transaction。
8. 對外發通知與结算 request，見下一節。所有同步 listener 返回後，若 dirty，仍在 scope 內用**最新 live capture**做一次補存，不能重用 step4 candidate，也不能重新安裝 next。補存成功後或明確記錄補存失敗／fresh retry pending 後才 release scope；沒有 listener 尚在執行或保存通知待處理。下一段在 guard 釋放後開始，触發新的 entry capture。

### Store outcome 與跨程序邊界

既有正常 `RunSaveStore.write` 的 rename 安裝完整主檔是 durable commit point；實際 power-loss fsync 保證仍需平台驗證，不在此文宣稱。新輪的 `.newrun`／freshbak 流程已有不同恢復政策，故事結果不能另啟用 confirmed_overwrite。active run 尚未成功建立 base slot／新輪 marker 未恢復時先拒絕或由 Main 完成既有恢復，再開故事 batch。

最低需把故事 writer 回值分為 `{committed:false,error}`、`{committed:true,cleanup_issue?}`。normal false 只限 commit point 前；主檔已 rename 成合法候選後，清理標記／日志／備份的錯誤不能偽裝成未提交並重播付費。可用 Store 內部 outcome 記錄達到，不讓 coordinator 因 false 再猜磁碟。若 owner 仍只留 bool，必須證明故事專用 normal 路徑所有 false 都在 commit point 前，且無 unresolved `.newrun`；無法證明就拒絕能力，不做近似實作。

跨程序退出：commit point 前读取完整旧主檔或完整旧 bak，重試本段；commit point 後读取完整 next candidate，已完成段不再付費，或者依 candidate 明確下一段 id 續播。不能接受 only flags、half custody 或只改帳本的 candidate。若 rename 回滾失敗，現有 bak／tmp 原件保留，read 只能依既有完整驗證政策恢復；不能合成新 receipt 洗平帳務。保存成功後且通知前崩潰，由已寫入的 completed 防止再次獎勵，不依曾否看見 toast 判斷。

沒有「保存已 committed 後安裝可失败」正常回值；typed prepared assignment 要保證完备。故障注入一律在 step6 前模擬各 owner prepare／IO 錯誤。若要測中途進程崩潰，使用独立程序在 durable commit 前／後終止，重新讀取完整槽驗證。不能測試用 callback 在 step7 半份安裝中呼叫 gameplay，然後把此不可接受窗口當正式 API。

## 通知、request 與 ordinary spending 的順序

step7 完成後所有信號观察者已能讀到完整新 flags／wallet／receipt／custody／world／completion。coordinator 尚在 PUBLISHING：

1. Progression 發一次 aggregate credits_changed(current wallet, batch delta)（delta 非0）；接著 applied transaction IDs，包括0元。signal 首發的 current wallet 取安裝值；listener 若呼叫 ordinary spend，內層 spend 的新 credits_changed 照原規則同步發出。批次事件的 before/after 放 immutable committed record，不能把稍後 current wallet 當批次結算結果。
2. Item acquired／transferred 與合理 toast 按已提交 item events 發布。StoryItems 的 acquisition count／NEW 等 query 讀完整现况；callback 可以 mark_seen 或普通 spend，造成 save dirty。禁止 callback acquire／transfer 或新 story transaction，回明確 busy；不能在 emit 返回後再把 prepared custody／credits assign 一次。
3. 以真 request 設 `_finished_request`，發 `Story.scene_finished(id)`。atomic scene 的 `_apply_scene_flags`、anonymous completion/save listener 與 StoryItems `_on_scene_finished` 必须查正式 scene policy並**略過自身 side effects**；已由 batch 安裝的 completion 不再寫。legacy scene 保持原行為。Main listener 可 queue current save，不得再次改已更新的 cinematic metadata；導航/HUD observer 在完整state上更新。
4. 若沒有已規劃 continuation，呼叫實際 `_complete_request(request, true)`，讓 `_request_results` 先填值再 request_settled。NpcActor._present_talk 保持「await返回成功→talk_count增加→_give_reward」顺序與失敗不加次數。若有 continuation，保留同 request 至末段，不先把整串 waiter 解開；只在 commit 後準備 queue 記錄，開始要等 guard release。
5. 等全部同步 callbacks 返回，清 `_finished_request`。批次結果 immutable record 保持自己的金額；不再次install next。Main 若 dirty，仍在 scope 內重新 capture **此刻** live 並補存；安排必要的fresh retry後才解除scope。例：batch付款200後 observer又普通spend20，wallet与後續保存都必須少220，不能因舊 proposal wallet 再填回少200。補存失敗不撤銷已durable的batch或live ordinaryspend，不回false waiter／重複付費；保留dirty且顯示「最新變動尚未保存」，下一次嘗試一定重抓live。

production NpcTalk 的 `_give_reward` 不得與 completion results 重覆配置同一 credits／story item。compiler／registry validation 要拒絕重覆來源；production story 紙物用 MANUAL completion，資料盤用真 pickup，不在 NpcTalk reward 列表。這樣既有 NPC waiter 次數／冷卻 bookkeeping 可保留，真 reward 已在batch。legacy reward保留；production callback後的 talk_count／claimed world bookkeeping 若需要落盤，Main recapture/save dirty，不能用它補發一次 canonical款項。

source cleanup／queue_free 只在完整 state 已對外可讀時進行；其 tree_exiting／navigation listener 若要求 route/reset，同 scope 暫存到 release 後。既有 `_start_cinematic` 的 scene_started 不能在 PUBLISHING 裡叫，否則 Main 會抓到錯誤的 `_cinematic_entry`。

Main `_queue_save`／`_queue_runtime_save`／`_flush_save`／critical save／quit 皆要識別 scope：活動時只標 dirty，不開獨立 storewrite，不復用 entry override；release後用最新現況。同一 deferred queue 不能持有舊 capturedsnapshot；原本 `_flush_save` 已即時capture，可保留這個特性並加scope判斷。不得「清掉 `_save_queued` 就假裝保存了 listener 的更動」。

目前 StoryItems.mark_seen 不 request_save，因此必須在 scope publication 的真mark_seen成功變更時明確標dirty，或讓其一般owner方法統一request_save；不能假設Main已有NEW signal。guard內第二次writer與初次writer同樣不發toast callback，診斷提示排在解除scope後，防止保存失败提示listener重入無限保存。

## 檢查點與 durable 故事資料

原子段的receipt、wallet delta、完成史和custody必须在死亡／retry後仍對帳。現在persistent_world區域保留Progression，non-persistent區域則會把整份Progression回到checkpoint／level入口。僅合併最新receipts到舊wallet会造成「收據顯示已付，但錢退回」；反過來僅保留wallet也会讓舊receipt重新收費。

最小第一階段明確只在真persistent_world runtime承諾atomic能力，並核對既有retry/checkpoint/portal目的地不會走舊non-persistent Progression還原。若來源或已完成atomic史需要進入該舊還原路徑，先回`unsupported_restore_boundary`且保留現況，不改舊場景的checkpoint政策，也不靜默猜一個receipt-only merge。

之後若要支援non-persistent故事段，Progression owner須定義一次性故事金額與一般checkpointrun成長的還原政策，保存所需真證據並為每種付款／0帳／720領款／一般spending／死亡費用測完整矩陣。不能新增第二個可花wallet，不能用固定金額把當刻ordinaryspending補平。這個政策和版本完成之前，不宣告跨non-persistent區域的production能力。

## 拒絕、取消與 rollback

**開始條件不符／交易不足／producer未知／world尚未安裝／保存失敗**：未達durable commit，沒有 state mutation、scene_finished、item／wallet signal、下一段或true waiter。支付200不足只用明確碼轉既有完整不足额選擇；其他錯誤保留進度並可返回，不默默變欠條或招待。

Story 在 atomic拒絕時走独立 `result_rejected(scene_id,request,status,message)` presentation結果入口，或強型別 UI owner 方法；它是失败資訊，不當作 scene_finished。拒絕前仍保留handle，清理presentation时只結算 `_complete_request(request,false)` 一次，移除尚未完成的 _seen，確保再次真互動可重試。沿用 `_presentation_generation` 防舊 player.finished／deferred passive callback 完成新的同名request。user確認返回也false，不執行skip-default或completion。

新的 production segment 不在播放中直接調 acquire/spend/set完成flag；route intent 是另一个明確且可取消的 reversible choice contract，須在該意圖單位合法保存，不能把晚間已選route每次置unset。取消production segment因此只撤presentation／暫定pose，不以全輪入口回滾覆蓋播放期間普通戰鬥錢、拾取、機關與死亡事實。**已完成前段**已在durable candidate中，不能在下一段取消時重新還盤／退款。

Legacy scenes仍用ST-22既有完整entry rollback政策，這輪不擴張或修正它對passive ordinary gameplay的政策；新atomic政策需獨立分流。若production仍有必須rollback的暫定世界演出物，建立明確`presentation_delta`／pose-only adapter，只撤這段自己擁有的變動，不能 RunSnapshot.rollback_presentation(fullentry) 洗掉並行normalspending。

`reset_active_presentation(reason)` 若在 scope PUBLISHING 裡由 callback要求，先記 pending request；不能一邊scene_finished一邊reset把已持久完成變false。durable commit後的route/death/quit都以**已完成**状态處理；沒有追溯撤銷。外層真正死亡在commit前取消就由Level既有死亡結算处理，保存真死亡計數／扣费；不以故事completion代替死亡事實。

## RunSnapshot 還原路徑需同步修正

不能拿現在的 `_apply_components` 做batch install或batch failure rollback：Progression.restore立刻發訊號，GameState.restore_story_progress先清flag、再Story.restore_progress触發取消，又StoryItems.restore，最后导航与lives_changed；這不是静默全量還原。

後續另拆 `RunSnapshot.prepare_components(data)` → typed prepared bundle、`_install_components(prepared)` → silent、一個 `publish_restored(bundle)` → 全量通知。已驗 RunSaveStore／RunSnapshot.prepare 的完整讀檔可以使用 bundle；Story cancellation必須在**舊狀態尚完整**時先處理，標 load/new_run generation使Main._on_presentation_cancelled不再觸發入口rollback，然後安裝完整讀檔状态，再通知Progression全量变更／导航／lives。整輪apply的start_new_run同樣會reset signals，需先拆reset preparation與silent reset，不能在安装中呼叫目前start_new_run。

legacy `rollback_presentation` 也需先capture並準備保留actual run_time／kills／finishers／deaths／lives_left／last_death_clock，把保留值**放入prepared前**，silent安裝整个rollback bundle後才發通知。現在先_apply_components再把actual scalar补回會让listener短暫看到旧death；不得保留此半份觀察窗口。Level.rollback_presentation_world／WorldState.restore有真实Node side effects，必须在准备好完整目标后用明確worldadapter同步安裝／deferred清理，不让tree_enter／exit listener夹在一半資料中。producer未支援worldadapter就不要宣告能力。

上述restore拆分不改变legacy資料迁移規則／已發布scene結果內容；只建立合法同步觀察邊界。不是先「把訊號disconnect再connect」；那會丢listener变化／順序且無法擋Node signals。使用owner明確silent方法。

## 真服務驗證與故障注入

planner fixtures不能代替以下原生Suite與獨立程序驗證。測試使用隔離user path／實際Main+Level+autoload services，真七份交易資源和真StoryItems目錄；正式場景尚未發布的部分列待驗，不假造已完成capabilities。

| 情境 | 真服務必須可觀察的驗收 |
|---|---|
| 登記有order、現金199，真付款scene完成入口 | wallet／receipt／item／flag／completion／Node／NPC次数全不變，沒有成功通知；只進不足额presentation |
| 現金200付款成功 | 第一個credits／item／scene listener读取整份一致state和真磁碟candidate；本段只完成一次，requesttrue在完成通知之後 |
| 同批0交易＋MANUAL紙物＋flag | 0receipt寫磁碟、發一次transaction notice，紙物与flag已经存在，wallet不發delta0假變動 |
| 真保險箱data_disk拾取 | Level._tracked key與actualresource吻合、world consumed与held/history同存；run_snapshot、死亡、portal保存後不复生；radio本身不發盤 |
| 真交接櫃收盘→取回執→摘要 | 三段各自保存；第二／三段cancel與跨程序重讀不还原已交盤，沒有720；未知／未建櫃明確拒絕，不用fixtureobject代交付 |
| credits_changed callback ordinary spend20 | callback先看到新receipt／completion，再實際spend；最终live与後续disk少220，所有旧candidate丟弃，不复盖少200 |
| acquired callback mark_seen及ordinaryspend | NEW與wallet最新變更保留並recapture；acquire／transfer／storytransaction重入busy，一般花费成功 |
| scene_finished／request_settled callback要求play/reset/route/load/quit | scope內明確busy或boundedpending，解除後按generation处理；不重領、不半套restore、NPC舊callback順序不變 |
| 旧／production自动scene grant与NpcTalk reward | legacy正常一次；production同一item／款項多來源被compiler拒絕，通知listener不再獎勵一次 |
| 每個owner prepare拒絕、worldidentity stale、RunSnapshot prepare失败、encode过界、tempopen/flush/verify/backup/rename失败 | 全部在commitpoint前，真实live bytes與trackedNode不变，無任何通知／requesttrue；旧文件／backup证据保留 |
| 正常save rename成功之后cleanup診斷 | durable outcome仍committed，不能重试收費；新完整candidate可read，warning不触发退款 |
| commitpoint前／後獨立程序终止 | 前者完整旧段可重试；后者完整新段不能重收，continuation是明确已登记next，不靠toast／fixture／scene猜測 |
| restore／legacyrollback listener取wallet+items+flags+deaths+area | 所有notification都只能看到整份target，actualdeath保留值在第一条signal前已安裝，不出现临时旧值 |
| buffered旧_flush_save、activecinematic、then鏈取消 | 成功存檔不被_cinematic_entry替代；下一段entry含前段receipt/transfer；listener ordinary mutations再存最新live |
| atomic段完成後retry到non-persistent checkpoint | 第一階段精確拒絕不支援還原邊界，不能退回paid money或重新領720；擴充後才跑完整付款／普通花費對帳矩陣 |

故障注入置于explicit prepare/store测试port的固定阶段，不能新增production任意handler。所有正常拒絕逐一比较service快照bytes、signal counters、Nodeidentity与隔離文件checksum；成功后的进程崩溃测试以跨程序read/assert驗证恢复结果。准备后的slot／资源被替换的测试必须在preflight stalecheck发现，不能在step7动态fallback。

实施次序：共享condition proof与custody先合入且原生驗證；再silent准备/安装owner和restore观察边界；再Main durablewriter/coordinator与Story completion分流；再真实producer/worldadapter；最后正式compiler开atomic能力、正式scene/choices/quests生成与ST22取消矩阵、changed suites、退出读档／实画面驗收。此文不替任何未實作步骤宣告通过。
