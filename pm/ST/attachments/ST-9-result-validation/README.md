# 故事結果的原始資料驗證

原本的結算先把結果清單篩成物件；非物件項目被靜默丟棄，旗標值也未在交易前檢查。合法餐費和壞項目放在同一段時，可能先扣200並寫收據，再忽略壞旗標，或寫入續玩時不接受的旗標型別。

現在內容檢查與段尾預檢共用同一份原始資料契約，在篩選或執行交易之前檢查整份 results／set_flags。清單、每筆種類與名稱、有限純量及已宣告旗標型別須正確；錯誤指出場景與索引並拒絕這份結果。JSON的2.0可表示整數2，沿用存檔owner既有相容規則。資料樹有界驗證沿用原RunSaveCodec，不呼叫作者handler。

此單位只修壞資料造成的段尾部分效果；沒有接通通用故事耐久coordinator、改寫保存順序、修改場景完成通知或新增道具演出。ST-9的原未勾條件保持，不能把這次檢查當成整票完成或完整保存邊界驗收。

## 真引擎負控制與修後

Godot 4.7.2官方Linux、headless。負控制使用原產品，先透過正式交易建立200餐帳、給400信用點，再以真正Story段尾入口驗15種壞資料：清單型別錯、非物件項目、無效旗標值／型別／名稱及set_flags錯型。每案檢查內容診斷、拒絕位置，以及旗標、物品、錢包、收據的完整bytes保持。另驗正常付款、布林與JSON整數相容值仍成立。

| 範圍 | 結果 |
|---|---|
| 最終測試配原產品 | 342檢查、42個預期失敗、0腳本／解析／編譯錯誤，退出1 |
| 修後原選擇器，固定base d4d8647e | Chapter1Map／Continuity／Cutscene三組，2414檢查，0新／已知失敗，200秒，退出0 |
| 原正式資料 | 載入的章節與合法交易仍通過原檢查；未改故事JSON、金額、旗標預設或圖片 |

原先新增的fixture名稱未用該套件頂部規定的`test_bad_cutscene`命名。第一次修後342檢查0斷言失敗，但15行刻意壞資料ERROR不在既有容錯命名內，因此原執行器正確拒絕、退出1；原始log完整保留。只改fixture的一個ID，62項新增檢查不變，再以原產品重跑42個預期失敗後，才執行修後完整三組。精確修正紀錄的可攜副本在raw.zip；沒有改filter或新增known failure。

最終log仍包含刻意壞資料的ERROR與引擎退出資源診斷，[逐條訊息與次數](engine-errors.json)保留。0腳本錯誤不等於全輸出無ERROR。此次沒有新增或變更遊戲畫面，不用重拍圖片冒充資料契約證據。

## 來源與重跑

開始前讀User-guide、continuity-qa與既有故事原子安裝方案。研究核對 [Godot JSON型別檢查](https://docs.godotengine.org/en/stable/classes/class_json.html)、[inkle的執行期整合與故事狀態](https://github.com/inkle/ink/blob/master/Documentation/RunningYourInk.md)及[其狀態格式驗證來源](https://github.com/inkle/ink/blob/master/ink-engine-runtime/StoryState.cs)。採用「解析成功後仍驗資料契約、正式狀態由原owner維護」的原則，不引入ink，也不從相近遊戲截圖推斷交易／保存實作。[既有五作視覺研究](../../../../design/08-lighting/READABILITY_REFERENCES.md)仍只供畫面參考。

在自己的d4d8647e暫存checkout，正常匯入，將[replay](replay)測試放回原路徑。before／after產品分別放`core/story_outcomes.gd`，跑：

```sh
GODOT=<官方4.7.2> SHARDS=1 LOG_DIR=<absolute-directory> tools/run_tests_parallel.sh --only=CutsceneSuite
GODOT=<官方4.7.2> SHARDS=1 LOG_DIR=<other-absolute-directory> tools/run_tests_changed.sh d4d8647ee80cfa3db05e5eb448acf21ea665c6fa
```

負控制預期退出1、42個斷言失敗；修後原範圍預期退出0。只操作自己的暫存checkout，測後恢復after。[完整20份原始檔](raw.zip)、[逐檔SHA](manifest.json)、[最終來源與受保護檔案SHA](source.json)。原選擇器、filters、known_failures、純planner、silent install與磁碟writer均逐位元保持。
