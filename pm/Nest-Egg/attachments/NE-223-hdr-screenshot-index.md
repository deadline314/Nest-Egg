# NE-223 HDR 色彩修正後的實際截圖

2026-10-09；以 dfacf916 為 main 基線，Godot 4.7 stable、Forward+／Vulkan／llvmpipe，PNG 已從 HDR 2D 線性色彩轉成 sRGB。所有渲染與匯入沿用共享 GPU 鎖；沒有操作 ComfyUI。

沿用既有 UI、真實九區地圖與視線探索取樣，沒有改故事／角色／關卡。28 張介面樣本均有水印，不算正式主線驗收；另有當前正式入口五張及同基線修前對照一張。

| 畫面 | 亮場景 720p | 暗場景 720p | 亮場景 1080p | 暗場景 1080p |
|---|---|---|---|---|
| HUD | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-hud-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-hud-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-hud-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-hud-1920-fixture.png) |
| 進行中／全部 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_all-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_all-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_all-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_all-1920-fixture.png) |
| 主線 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_main-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_main-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_main-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_main-1920-fixture.png) |
| 支線／阻塞建議 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_side-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_side-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_side-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_side-1920-fixture.png) |
| 已完成 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_completed-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_completed-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests_completed-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-quests_completed-1920-fixture.png) |
| 區域地圖 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-region-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-region-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-region-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-region-1920-fixture.png) |
| 世界地圖 | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-world-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-world-1280-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-pawnshop-world-1920-fixture.png) | [查看](../images/NE-223-hdr-20261009/NE-223-vault-world-1920-fixture.png) |

正式來源（不載入樣本任務）：

- [hud](../images/NE-223-hdr-20261009/NE-223-pawnshop-hud-1280-source.png)
- [pause](../images/NE-223-hdr-20261009/NE-223-pawnshop-pause-1280-source.png)
- [quests](../images/NE-223-hdr-20261009/NE-223-pawnshop-quests-1280-source.png)
- [region](../images/NE-223-hdr-20261009/NE-223-pawnshop-region-1280-source.png)
- [world](../images/NE-223-hdr-20261009/NE-223-pawnshop-world-1280-source.png)

[同基線線性 PNG 修前](../images/NE-223-hdr-20261009/NE-223-pawnshop-hud-1280-linear-before.png)與[轉成 sRGB 後](../images/NE-223-hdr-20261009/NE-223-pawnshop-hud-1280-fixture.png)可直接對照。場景為兩次實際啟動，動畫／計時的微小差異不作色彩驗收依據；已知顏色、透明度、尺寸以[基準檢查](NE-223-hdr-capture-check.log)核對。

五份版面報告均為 0 溢出，捲動內容允許裁切並可由鍵盤／手把捲動：

- [layout-pawnshop-1280-fixture](../images/NE-223-hdr-20261009/layout-pawnshop-1280-fixture.json)
- [layout-pawnshop-1280-source](../images/NE-223-hdr-20261009/layout-pawnshop-1280-source.json)
- [layout-pawnshop-1920-fixture](../images/NE-223-hdr-20261009/layout-pawnshop-1920-fixture.json)
- [layout-vault-1280-fixture](../images/NE-223-hdr-20261009/layout-vault-1280-fixture.json)
- [layout-vault-1920-fixture](../images/NE-223-hdr-20261009/layout-vault-1920-fixture.json)

[截圖執行紀錄](NE-223-hdr-screenshot-runs.log)、[全文可讀性](NE-223-resume-story-lint.log)、[當前正式來源稽核](NE-223-resume-source-audit.json)。正式任務仍為 0，稽核預期退出 1；不是驗收通過。沒有實體手把／硬體 GPU，未宣稱人工操作與實機效能。保留既有退出時資源診斷，未出現 SCRIPT ERROR。
