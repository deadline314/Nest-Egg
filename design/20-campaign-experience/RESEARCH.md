# 設計依據與採用界線

2026-10-10 查核。以下是開發者做法與官方指南；採用方案為 Nest Egg 的設計判斷，不表示存在所有玩家一致認可的最佳樣式。玩家論壇只用來識別需要遊測的風險。

| 來源 | 原資料支持的重點 | 本專案採用 |
|---|---|---|
| [Dead Cells 主設計師：關卡設計](https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/) | 手工功能區與固定世界結構讓布局有邏輯，敵人放置受用途約束 | 先有區域連線與功能，再做地形；保持高峰、低谷與區域特色 |
| [Team Cherry 官方訪談](https://www.nintendo.com/au/news-and-articles/the-metamorphosis-of-hollow-knight-with-team-cherry-aussie-developer-interview/) | 可探索其他路線再回到難關，人物有動機與事件反應 | 支線、捷徑、安全區與回訪對話；不硬套完全非線性 |
| [Supergiant：Hades 更新紀錄](https://www.supergiantgames.com/blog/hades-updates/) | 支線與角色事件需要條件、優先序和頻率修正 | 正式任務、反應式對話、首次與重複演出分開驗證 |
| [Supergiant：Bastion 寫作](https://www.supergiantgames.com/blog/in-depth-writing-bastion/) | 敘事可回應玩家當下活動 | 調查、探索、死亡與選擇引出合理反應；避免僅靠強制長對話 |
| [Dead Cells 經濟改版](https://store.steampowered.com/news/posts/?appids=588650&enddate=1595515515&feed=steam_community_announcements) | 價格與收入曲線影響玩家是否敢購買、嘗試裝備 | 跨章收支與購買體驗實測；不照抄數值 |
| [Dead Cells 動畫美術師](https://www.gamedeveloper.com/production/art-design-deep-dive-using-a-3d-pipeline-for-2d-animation-in-i-dead-cells-i-) | 清楚關鍵姿勢與時機先成立，特效補力度 | 武器預備、有效段、收招與身體動作先驗收，再加少量特效；保留目前骨架管線 |
| [Dead Cells 場景美術師](https://www.gamedeveloper.com/production/art-design-deep-dive-giving-back-colors-to-cryptic-worlds-in-i-dead-cells-i-) | 背景、地形、互動物與威脅有不同視覺優先序，装飾有放置語法 | 各區色盤、用途、安裝面与素材清單；敵人、落點與互動提示優先 |
| [Dead Cells 官方無障礙更新](https://dead-cells.com/patchnotes/29) | HUD、文字、輪廓、攻擊預告、粒子與背景對比可調 | 高清像素介面可讀、圖形与色彩並用、威脅不被特效淹沒 |
| [Godot 多解析度](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) | 像素整數縮放、渲染方式與 UI 適配需分開決定 | 共用像素密度、中文字可讀與寬高比安全區；不降低整個世界解析度 |
| [Steam Input 官方指南](https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs) | 完整手把导航、裝置提示一致、裝置拔插處理 | 真手把全流程、近期輸入提示、斷線處理；不要求以 Steam SDK 重建輸入 |
| [Microsoft XAG 112](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) | 一致確認、返回、分頁、焦點順序與放大文字布局 | 所有頁面同一操作語法、焦點恢复、清楚資訊階層 |
| [Microsoft XAG 113](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113) | 跨背景清楚焦點，模態畫面焦點範圍正確 | 焦點不用微弱發光當唯一標記；不穿透到背後頁面 |
| [Microsoft XAG 117](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117) | 可减動態，閱讀區動效不妨礙理解 | 可調轉場、鏡頭震動、閃光與裝飾粒子，保留必要資訊 |
| [Godot Windows 匯出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html) | 支援嵌入 PCK 單執行檔，總大小有约3.89GB限制 | 累積章節單檔產物、白名單及體積檢查、本機乾淨目錄啟動 |
| [PlayStation：開發者談戰鬥打擊感](https://blog.playstation.com/2022/10/04/game-developers-explain-what-makes-god-of-war-2018s-combat-tick/) | 動畫、聲音、受擊與命中停顿共同形成重量；攻擊提示分清防禦能力 | 重武器用姿態与時間成本表現；不單靠閃光／震動；盾面与實際判定相符 |
| [Hades Superstar 官方更新](https://www.supergiantgames.com/blog/hades-superstar-update-patch-notes/) | 盾回收、投射物呈現及單次攻擊重複傷害都需修正 | 視覺、碰撞、反射與單擊傷害一起驗證，不把新素材直接視作戰鬥完成 |
| [Leyla In Veil 官方 Steam 截圖](https://store.steampowered.com/app/3904870/)（2026-10-11 實際看過 10 張） | 戰鬥 HUD 不加框，集中在左下：彈匣／備彈數字、武器像素剪影、細血條帶心電圖線；左上信用點與會淡出的拾取紀錄；背包左列物品、選中列反白、數量靠右且不足時轉紅、右側角色立繪；分頁圖示兩側標 Q／E；互動以按鍵字母浮在物件上 | 背景 HUD 留在角落、讀取或選單時退讓；選中態用高對比反白而不只靠發光；數量與不足狀態靠顏色加數字；分頁按鍵直接標在分頁旁。沿用 Nest Egg 霓虹色盤、字型與高低多方向地圖，不照抄其紅黑配色與立繪 |

## 玩家樣本與限制

| 樣本 | 觀察 | 對驗收的影響 |
|---|---|---|
| [美術與視覺雜訊討論](https://www.reddit.com/r/metroidvania/comments/tw2wkd/metroidvania_with_highend_or_beautiful_graphics/) | 對高細節美術與粒子雜訊的感受不同 | 看高速操作中是否能辨敵人、落點与互動物；不宣稱某畫風普遍最佳 |
| [頻繁劇情打斷討論](https://www.reddit.com/r/metroidvania/comments/1hqjn5v/give_me_the_absolute_worst_metroidvania_you_can/) | 有喜歡故事與美術但不喜歡頻繁中斷的回覆 | 演出丰富與可跳过、重试不重播、主動交談同時做到 |
| [格擋提示討論](https://www.reddit.com/r/deadcells/comments/1eb2enf/i_just_learned_the_trick_for_parrying_and_i_feel/) | 一致提示有助理解，但距离、敌人动作仍影响時機 | 盾的前／中／後窗口、方向及距离驗證，提示不假裝是一律成功時刻 |
| [盾牌價值討論](https://www.reddit.com/r/deadcells/comments/1cmn6ec/are_shields_useless/) | 新手、雙武器與格擋玩家偏好不同 | 教學说明覆盖與時機，避免唯一有效玩法，支持其他戰術 |

無通用最佳連段數、停顿秒数、傷害倍率、盾外形、過場比例、章節時長或敵人重複率。這些值由本專案設計、實際玩法與人工遊玩校正。21:9 接近預告是本次使用者要求，不當作業界普遍做法；具體預告範圍與時間先做可操作樣本再定稿。
