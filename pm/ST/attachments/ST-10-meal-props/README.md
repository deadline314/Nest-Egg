# ST-10：凜吃完的碗與跨段舞台狀態

2026-10-21（Asia/Taipei）。正式吃麵段在凜說「這碗我吃完了」前，桌上左碗改為吃完、不再冒煙，右碗保留食物與蒸氣。下一個報地址段的全新舞台，在進樹與fade前就重建餐後狀態；不借用上一個播放器，不另外發故事結果。整票仍進行中，第29項完整動作條件保持未勾。

## 原圖與研究

先重看 [Katana ZERO、Hollow Knight、Ghost Song、Blasphemous2、Ori五款作品的原圖與來源](../../../Nest-Egg/attachments/NE-278-references/sources.json)，再實看 [Spiritfarer與Eastward官方Steam圖來源及SHA](references/sources.json)。六張新研究圖全部保存在references目錄與raw.zip，本頁直接顯示兩張。Spiritfarer圖可參考坐著的人、燈與對話區的關係；Eastward圖可參考多人場景的支撐、層次與阻擋。這些圖不包含逐格吃麵動作，不把它們當烹調動畫研究或玩家偏好民調；存讀與結果邊界另依本作設計。

![Spiritfarer：戶外坐姿、燈與對話區](references/972660-0.jpg)
![Eastward：多人物的場景站位](references/977880-2.jpg)

## 圖像來源

編輯原正式RGBA桌子，保留工具直接輸出的採用候選與完整prompt／metadata／hash。第一次結果把兩碗都清空，與只寫凜吃完的台詞不符，拒絕採用，原件在raw.zip的rejected/both-empty.png。第二次只有左碗空，右碗保持食物與蒸氣。要求304×255，但工具實際輸出1369×1149；seed／model／job未提供，明確為null，不編造。

採用原件byte copy後，以標準管線產生normal與import設定；重建先核對來源SHA，沒有另用繪圖程式改色或補畫。這是生成變體，桌腳與線稿有重新繪製，不宣稱外圍像素完全相同。世界寬度、比例與位置由相同舞台定義補償來源解析度；自動檢查寬度差<0.01、畫布高度差≤1舞台px，原生逐張看桌椅支撐、角色落地與對話框，未挪動演員或既有板凳。四個PNG／import產物均實際重建再逐檔比對SHA，bytes完全相同。

## 驗證

原CutsceneSuite新增14項狀態／原尺寸／資料拒絕／無結果副作用／正式步序回歸，原斷言不刪；既有Cutscene、ChapterCutscenes、LayerOrder原套件493／0。原run_tests_changed以固定ddbb6248重跑最終最新main合併來源，精確結果在validation.json。原選擇器、filter、known failures不變，SCRIPT ERROR仍算失敗。

同一凍結探針的修前控制13項／3預期失敗：其中2項是原版沒有新狀態查詢API，另一項是正式流程確實沒有到達餐後狀態；不把3項都稱作獨立玩家Bug。候選normal15／0、cancel18／0、skip13／0、writer12／0、另程序reader6／0。後兩者是真Main整輪存讀，在報地址首句保存完成的餐點與尚未完成的地址，真正新程序從正式入口重建餐後桌面。取消重進回滿碗，跳過只結算已選的餐點，下次對話再接地址；物件切換本身不發金錢、帳單或完成。native結果與全部失敗詳見validation與raw。另以衍生探針在已顯示空碗但尚未完成餐點時正常退出，新程序依既有規則從該段開頭重播，先回滿碗再自然走到餐後與地址；這是段落重播，沒有宣稱保存了動畫游標。中途餐點恢復會保留既有「續玩來源不符，不發放NPC獎勵」警告；本probe只驗旗標、物件與段落重播，不代稱NPC waiter或獎勵接續已驗收。

接上已合入NE-240／ST-9的最新main後，另跑normal、writer、reader，逐項結果仍記validation；原生採Forward+ HDR、Vulkan llvmpipe軟體，安排既有晚間結果、把玩家放阿梨附近並呼叫真NPC._talk，再由真選項stay／accept走正式場景，畫面明標安排條件。這不是人類自然遊玩、完整章節或實體GPU／手把／鍵鼠手感。與原回歸程序並行，不能拿elapsed作效能比較。

## 歷史失敗與連續性

第一個baseline探針的state變數讓舊Stage缺少方法時無法型別推導，編譯失敗保留；改成明確String並凍結同份探針重跑原版／候選。兩次控制都finally精確還原本Session的來源，receipt與來源SHA在raw。第一次資產檢查被既有其他recipe的整數尺寸陣列觸發TypeError，修正只略過非asset-record的純量metadata，原asset檢查保持；第二次完整資產檢查OK。中途退出探針V1在呼叫非同步退出後仍繼續跑完整餐點斷言，最終13項有2個探針失敗，已保留；該錯誤探針過早要求成功退出而回exit0，仍明確算失敗，不當成通過；V2讓未完的writer流程真正返回後再退出，沒有改產品或改掉原凍結baseline探針，另用reader驗段落重播。不得把這些初次失敗刪掉或稱通過。

- [x] 正式meal與address的旗標／結果／對話內容沒有改，視覺步序先於吃完的末句。
- [x] 全新stage預設滿碗，餐後入口在淡入前選定eaten；取消、重進、跳過、另一程序續玩各自核對。
- [x] 未知物件／狀態保留原材質；錯誤texture、任意handler與錯誤初始狀態由內容檢查拒絕。
- [x] 狀態不改角色位置、舞台層、支撐定義、貨幣、道具、flag或完成史；原主要流程／比例／圖層套件保留。
- 死亡扣款、輸入與劇本文字不改；關爐、裝水、真正進食與交盤手部接觸依原票完整條件，沒有代勾。原生圖未重新驗全角色接點與所有姿勢。

[設計邊界](../../../../design/20-campaign-experience/MEAL_PROP_STATES.md)。raw.zip所有entry回讀核對bytes／SHA256；重播探針、生成源、拒絕候選、原生圖／log／退出碼與所有測試紀錄一併保存。
