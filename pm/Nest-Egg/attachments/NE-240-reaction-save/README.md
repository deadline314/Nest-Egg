# NE-240：既有一次性反應的整輪保存

2026-10-21（Asia/Taipei）。只修正既有可選 once 反應的保存契約；正式角色資料目前沒有 once=true，因此不改任何正式角色的反應次數、動畫、美術或獎勵。整票保持進行中、三項驗收保持未勾。

## 實際證據

[validation.json](validation.json) 記固定 ddbb6248 基準、原 tools/run_tests_changed.sh 的完整受影響結果，原斷言、選擇器、filter、known failures 不變。原 RunSaveSuite 增加15項檢查；原核心控制550檢查／8預期失敗，候選550／0。控制finally精確還原receipt及來源SHA已封存。原測試含故意壞資料與既有引擎清理診斷，不宣稱全部log零ERROR；SCRIPT ERROR依原runner必須失敗。

另兩個真正獨立程序：writer2／0，reader9／0。明示 fixture 建立實際 NpcActor／NpcAwareness 狀態，四處 world（runtime、當前area、checkpoint、persistent area）經實際 RunSaveStore／RunSnapshot 保存後，新程序交給真 NPC restore_state，核對 talks=3、claimed=[1]、reacted=[0]，既有 pick_reaction 對已做過的 once fixture 回-1。這不是自然通關或正式角色新增一次性招呼，也沒有用手動啟用的 fixture 冒充正式內容。純保存修正沒有新畫面，不套用舊截圖作本次證據。

## 連續性核對

- [x] 原資料已捕捉 reacted；整輪清洗漏欄位已修復，所有四處經同一清洗規則。
- [x] 舊NPC紀錄缺 reacted 保持原可選結構；錯誤型別、負值、非整數、bool、字串、重複、過量均測；合法JSON整數浮點可接續。
- [x] 保存只處理資料，不發手勢、物品、金錢、旗標或完成通知；原 talks／claimed 保持。
- [x] 新程序讀回後實際owner保有一次性資格記憶。
- 死亡扣款、場景切換、文字與輸入不改；原受影響的死亡／遭遇／介面／地圖套件仍由原選擇器執行。本次未新增人工控制或實體裝置證據。

研究沿用本輪先實看 [五款作品原圖與來源](../NE-278-references/sources.json) 以及 [Hades官方更新](https://www.supergiantgames.com/blog/hades-updates/) 的對話資格／順序修補。只採前後資訊一致的檢查原則，不推論對方內部存檔結構。設計：[NPC保存邊界](../../../../design/20-campaign-experience/NPC_REACTION_SAVE.md)。raw.zip逐檔回讀核對bytes／SHA256；準確來源、前後測、隔離槽與重播探針一併保留。
