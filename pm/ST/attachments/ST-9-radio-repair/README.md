# 通訊修復拒寫後載入原進度

整份進度需要修復時，通訊保存原本會拒絕寫入，卻繼續提供無法成功的重試。現在提供載入原進度，仍保持尚未讀完、世界暫停與取消規則。

相同真writer回歸613項／1失敗→613／0。首次0checks的編譯失敗來自最新main新類別尚未匯入，另存原log；重新匯入後才取負控制。七組受影響回歸：checks: 3544, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 188 s)。正式Main、正式街道、真玩家子彈、敵人、公開通訊確認與真存讀檔15項通過；0引擎錯誤／退出洩漏，兩張原生圖逐張看過。工具明示安排戰鬥位置、耐久9999、略過前置演出，以及在末句確認前製造缺少必要物品的live舊狀態；沒有注入通訊目標旗標，不代表真人整章。按恢復後真正重建Level、釋放暫停且通訊仍未讀，沒有補發新結果。

沿用[既有保存設計與參照](../../../../design/20-campaign-experience/TERMINAL_STORY_RESULTS.md)，重看Ghost Song的對話資訊層次；圖片不能證明存檔時序或玩家偏好。本次重新讀Godot官方保存文件收到HTTP403，未重試或繞過，不宣稱重新讀取成功。[原始紀錄](raw.zip)、[SHA](manifest.json)。母票其他結果與動作的驗收保持原狀。

![原進度恢復](../../images/ST-9-radio-repair.png)
![Ghost Song既有來源圖](../../images/ST-9-npc-ref-ghost-song.webp)
