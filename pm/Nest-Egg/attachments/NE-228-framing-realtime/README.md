# NE-228：真正時間與短距離遮幅返回

基準`96f602e8`完整[CI 39753116995](https://github.com/deadline314/Nest-Egg/actions/runs/39753116995)仍95,970項、1新失敗、489秒。前次只換物理更新階段不足，歷史本機通過不代表遠端已綠。

同一原helper、原0.48秒，高更新率上限120fps重播260／2；只加暫時追蹤的另次260／4。四次從goal設0已真正經過0.370–0.394秒，Tween只累積0.251–0.273秒。來源、鎖、演出皆清。這是觀測，不推定引擎內部根因；追蹤未留在正式程式。

沿用Sine曲線，以單調時間和custom_step手動推進，停用自動推進避免重複。完整開合仍0.28秒；短行程返回0按剩餘距離縮時。只換真正時間的中途版高更新率260／0、兩組1496／0，但間歇負載260／3，完整保留後再驗最終組合。

| 最終範圍 | 結果 |
|---|---|
| 原helper高更新率／間歇負載各20次 | 各260／0，原等待與判定保持 |
| 原選擇器NPC、介面兩組 | 1496項、0新／已知失敗、51秒 |
| 真CI前置NewEnemies→UiKit→UiScreens | 571／0 |
| 新增慢動作公開scope開合兩項 | 同測試換回舊正式程式，兩項均如預期失敗 |
| 正式Main一般／1080p120%字／減動態 | 60／0，三程序exit0、0引擎ERROR／洩漏警告；12張圖逐張看過 |

原tests由移除新增方法／呼叫及一個失敗診斷欄位可逐位元重建；原selector、runner、filter、known failures未改。原helper重播回收警告保留，不聲稱引擎乾淨；前票獨立舊關卡原生退出250仍未定位，未從CI移除。

原生真正Main、安排換區／玩家位置，再公開移動、互動與確認，無旗標注入。120fps是上限，非固定實測幀率。軟體Vulkan Forward+ HDR不代稱實體硬體或人工全章。圖中大型世界氣泡仍在，這批不能當整體構圖或角色拼接驗收。

[設計與Godot／W3C官方依據](../../../../design/20-campaign-experience/FRAMING_REALTIME.md)。沿用本輪已看的Hollow Knight、Blasphemous、Celeste、Hades、Cyberpunk 2077五作實圖；不由靜態圖推定更新機制。

[原始包](raw.zip)、[逐檔SHA](manifest.json)、[收據](validation.json)：93項、7,919,056 bytes，ZIP SHA256 `02257c22b7e131754478151e65cf24cefe4dc7cc56390048ebf2643ee0ed3f89`，逐檔回讀通過。含修前／最終／中途／追蹤來源、全部日誌、前次CI原文及artifact、三組原生圖與存檔、負控制、探針與五作來源。依包內路徑解回專案，使用work/ne228-reverse/matrix.py重播Main；final-changed.log記原選擇器結果。新完整CI待推送後核對。
