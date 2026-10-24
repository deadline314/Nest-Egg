# ST-21：閱覽權不等於原盤持有權

交盤受領書中文與日文都有「非原盤持有權」，舊英文省略。現在英文說清M17及付款附件只有閱覽權，並不給予原盤持有權。保留碼頭保險箱資料盤委託、實體驗收與委託方保管原盤、800信用點次晨核對、老K既約10%、凜預計720淨額尚未入帳。只改此份英文body；中文／日文／其餘道具／描述及金額政策不變。

[設計](../../../../design/20-campaign-experience/DISK_VIEWING_RIGHTS.md)、[原檔](raw.zip)、[逐檔SHA](manifest.json)、[收據](validation.json)。先讀User-guide，對照正式中文與日文；沿用[全文閱讀的Hollow Knight／Ghost Song圖片研究](../../../Nest-Egg/attachments/NE-228-full-text/README.md)，沒有新網頁擷取／民調，圖片不能證明本作權利或帳務事實。

| 驗證 | 結果 |
|---|---|
| 原Collectibles加一項限制控制 | 306／1失敗→306／0 |
| 最新3c99d3ef上原選擇器三組 | 757項／0新／已知失敗，19秒；原高度契約也通過 |
| 同配置真正Forward+修前／修後 | 各64／0，退出0，0引擎ERROR／洩漏 |

原Collectibles整份未改；既有M17兩項控制去掉唯一新加的受領書檢查後逐位元相同。原runner／selector／filters／known failures保持。Headless原故障診斷依原filters保留，無SCRIPT ERROR，不稱headless無ERROR。正式負控制在1fd1bf2e；其譯文與3c99d3ef逐位元一致，沒有冒稱整份checkout相同。最終回歸與兩輪原生均在3c99d3ef來源上執行。

真正1280×720 EN120平滑，正式InventoryScreen／StoryItemsPage、實際PAUSABLE關卡與明示取得／選取fixture。原NE-228 probe只把第一個資料id由M17換成交盤受領書，其餘判斷保持；UI原生仍驗實際完整body、焦點、同選取返回、世界暫停、合成手把、旗標／金錢不變及人工長文可捲到底。原生修前64／0只證明舊文可正確顯示，不證明舊文語義完整；缺漏由新增限制控制306／1抓到。

兩輪16張PNG保留；本輪只逐張檢視兩張受領書全文圖，不冒稱其餘14張重新視覺驗收。不是自然取得、真正Main保存／續玩、真人或硬體手把驗收，不代勾整章或全部三語文義。上一票3c99d3ef完整CI推送後另核對。

ZIP 48項原檔，SHA `b0ad1a88e741eda9ff49314a56671b3bdd62224be8946007e3992f728b5919c2`。
