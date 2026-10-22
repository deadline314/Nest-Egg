# 通訊顯示與背景說明同步

2026-10-22，NE-228。先讀User-guide、原背景Hover守門與world text說明。BG-50第二輪原50組55025項有2項通訊守門失敗；同一原十組前置加唯讀觀察後8774／0，沒有放寬原兩物理影格或原斷言。原失敗缺當刻資料，不補造其唯一根因。

觀察取得另一個明確的同呼叫缺口：Story.play完成後radio_visible=true、root.visible=true、radio_wait=0，但guard.blocked=false，仍保留已顯示Tooltip；例為physics_frame929／process_frame1932。到physics931／process1937才blocked=true。原守門只輪詢_process，多個物理步驟在同一畫面影格時沒有即時同步。

改法採原EventBus契約：所有DialogueLayer真radio root的visibility_changed及來源離樹都發同一個無狀態通知，守門同步重查原radio_visible。延遲而未顯示的通訊不擋背景；淡出仍可見的面板保留占位，多來源只在最後一個消失才解除。保留每格布林輪詢作後備，不改文字、排隊、閱讀時間、動畫、Story結果、操作鎖或全域暫停；事件只描述畫面可見性。

先加同次呼叫開／關、真Tooltip取消、第二個真DialogueLayer、延遲與來源離樹的負控制，再改產品。既有原判斷與等待保持；沒有讓測試清空佇列、關特效或延長原等待來通過。原50組兩輪不同失敗及觀察的成功十組保留，原選擇器最後須通過後分票交付，BG-50修改另在自己的分支保存。

開始前實際重看Hollow Knight暫停圖與Hades主選單原圖（NE-229既有來源包）：前者清楚分開活動介面與背景，後者保留一組主要選項層級；兩張沒有Tooltip時序，不據圖片推論內部事件或玩家民調。保留原作者／來源，畫面層級原則之外的時序由本作原程式與負控制證明。官方CanvasItem的visibility_changed語義用來描述實際可見性，不能拿Story開始當面板已可見。


## 已取得的負控制與驗證

新增9項，原CombatHud76／6→76／0；初版8項75／5→75／0保留。原既有斷言／輸入／等待按序逐位元相同。原生v2明示當舖UI顯示fixture，真Tooltip與純展示台詞，13／5→13／0；兩程序0引擎ERROR／0退出洩漏診斷，8張最終圖逐張檢視。讀回圖晚於同次呼叫快照，原版下一格輪詢後也正確，所以不稱拍到壓字影格；快照已證明原可見root＋同一Tooltip instance＋guard=false，新同步為guard=true及Tooltip id0。

原選擇器實際76組，首輪六程序90856／1（未改動彈帶29.6畫面像素，原小於24）；此前口頭88已更正。未修改7a及本次來源隔離該組各33／0，未重現不稱修好彈帶根因。四核心配額後採兩程序保留背景worker空間，維持原選擇器、斷言／輸入／等待／filter／knownfail；最後收據與cpu.stat見同票附件。
