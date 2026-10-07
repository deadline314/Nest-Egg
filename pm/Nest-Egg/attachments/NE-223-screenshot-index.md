# NE-223 實際截圖索引

Godot 4.7 stable，Forward+／Vulkan，Linux llvmpipe 軟體渲染。所有圖片為遊戲視窗實際擷取；未宣稱硬體 GPU 效能或實體手把人工驗收。

任務、旗標與完成狀態使用明確標示的介面驗證樣本；地圖地形、出入口與標記來自真實第一章九份關卡。探索取樣使用真實視線遮蔽演算法，並非人工走完章節。正式故事來源任務数為 0；樣本不作為正式主線驗收。

| 畫面 | 亮場景 1280×720 | 暗場景 1280×720 | 亮場景 1920×1080 | 暗場景 1920×1080 |
|---|---|---|---|---|
| HUD | [查看](../images/NE-223-pawnshop-hud-1280-fixture.png) | [查看](../images/NE-223-vault-hud-1280-fixture.png) | [查看](../images/NE-223-pawnshop-hud-1920-fixture.png) | [查看](../images/NE-223-vault-hud-1920-fixture.png) |
| 進行中／全部種類 | [查看](../images/NE-223-pawnshop-quests_all-1280-fixture.png) | [查看](../images/NE-223-vault-quests_all-1280-fixture.png) | [查看](../images/NE-223-pawnshop-quests_all-1920-fixture.png) | [查看](../images/NE-223-vault-quests_all-1920-fixture.png) |
| 主線 | [查看](../images/NE-223-pawnshop-quests_main-1280-fixture.png) | [查看](../images/NE-223-vault-quests_main-1280-fixture.png) | [查看](../images/NE-223-pawnshop-quests_main-1920-fixture.png) | [查看](../images/NE-223-vault-quests_main-1920-fixture.png) |
| 支線／阻塞建議 | [查看](../images/NE-223-pawnshop-quests_side-1280-fixture.png) | [查看](../images/NE-223-vault-quests_side-1280-fixture.png) | [查看](../images/NE-223-pawnshop-quests_side-1920-fixture.png) | [查看](../images/NE-223-vault-quests_side-1920-fixture.png) |
| 已完成 | [查看](../images/NE-223-pawnshop-quests_completed-1280-fixture.png) | [查看](../images/NE-223-vault-quests_completed-1280-fixture.png) | [查看](../images/NE-223-pawnshop-quests_completed-1920-fixture.png) | [查看](../images/NE-223-vault-quests_completed-1920-fixture.png) |
| 區域地圖 | [查看](../images/NE-223-pawnshop-region-1280-fixture.png) | [查看](../images/NE-223-vault-region-1280-fixture.png) | [查看](../images/NE-223-pawnshop-region-1920-fixture.png) | [查看](../images/NE-223-vault-region-1920-fixture.png) |
| 世界地圖 | [查看](../images/NE-223-pawnshop-world-1280-fixture.png) | [查看](../images/NE-223-vault-world-1280-fixture.png) | [查看](../images/NE-223-pawnshop-world-1920-fixture.png) | [查看](../images/NE-223-vault-world-1920-fixture.png) |

## 正式來源的當前入口

這組已於 ST-3 319eaf87 合入後重拍，沒有載入樣本任務：真實空目錄與沒有目標列的 HUD 是目前來源的實際限制。

- [HUD](../images/NE-223-pawnshop-hud-1280-source.png)
- [暫停選單](../images/NE-223-pawnshop-pause-1280-source.png)
- [任務空目錄](../images/NE-223-pawnshop-quests-1280-source.png)
- [區域地圖](../images/NE-223-pawnshop-region-1280-source.png)
- [世界地圖](../images/NE-223-pawnshop-world-1280-source.png)

## 版面與資料稽核

版面檢查排除受捲動容器裁切的內容，檢查其餘可見控制項是否超出視窗；仍需使用者審查可讀性與操作感受。

- [pawnshop 1280 樣本版面](NE-223-layout-pawnshop-1280-fixture.json)
- [vault 1280 樣本版面](NE-223-layout-vault-1280-fixture.json)
- [pawnshop 1920 樣本版面](NE-223-layout-pawnshop-1920-fixture.json)
- [vault 1920 樣本版面](NE-223-layout-vault-1920-fixture.json)
- [正式來源版面](NE-223-layout-pawnshop-1280-source.json)
- [真實故事與關卡來源稽核](NE-223-source-audit.json)
- [截圖執行摘要](NE-223-screenshot-runs.log)
