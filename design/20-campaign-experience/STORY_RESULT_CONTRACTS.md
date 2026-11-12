# ST-3：正式內容契約 catalog

**選擇：在 `StoryResultSources` 資料查詢處放 Seam，以 catalog Module 資料化既有 NPC results／choices／可逆 intent；Main 保留真來源與保存授權。** 不新增 plugin／callback／`atomic_v1`。2026-11-12 設計確認，來源固定 published `5a363c4e`；以下是實作與驗收要求，不是已完成聲明。

## 1．兩個小 Interface；選 B

| 方案 | Interface／代價 |
|---|---|
| A：直接資料查表 | `record(id) -> Dictionary`，沿用 `owns/npc_source/boundary` 各自讀表。改動少，但 `{}` 混合不存在與載入失敗；caller 各自處理分類、跨段與 mutation，Depth 低且易落回 legacy。 |
| **B：載入快照＋內容匹配** | `reload()`（僅 loader 的生命週期）；`inspect(id, scenes, sources)` 回 `MATCH / NOT_OWNED / REFUSED`、具體 path/error，以及內部唯讀契約的受控視圖。Module 一次處理 schema、完整圖路由、獨立預期與當前 scene 比較。caller 不處理檔案／章節合併。**採 B。** |

保留現有 `Sources.choice/boundary/continuation/npc_source/authored_source` 作相容 Facade，保留既有驗證 Implementation，先換資料來源。結果 owner 的 `choose:40`／`complete:130` 必須先處理 `REFUSED`，不得用空 Dictionary 推斷 unowned。`inspect` 的 MATCH 只證明「目前載入內容符合正式契約」，**不是**可以寫入的許可；Main 仍須做原實體檢查。測試跨同一 Interface，不設模式或 adapter registry。

載體選既有 `JSON Resource + Dictionary/Array`，供 Python 作者共讀，不新增巢狀 `.tres` 型別。現有 `ResourceCatalog.load_dir:9` 不可直接當成功判據：它會跳過缺檔／錯型，且 `validate()` 記錯後仍 append（:25–37）。catalog 必須整份驗證成功才發布快照。

## 2．資料、搬移與呼叫端

固定入口 `res://data/story_contracts/catalog.json` 宣告 schema version、正式 story source 與章節契約檔；各章以 **records Array** 收錄唯一 scene ID、source、原 NPC resource／允許 Level、role、精確 policy／when／results／then／failures，或 choice 的 default／ordered options／intent／waits。契約獨立受審，compiler 只讀；不把待執行 scene 的 results 自動複製成授權。

| 目前位置 | 最小搬移／保持 |
|---|---|
| `story_result_sources.gd:11–230` | 搬 NPC 相關三表、人物與 source 對應的值；保留 policies、route64、匹配演算法。 |
| `story_result_ch2.gd:3`、`story_result_supper.gd:3/9/145` | 搬 NPC／boundaries／choices 值。餐費仍只引用 canonical transaction ID，不加金額 override。 |
| `ch1_runtime_backend.py:248–269`、`chapter_compiler.py:211` | catalog rows 的政策由契約生成／比對；保留 home／clinic 專屬邏輯。`ch1_closure.py:878` 的三個 intent ID 改為與該 choice 契約的精確 flags／值比對，仍禁止 transaction／交物充當 intent。 |
| `StoryResultCompletion`／`Story.load_all:223` | owner 新增三態拒絕／generation；loader 明確 reload。刪除無 caller 的 `const NPC_SOURCES := Sources.NPC_SOURCES` (:15)，不另維護快取別名。 |
| `Sources` 直接 caller／測試 | production 呼叫在 `story_result_completion.gd:43/58/136/151/202/329/394`；原 Ali／Voice／Supper／Prologue／Clinic source checks、`story_contract_audit`、`supper_completion` 保留。直接迭代舊 const 的測試移至**獨立原預期 fixture**，不可改成只迭代新 catalog 自證。 |

只搬既有 NPC owner rows，逐筆核遷移去向。自動 dinner `SEGMENTS`、clinic death episode、FlagSources home／recording、世界拾取與真櫃目的地檢查仍用原 Adapter。新世界／診間／目的地能力仍需 code；transfer 只可沿原櫃能力。

**JSON 型別：** exact keys／ID／路徑、原 tree／route 上限；跨檔重複 ID 拒絕。version、索引用現有 `StoryTransactionData.integer_in:33` 的有限且整數條件正規化，接受 JSON 的 `1.0`，拒絕 `1.5`、bool／NaN／INF；wait 保持有限小數與原值比較，不取整、不加 epsilon。flag／intent 不把 bool、字串或數字互轉。現有 Sources `_value_equals:248` 只接受 bool／字串預期，因此本次新增例限定 boolean／既有 enum；不得藉換 JSON 默默擴張數值旗標的正式 owner 能力。錢額只由 `StoryTransactionData.descriptor` 決定。

## 3．readonly cache、重載與失敗

載入深複本、驗證後唯讀封裝，不向 caller 暴露共享 `JSON.data`／cache Dictionary。相容 accessor 僅在完成操作時回小份副本，無每幀深拷貝。只 cache 正式**預期**；inspect 仍比對當前 scenes／sources 與全關聯圖，同 identity／path 不代表未被 RAM 改動。 僅鎖原效果欄位與步驟文法；台詞／選項顯示文字沿原翻譯規則，不以整 scene SHA 取代來源證明。

`Story.load_all` 先失效舊 generation、讀取新實體內容、驗證後一次發布；可沿現有 `AudioData.read_root(... fresh)` 的 cache-replace 慣例（`audio_data.gd:15`）。公開 `load_chapter` 改變已收下的 scene 時也使匹配失效；不登記被拒 duplicate。reload 若遇尚未退休 owner，先拒絕新提交／安全取消，不把待重試候選換到新契約；舊 generation 到 commit 前須拒絕重建。generation 穩定不代替 live state／ledger／來源檢查。

缺 root／子檔、壞 schema、重複／缺 route、循環、錯 source，**保留 REFUSED 狀態，記 catalog 檔＋record index＋欄位，按 generation 去重**。壞目錄不能被替換成空的「載入成功」或退用舊快照重試。real Main 遇本 Module REFUSED 回 `handled=true,ready=false`，不進 `Story.apply_choice:1340`／`_apply_scene_results:332` legacy 寫入；明確仍由其他既有 owner 承接者保留原准入。

目錄有效但 ID 未登記時，NOT_OWNED 只允許已盤點的純呈現／其他 owner 路徑；對 manifest 所管理 story source 的新 results／intent／保存政策卻無契約者，必須 REFUSED。啟用 coverage 前逐一盤點章節寫入入口與 owner，避免誤拒未搬的合法段落。coverage 不從 scene policy 反推；缺檔失去 ID 清單也不能放行 legacy 副作用。未知新政策與跨 owner 重名也拒絕。

**原保存責任不搬：** Main 的原 persistent Level、原 layout spawn、actor instance／NPC resource／talk index／request（completion:195–223/328–344）；道具原件 custody、已交付不復生、transaction descriptors／當前 ledger／locked（v4 outcomes:238）；完整快照、真寫入、無回呼安裝、再發布（completion:278–315）。不相信作者 `source_binding` 或 policy 自報一個現實不存在的來源。

## 4．可驗收的 data-only 例與拒絕矩陣

同一現有巡邏員、原市場入口實體 spawn、無 NPC 自帶獎勵：只改作者宣告／catalog／NPC talk／合法資源並重產 JSON，不改 Module／owner。

1. `ch2_t_patrol_note_ack`：完成後只寫新已宣告 bool `ch2_patrol_note_seen=true`。
2. `ch2_t_patrol_copy`：完成後取得新 `Trigger.MANUAL` 物品 `ch2_patrol_copy` 並記旗標；不加自動 SCENE_FINISHED trigger、不借世界原件或診間布。
3. `ch2_t_patrol_copy_prompt`：accept 保存新可逆 bool intent 並連到例 2；later 無結果且為 default。兩段登記同 NPC／Level／source，保留原 2–4 選項與 route64 限制。

正控需真 Main 完成、選項與實際 talk_count 同次保存、拒寫不發布、重試只一次、冷讀不重發；data-only diff 不含 `.gd`／compiler 演算法。負控沿原 source checks：改遠端 terminal 結果／順序／typed flags、foreign source、cycle、未註冊 wait／material default 均仍拒絕；另測缺檔／壞 schema 後不 legacy 提交、RAM 改 scene 立即拒絕、caller 改回傳資料無法污染 cache、reload 後舊 request 拒絕。複製 actor、錯 Level／talk index、舊請求、假 policy、壞帳本與已交原件仍由原 owner 拒絕。

## 5．實作範圍與生命週期限制

先資料化既有 NPC 結果、選項與意圖能力，不重做 Main 保存、診間、世界取得、交接櫃或玩家操作框架。保留原相容 Facade，只有一個 catalog Module 隱藏讀檔、schema 與內容匹配；測試保留獨立原預期，不從新 catalog 產生自己的正確答案。

優先沿用既有演出取消、request 與重載機制；只 cache 契約預期，不 cache live scene 是否符合。無關章節的公開載入不應單憑呼叫次數取消合法演出。若真正重載契約會讓已準備的提交跨版本，須由最小 revision 或既有 request 失效機制拒絕；不為假設的熱重載另造全域事件框架。

資料新增驗收使用明示的測試內容 overlay 與真 Main／原實體來源，不把額外巡邏員支線或道具混入正式故事。新增例的最後 diff 只含作者／契約／合法內容資源，不含 engine 或 compiler 演算法。缺檔、壞 schema 與改 live 內容的拒絕案例必須先建立，再實作；原負向斷言與保存拒絕、取消、冷讀流程保留。

## 6．交付結果（2026-11-13）

以上第 1–5 節保留 2026-11-12 實作前設計，行號僅屬當時來源。最終 facade 使用 `reload_catalog()`，避免撞上原生 Script 方法。只快取唯讀預期；真內容每次匹配，真正重載才使舊請求失效，無關章節載入不取消合法演出。公開載入保留任務目錄的失效處理。

已將 48 筆既有 NPC 邊界／選項搬入正式契約，原 30 筆 legacy 效果與入口另有固定遷移投影。新 NPC 效果／意圖須有獨立契約；未知 Binding、缺失實體入口或錯 NPC 資源均拒絕。未 Binding 且不在已知 NPC 入口的通用演出不以名字、speaker 或 policy 猜來源；執行時真實 owner 始終保有准入權。被動接續沿請求保留經驗證的 context，不以自報政策授權。

三個 data-only 例已在真 Main／原 NPC／原 writer 驗證，13／0、21／0、12／0；正式三章逐 byte 不變，範例只存在 fixtures。真拒寫、修復後重試、取消、新程序冷讀與來源重載亦通過。JSON Resource remap 的真 PCK 讀取 10／0，僅驗該讀取邊界。

兩次原受影響 61 組各 63,316／0；最終兩個純 Python 作者檔晚於第二次長測，原選測 0 Godot 組，另跑作者 18／0、政策 6／0 及三章產生比較。完整作者 40 項仍保留原 StageWeather 三項基線失敗。沒有宣稱最終 50 檔都在同一長測 epoch，也不代稱原生畫面、真人通關或效能驗收。

正式原件與可攜 reader：`pm/ST/attachments/ST-3-data-contracts-2026-11-13/`。
