# 取盤路線的完成規則（NE-223）

2026-10-20（Asia/Taipei），先讀 User-guide，再檢查 7b032bcc。正式資料把「取得資料盤」當成整項任務完成；若舊檔或非正常路徑只記得取盤而缺少清路／看門狗／水閘，任務目錄會把中途指引藏進已完成，預設目標轉去交盤。

本票驗收明確要求取盤不能掩蓋中途指引。提供選擇性的 `completion_requires_steps: true`：完成旗標與來源內每個步驟都成立才完成。只由第一章取盤任務選用，不新增故事旗標、不補寫路線完成、不發獎勵。其他任務維持既有終點旗標規則，序章略過不要求假做練習。旗標缺漏的存檔自然顯示最早未完成步驟，不遷移或修改存檔。

## 實際看過的研究圖片

[原圖與來源 SHA](../../pm/Nest-Egg/attachments/NE-223-route-references/sources.json)。不是玩家民調，不推論圖片背後的存檔或條件實作。

| 畫面 | 可借用的原則 |
|---|---|
| [Hollow Knight 地圖](https://interfaceingame.com/screenshots/hollow-knight-map/) | 橫向探索的上下層、所在位置和路線連接必須看得出來 |
| [Blasphemous 地圖](https://interfaceingame.com/screenshots/blasphemous-map/) | 橫向地形保留已知路徑與端點，未走的路不冒充走完 |
| [Hades 路線圖](https://interfaceingame.com/screenshots/hades-map/) | 玩家所在階段與後續分支分清楚；不照搬單線章節結構 |
| [Cyberpunk 2077 日誌](https://interfaceingame.com/screenshots/cyberpunk-2077-journal/) | 明確區分可選步驟與當前要做的目標 |
| [The Witcher 3 任務](https://interfaceingame.com/screenshots/the-witcher-3-wild-hunt-quests/) | 進行中、已完成步驟和任務整體狀態必須一致 |

前三者提供動作／探索結構，後兩者提供多步任務表達；後兩款同屬 CD Projekt Red，未算成兩個團隊。沿用使用者選定的終端機雙欄版面，不以這次完成規則變更重做整頁。

## 驗證界線

資料回歸涵蓋三項路線旗標的全部八種組合、JSON 往返、主線預設追蹤、完整完成與略過序章例外。安排舊檔缺旗標樣本的畫面只驗證該缺口，不代替真實戰鬥清路、真人通關或實體手把驗收。
