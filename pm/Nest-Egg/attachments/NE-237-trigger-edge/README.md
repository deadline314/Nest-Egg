# NE-237：按住扳機不重排近戰點按

RT維持按下時送出0.92／0.8／1.0／0.85的類比變化，原事件路徑會把每次都當作新命令。現在和原輪詢規則一致，一次點按只排一次；放開再按仍接受。暫停中放開也能退休狀態。原招式、緩衝期限、連段／取消時間與引擎死區保持。

[設計與研究](../../../../design/14-combat-variety/MELEE_TRIGGER_EDGE.md)、[完整原檔](raw.zip)、[逐檔SHA](manifest.json)、[收據](validation.json)。讀User-guide與原四裝置同格規則；實際取得並讀Valve Activators的Start Press及Turbo分別定義，重新看既有Dead Cells開發文章部分頁面存圖。圖片只能支持攻擊姿勢層次，不能證明按鍵規則；沒有玩家偏好民調。Godot官方JoypadMotion頁回403，未重試／繞過。前票1fd1bf2e完整CI40083178459實際96,424項／0新／已知失敗，502秒，完整job亦保存；不以推算數字代替實際log。原HTML留本機ignored工作區，公開包僅含短摘錄及取得SHA，沒有冒稱保存了全文。

| 範圍 | 真正結果 |
|---|---|
| 同一四項公開事件控制 | 原程式4／1失敗；最終4／0 |
| 只加鎖存的拒收對照 | 4／1：暫停中放開後，下一次點按被舊狀態擋掉 |
| 最終原受影響28組 | 45602項／0新／已知失敗，616秒；含原main及原四裝置五武器完整矩陣 |
| 原生V2同配置修前／修後 | 5／1→5／0；第五項為真視窗保存，皆0引擎ERROR／洩漏 |

新helper只增加四項。原MeleeSuite所有既有斷言、輸入及等待去掉唯一新增呼叫後逐位元一致，runner／selector／filters／known failures未改。Headless原診斷按原filters保留，各shard數見收據；沒有SCRIPT ERROR，不冒稱headless完全無ERROR。

初始完整單組pilot先跑到既有長矩陣，新helper尚未執行時主動停止，保留為不完整紀錄，不算負控制或通過。聚焦控制直接繼承原smoke runner的關卡／斷言／清理方法，只呼叫同一新helper；原完整矩陣由最終原選擇器照常跑完。早期測試草稿曾把武器路徑寫成不存在的tonfa，於import階段改回正式melee_blade，尚未執行新helper；不冒稱曾完成錯誤路徑的檢查。研究轉文字先因本機無bs4失敗，後用標準庫擷取；沒有補造成功。

原生為Godot4.7.2、Forward+／llvmpipe、1280×720真正視窗。圖上明示INSTRUMENTED FIXTURE，固定演員只隔離命令接收，實際Input.parse_input_event／flush_buffered_events送RT；不是自然交戰、整段招式錄影、手感或實體扳機驗收。原版只還原命令腳本，非整份歷史checkout。首版診斷覆層用錯邏輯／實體大小而截斷，兩圖看過後拒收；V2改診斷版面重拍兩圖均逐張看過，產品來源SHA相同。沒有把診斷字級當作遊戲UI修正。

Native在be4e5db5來源上執行；接上1fd1bf2e時，只有無關M17譯文、Collectibles及文件差異，九個關注來源SHA完全保持。最後原28組是在1fd1bf2e合併結果上執行，原生不假稱整份checkout同一。

ZIP 58項原檔，SHA `a9b8bc159ea15aacc33979e09e2560c6995f445a61f78d8dce6f6afe4e6a4234`。母票尚有真正裝置的完整驗收，維持進行中。
