# ST-3：正式條件入口的結構拒絕

原正式入口在not下把未知條件反轉成true，any的前支成立時也略過後面的壞格式。現在先完整核對有界格式，再沿原路讀取事實及求值；壞條件回false並指出巢狀位置，不讀facts、不改旗標／物品／錢包／進度。合法條件、空條件、預設比較、呼叫端候選facts及各章原收據名稱保留。

## 原始結果與重算

`original/`保留隔離驗證者的原交付，內含實際兩檔LF來源與原raw ZIP。其README的「未採C」是隔離階段界線；本次主協調的`source-adoption.json`記錄已採用同一核心程式及測試追加段。主要工作區原有NPC測試修改保留；Git只發布純受測測試檔。外層`.gdignore`防止證據中的同名來源被引擎當成第二份正式類別。

```powershell
python -X utf8 pm/ST/attachments/ST-3-condition-boundary-2026-11-12/original/verify.py
```

不用引擎、GPU、來源工作樹或網路；原件SHA／CRC、真正13項／6失敗、最終74／0、正式524條件×10種facts的5,240／0，以及原受影響22組／45,500項／0新／0已知失敗均會核對。原入口腳本exit0、13157份來源前後相同；原兩個runner、filter及known failures保留，沒有虛構各child退出收據。

原filter允許的退出診斷全部保留，這不是0ERROR或0leak：分片0有AreaRID／CanvasItem／ObjectDB／resource訊息，分片1有CanvasItem／ObjectDB／resource訊息。0SCRIPT與局部74項通過不代稱全套嚴格零洩漏。最初重疊import造成的資源錯誤回合仍列無效；正式原紅在獨立順序匯入後重跑，沒有把快取錯誤當產品反例。

## 驗收界線

這次只修執行期結構邊界，不把純框架第一章七ID政策直接套入正式三章。facts回null的既有預設比較保留，直接寫equals:null仍按設計拒絕。未知名稱／損毀帳本的值級接線、有限耐久來源與資料擴充仍各需驗證，ST-3維持進行中。

`original-audit/`是固定dbbafd79的九條只讀審查及原歷史封包核對；不是本次新引擎執行，也不是後續條件修正後的全部世界狀態證明。其死亡1/2/3測試fixture與正式1/3/5配置、正式灰布與舊茶杯指示、已接正式入口與框架分開記錄。新增來源的授權與保存邊界不可為方便而放寬。
