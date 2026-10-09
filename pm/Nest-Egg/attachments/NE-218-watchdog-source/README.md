# NE-218 四足看門狗：靜態來源基線

此交付只建立專屬四足來源與透明背景證據，不是分件、骨架、動畫或遊戲整合驗收。遊戲目前仍使用原有替身。

## 來源與重跑

原始 1536×1024 RGBA、種子 21801、30 steps、模型名稱、完整提示詞、工作流及快取工作紀錄保存在 `art_src/creatures/watchdog/design_21801/`。未縮圖，原始 PNG 保持不變。生成必須依現有 Comfy guard／GPU 鎖操作；本次實際 Comfy 安裝位置為 `D:/ComfyUI`。

在專案根目錄執行：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' art_src/creatures/watchdog/design_21801/rebuild.py
& 'D:/ComfyUI/.venv/Scripts/python.exe' pm/Nest-Egg/attachments/NE-218-watchdog-source/verify.py
```

原圖背景有低 alpha 紫色霧，且金屬內部不完全不透明。沿用既有 `clean_alpha` 清除 alpha≤8 的背景；對 alpha≥127 遮罩向內縮 5 像素的內部設為 255，明確修正金屬透明度。清除 1,232,389 個背景像素（包含原先透明但 RGB 未清空的像素），142,971 個內部像素補為不透明。保留區域 RGB 完全一致，輪廓抗鋸齒未改。這不是補繪被遮擋部件，也不是把棋盤格當透明背景。

`rebuild.json` 記錄原圖與輸出 SHA；輸入損壞時在寫入前拒絕。`verify.json` 記錄兩次重跑一致、單 byte 損壞負控制及六張原生 PNG 的尺寸／顏色對照。黑白底完全一致；灰底最大通道誤差 1，源於 GPU 混色量化。全部 1536×1024，沒有縮放。

## 原生截圖

停用 Comfy 常駐模型後，在共享 GPU 鎖內執行：

```powershell
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://pm/Nest-Egg/attachments/NE-218-watchdog-source/capture.tscn
```

本次 Forward+／RTX 4070 SUPER，退出碼 0，執行無 ERROR。六張圖位於 `pm/Nest-Egg/images/NE-218-watchdog-source/`。這些是實際 SubViewport 來源圖預覽，沒有骨架、材質法線或場景光照，不能充當遊戲內畫質與戰鬥驗收。

## 下一個驗收邊界

四條腿與四個單足逐一確認像素所有權；後腿須保留犬科膝與飛節，不能硬套人形雙段腿。遮擋處須補足獨立底層。站姿接合、動態逐格、地面接觸、攻擊／受擊／死亡、左右翻面、原碰撞與平衡回歸、HDR 材質及實際關卡均依原技能門檻檢查。任一細縫、混入另一足、未驗證底層均不通過。
