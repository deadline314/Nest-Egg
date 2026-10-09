# NE-225 道具圖示交付紀錄

檢查 11 份 LevelData、10 張正式地圖，含第一章各區與已實作第二章。清晨當舖共用原地圖；計數按 LevelData 記錄，不代表互不重複的地圖實例。24 種實際拾取圖示皆有素材，缺圖 0。

下表為關卡實際使用種類。另補齊 pistol，供初始武器及未來掉落沿用同一風格，沒有增加新的關卡掉落。背包與武器手持圖維持既有素材。

| 圖示 | 出現數 | 本次處理 |
|---|---:|---|
| ch1_data_disk | 1 | 沿用既有實物圖示 |
| credits_large | 8 | 沿用既有實物圖示 |
| credits_small | 37 | 沿用既有實物圖示 |
| doc_flyer | 1 | 沿用既有實物圖示 |
| doc_log | 1 | 沿用既有實物圖示 |
| doc_news | 1 | 沿用既有實物圖示 |
| doc_notice | 1 | 沿用既有實物圖示 |
| doc_stub | 2 | 沿用既有實物圖示 |
| document | 6 | ComfyUI 實物圖示 |
| laser | 2 | ComfyUI 實物圖示 |
| launcher | 1 | ComfyUI 實物圖示 |
| med_injector | 16 | 沿用既有實物圖示 |
| melee_blade | 1 | ComfyUI 實物圖示 |
| melee_dagger | 3 | ComfyUI 實物圖示 |
| melee_glaive | 1 | ComfyUI 實物圖示 |
| melee_maul | 1 | ComfyUI 實物圖示 |
| melee_whip | 1 | ComfyUI 實物圖示 |
| railgun | 1 | ComfyUI 實物圖示 |
| recording | 3 | ComfyUI 實物圖示 |
| repair_pack | 9 | ComfyUI 實物圖示 |
| rifle | 2 | ComfyUI 實物圖示 |
| shield_cell | 10 | 沿用既有實物圖示 |
| shotgun | 2 | ComfyUI 實物圖示 |
| smg | 2 | ComfyUI 實物圖示 |

## 圖像與記憶體

15 張原生透明 RGBA 由本機 ComfyUI 的 Qwen Image 2.1 工作流程逐張生成；來源、提示詞、種子、模型名稱與 SHA-256 保存在 assets_src/generated/world_items。生成規格640×640、20步，固定種子；加工為96×96貼圖，以24×24世界單位顯示，淡色輪廓與小幅浮動提供辨識。工具一次僅處理一張圖片，生成完成即停止 ComfyUI。未使用整批解碼圖像快取。

按使用者要求移除預先停止的 RAM 門檻，改為觀察用量。模型載入曾短暫只餘約0.34 GiB可用 RAM，生成期間 ComfyUI 回報約4.83/11.60 GiB VRAM可用；完成並停止服務後 RAM 回到約18.8 GiB。這是實際生成紀錄，不能據此保證日後重跑一定安全。此次沒有當機，模型已釋放。

逐張檢查來源與96×96貼圖的透明通道、來源雜湊及空白自發光層。人工查看小圖與原生遊戲畫面：輪廓可辨認，沒有假字、額外背景或白色發光塊；細長武器以遊戲外緣輪廓輔助辨識。

## 原生畫面

Godot 4.7.2 / Intel Arc B580 / Forward+，1280×720原生截圖，沒有縮放圖片。第一章夜景、同街道中性明亮照明壓力測試、第二章，均有低/高畫質。明亮組為控制光照，不是正式夜景。擷取時在真實關卡擺放七種拾取物供同場比較，不改正式關卡配置。

修後圖：pm/Nest-Egg/images/NE-225-after-*.png。修前以相同擷取工具和4b32e788的道具程式及素材重現，移除本次新圖的匯入映射，避免快取誤用；after與before均在最新811351caf佈景上擷取，僅道具程式和素材不同。遊戲退出有ObjectDB warning；保留完整輸出。

## 證據

- ne225-scope.json：實際關卡盤點與零缺圖結果。
- asset_checks.json：15張來源雜湊、尺寸與透明通道。
- ne225-generation-*.log：逐張生成與 RAM/VRAM觀察。
- ne225-red.log：新增素材接點測試在替換前確實失敗。
- ne225-final-affected.log：修正完成後依固定基準4b32e788選出的受影響測試。

最終驗證：固定4b32e788受影響49群33,312 checks / 0新或已知失敗，261秒；rebase811351caf後6套交集3,197 checks / 0新或已知失敗，27秒。兩輪皆無非預期腳本錯誤；首次headless主選單貼圖初始化錯誤沒有當作通過，保留first log，未更改filter。
