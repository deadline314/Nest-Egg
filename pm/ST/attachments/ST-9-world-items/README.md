# ST-9 世界劇情道具先保存

真正Main、正式保險箱區資料盤與碰撞來源。真目錄擋住slot.json.tmp，修前無頭12項／4預期失敗，修後不先發盤、旗標或通知；原生同探針修前14／5。最終七個成功原生程序156項／0失敗，含公開重試、放回再進範圍、通知回呼的金錢／已讀變更、另一程序續玩、已提交異動與回滾失敗恢復。中英日文120%與720／1080p合併驗，18張最終原圖逐張看過；八程序皆0引擎／腳本ERROR、0資源洩漏訊息。

原受影響選擇器固定157c5de2，63組65,130項、0新／已知失敗、494秒。原tests、runner、selector、filters、known_failures沒有修改，雜湊核對交付產品與原生／測試凍結來源一致。全套由CI接續，上一版157c5de2完整CI95,989項／0失敗（CI39769993848原始job也在包內）。

[validation.json](validation.json)列全部範圍與各輪結果，[manifest.json](manifest.json)列逐檔SHA256，[raw.zip](raw.zip)有318檔、4,882,991 bytes；SHA256 `5c35a84280c2df16c08ab83947af51fd66cd18c75fb7a51f0780c7d5f21b0984`。已解壓核對全部雜湊。保留work/.gdignore後再匯入，避免比對用的舊class變正式來源。

[Hollow Knight與Ori實際圖片及來源](../../../Nest-Egg/attachments/NE-278-references/)在製作前重看，借用清楚文字與場景層次，不推論對方保存程式。研究圖與本作真畫面分開。

先前找錯倉庫前／後區與存活欄位的探針失敗全部保留；新模組第一輪12項斷言雖過卻有SCRIPT ERROR，拒收。真正area_states鍵是區域id，修正後無腳本錯誤。第一輪原生冷續玩在Transition尚未結束就檢查，圖仍是轉場，保留1失敗；最終等真正操作鎖與轉場釋放。v2收據曾誤讀v1 frozen路徑，原錯誤收據保留；已由當時紀錄的writer SHA與不可變v2原檔校正，driver也改路徑並加相等檢查。

真正reader一直讀v2 writer的同一保存目錄；續玩前slot與v2 frozen SHA皆`e68cd58297dcf82d8b1734277a0a14e6b479a80d5ea9e5002c020096f62788f0`。回滾故障與已提交異動用既有writer測試掛點，真目錄拒寫則是實際檔案系統故障。關鍵物品／世界來源會先一起寫入候選，成功才發布；不建立假的Story完成場景。

Godot4.7.2、Forward+ HDR、llvmpipe軟體Vulkan與Xvfb；明示前提旗標、位置、存活下限1及公開合成輸入，不稱真人整章、實體手把、全章拾取原生驗收或完整故事coordinator。故事原三條整票未勾項保持。截圖另發現世界提示移動途中仍可能蓋人物，屬NE-228接續檢查，沒有當作本票新保存介面全遊戲驗收。
