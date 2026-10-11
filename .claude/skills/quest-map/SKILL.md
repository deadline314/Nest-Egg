---
name: quest-map
description: 新增或驗證任務、地圖標記、探索狀態、釘選及 HUD 指引時使用；任務真相保留在故事產生器，地圖使用實際 LevelData。
---

# 任務與地圖

先讀 `design/18-quest-map-ux/DESIGN.md`、`design/13-story-v2/DIALOGUE_READABILITY.md` 和本票完整交付紀錄。跨 Session 接線先核對 origin/main，依 `design/18-quest-map-ux/SESSION3_INTERFACE.md` 一次交接，不同時重寫故事、旗標或主流程。

## 唯一資料來源

任務由故事產生器輸出到章節 JSON 的 `quests`。不要只改輸出 JSON，不要另外維護任務故事、硬編旗標或用 UI 測試樣本填補正式主線。

一项任務包含 `id`、`kind`（main / side）、`title`、`background`、`reward`、`complete_flag`、`steps`。每一步包含 `title`、`complete_flag`、`location`（真實 LevelData 路徑 `level` 與整數格座標 `cell: [x,y]`）。格座標是角色腳底所在的格子，不是像素座標。

`requires_flags` 表示前置條件；不滿足時要提供 `blocked_reason` 和 `suggestion`。`visible_flags` 表示可以公開任務的時機，避免提前劇透。完成、前置與公開旗標必須使用故事服務已定義、有生產者且可達的旗標。UI 僅讀取，不設定它們。

## 新增任務

1. 從劇本、故事生產者與真實關卡核對完成條件、目的地、獎勵和前置。缺少語義先交故事 Session 補充原始產生器。
2. 在原始產生器加入或更新任務欄位，重產資料；不把測試樣本當故事內容。
3. 跑任務資料檢查與故事的順序模擬。每一個可玩狀態都至少有一個可進行主線目標；包含新遊戲、第一章結尾、序章正常結束與跳過。
4. 對照完成旗標的生產者、位置有效性、公開時機及前置可達性；存在旗標名稱不代表玩家實際到得了。
5. 跑 `tools/run_tests_changed.sh <交付前基準SHA>`；NE-223 還要求完整測試。提交或 rebase 後使用保留的基準，不能誤跑空集合。
6. 使用 `tools/quest_map_probe.tscn` 在 Forward+、亮暗區域、1280×720 與 1920×1080 檢視所有分頁及 HUD。HDR 2D 截圖沿用 `tools/viewport_capture.gd` 將線性色彩轉為 PNG 的 sRGB；不要直接儲存線性 readback。`--fixtures` 的樣本畫面不能當正式任務驗收。渲染和匯入使用 `tools/comfyui/gpu_lock.py` 的共享鎖。

## 地圖與狀態

區域、連接與標記來自 LevelData / LevelBuilder。出入口提示沿用 `PortalData.locked_text`；閘門提示沿用 `MechanismData.hint`，原因與取得方式須在原始產生器補完整，保持遊戲內與地圖一致。

探索以可見格子保存；實心地形與未破壞的秘密牆遮擋視線。圖形依探索版本快取，不在每影格重建。傳送尚未由遊戲提供時只標示已啟用復原點，不做不能實際執行的傳送按鈕。

主流程把 `QuestMapState.for_run().snapshot()` 放進正式存檔的 `navigation`；還原故事／區域狀態之後才呼叫 `restore(raw, catalog, index)`。不要另建獨立的導覽存檔而與故事存檔不同步。損毀測試要核對警告中具體欄位、有效資料保留和安全預設；快照往返不能代替真正退出遊戲再讀檔。

## 視覺版面

- 依據與範本在 `design/18-quest-map-ux/VISUAL_RESEARCH.md`（使用者 2026-10-11 選定：終端機雙欄＋模糊遊戲畫面當底＋斜切目前步驟橫幅）。改版前先看那份與實際截圖，不回到一排同重量大按鈕的做法。
- 共用元件：`FlatStyle`（分頁、分段、清單列、按鍵提示）、`SceneBackdrop`（模糊底）、`SlantBanner`（目前步驟、HUD 目標列）、`ScrollCue`（下方還有內容）。字級用 `UiKit.caption()`／`heading()`，像素字體會自動退回內文字級。
- HDR 2D 在線性色彩混色：半透明疊色、格線看起來比數字亮，調不透明度要看實際 Forward+ 截圖。

## 可讀性與操作

- 任務標題用動詞開頭，寫完整的一件事；背景、阻塞原因、建議和 tooltip 寫完整句子，不用兩三字片段裝酷。
- 內文允許捲動，任務標題和目標列必須一行可讀；看過實際畫面才勾選版面驗收。
- 鍵盤、手把的確認、返回、方向、切分頁、釘選與跳圖都要驗證。手把聚焦圖示後，底部要顯示與滑鼠 tooltip 相同的文字。
- 返回回上一層且恢復選中項與焦點，不能直接跳回遊戲。
- 沒有正式任務資料時顯示真實空狀態，保留票為進行中；不要用樣本或空白 HUD 假稱完成。
