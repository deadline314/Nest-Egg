# NE-223：任務內文使用劇本語言

2026-10-22。先讀使用者指南、任務介面設計、原視覺研究與完整句子規則。

## 問題與決定

三章任務的正式來源已生成 `title_ja`／`title_en` 等譯文；任務目錄與 HUD 直接顯示中文原欄位，沒有使用目前的 `Story.language`。改由同一個只讀顯示入口沿用 `StoryLocale`：所選語言缺譯退回英文，再退回中文；記錄具體來源與欄位。原始任務字典、ID、旗標、條件、地點與獎勵數值不因切語言而重寫。中文長度驗證仍針對中文來源，不能用英文長字串讓原本合法任務消失。

涵蓋清單標題、細節標題、背景、獎勵、步驟、當前目標、阻塞原因與建議。既有介面導航字樣沿用原來的介面語言；本票接通的是故事資料已提供的任務譯文。HUD 在原本的目標刷新時讀取目前語言；已開啟的目錄在語言變更後重建顯示，保留任務ID、分頁、釘選、歷史、細節捲動與穩定焦點；快取只記上次顯示語言，不改任務真相。任務列使用省略號而非硬切，右側標題與細節保留全文；HUD的一行限制沿用原版，Hover 顯示完整目標，任務目錄亦可閱讀全文。

第三章支線標題由「第三個抽屜的錄音」改為「借閱第三個抽屜的錄音」，日文「三段目の引き出しから録音を借りる」、英文 “Borrow the third drawer's recording.”。登記借出仍由原步驟說明，沒有改成免費取得或提前完成。

## 依據與驗證

- [既有同類介面圖片研究](VISUAL_RESEARCH.md)：Prince of Persia: The Lost Crown、Hollow Knight 等的任務／地圖資訊層級；本次保留原構圖與焦點語義。
- [Godot 官方國際化文件](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html)：字串來源、退回與文字長度須實際測試，翻譯欄位存在不等於 UI 已使用。此專案沿用既有 JSON／StoryLocale，不另引入第二套翻譯服務。
- 用真正任務列／細節與 HUD 重現原版，分別驗三語、缺日文退英文、缺兩者退中文及不改原字典／進度。從正式產生器重建第三章，差異限三語標題；跑原範圍回歸、StoryLint，原生 Forward+ 檢視放大文字與完整內容。這些不代替母語審稿、實體手把或全章遊玩。

## 標籤與複核

放大文字時，追蹤標籤最初依最小尺寸定位，實際Label舊尺寸較大會把右字推出列外；改用父列右下錨點、向左上擴張並讓文字靠下，與地點／進度共用說明列。中途版曾先解除裁切卻讓文字靠近標題，保留該版圖並繼續修正；邊界數值通過不能代替看圖。

本輪補充實際重看五個不同團隊的既有來源原圖，並沿用原來源收據，沒有把別人的歷史觀看紀錄當成本次新增研究：

| 作品／圖 | 本輪看到的內容與採用處 |
|---|---|
| [Hollow Knight地圖](../../pm/Nest-Egg/attachments/NE-223-route-references/hollow-knight-map.jpg) | 地形與節點是主體，名稱退為定位資訊；保留地圖原層級。 |
| [Blasphemous地圖](../../pm/Nest-Egg/attachments/NE-223-route-references/blasphemous-map.png) | 操作說明集中頁尾；切語言保留焦點與原操作說明位置。 |
| [Hades路線圖](../../pm/Nest-Egg/attachments/NE-223-route-references/hades-map.jpg) | 路線／獎勵圖示與背景分層；語言顯示不順便重寫路線、獎勵或進度。這是本作的設計推論，非他作內部實作。 |
| [Cyberpunk 2077日誌](../../pm/Nest-Egg/attachments/NE-223-route-references/cyberpunk-2077-journal.png) | 左側選中任務與右側完整目標／可捲動背景；保留短列與全文細節，長列以省略號表明尚有全文。 |
| [Metroid Dread任務紀錄](../../pm/Nest-Egg/attachments/NE-279-references/metroid-log.jpg) | 列表與選中項的完整閱讀面板分開；目標列有限時仍提供可讀全文。 |

原來源／圖片SHA見[任務原圖索引](../../pm/Nest-Egg/attachments/NE-223-route-references/sources.json)及[Metroid官方圖來源](../../pm/Nest-Egg/attachments/NE-279-references/sources.json)。圖片只支持可見的資訊層級，不作玩家偏好統計或翻譯／回退實作證據。

即時更新也必須保留外部焦點：新增回歸在三語中均重現其他畫面已取得焦點卻被任務列搶走。重建時只在任務頁原本持有焦點才安排第一項與原位置的焦點恢復；背景頁照常更新內容，不覆蓋別的頁面／模態控制項的焦點。靜態版面五組是在此焦點守衛前完成，原版面建置路徑預設保持相同；最終來源另以真正原生即時更新及原範圍回歸複驗。
