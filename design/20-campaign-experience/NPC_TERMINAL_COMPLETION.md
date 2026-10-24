# 讀標籤與交談的耐久完成

2026-10-22，ST-9。先讀User-guide、TERMINAL_STORY_RESULTS及原NPC waiter／完整RunSnapshot規約。真Main從新遊戲公開換區、定位到正式懷錶標籤，以公開互動／確認讀完；真slot.tmp目錄拒絕寫入時，原版14項／5失敗：旗標、完成史、通知、talk_count都提前成立且沒有重試UI，原槽bytes仍舊。沒有注入目標旗標。最初探針在headless等待render及另一輪缺少匯入檔均是工具失敗，修正工具／補齊既有匯入後才取此乾淨負控制；產品尚未改時已0ERROR／0SCRIPT ERROR。

限定第一章四個標籤（當舖／翌日當舖）與屋頂鷺第一次簡報，都是無獎勵、無選項／續段的正式終段。由compiler指定既有main_terminal_results_v1，不能只手改生成JSON。準入核對真正Main／persistent Level、載入劇本來源、當前request/context、原entities的直接NPC、canonical resource、layout resource identity與cell、正在進行的talk_index及舊flags所解析的正式dispatch。NPC不屬於Level._tracked，不能借世界pickup準入假設。

同一完整候選同時帶新結果與該NPC下一次talk_count，精確寫入runtime.area.world及state.area_states的該鍵；其他state/runtime仍與原標準化來源逐項相同，不容許整輪修復混入本次結算。保存前後重查所有來源與NPC狀態；來源過期不發布，已提交異動走讀取已保存結果，回滾失敗讀完整原備份。成功後在通知前無回呼安裝旗標／完成史／錢包／物品及NPC次數、冷卻，保留Level._area共享參照。單次presentation暫態已結算標記避免waiter重複加次數，沒有第二份持久真相；同一NPC不能重入覆寫自己的marker。普通有獎勵對話仍沿原路，不隱含聲稱原子化。

結果發布後只從最新live狀態補存，不能重裝舊proposal覆蓋合法通知回呼。冷讀要核對writer frozen bytes、完成史與實際NPC talks=1。完整ST-9與通用atomic_v1、餐費含續段／選項等不由這五個producer代勾。

開始前實際重看Ghost Song與Blasphemous 2原圖（NE-278-references，保留來源／SHA）：前者講者頭像／名字、文字與繼續提示分層，後者清楚保留人物與實體互動物關係。圖片不證明存檔時序、玩家偏好或內部事件；保存機制由本作原始程式、真IO負控制與跨程序reader驗證。原生Main維持PAUSABLE、觀察節點ALWAYS；工具安排換區與位置不是自然整章或人工實玩。

## 中途退出與來源接回

第一次實作完成後另驗中途退出：真正writer在首句保存原場景／context、結果仍未生效，另一程序讀相同frozen bytes。發現原NPC的續玩準入只沿then、不先解析dispatch，Level因此退成無NPC waiter的播放；這與新耐久來源要求不相容。未修續玩接回前，冷reader5／1，明確來源不符警告；修後同一份writer bytes 12／0，接回真NPC後仍能真IO拒絕、公開重試，再一次結算。準入現在先依已恢復的舊旗標找正式分派段落，再保留原then檢查；不同producer或已完成的段落仍拒絕，不擴大到任意選項／續段。

工具另一次初稿將物件互動位置一律移36px，實際懷錶旁雨衣更近、讀到了雨衣；該輪8／2是探針前提失敗，不當成產品錯誤。物件保留原8px、人物36px，開始前核對真正互動目標，畫面再等確實的對應段落完整首句；鷺需同時看見兩位真正演員。所有失敗源碼與收據保留。

## 整輪修復不得混入標籤結果

另以真writer與正式必要物品修復規則建立負控制：只明示把live「已取得資料盤」設true、物品仍無盤，原槽bytes保持合法舊資料。從已標準化／修復的original複製候選，會在讀標籤時偷偷補發資料盤；原RunSave＋新控制611／3。改深複製真實raw捕捉後，writer的修復差異仍須被精確比較拒絕，611／0；不消耗、補發或通知無關物品。原始runtime與live area的別名同樣切斷，沒有回到直接改live world。另增加未提交修復的UI判定：提供載入原進度，不讓唯一按鈕永遠重試，也不誤稱本次結果已保存。原四個終段邊界不擴大此NPC能力。

## 冷續玩首繪的真實鏡頭

原生整合十五程序245／0的功能檢查通過，但逐張圖發現中途冷續玩的背景是地圖外的雨天遠景。實際camera.global=(666,279.9977)，screen_center=(77.7,32.6664)，主角viewport點(1246.016,731.6761)在視野外；當時樹已暫停、Scene／request正確、NPC次數0。只force_update_scroll、不解暫停、不改角色／結果，即可把screen_center同步到正確global，主角點(116.48,256.8)回到視野。這是正式snap尚未發布viewport捲動，原生控制18／1→18／0，兩次0ERROR／0退出洩漏；同一frozen writer檔。

修法只在LevelCamera.snap_to_target的reset_smoothing之後立即force_update_scroll；平時追蹤、平滑、震動、縮放與物理更新保持。最終中途續玩新增真玩家世界點位於實際viewport的檢查，再完整複驗全部十五程序與原61組。較早61組在看出畫面問題後主動終止（197.97秒），完整部分log與精確私有PID證明保留，不當成產品回歸失敗或已通過。

## 2026-10-24：非NPC結果的全輪修復拒寫

需要全輪修復的非NPC末段結果也須載入原進度；不能因沒有NPC欄位就只留下不可能成功的重試。共用結果邊界保持不寫、不安裝、不發布，真正恢復仍由Main整輪reader負責。正常完成、NPC交談次數與已提交恢復不變。

正式當舖地圖觸發自然晚飯鏈抵達真正food reader，先保存有效slot才製造無關缺盤旗標；沒有注入晚飯完成。原生17／3→17／0，公開按鈕後原slot重建關卡、清除舊鎖且晚飯未讀。[原檔與範圍](../../pm/ST/attachments/ST-9-repair-owners/README.md)。
