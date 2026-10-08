# NE-66 三檔光影與風格審查

本次保留既有 grade_master、LightKit、25 份光影 profile 與角色 shader 設定。BG-17 僅調整環境匯入資料與尺寸補償；沒有重新調色、生成美術、改家具／地圖位置。原 NE-66-before-after.png 的替換前風格對照仍保留。

## 三檔對照

原生 Forward+ / 軟體 Vulkan llvmpipe，640×360，同一份 environment_probe、第一與第二章各三處、5 隻靜止 grunt，HUD 隱藏；保留目前 main 的地圖氣泡與通訊面板（其文字／時序由 ST-15 決定），它們可能遮住部分中景。每點暖機 120 frames 後取樣，截圖在計時後保存；30-frame 樣本僅服務三檔畫面對照，不當效能驗收。背景動態霓虹／雨的相位會不同。

| 品質 | 法線 | 動態光源／陰影 | 光錐 | 後製顆粒／色差 |
|---|---|---|---|---|
| 低 | 關 | 8／1 | 關 | 關 |
| 中 | 開 | 14／2 | 半細節 | 關 |
| 高 | 開 | 24／4 | 全细節 | 開 |

第一章取樣屋頂巷弄／霓虹市集／貨運站，第二章升降井入口／夾層／電力室。完整兩章修前／修後高檔環境與舞台對照見 BG-17 票內圖片，資料加工前舊美術風格參考見 NE-66-before-after.png。

## 需要使用者審查

1. 深藍紫底、青／洋紅霓虹與暖色室內是否繼續沿用。
2. 高／中檔法線與光錐強度是否合適；低檔敵人輪廓是否足以辨識。
3. BG-17 降低匯入解析度後，背景線條、招牌、家具及舞台是否有可見品質退化。
4. 角色霓虹／曝亮問題由 Session 1 的 NE-222 接手；本次未改角色、骨架或共用全局參數，也未替使用者勾選風格同意。

## 未通過與接手條件

同機低檔相對 ca369c71 的 105% 耗時尚未達標；無實體 GPU，軟體渲染結果不代表 Arc B580 實機。暗場敵人對比不足也可在未改動的 6f4805be 重現，原票 12 個區段通過的紀錄不能替代目前 16 個區段複驗。依實測保留未通過勾選，不宣稱 NE-66／BG-17 完成。

重現：BG-17 的 attachments/BG-17-protocol.md；可讀性固定 640×360、每點 16 個時間樣本，玩家≥0.6、地面≥1.0、敵人≥0.45（log 顯示一位小數 0.5，實際門檻是 0.45）。完整測試結果另記票內，CI 查詢 Forbidden 時如實記錄無法核對。

## 原始圖與 log


low / level_01：[tile 30](../images/NE-66-session5-low/level_01_30_low.png), [tile 115](../images/NE-66-session5-low/level_01_115_low.png), [tile 200](../images/NE-66-session5-low/level_01_200_low.png)。

low / level_02：[tile 30](../images/NE-66-session5-low/level_02_30_low.png), [tile 175](../images/NE-66-session5-low/level_02_175_low.png), [tile 350](../images/NE-66-session5-low/level_02_350_low.png)。

medium / level_01：[tile 30](../images/NE-66-session5-medium/level_01_30_medium.png), [tile 115](../images/NE-66-session5-medium/level_01_115_medium.png), [tile 200](../images/NE-66-session5-medium/level_01_200_medium.png)。

medium / level_02：[tile 30](../images/NE-66-session5-medium/level_02_30_medium.png), [tile 175](../images/NE-66-session5-medium/level_02_175_medium.png), [tile 350](../images/NE-66-session5-medium/level_02_350_medium.png)。

high / level_01：[tile 30](../images/NE-66-session5-high/level_01_30_high.png), [tile 115](../images/NE-66-session5-high/level_01_115_high.png), [tile 200](../images/NE-66-session5-high/level_01_200_high.png)。

high / level_02：[tile 30](../images/NE-66-session5-high/level_02_30_high.png), [tile 175](../images/NE-66-session5-high/level_02_175_high.png), [tile 350](../images/NE-66-session5-high/level_02_350_high.png)。
