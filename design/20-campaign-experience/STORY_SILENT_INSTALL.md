# 故事／整輪資料的準備與靜默安裝

2026-10-10。分工基線 `c744a44f2`。此階段實作 [原子安裝方案](STORY_ATOMIC_INSTALL_PLAN.md) 的四個資料 owner 準備與安裝接口；沒有啟用正式 atomic scene、修改正式 JSON、接 coordinator、修改 Level／Main／導航，也没有改变既有公开 restore、apply、rollback、scene_finished 或 NPC callback 行為。

## 具體接口

| 接口 | 契約 |
|---|---|
| `Progression.prepare_install(raw)` | 有界純資料驗證後，產生 `PreparedInstall`：唯一 wallet 的 credits、typed upgrades／abilities／equipped／pawned、獨立 ledger。真 WeaponData／upgrade／ability／consumable 必須存在且可用；帳本要符合真七份 transaction resource descriptor 與共享 `StoryConditionTree.verify_ledger`，不複製帳務判定、不固定金額／指紋 |
| `StoryItems.prepare_install(raw)` | 共用已發布 custody `prepare_snapshot`，包括 legacy 遷移；事先建立四份 typed owned／held／transferred／unseen 集合，不發放任何物品 |
| `GameState.prepare_install(state, flags, difficulty_path, whole_run)` | 事先建立完整 typed scalar／dictionary／Vector2／StringName／DifficultyData。整輪模式載入真難度，清 transient carried loadout；story 模式保留它。宣告過 default 的 flag 要符合型別；JSON float 整數只在 declared int 邊界正規化。整輪容許已發布 legacy set_flags 的未宣告 scalar，batch 只能原樣保留它們，新增／修改 flag 必須有 default |
| `Story.prepare_install(completed, whole_run)` | 完成 id 必須來自實際 loaded scenes 且不重複。整輪 mode 要求沒有 active／queued／passive／waiting／finished request；否則拒絕，沒有取消或 reset。batch 保留 pending `_seen`，完成史只能增加；不清 queue、waiter、framing 或 presentation |
| 四個 owner `_install_prepared(typed_state)` | 只給 bundle 使用的內部接口。固定 field／container assignment；沒有讀檔、資源載入、驗證、warning、clone、grant、reset、信號、save、callback、deferred 或 await |
| `StoryInstallBundle.prepare_components(data)` | 呼叫端已持有 `RunSnapshot.prepare` 完整結果時使用；整輪／release／story／progression／custody／ledger 版本及全部 owner 準備成功後才回 `{data: bundle}`。embedded checkpoint／level-start progression 亦檢查當前資源與帳本。失敗只回 error／unknown_version，現況與輸入不動 |
| `RunSnapshot.prepare_install(raw)` | 先走既有 `RunSnapshot.prepare` 的整輪遷移／正規化，再準備上述 bundle。既有 loadout、runtime 與 difficulty repair 政策不重寫成另一個存檔格式；此 wrapper 尚不負責任何 Node／navigation 安裝 |
| `StoryInstallBundle.prepare_story(next)` | 只收已成功 `StoryResultPlan.next` 的精確六欄投影 flags／items／credits／ledger／area_states／completed。其餘 progression、loadouts、統計和 carried loadout 取同拍現況。current ledger 必須可信且所有既有 receipt 原樣保留；新 area 必須拒絕。producer 身分與 world Node 仍由 caller 的真 registry／adapter 負責，這個 API 不認證 caller、不授權能力 |
| `bundle.preflight()` | 使用前再比對全部來源；回 `{ready: true}` 或具體 error，不寫 owner |
| `bundle.install_silent()` | 先做最後 preflight，error 都在第一次寫入前。成功 result 也事先配置好，再標 consumed、同步交接 Progression → StoryItems → GameState → Story 的 typed references，丟掉 bundle 的 prepared aliases，回 `{installed: true}`。不產生事件與通知，不保存、不反覆安裝 |

Prepared state／bundle 是可信 owner 內部的 opaque object。只有外部 raw 純資料是不可信邊界；不可讓 author data 或任意 handler 持有／改寫 bundle 的 `_` 內部欄位，也不可繞過 bundle 直接調 `_install_prepared`。GDScript 的 underscore 是內部 API 契約，不是假稱能認證惡意執行腳本。raw 入參在有界驗證後才複製；修改呼叫端原始 raw 不會修改 prepared 或 installed containers。

沒有新增另一個可花錢的 wallet；預備 credits／ledger 是同次未安裝候選。安裝後 wallet 仍只有 Progression，bundle consumed 後不能再覆蓋它。沒有 generic Callable dispatch、trusted=true、signals disconnect／reconnect 或 world capability 占位 handler。

## 來源檢查與尚未接上的 guard

preflight 比對有界 tree 的 Variant bytes，保留 scalar 型別與 dictionary order，刻意採保守拒絕：GameState 全部 run scalars、area/checkpoint/entry dictionaries、flags/defaults、carried loadout、difficulty path、autosave／queued 狀態；Progression 完整 snapshot；StoryItems 完整 custody；Story seen/completed、presentation generation、request serial、current/finished handles、queue/context、passive requests、waiters/results、resetting 和 loaded scenes。int-key waiter maps 先轉 bounded pair arrays。來源有 corrupt／非純資料或單筆故事交易正在通知時拒絕，未複製無界 live tree。

因此準備後的普通 spend、flag 改變、mark_seen、area marker、已完成段或 presentation generation 改變會拒絕整份候選，所有 owner 尚未写入。相同內容的 ABA 並不是 monotonic revision；這個接口不假稱有全域 lifecycle revision。所有正式 mutation 仍走原有公開 API，此輪沒有讓它們回 busy、延後 route 或改事件順序。未來 coordinator 仍必須有真 Main／Level owner、generation／identity guard，禁止 scope 中途 route／restore／new request，並持有主執行緒同步邊界。不得跨 await 或不受控 callback 保留一份「ready」證明。

安裝前的 preflight 可以配置 source snapshot／bytes；第一個 live assignment 開始後是固定 prepared reference 交接，不再配置／驗證資料或呼叫外部行為。成功之後預備 owner aliases 釋放，重新 install 會拒絕。安裝後 ordinary spending 合法，後續保存／通知必須讀最新 live；不能拿舊 bundle 重安裝或再次寫舊 wallet。

這是資料 owner 的準備邊界，**不是** durable coordinator。未來 durable write 必須在全部資料 owner、Level world／`_area` shared reference、navigation、presentation metadata 都準備好且 preflight 成功之後進行；寫入途中不得有會改 source 的 listener。若 durable commit 後 preflight 不成立，不可把它當正常未提交重收費；應在 coordinator 設計時消除這個窗口。低層 API 的可拒絕 preflight 並不提供「commit 後可安全 rollback」語義。

## 整輪還原與發通知的剩餘接線

`RunSnapshot.apply`、`_apply_components`、`rollback_presentation` 原路徑完整保留，沒有偷偷將其中一部分改成 silent 而漏掉剩餘 owner。它們目前仍有先 Progression signal、再 GameState／Story cancel／items／導航的既有順序；本階段未宣稱已修正那個觀察窗口。

整輪 coordinator 後續要在**舊 run 完整狀態**先處理 Story cancellation／Main entry policy，並確認沒有 active requests，再準備／重查完整 bundle。runtime／navigation／Level actual Nodes 和 `_area` reference 必須在同一 observer boundary 安裝；本 bundle 會換 GameState.area_states 引用，所以 live Level 尚未 rebind 時禁止把這個接口用在正式 gameplay。prepared target 的 Navigation 和 runtime 在 RunSnapshot 已驗證但尚未由本 bundle 安裝；不能僅安裝四個資料 owner 就宣稱整輪 resume 成功。

silent 完成所有 owner／Nodes 後才能由 coordinator 明確 publish existing notifications、scene completion／request settlement。`Story._complete_request`、NpcActor 既有 awaited callback 順序、legacy scene flags／自動 StoryItems awards 在此階段未變。production 分流與避免 double grant 要先完成才開 capability。新結果成功保存不能走 Main 的 `_cinematic_entry` 替代；相同要求適用 ordinary callback 後 fresh recapture/save。死亡／取消保留的 actual scalar 要在 prepare 前併入目標，不在通知後補改。

## CPU 與引擎驗證

新增 `tests/helpers/story_install_checks.gd`；existing RunSaveSuite 僅新增一行 helper invocation，所有原測試、fixtures、selector、registry 與 known failures 保留。helper 使用真 autoload、七份正式交易資源、正式 item catalog／loaded scene／radio request，不用替代服務。涵蓋 future versions（含 embedded checkpoint）、錯 flag type、unknown owner references、receipt delta／fingerprint／paid+gift 衝突、失敗 bytes 與 input 不變且無事件、七種合法帳務 path、detached caller raw、完整 coherent silent install、upgrades／equipped／pawned／loadout preservation、兩份候選 stale／one-shot、安裝後真 ordinary spend 的第一個 listener、pending radio 保留、whole-run active request 拒絕、各種來源 stale、實際 legacy 檔案未寫。

分工先以 CPU `gdparse` 檢查，根代理完整讀取各 owner／bundle／helper，逐份核對原行為本文保留，再在 main `951f3add2` 執行 Godot 4.7.2 完整 headless editor import（自然退出0，無 SCRIPT／Parse／Compile／ERROR）。RunSaveSuite 167項、0失敗、9秒、自然退出0，完整輸出無 ERROR。原 `tools/run_tests_changed.sh` 選取65組，41891項、0新失敗、0已知失敗、1153秒、自然退出0；保留原測試、選取器與已知失敗。這是實際 headless 引擎驗證，沒有原生遊戲畫面或章節通關宣稱。獨立程序 durable read／失敗注入、Level共享引用、通知／普通花費補存矩陣留待 coordinator 階段真服務測試。

實際 CPU freeze 檢查：`PYTHONPATH=C:/tmp/ne230-python C:/tmp/ne230-python/bin/gdparse.exe` 對四個 autoload、RunSnapshot、StoryInstallBundle、helper、RunSaveSuite 八份 `.gd`，EOF／exit 0，無語法輸出。與目前正式 main 只讀比對：五份 existing implementation 只新增接口區塊（原功能本文不變；兩處區塊附近只涉及空行）；RunSaveSuite 刪去唯一新增 helper invocation 後，全文逐字等於 original。未呼叫 Git 操作、沒有生成 engine UID；source hash 列表隨分工交接回 root review。

CPU 另按現行五份 `Story.CHAPTER_PATHS` 的實際 JSON 合併方式量測 `_scenes`：93個 scene、無重複 id，2554個 Codec value nodes，subtree最大depth6（放進 source 時depth8），最長key／文字47字、最大container93、peak pending125，compact UTF-8 JSON40573 bytes，沒有 Codec 型別／長度／深度超界。source 的200000 nodes上限扣掉 scene subtree 尚有197446 nodes給其他 owner／metadata；live source 若合計超界仍明確拒絕，不先無界複製。此數字是實際作者 JSON 的 CPU量測，不是 Godot runtime pass。

受影響範圍的完整原始紀錄保留 75 行 ERROR，原 runner 的既有 filter 未發現非預期腳本錯誤；不能把它改寫成 raw 無 ERROR。詳細分類與來源雜湊見 [驗證附件](../../pm/ST/attachments/ST-3-silent-install/manifest.json)。本階段不呼叫正式 gameplay bundle、不啟用新 production capability，也沒有保存／發布 coordinator 或完成 ST-3 整張票。

同步4440a79fc後，另一台電腦新增原生姿勢網格與PoseMeshSuite；十一份已測交付來源SHA不變。重新完整引擎匯入（自然退出0、無SCRIPT／Parse／Compile／ERROR），並以原runner執行main、RunSave、StoryLint、StoryContent、Economy、Collectibles、Cutscene與PoseMesh八組整合回歸：3855項、0新失敗、0已知失敗、112秒，自然退出0。整合原始紀錄亦保留預期負向案例及既有引擎診斷。65組完整受影響來源測試的基線仍明列951f3add2，不冒充最新角色改動上的全量回歸。
