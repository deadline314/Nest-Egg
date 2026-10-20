# ST-9：晚飯與交接櫃的獨立段落保存

2026-10-21（Asia/Taipei）。整票維持進行中，原三項未勾條件保持。只採用正式 compiler 指定的四段：晚飯、交盤、取回執、留摘要。保存成功前，原件、旗標、錢包／收據、完成史與真請求保持；成功後一次安裝，再發通知及結算 NPC waiter。交盤核對真 Main 的當前 persistent Level、真正交接櫃及其互動情境；不是世界拾取或全章 atomic_v1 capability。

## 驗證

以 [validation.json](validation.json) 的固定基準原選擇器結果為準。新增七條累計預檢回歸附在原 CutsceneSuite 前，原斷言、選擇器、filter、known failures 不變。同測試換回原 preflight 的診斷控制為349檢查／4預期失敗；候選349／0。最終完整受影響結果另記 validation。

V3同份探針：原main11檢查／3預期失敗，候選11／0；真交接櫃三操作各兩次真寫檔拒絕後重試成功，73／0；另開真正新程序讀回5／0。四個V3原生log皆0 ERROR／SCRIPT ERROR。每次變回舊來源只在本 Session 自有工作樹，finally精確還原，receipt與來源SHA在raw中。

前提由公開 custody取得資料盤、加237信用點後安排在正式交接區，呼叫真 NPC._talk、由真選項選 deliver／take／save；不是人類按鍵／實體手把／自然取得資料盤／完整章節。玩家位置安排在櫃前60像素；畫面有明確標籤。Godot4.7.2官方、Forward+ HDR、Vulkan llvmpipe軟體，不能替代硬體條件。通知中確認第一個observer已能讀到完整live與磁碟結果，拒絕重入交物、故事交易、播放與路由；合法讀掉NEW、普通各花1後，真冷續玩保持235，不由舊候選覆蓋。

## 歷史診斷

首個--script試跑找不到autoload Transition，失敗保留；後改正式tscn入口。V1的67項功能檢查是早期診斷，當時探針來源未單獨凍結，故不作最終重跑依據。V2錯把2倍UI文字取樣在y10..24，導致baseline4失敗（3功能＋1探針）、negative1探針失敗、write6探針失敗；圖片其實有字，全部保留，沒有改產品讓它通過。V3固定1280×720文字實際y26..48，不降低64個白字樣本門檻；同版before／after皆驗，實際圖片逐張看過。原測試的故意壞資料及既有引擎清理診斷完整保存，不宣稱全部歷史log無ERROR。

## 研究與界線

先重看 [Katana ZERO、Hollow Knight、Ghost Song、Blasphemous2、Ori的五份原圖與來源](../../../Nest-Egg/attachments/NE-278-references/sources.json)，原圖保留在同一資料夾；只借明確選項、人物／物件關係與不遮資訊，不聲稱偏好民調或其內部存檔算法。[Godot官方存讀檔](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)與[Hades官方對話進度修補](https://www.supergiantgames.com/blog/hades-updates/)支持狀態與回訪核對方向。本作沿用已存在的整輪writer，不宣稱斷電fsync。設計見[獨立段落保存邊界](../../../../design/20-campaign-experience/TERMINAL_STORY_RESULTS.md)。

尚未套用的付費續段、世界拾取及診間托盤保持原票狀態；道具／手部與完整人工通關不在本次證明內。所有raw檔案逐檔bytes／SHA256已與zip回讀比對；精確來源與負控制保存在同一份raw.zip。

## 最終來源修正與最新main整合

先前V3及第一輪803秒受影響測試後，補了兩個修正：既有提示在重試進入「必須恢復原備份」時更新按鈕；同一runtime的非水平aim向量比較，兩側都通過writer相同的JSON與第二次驗證邊界。原先一側少一次float32單位化，可能因一個ULP拒絕未變的狀態；未加容忍量、未略過runtime欄位。V3來源保存在source/v3-ordinary，最終採source/after，並包含本輪已合入NE-240的核心整合來源。

V4故障控制只移除提示刷新，14檢查／1預期失敗；精確還原後14／0。實際writer已輪替主檔、由受控hook只建立屬於本探針的空主檔目錄，真OS rename及回滾同時失敗，完整原備份保留。先前tmp拒絕後同一提示改成「載入原進度」，只移除自己擁有且確認為空的阻擋目錄，真Main reader重建新Level，保留原未提交事實、釋放本owner自有UI與鎖。不是假mock回傳成功，也不是提交本次結果後讀回。重載原入口可以合法再次暫停，因此不宣稱全樹必定unpaused；恢復舊演出沒有原NPC waiter會記來源不符不發獎勵警告，不作完整NPC中途續接證據。

V4普通73／0、另程序5／0。再接上最新main的NE-240保存修正後，原生恢復14／0、普通73／0、另程序5／0；這三輪及V4控制／候選皆逐行0 ERROR／SCRIPT ERROR。與原測試並行，只作功能與圖像證據，不作效能比較。固定ddbb6248原選擇器對最終來源及整合結果重跑，結果以validation.changed_summary為準。沒有修改原assertions、filters、選擇器或known failures。

早期recovery控制／候選各13檢查3失敗，當時canonical比較拒絕在OS rename前，且探針誤用刪除／Level還原與全樹pause斷言，僅影響隔離測試槽，全部失敗保留；不得拿來作晚期故障證明。diagnostic-v2的13／1及v3的7／1保留真正向量差值與當時錯誤斷言，V4改為驗新Level instance、自有鎖及確認過的空目錄。沒有以降低產品驗收條件把它們改成通過。

連續性：獨立段落的四owner與真請求／源頭已驗；取消不開放給必須完成的段尾，讀回原備份走既有正式入口；普通NPC物品與錢包通知不重建Level。自然取得盤、整章前因、手部接觸、實體手把、母語／120%三語人工驗收保持原票的範圍，不以安排slot代稱全部通關。

## 合併後測試曾崩潰（保留，未歸因）

第一輪最終整合的原67組跑484秒，只有65,375個已完成檢查、0斷言失敗，但Melee程序發生原生SIGSEGV而沒有結果行，整輪exit1，明確是失敗。不是65524項成功，也沒有把崩潰加入過濾。保留完整C++地址與原輸出。官方4.7.2 crash handler在收到signal後會先通知MainLoop，再印backtrace，因此propagate_notification訊息不能單獨當成根因；沒有符號資料，不臆測地址對應的函式或宣稱已修引擎。

本輪已合入的NE-240來源（不含ST-9修改）之遠端完整CI通過95,837項、0新／已知失敗，[原run](https://github.com/deadline314/Nest-Egg/actions/runs/39503750131)與decoded job log保留。另以該基準本機單獨跑原MeleeSuite，結果：checks: 149, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 501 s)；exit=0。ST-9候選不改source／assertions／filter，原固定基準67組完整重跑：checks: 65524, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 501 s)。重跑通過是該輪結果，不能宣稱已定位或修復先前崩潰；全部failed run與基準對照分開封存。
