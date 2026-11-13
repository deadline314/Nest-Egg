# v8 拓樸與遷移摘要（CPU 資料）

| 區域 | 幾何與主路線 | 能力返訪／回環 |
|---|---|---|
| street 208×56 | 主線由 foot51 上到31、落到51、再跨36；實牆強迫上下層移動 | 高處 credit (100,23)，market foot31；維修道 foot15 |
| warehouse 166×56 | 保留 watchdog→三階水位→深處；貨運階梯45/41/37/33/29/25/21/17，出口 foot16 | 不以新能力繞過首次水位／診間流程 |
| vault 124×56 | ground49→階梯45/41/37/33→資料盤 foot28，再至 foot12 | 安全練習 foot20→12；失手落回原台階／地板，敵人保持真啟用 |
| rooftop 72×56 | 原 Egret (54,49)；階梯45/40/35/32 | 維修道 portal (66,31) 接回 street |

四個主要區 `layout_revision:2`，舊 cell 平移 `[0,32]`，個別 override 明列 `legacy_layout.cells`。七個原安全區仍 height24、座標不變。246 舊記錄逐筆對應在 `source-v8/mapping-actual-v8.json`；八個不持久化的退休 arena gate glyph 明標未再佈置，真 encounter／敵人／增援未刪除。相同舊 cell 不拆成相互衝突的新 key。

`vault (116,12) ↔ street (122,15)`、`street (46,15) ↔ roof (66,31)` 四端都真要求 `ledger_disk_obtained`。late 檢查仍從本區 P 出發，不用互相 portal seed 自證孤島可達；普通目標維持原5格模型。warehouse／vault row0..3 頂板恢復原室內 covered-column 分類。

作者真 Binding／QUEST_LOCATIONS 對齊實際 completion owner。139 scenes／10 quests 與原版僅7個 location scalar 差異，沒有改 effects／transaction／source／catalog 權限。存檔 runtime 遷移由 NE297 獨立負責，本文只有作者 mapping，不代稱新 Main 冷讀或正式聯集已驗。
