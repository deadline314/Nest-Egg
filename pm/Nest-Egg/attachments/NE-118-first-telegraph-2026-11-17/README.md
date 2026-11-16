# NE-118：鎖鏈預兆首格與現行配置驗證

Godot 4.7.2 ed1daf0bf、原生 Vulkan Forward+、Radeon RX 9070 XT、1280×720。
執行 `python verify.py` 可獨立核對壓縮包內 119 個原件及 48 張 PNG，無須啟動引擎。

## 問題與最小修正

第一次鎖鏈預兆出現時，方向仍是預設右方，即使玩家在左邊。下一個物理影格才更新，造成預兆首格與真正出手方向不同。
在正式狀態入口先沿原流程轉向，再初始化瞄準方向；前段追蹤、後段鎖定、範圍、時間、傷害及鎖鏈解除均保持。

嚴格拍攝工具使用相同自然 FSM 入口，確認目標狀態真的出現後才凍結兩個繪製影格拍照。原流程可能在等待過程中錯過短狀態，現在未出現會直接斷言失敗。沒有直接指定敵人的 FSM。
章節配置工具先讓敵人落地，隱藏 HUD 與附近道具的說明；配置照之後只隱藏主角圖像，使近身武器不被遮擋。玩家碰撞、目標與敵人判定仍在。這是外觀審查安排，不是自然通關或實體輸入驗收。

## 原始對照與測試

| 來源 | 結果與界線 |
|---|---|
| 初輪章節配置 | 8 張原生圖；世界道具說明遮住近身敵人，保留原圖 |
| 第二輪 | 8 張原生圖；只藏 HUD 仍無法移除世界提示，保留原圖 |
| 嚴格原版 | 8 張實際第二章配置／預兆及 12 張四敵人的狀態圖；發現第一格方向錯誤 |
| 首格回歸原版 | 138 checks／1 failure，正是第一格朝向；沒有刪除原失敗 |
| 最終原生 | 相同嚴格工具，12 張狀態圖、自然 exit 0、來源不變、無 ERROR／SCRIPT ERROR |
| 原受影響入口 | 固定 3713db51062b14ed33ab61488559109fc41e2bfd，32 組、56,758 checks、新失敗 0、已知失敗 0，666 秒 |
| 執行前後 | 四份產品／測試／工具來源 SHA 完全相同，與交付版本相同 |

正式測試原始日誌含故意損毀 fixture 的診斷；第一個程序退出時另有 1 Area2D RID、1 CanvasItem、4 ObjectDB、2 resources 未釋放的診斷，第二個程序末尾沒有此退出診斷。正式入口判定通過、兩份均無 SCRIPT ERROR；不把整輪 raw log 寫成零 ERROR，也不以原生拍攝乾淨代稱這些退出診斷消失。最終回歸包含既有跳躍／蹲躲、格擋／打斷、拉扯與牆面，以及章節互斥配置。

原版 CPU 負控制意外從主工作樹啟動，並非隔離樹。其來源在負控制結束、產品修正前保存；`source-after-control-before-fix.json` 如實記錄時點，沒有偽稱為執行前量測。該產品仍為已發布原版；新增斷言是故意差異。最終 32 組及原生拍攝均在獨立工作樹執行。

`native-placement/reconstructed-published-source` 是由已發布 Git blob 重建、且逐檔吻合當時 request SHA 的來源，並非假稱當時另存過一次。其餘當時實際保存的工具與資料原 bytes 原樣收錄。

## 圖片與重跑

票上首格前後圖直接複製自 `native-v3/strike_enemies/chain_hook_windup.png` 與 `native-final/chain_hook_windup.png`；沒有縮放或重畫。雨、蒸汽與相位會因獨立程序不同，未以整張像素差宣稱單因子改善。可見改變是預兆路線立即朝玩家。

```powershell
python tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/screenshot.tscn -- --out=<新絕對資料夾> --scenario=strike_enemies
```

`--scenario=strike_placement` 可重拍實際第二章的四種配置。來源與安排見每次 `request.json`；高生命、安排站位、隱藏其他敵人與拍攝凍結均有明記。沒有更換敵人素材、行為數值、章節生成資料或預兆門檻。
