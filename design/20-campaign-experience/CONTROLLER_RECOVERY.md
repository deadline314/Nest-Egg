# 手把斷線後的恢復（NE-229）

2026-10-19（Asia/Taipei）。先讀 User-guide，再檢查 339cc5d1：遊玩中斷線會取得暫停鎖、清掉按住狀態，但只播會自動消失的通知。暫停持續時，玩家缺少一直可見的操作入口。

## 實際看過的圖片

五款、五個團隊；原圖與來源／SHA 在 [附件](../../pm/Nest-Egg/attachments/NE-229-recovery-references/sources.json)。以下觀察只涉及所見介面，沒有實測這五款的裝置拔插，也不視為玩家偏好民調。

| 作品 | 觀察 | 採用理由 |
|---|---|---|
| [Hollow Knight／Team Cherry](https://interfaceingame.com/screenshots/hollow-knight-game-menu/) | 遊戲畫面壓暗，恢復項目置中，有左右焦點裝飾 | 保留停住的世界作背景；恢復操作明確可見 |
| [Celeste／Maddy Makes Games](https://interfaceingame.com/screenshots/celeste-paused/) | 像素面板、選中項目亮色，背景仍辨認得到 | 沿用本作像素面板，焦點用色彩與邊框共同表達 |
| [Blasphemous／The Game Kitchen](https://interfaceingame.com/screenshots/blasphemous-options/) | 固定底部 A／B 提示，列表與說明分開 | 恢復操作與簡短原因分層，按鍵提示不混進標題 |
| [Hades／Supergiant](https://interfaceingame.com/screenshots/hades-main-menu/) | 操作項與角色畫面空間分開，高對比且層次少 | 只提供必要的繼續入口，不堆選單與假手把圖示 |
| [Cyberpunk 2077／CD Projekt Red](https://interfaceingame.com/screenshots/cyberpunk-2077-pause/) | 壓暗模糊背景、終端色盤、角落獨立操作提示 | 借用資訊層級，不搬用雜訊、故障動畫或造型 |

前三款是橫向動作／探索／平台作品；後兩款補充動作遊戲與賽博介面的資訊層級。恢復安全規則來自本專案需求，不聲稱是上述圖片能證明的機制。

## 行為與驗證範圍

- 只有原本需要斷線保護的遊玩狀態新增持續面板。既有對話、商店、暫停等模態保留各自暫停與焦點。
- 斷線立即暫停、清掉按住與震動；游標可見。面板無倒數、不自行消失、無閃爍或等待動畫。
- 重接本身不恢復。鍵盤確認／暫停鍵、手把確認／暫停鍵，或滑鼠點「繼續遊戲」才恢復；同一次操作不能漏成跳躍／射擊。返回與漂移不恢復。
- 操作提示跟目前裝置同步；面板不要求一定使用已斷線的裝置。文字支援繁中、日文、英文與 120% 字級。
- 恢復只釋放自身的鎖；玩家離開場景即清理，避免殘留面板阻塞下一關。
- 合成事件、軟體 Forward+ 截圖與真實手把拔插、震動、人工全流程分開記錄。
