# NE-228：當舖標題與長詳情

父代理曾將縮小預覽中的折行誤判為數值欄裁字；同幀字格與原圖放大已證偽，沒有因此修改產品。兩份原生補證各28狀態，另外驗證典當／贖回數值；不計入原252格矩陣，也不宣稱新增完整42格配置。

120%文字下，正式當舖標題與分頁重疊，典當／贖回詳情及確認動作越過固定頁尾。現在標題按真正尺寸留間距；長詳情在有界區域閱讀，確認動作固定在頁尾上方。保留原文、價格、字級、交易規則及正常動畫。只有兩份共用UI產品與兩份永久測試變更，精確bytes見`index.json`的`candidate_files`。

## 可獨立核對的結果

| 證據 | 實際結果 |
|---|---|
| 隔離、冷程序、原兩產品＋最終新兩測試 | UiScreens 513 checks／3 failures，Godot exit1，沒有SCRIPT ERROR；三個失敗為標題相交、詳情／動作越界、缺有界閱讀區 |
| 原受影響入口 | 基準6e47e2fe＋四候選，SHARDS=2，12組6,527 checks，0新／0已知失敗，307秒、exit0 |
| 本機原UiScreens＋Collectibles | 519＋306＝825／0；長文原始內容高度、全文、價格、聚焦及公開閱讀輸入均通過 |
| 原生真原版 | 同一醫療針／ShopData，42狀態／8版面失敗、exit1；四處標題相交，典當及贖回各有詳情、動作越界 |
| 最終原生平滑字型 | 五配置各42狀態、合計210／0；另五張實際PgDn末行原圖，PgUp回到起點 |
| 最終原生像素字型 | 1080p／120%單組42／0，另末行原圖；未擴稱完整五配置像素矩陣 |
| 原公開controller-capture CLI | 720p／100%與1080p／120%，各38／0，28原圖；真Main→難度→序章→背包／暫停／任務／兩地圖／設定／取消→返回遊戲 |

正式12組為AmmoIconsSuite、CollectiblesSuite、DevMenuSuite、EconomySuite、FxUpgradesSuite、MeleeWeaponsSuite、ProgressionSuite、ReadabilityTargetsSuite、SupplySuite、UiKitSuite、UiScreensSuite及main。原入口、selector、filters與known-failures皆保存，未縮選或放寬。14,479份受記錄來源before/after相同，原16份NE256／NE266私有檔亦逐份保持；這不是聲稱整棵工作樹只有四個dirty檔。原始shard0保留CanvasItem／ObjectDB／resources-still-in-use退出診斷，原filters有既有退出相容規則；所有shard無SCRIPT ERROR。獨立原生程序則無ERROR或退出洩漏診斷。

513→519的檢查數差異是六個依閱讀區存在才執行的輸入／導引／同層閱讀頁檢查。原冷紅及候選使用同一最終helper，不能把它寫成「同513項全綠」。本機第一版候選8格動畫幾何失敗與runtime-hotload無效控制，亦與真冷紅分開保存。

五組配置：1280×720／100%普通、1280×720／120%減動態、1920×1080／100%普通、1920×1080／120%普通、2560×1080／120%減動態。實際Settings、FontFile來源、Label／Button字級、活動viewport、原生外窗與PNG尺寸分別記錄；整數字級按實際讀回，不把要求倍率當精確renderer倍率。這些是版面觀察，沒有性能門檻結論。

## 離線重算

安裝Python3即可，不需Godot、GPU、原D槽、原存檔或網路：

```powershell
python -B verify_packet.py --receipt offline-receipt.json
```

讀取器逐包核SHA與所有member的size/SHA，拒絕絕對路徑、父目錄、symlink、重複或非檔案member，安全解到隨機temp後清理。沿既有`matrix_reader.py`重算252個最終PNG／狀態、六張末行原圖與同版來源，核正式冷紅／受影響日誌、公開CLI的76項／28圖，並重算原版八個幾何失敗。另以真正舊raw拒絕省略號／錯宿主及未載入地圖，再用變造的正文、導航和重疊資料確認reader不信任producer的空errors。合成reader負控制與實際原生失敗分列在輸出中。

`index.json`列archive SHA、size與獨立member manifest SHA。每包小於50,000,000 bytes；`.gitattributes`保存raw bytes，`.gdignore`避免附件來源被Godot當正式腳本掃描。`images.json`記14張公開圖的原始來源／SHA；其中六張contact為縮小排版的review衍生圖，八張原生圖未重繪。

## 來源與原生重現

封包分為`native/`、`official/`、`work/`及`reviews/`。`work-source.tar.xz`保存原工具、每次producer／reader舊版本、路徑遷移、原產品、四份freeze、caller與拒收紀錄；各native run另保存當時guard內1539份實際程式／data／字型／私有producer來源。這個守衛不涵蓋未列入的其他美術貼圖，不聲稱所有素材都逐份凍結。正式隔離測試則有它自己的完整來源名冊，基準及四候選副本與manifest；原生及正式測試不是同一整棵checkout，所用兩UI bytes相同。

離線重算可以直接從冷clone附件執行。重新跑原生則需要正常可匯入的完整遊戲工作區，不能把附件當完整遊戲／存檔。先安全解包：將`work/`內容複製到遊戲的`work/ne228-matrix-20261117/`（scene與preload使用此明示res路徑），四candidate按清單放入相同位置；保留其他檔案。`run_native.py`／`run_remaining_v6.py`內repo與D輸出是當時本機安排，重現前改為本機獨立絕對OUT及Godot路徑；不要覆寫原證據。每輪command、renderer／adapter、profile路徑與UTC在原report/exit/caller中。原公開流程用`source/tools/run_controller_capture.ps1`及其三個原依賴，外層只取一次共用GPU鎖；沒有重入鎖。

原生矩陣用正式元件和原始資料安排狀態。餘額／醫療針、P17持有、回顧解鎖、單獨選項、死亡／結算與復原提示是版面fixture；選項不套用結果。最終v6直接load正式Pawnshop LevelData，沿真正入口自動略過原intro，沒有手填current map或探索；當格data/current/player/canvas path一致，實際探索110格、真地形貼圖與▲玩家標記。氣泡沿真正Story.play使用Rin原句，捕捉同post_draw的非空正文、來源、alpha、字型及rect，不再用NPC未讀「…」代替。

## 拒收與歷史保留

- v1五配置曾被舊reader報210/210，其氣泡只有NPC「…」；舊成功log與原reader保留，但不計有效252。
- v2 Story.play回true，當格宿主仍在播先前招呼且正文rect為0；有效gate真正拒絕。
- v3及v5仍用了失去resource_path的LevelData副本，區域圖顯示「尚未載入區域」，世界圖沒有目前位置；不把42／0或舊210當正式導航通過。
- `layout-original-1080-v4`為真原版8幾何失敗；它的其他舊map資料不作最終導航證據。
- `layout-candidate-v1`／`layout-eight-frame-observation`量到正常頁面滑入第10格x偏移3.872；action下緣284.1、footer上緣304.4沒有相交。永久純版面fixture改存／設／還原減動態，並保留正常原生動畫；未改產品動畫或幾何門檻。
- `layout-static-original-v2`是無效runtime reload：SCRIPT ERROR／engine0／checks0，不能當有效紅測。正式D冷程序513／3才是本次永久回歸的原版控制。

舊拒收／部分run的所有report、log、command、receipt與來源bytes，及受影響代表PNG均封存。683張其他舊PNG未重複上傳，逐張SHA／size／原D絕對位置見`omitted-historical-png.json`，原件保留且未刪；portable verifier只核其清單與分類，不能離線重建未封存舊圖，更不會重算舊假陽性210為有效。最終v6全部252張狀態、六張閱讀末行、寬窗原capture、兩組公開CLI全部28圖完整封存。

公開CLI使用合成device999，復原提示亦非真正拔除硬體；原生不是人耳／實體手把或真人完整章節驗收。矩陣不涵蓋自然全章戰鬥、每個敵人的威脅遮擋與所有語言／字型配置；整張母票未完成條件維持。沒有封裝任何APPDATA／LOCALAPPDATA profile或使用者存檔。

父代理的獨立審查另附`ROOT_REVIEW.md`，不覆寫本包raw。

## 數值欄裁字疑慮的核對

`stats-validation.tar.xz` 保存平滑／像素字型的v8原圖、完整來源、實際Label字格與捲軸幾何，以及v7私有觀察器的Index錯誤。v7雖引擎退出0，strict_clean為false，明確拒收。v8兩程序自然退出0、無診斷、1,539份指定來源前後相同，兩UI產品與原freeze完全一致；其餘來源按各自epoch記錄。

平滑字型首行「價／利」的字格右緣485.65625，捲軸左緣488；像素字型首行「售／含」右緣480，後半正常換到下一行。父代理檢視兩張最近鄰放大原生裁圖，確認字形完整且與捲軸有空隙。獨立讀者重算兩字型×典當／贖回四案例的全文字格與水平可見邊界；不把字格等同精確ink遮罩，也不擴稱所有配置、所有文字均有像素遮罩驗證。
