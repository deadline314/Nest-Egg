# 純敘事條件樹契約

此階段只交付 `core/story_condition_tree.gd` 的唯讀驗證與求值，以及既有 `StoryContentSuite` 的回歸案例。尚未接入 `StoryRules`、`Story`、選項 UI、場景前置條件、存讀檔或正式故事產生器。不是十項 production backend capabilities 的完成聲明，也不是第一章完整交付。

## 來源與既有行為

- 作者來源：`tools/story/ch1_closure.py` 的 `flag`、`item`、`receipt`、`account`、`all_of`、`any_of`、`negate` 與 `ACCOUNT_RECEIPTS`。讀取位置為 `C:/tmp/Nest-Egg-ch1-formal-story`；不改作者來源或正式 JSON。
- 帳務來源：NE-231 的 `StoryTransactionData.descriptor()`、`StoryTransactionLedger.snapshot()` 與七份 `data/story_transactions/ch1_*.tres`。帳務框架已於 `d68ddb79a` 合入 main；目前整合基線是 `ea48f8c6e`，使用本工作樹正式資源。已移除的交易工作樹不是依賴。正式資源是唯一金額與指紋來源；條件器只保存受支援 ID 與作者的六組餐費集合，不保存另一份金額、指紋或帳务狀態。
- 舊 `StoryRules.eligible()` 的 `requires_flag`／`unless_flag`／`requires_item` 不變。新的 `{item: id}` 必須表示「現在仍持有」，不能由取得歷史旗標代替。資料盤交付後即使 `ledger_disk_obtained=true`，新 item predicate 仍應為 false。未接 adapter 前，不以新條件替換舊欄位。
- 讀過 `continuity-qa`、`chapter-design` 及 `DIALOGUE_READABILITY.md`。本變更不含玩家台詞或章節編排；不能以 fixtures 代稱正式章節、真人遊玩或畫面驗收。

## API 與條件格式

`StoryConditionTree.validate(condition)` 驗證 schema；成功回傳 `{valid:true,value:true,error:""}`。`evaluate(condition, facts, context={})` 回傳 `{valid:bool,value:bool,error:String}`。無效時固定 `value=false`，error 含條件或資料 path，最多 512 字元。呼叫端必須先看 valid；不得反轉無效結果以取得 eligibility。

| 格式 | 意義 |
|---|---|
| `{}` | 作者無前置條件；為 true |
| `{"all":[...]}`／`{"any":[...]}` | 非空子條件清單；完整驗證 schema 並求值所有可驗的分支 |
| `{"not":condition}` | 只反轉有效值；not(invalid) 仍 invalid |
| `{"flag":id,"equals":scalar}` | 與已宣告的可信事實精確比較；bool、String 與 numeric 不互相強轉；int／float 數值可以相等 |
| `{"item":id}` | 已宣告道具的當前 holds bool |
| `{"receipt":id,"status":"recorded"}` | 經當前定義核對的收據是否存在 |
| `{"account":"ch1_lounge","equals":state}` | 由 exact meal receipt subset 求得 state |

只接受上述 exact keys；額外欄位、未知 op、空 all／any、不支援的 receipt／account／status、Array 或物件 scalar 均 invalid。作者目前實際的 flag equals 為 bool 與 String（包含 `ch1_supper_choice="unset"`）；保留有界 finite numeric 作共用事實型別，不允許 null、NaN、INF 或 StringName 偷渡 scalar。ID 為 1–64 個字元，首字為小寫英文，其餘只允許小寫英文、數字、底線與句點；StringName key／ID 別名也不接受，adapter 應輸出 plain String。

缺少已宣告的 flag／item 不是 false，而是 invalid。後續 adapter 需以 producer／item registry 宣告全集，把已知未完成旗標與已知未持有道具補為 false，把 string flag 的正式 default 補入（目前作者 `ch1_supper_choice="unset"`）。不能對拼錯或未登記的名稱自動补 false，否則 not 會讓錯誤資料取得資格。

## 可信資料的責任

facts 只允許 `flags`、`items`、`ledger`；context 只允許 `ledger_locked`、`transaction_definitions`。不需要 ledger 的條件可只傳旗標／道具事實；receipt／account 需要完整下列資料。

```text
facts.flags = {plain_string_id: bool / finite bounded number / bounded String}
facts.items = {plain_string_id: current_holds_bool}
facts.ledger = {version: 1, receipts: {id: {definition_fingerprint: sha256, credits_delta: integer}}}
context.ledger_locked = actual_ledger_locked_bool
context.transaction_definitions = {canonical_id: current_resource.descriptor()}
```

context 只能由實際 service／正式 resource loader 產生。`ledger_locked=false` 是 owner 快照的一個欄位，不是任意人寫下的「trusted」認證；必須同時提供帳本證據與七份當前 descriptor。純函式無法證明呼叫者的來源，所以 adapter ownership、loader path 與 snapshot 同時性仍待整合驗收。禁止把任意 boolean trusted、舊旗標 `paid200` 或 `account` 文字映射成真實證據。

七個支援 ID：`ch1.daily_dinner`、`ch1.commission.settled`、`ch1.revival_meal.order`、`ch1.revival_meal.paid`、`ch1.revival_meal.tab`、`ch1.revival_meal.gift`、`ch1.revival_meal.later_pay`。加入其他章節 ID 必須明確擴充契約；本階段遇到未知收據不得略過。

每份 descriptor 必須恰有 `id`、`credits_delta`、`required`、`excluded`、`fingerprint`，id 與外層 canonical key 一致；delta 是 ±99999 內整數；依賴與排斥為有界、已排序、已支援、無重複、無自我引用且不交疊的 String Array。以 NE-231 v1 的 `[id,1,delta,required,excluded]` 重算 descriptor fingerprint，驗其自洽，再將每張既有收據的 fingerprint **與 delta** 比較當前 descriptor。條件器不硬寫任何交易金額或另一份 fingerprint。

有既有收據且正式資源定義改變時 invalid，哪怕把 not 放外層、另一支 any 已 true、或另一支 all 已 false；前置收據缺漏與排斥收據並存也 invalid。鎖定、未知版本、malformed、untrusted 欄位／別名、未知收據均不能變成 none。若帳本是可信空帳本且七份當前 descriptor 都完整合法，none 可求值；沒有既有收據時不能捏造「定義漂移」。

## exact meal subset

根代理另加入公開 `verify_ledger(facts, context)`，使用與 evaluate 相同的嚴格 facts／context 驗證後，驗整份當前帳本。即使場景入口沒有帳務條件，整段結果預演也可使用這個唯讀契約；不需呼叫 private 方法或構造必真的 account 條件。回傳成功時的 account 仍只是局部投影，不能另存帳目。公開入口測試另驗 malformed、locked、回傳 alias 與不改輸入。

以下只列五個 `ch1.revival_meal.*` ID 後綴；dinner／commission 收據仍驗真，但不進餐費子集。

| state | 唯一允許的 exact recorded sets |
|---|---|
| none | 空集合 |
| open200 | order |
| paid200 | order + paid，或 order + tab + later_pay |
| owed200 | order + tab |
| gifted200 | order + gift |

五收據的 32 子集必須恰有 6 組合法、26 組 invalid。沒有可儲存的 account 值，僅一次呼叫內局部 cache 避免重複驗帳。

## 邊界與副作用

根節點深度為 1；深度 ≤16、節點總數 ≤256、每個 all／any ≤32 子節點。重複引用同一合法 Dictionary 可以求值，各 occurrence 分別計數；自我循環最多到深度上限便 invalid，不用先做遞迴 duplicate。旗標／道具字典各 ≤1024 entries，String scalar ≤256 字元，numeric 絕對值 ≤999999999；帳本沿 NE-231 的 ≤1024 receipts 上限，受支援 ID 集合另限制此階段種類。條件不接受任意 Callable、Object 或 Resource。

RefCounted 只使用 pure static API：無 autoload、signals、保存、推送 warning、檔案讀取或服務寫入。輸入不排序、不 duplicate、不 normalize；只排序／重算 descriptor 的責任屬資源 owner，此 evaluator 驗已排序的資料。方法內 budget/cache 與回傳 Dictionary 不與輸入共用可寫結構。

## 驗收與待接手

既有 `tests/suite/test_story_content.gd` / `StoryContentSuite` 已有 smoke registry，本變更不改 registry。新增案例從七份正式資源取得 descriptor，涵蓋全部 32 餐費子集、七份既有收據與 current definition 漂移、空帳本與合法當前定義、not 壞收據、boolean 分支不藏 schema／fact 錯誤、型別、缺漏、深度／節點／子數／ID 邊界、cycle、共享 child alias、context 別名與無突變。

CPU `gdparse` 僅確認 GDScript grammar；獨立 Python 讀取作者與七份 resource 做子集／ID／依賴集合對照，不能代稱引擎执行。本分工不啟動 Godot。主代理接手後，須先整合 NE-231 正式資源與 classes，再跑受影響 `StoryContentSuite` 及 `tools/run_tests_changed.sh`，解 semantic／runtime 錯誤後才能稱程式通過；未接線前不要把 `canonical_account_predicates_v1` 或其他 production capabilities 宣告為已提供。

## 根代理引擎驗證（2026-10-10）

先整合 d68ddb79a 的交易框架與七份資源。首次 headless editor 匯入自然退出0且沒有腳本診斷，但實際 StoryContentSuite 載入捕捉到布林迴圈區域變數無法推斷型別；該次852項／0斷言失敗仍判定失敗，原 runner 退出1，完整紀錄保留。修正為明確 bool 宣告後重新匯入及原 changed selector：StoryContentSuite1133項、0新增／已知失敗，自然退出0，無SCRIPT／Parse／Compile或ERROR。

再 rebase 至 ea48f8c6e 的已驗證物品交付服務，重新匯入自然退出0並驗 StoryContentSuite／CollectiblesSuite／RunSaveSuite：1512項、0新增／已知失敗，14秒，原 runner 自然退出0；原始輸出沒有 SCRIPT／Parse／Compile或ERROR。既有負向存檔測試的警告保持可見。此為底層介面相容驗證，沒有安裝正式場景或全輪遊測的宣稱；本階段不新增可見遊戲畫面。
