# 故事信用點交易與收據

NE-231 第一個交易 phase，2026-10-10。設計基準為根代理指定的 `7e05a6e7`，隔離目錄 `C:/tmp/Nest-Egg-story-transactions`。根代理完整審查本設計後放行CPU實作；ST9腳本已根審並合入 `53664537`，七筆定義按其帳務裁定建立。尚未故事接線。根代理將測試來源整合至 `a52e57ea47e775f9aefc229eca8f712dc8a0183e` 後，已完成下述引擎與原受影響範圍測試；Git與票務仍由根代理統一處理。

## 目的與交付界線

同一件故事款項只能結算一次；信用點與防重複收據必須同時改變、同時保存、同時回溯。價格、前置收據與互斥結果由資料宣告，故事接線者不再各自寫 `add_credits()`、`spend()` 和已領旗標。

本 phase 只處理既有信用點錢包和收據。物品、能力解鎖、故事旗標、演出完成與磁碟成功的跨服務提交，由後續 Story owner 接線；此處成功只表示記憶體中的錢包與收據已提交，不表示故事或存檔已完成。不新增 XP、貨幣、銀行、商店或 autoload。正式任務、第二／三章經濟、三類成長與實戰驗收仍屬 NE-231 後續範圍。

可修改範圍限本文件、`core/story_transaction_ledger.gd` 與自有 UID、`data/scripts/story_transaction_data.gd` 與自有 UID、`autoload/progression.gd`、既有 `tests/suite/test_economy.gd` 與自有測試 helper、已核定的少量 `data/story_transactions/` 定義。Story、Main、RunSnapshot、Level、NpcActor、UI、產生器、票務、測試註冊／selector 均不修改。Git 操作由根代理串行處理。

## 目前來源與差異

| 來源 | 已存在的行為 | 本設計承接方式 |
|---|---|---|
| `autoload/progression.gd` | 新輪信用點0；上限99,999；加款可能只加剩餘容量；購買不足時不扣；改裝、能力、當票與信用點共用 snapshot | 故事交易採全額成功或完全不變，不改普通拾款／購物規則 |
| `autoload/story.gd` | 場景結果與選項目前只寫旗標；skip 套用預設選項；已完成場景才寫入可保存觀看記錄 | 後續 Story owner 使用交易結果決定完成，不在本 phase 插入演出指令 |
| `game/npc/npc_actor.gd` | 獎勵按本區人物格位／對話索引領一次；WorldState 記錄 claimed | 不改既有 NPC；正式故事款項另用不依位置、對話排序的穩定事件ID |
| `game/main.gd` | 未完成電影／人物對話保存整段入口快照；完成後保存現況 | ledger 跟 Progression 一起進入口快照；後續接線不得提早把結果當不可撤銷 |
| `game/level/level.gd` | 正式第一章持久世界不回溯；非持久關卡重試回溯 Progression 與 WorldState | ledger 必須置於 Progression，不只寫不回溯的 Story flag |
| `core/run_snapshot.gd` | Progression 欄位先有界驗證、複製；未認識的子欄位保留 | 新 ledger 由 Progression.restore 自行驗證；本 phase 不宣稱整槽 prepare 已拒絕壞帳本 |

第一章文稿的27,400是歷史存款敘事，480,000是房價；本 phase 不發同額可花信用點。盤點基線的 `ch1_b_dinner`「交40」只有臺詞／旗標，餐酒120＋80也沒有實際扣款證據。ST9已根審裁定日常第一晚為0，不補造40支出；餐酒款先有order才可結算，不憑臺詞退款或立重複欠條。

參考來源：[總設計](DESIGN.md)、[研究與採用界線](RESEARCH.md)、[第一章文稿](../13-story-v2/SCRIPT_CH01.md)、[第二章結算契約](../13-story-v2/SCRIPT_CH02.md)。文稿金額不是已接線或已遊玩結果。

## 不可變交易定義

`StoryTransactionData` 為 Resource，只含下列資料，不包含任意 Callable、物品路徑、演出、旗標或 JSON 指令。

| 欄位 | 型別／上限 | 用途 |
|---|---|---|
| `id` | StringName，1–64字元，ASCII `a-z`、`0-9`、`_`、`.`；首字為字母 | 全局穩定事件ID，不能用場景順序或 NPC 格位替代 |
| `definition_version` | 正整數，初版1 | 明確標示定義格式；本 phase 只接受1 |
| `credits_delta` | 整數，−99,999至99,999，允許0 | 正數收入、負數支出、0為有效的決策收據 |
| `requires_receipts` | 最多32個唯一合法ID | 所有前置收據都要存在 |
| `excludes_receipts` | 最多32個唯一合法ID | 任一已存在便拒絕；不能和前置重疊或包含自己 |

定義使用前先驗證並轉為只含標量與有界ID陣列的描述；不保存可變 Resource 參照。每次嘗試都讀取當次描述，不修改輸入資源。收據保存描述的 SHA-256 指紋；指紋的 canonical 輸入為固定欄位順序、合法ID、版本、整數金額以及排序後的兩組ID陣列，與 Resource 路徑、翻譯文字、序列化的鍵順序無關。相同集合不同順序視為相同定義。

有界驗證先檢查容器大小，再走訪；不先配置超大陣列、把字串轉成整數或截短事件ID。整數驗證只接受有限且無小數的 TYPE_INT／TYPE_FLOAT，拒絕 bool、String、null、NaN、Inf及越界數值，兼容 Godot JSON 將整數載成浮點值。定義錯誤拒絕該次交易，不把錯誤當成0元或空前置。

## 可審查的公開 API

```gdscript
# Progression：唯一錢包擁有者，所有接口同步，不 await。
func story_transaction_status(transaction: StoryTransactionData) -> Dictionary
func apply_story_transaction(transaction: StoryTransactionData) -> Dictionary
func story_receipt_status(id: StringName) -> Dictionary

# StoryTransactionLedger：RefCounted，由 Progression 持有一份，不是 autoload。
# 下列純驗證接口可供下一個存檔／故事 owner 接線。
static func validate_snapshot(raw: Variant, where: String) -> Dictionary
```

`story_transaction_status()` 為唯讀預檢；它不扣款、不寫收據、不發 signal，也不代表其後必然成功。`apply_story_transaction()` 必須重新核對當刻狀態；caller 不能拿舊預檢結果跳過檢查。caller 只傳定義，不傳任意錢包餘額或收據資料。

交易結果固定含 `status`、`id`、`applied`、`credits_delta`、`credits_before`、`credits_after`、`message`；拒絕時 `applied=false`、實際delta=0、前後餘額相同。`status` 區分 `applied`、`already_recorded`、`definition_changed`、`missing_requirement`、`excluded`、`insufficient_credits`、`wallet_limit`、`receipt_limit`、`invalid_definition`、`invalid_wallet`、`ledger_locked`、`busy`。唯讀預檢可結算時回 `ready`，仍 `applied=false`、實際delta=0，另給 `planned_delta`／`planned_after`；不能把可結算誤報為已結算。玩家文案是一句可理解的話；診斷另以具體欄位／ID寫log，不把路徑與指紋直接顯示給玩家。

`story_receipt_status()` 回傳 `recorded`／`missing`／`untrusted`，不能把壞帳本回成單純 false 讓 caller 以為未付錢。有效但未知定義的ID仍可回 `recorded`，並附已保存收據的副本；它只證明曾經記錄該ID，不能推定現在的定義金額或故事旗標。壞帳本下未能可靠確認的ID回 `untrusted`。API 返回資料不得是內部可變字典的別名。

純 `validate_snapshot()` 回 `{valid, supported, issues}`，最多一條具體、至多512字元的診斷；不修改 raw、不讀寫磁碟、不修復錢包、不刪除收據、不發 signal。用 caller 提供的 `where` 指出 `run/progression/story_transactions/receipts/<id>/<field>`。這是格式驗證，不查 catalog；有效結果不表示收據與當前定義一致。下游確認已結算時必須用當前定義呼叫 `story_transaction_status()`，同時核對指紋與保存金額，不能只憑 `receipt_status=recorded` 推導可信的款項結果。本 phase 不在 Main／RunSnapshot 呼叫此接口。

## 原子提交與回呼重入

Progression 與 ledger 的內部協作只允許主執行緒，禁止在提交段 await、發 signal 或呼叫外部 Callable。

1. 拒絕正在提交中的巢狀故事交易；核對 ledger 未鎖定與定義合法。
2. 若同ID已有收據：指紋及保存金額都與當前描述相同才回 `already_recorded`；任一不符回 `definition_changed`。即使指紋正確，金額局部損毀也不能稱已結算。兩者都保留舊收據、完全不改錢；預檢與提交共用此判斷。
3. 核對前置／互斥收據與總收據容量，再驗證當刻錢包是0至99,999的有效整數。
4. 計算全額結果；不足或溢出完全拒絕，不部分支付、部分加款或吞餘款。0元事件在錢包上限也可成功。
5. 在無回呼的同步段內寫入收據與新錢包；二者全部完成後才發通知。signal handler 能看到一致的新錢包與該收據。
6. 實際金額非0時發既有 `credits_changed`；0元也發新增 `story_transaction_committed(id)`，供下一個Main owner決定何時保存。提交期間保持重入guard到通知結束；巢狀請求回 `busy`，不再付錢。外層結束後相同ID仍回 `already_recorded`。提交結果預先捕捉本次before／after；即使signal回呼又合法spend，結果仍指本次提交的金額，不拿回呼後餘額改寫。

不使用現有 `add_credits()`／`spend()` 串接兩次通知，因它們在收據寫入前就可能回呼。新增 committed signal 不等於已接上自動保存；本 phase 明示0元事件尚需下游保存接線。普通購物、拾款、死亡、典當沿用既有接口與signal，不受 ledger 鎖定影響。

## 收據快照與容錯

`Progression.snapshot()` 新增 `story_transactions` 子欄位，保留既有 Progression version與其他欄位。ledger 自有版本1：

```json
{
  "version": 1,
  "receipts": {
    "ch1.commission.settled": {
      "definition_fingerprint": "64-character-lowercase-sha256",
      "credits_delta": 720
    }
  }
}
```

| 限制 | 裁定 |
|---|---|
| 收據總量 | 最多1,024；滿時不淘汰舊收據，不允許第1,025次提交 |
| 單張收據 | 只接受上述兩欄；指紋恰為64個小寫十六進位字元、金額為有界整數 |
| ID／版本 | 同定義ID規則；版本必須是有效整數，1支援，其他明確數字版本鎖定 |
| 複製與走訪 | 先用既有 RunSaveCodec.validate_tree 的有限深度／節點／文字限制，通過才複製；不為 raw 自建無界深拷貝 |
| 每影格成本 | 無新增每影格掃描；正常只有提交、明確查詢、snapshot／restore 時處理 |

Progression.restore 先還原並驗證 ledger，再發既有成長signal，避免還原通知的回呼看到上輪收據。reset_run 在通知前清空 ledger 及鎖定狀態；只有明確新輪會解除不可恢復的壞帳本鎖，不提供「清空收據再領」接口。

| 輸入／重玩狀態 | 處理 |
|---|---|
| `story_transactions` 欄位完全缺少 | 舊快照：合法空 ledger；不憑舊旗標補款或補收據 |
| 欄位存在但為 null、字串、錯容器 | fail closed；保留原始欄位，故事交易鎖定 |
| 缺版本、字串／小數／null版本、缺 receipts | 損毀，鎖定；不能當舊快照 |
| 合法但不支援的數字版本 | 鎖定並保留 raw，不把未來版本改寫成空v1 |
| 任一收據格式錯、數量越界、非法ID／指紋／金額 | 整份 ledger 鎖定，不能只刪掉壞項讓同ID再領 |
| 格式有效但定義已不存在 | 收據按原ID保留；不因 catalog 中找不到就移除 |
| 格式有效但當前同ID定義改變，或收據指紋正確但保存金額不符 | 原收據保留；預檢與提交都回 definition_changed，不重領、不補差額、不改錢包；純格式驗證不冒充語義核對 |
| 非持久關卡重試 | 與 Progression 同時回溯：checkpoint前的錢／收據保留，之後的錢／收據一起撤回 |
| 持久世界死亡／回訪 | 錢只按既有死亡規則扣，收據保留；不重發款項 |
| 整輪讀檔／電影入口重播 | 依當次整輪 Progression 還原，不能把入口後暫定收據混進入口快照 |

壞／未知 raw 符合既有 tree 上限時，ledger 保存一份有界防別名副本，snapshot原樣放回，不篩掉證據；不能假稱原檔位元組完全不覆寫，因為普通商店仍可能觸發主流程保存。原始 raw 本身不符合既有 tree 上限時，不深拷貝，鎖定並保留參照僅供拒寫／診斷，snapshot也不能把它替換為可重新領款的空資料；既有 Codec 拒絕該整輪寫入並保留舊磁碟槽。正常正式讀檔早在 Codec就已拒絕這類超限資料，此支涵蓋直接restore的錯誤呼叫。

本 phase 只保證帳本證據不被此服務清空、故事交易不因損毀重發，以及提交本身同步原子；不宣稱整槽prepare拒用、磁碟立即成功、普通購買在壞資料下仍一定可落盤，或對任意外部直接改 `credits`／raw 的程式提供保護。

## 七筆已核定生產用定義，尚未故事接線

下表已經根代理核對ST9的點餐／餐酒承諾／完成時點並核定；對應七份 `.tres` 已建立於 `data/story_transactions/`。本phase沒有呼叫它們的正式故事接線，不把單獨資料定義當作遊戲已扣款或已發720。

| 穩定ID | delta | 必須已有 | 排除已有 | 意義 |
|---|---:|---|---|---|
| `ch1.daily_dinner` | 0 | 無 | 無 | 第一晚日常飯；不補造40收款 |
| `ch1.revival_meal.order` | 0 | 無 | 無 | 玩家確實點了餐與酒，建立該一次帳單；沒有點餐不能立200收據 |
| `ch1.revival_meal.paid` | −200 | order | gift、tab、later_pay | 全額付餐酒；不足時不付、不建paid、不自動欠款 |
| `ch1.revival_meal.gift` | 0 | order | paid、tab、later_pay | 阿梨免收該餐酒；不加200、不建立欠款 |
| `ch1.revival_meal.tab` | 0 | order | paid、gift | 明確選擇記這筆200欠款；不加200，不自動扣別筆收入 |
| `ch1.revival_meal.later_pay` | −200 | order、tab | paid、gift | 之後全額還該一次欠款；保留tab歷史收據，later_pay表示已清 |
| `ch1.commission.settled` | +720 | 無（物品／故事前置由Story owner保證） | 無 | 前章委託800−80的淨款，一章或二章S01只用同ID結算一次 |

表內 abbreviated order／paid等都指同 `ch1.revival_meal.` 前綴的完整ID；實際定義必須寫全名。三個當下結果互斥；later_pay只能在tab之後，不能把tab歷史刪掉或改成paid。720、日常飯、餐酒三件事獨立，tab不自動抵扣720，不扣40，也不與阿梨第二章私人本金或市場M17混帳。沒有order時 paid／gift／tab／later_pay全拒絕，且不創造任何餐酒receipt。

本批不設退款事件，因現資料沒有已扣款證據，而且核定方案gift是在結算前免收。若後續確實要先扣再退，需另一個有前置paid、退額守恆與互斥條件的核定交易，不可把gift改成+200，也不可覆寫已有ID語義。

## 測試與後續接手矩陣

所有新驗證放進已註冊 EconomySuite及自有helper，不改registry／selector、不移入known failures。測試先保留／還原使用到的Progression狀態；已有shop、典當、死亡比例與報表斷言保持原力度。

| 回歸 | 必須觀察的結果 |
|---|---|
| 同一獎勵多次／signal回呼重入 | 只有一次全額加款、只一張收據、訊號時兩者一致；巢狀拒絕，外層後再次為already_recorded |
| 0元order／gift | 不增加信用點、有收據、有提交通知；重播不再通知、不產生退款 |
| 199付200／99,500領720 | 錢與ledger完全不變；改為足額／有容量後才全額成功 |
| paid／gift／tab排列與未點餐 | 互斥結果拒絕；沒有order不建立任何200相關收據 |
| tab→later_pay→再次還款 | 只扣200一次，tab歷史保留；缺款不改狀態；720與40完全獨立 |
| JSON stringify／parse往返 | 整數載成float仍能還原，無小數／有限值規則保持 |
| checkpoint前後交易→還原 | 回到checkpoint後錢與receipt一致；合法再完成一次所得與未回溯路線相同，不額外多錢 |
| reset／舊缺欄位／null壞欄位 | 新輪清空；缺欄位legacyempty；null與錯型鎖定並保留原始證據 |
| 未知ID／指紋漂移／同指紋金額衝突／未知版本 | 不刪去重證據、不自動重領；同指紋但金額不符時status與apply都拒絕、完整快照不變；未知版本不降為空v1 |
| 缺版本／NaN／Inf／bool／小數／巨大容器 | 具體錯誤、有限工作量、fail closed；不先深拷貝再檢查 |
| 鎖定ledger後普通shop／pawn | 既有買補給、典當、贖回仍按原規則運作；snapshot仍保留壞ledger或讓既有Codec拒寫 |
| 1,024張後再領 | 新事件完全拒絕；已有事件仍能判定重複；不刪最早收據 |
| API返回字典／輸入資源被改 | 修改返回值不能改內部證據；已領後換同ID金額回definition_changed |

先寫交易回歸，再按根代理最初NOengine授權實作runtime；取得名額後才執行引擎測試。末次金額衝突回歸已在未修ledger上觀察2項失敗，再以最小補正得到0失敗，且重新跑完原受影響範圍。既有經濟64.19%模型／硬界線保持，不為本phase調整舊報表或斷言。

2026-10-10 CPU核對：`gdtoolkit 4.5.0` 解析上述五份GDScript成功；獨立Python逐檔核對七筆`.tres`的ID唯一／格式、完整依賴ID、金額、paid／gift／tab互斥與later_pay前置成功。引擎回歸另已執行真Progression.snapshot→JSON往返→restore，證明錢包與收據一起回溯；這是服務層實證，尚未以正式故事接線、真Level重試或獨立程序重開驗證新交易。

下游Story owner需要另驗真正choice、skip、取消／死亡、同影格完成、scene_finished前後與程序重開。它必須區分 applied／already_recorded（已結算可接續）、款不足（返回選擇）、壞帳本（告知而不偽造結果），並將物品／旗標的完成與ledger提交時點一起裁定。0元提交訊號接入主流程保存前，此phase不能宣稱單獨order會立即跨程序保留。正式章節未接線時不能勾選NE-231全章經濟或永久招式驗收。


## 本階段實際驗證與凍結證據

原始輸出保留於 `C:/tmp/ne231-evidence/`，以下均為自然退出。最終來源基準為 `a52e57ea47e775f9aefc229eca8f712dc8a0183e`；該基準包含已獨立交付的ST-3廣播fade生命週期修復。較早的 `dc6c` 只先提交證據，不能當作runtime修復基準。本phase未修改radio／DialogueLayer。

| 執行 | 真實結果 | 原始證據（相對上述目錄） |
|---|---|---|
| 首次editor import | exit0；Parse／Compile／SCRIPT／ERROR皆0；產生三份自有UID | `import.log` |
| 首次Economy | exit1、checks0；helper兩個Dictionary索引推導造成Parse Error，修正明確型別後再驗 | `economy-console.log`、`economy/shard_0.log` |
| 修型別後Economy | 181 checks／0 new／0 known，8秒、exit0；SCRIPT／ERROR／出口警告0 | `economy-final-console.log`、`economy-final/shard_0.log` |
| 原3c基準changed、兩worker | 44組、33,603 checks／1 new／0 known，480秒、exit1；SCRIPT ERROR0。失敗為DeathReaction首句立即顯示，不能稱本輪通過 | `changed-console.log`、`changed/shard_0.log`、`changed/shard_1.log` |
| a52 editor refresh與Economy | import exit0、Parse／Compile／SCRIPT／ERROR／WARNING0；Economy181／0／0、8秒、exit0 | `import-a52.log`、`economy-a52-console.log`、`economy-a52/shard_0.log` |
| a52初次changed（尚未補金額衝突） | 44組、33,629／0／0、759秒、exit0；保留為補正前結果，不冒充最終來源驗證 | `changed-a52-console.log`、`changed-a52/shard_0.log`、`changed-a52-diagnostics.json` |
| 同指紋但保存delta719，未修ledger負向 | Economy183／2 new／0 known、18秒、exit1；status與apply的拒絕斷言確實失敗；SCRIPT／ERROR／出口警告0 | `ledger-before-delta-check.gd`、`economy-delta-red-console.log`、`economy-delta-red/shard_0.log` |
| 最小補正後Economy | 183／0／0、8秒、exit0；status與apply均拒絕，wallet／receipt／完整快照不變；SCRIPT／ERROR／出口警告0 | `economy-delta-green-console.log`、`economy-delta-green/shard_0.log`、`economy-delta-diagnostics.json` |
| 最終a52 changed、單worker | **44組、33,631 checks／0 new／0 known、759秒、exit0**；Parse／Compile／SCRIPT ERROR0 | `changed-a52-delta-console.log`、`changed-a52-delta/shard_0.log`、`changed-a52-delta-diagnostics.json` |

最終命令在隔離worktree執行：

```sh
GODOT=C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe SHARDS=1 LOG_DIR=C:/tmp/ne231-evidence/changed-a52-delta tools/run_tests_changed.sh HEAD
```

局部Economy採同一Godot執行檔與 `SHARDS=1`，使用 `tools/run_tests_parallel.sh --only=EconomySuite`，各次使用表內獨立LOG_DIR。editor refresh使用 `--headless --editor --quit`。原changed selector實際挑44組；registry、selector、filters、known_failures均未改，也沒有手動擴成full。末次紅／綠只新增金額衝突回歸並最小修改duplicate判斷，之後整個44組重新跑完。

完整raw仍有ERROR，不能寫成「log無ERROR」。最終按未修改的 `tools/test_filters.sh` 分類：65條故意觸發的fixture ERROR、2條出口ERROR、0條其他ERROR；另有26條交易格式／金額／鎖定等負向fixture WARNING。出口原文記錄6個GodotArea2D RID、7個CanvasItem RID、25個ObjectDB instance，以及13個仍在使用的resource。這些原文完整保留，和0套件失敗、0腳本錯誤分開報告。早期3c失敗的兩shard同樣保留各自出口診斷，不以ST-3後來修好而覆寫失敗紀錄。

`source-a52-delta.json` 記錄15份實際受測來源（五份GDScript、三份自有UID、七份定義）的SHA-256／CRC32及Git LF正規化值；自然退出後逐份核對，`source-a52-delta-postrun.json` 為15／15一致、0 mismatch。本文件在測試完成後只補實證，不更改受測runtime。最終ledger SHA-256為 `e68d99794a1dd35e30bf770b43a0c8f379322ca3fed3d2393c5628e3bcd4f62c`，helper為 `d97530a15b36475c00101d4f53b85ec3f857bb0bf0a3036756e77cb49861fa0e`；完整路徑與雜湊以manifest為準。

交付仍是API／資料phase：沒有新UI，截圖不適用；沒有宣稱主線款項已扣／已領、0元receipt已自動落盤、整章可通關、三類成長或跨章經濟已驗收。下一Story owner仍需依上節矩陣接線並驗真正選擇、取消、死亡、skip與跨程序保存。票的階段紀錄及commit／push由根代理處理。

最新主線整合：在另一台電腦的重裝機槍手修復 `6ea4c6ec8` 上重排本交付，15 份受測來源 LF SHA 不變。重新匯入自然退出 0、0 腳本／引擎 ERROR；補驗 Economy／DeathReaction／RigMesh／RigActions／Posture 五組，3,055 檢查、0 新／已知失敗、48 秒、自然退出 0。這是新素材後的局部整合驗證，不將先前 44 組改稱在新基準執行。原始輸出見 latest-*。
