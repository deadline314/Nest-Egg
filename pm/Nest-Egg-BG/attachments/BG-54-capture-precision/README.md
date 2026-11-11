# BG-54 暗部截圖精度收據

2026-11-11，Godot 4.7.2、Forward+／Vulkan、HDR 2D、AMD Radeon RX 9070 XT。只改擷取編碼，未改背景、燈光、材質、模糊或曝光。原生執行經 repo GPU 鎖串行；同機仍可能有其他專案工作，不以此量效能或宣稱全機空閒。

## 原始位元組與獨立驗證

- `raw.zip`：45,825,862 bytes，SHA-256 `64fd0b8b1a33b0349919ca4ea4020ddb7adb33aebf994df2b36b01b443679d96`。
- `verification.json`：獨立 Python／NumPy 分段 IEC sRGB 公式，逐像素讀 ZIP 內原生浮點資料，與解碼後 PNG 核對；141 個 manifest 成員／來源收據驗證，六張共 8,985,600 像素，最大 sRGB 誤差 `0.003921308517456055`（≤1/255），alpha 誤差 0。
- 原始 bytes、PNG、執行 log、CPU 負控制、當時程式來源的 byte-preserving 副本、每個成員 SHA-256 與來源 SHA 均在 ZIP；驗證器來源亦封存。ZIP 不受 Git CRLF 文字正規化影響。外層 JSON 是驗證結果，原始收據以 ZIP 內 bytes 為準。
- `diagnosis-history.zip`：22,862,132 bytes，SHA-256 `e32cb7425e4f9252b5cc28e11a315a0d0c166a0b0a6fbc5dc7ec80080eddcec1`，99 個成員逐一驗證。保留完整早期 NE-223 背景診斷、兩次錯誤 ALWAYS 工具、修正後 frozen 單因素對照及工具來源；各階段的限制見封包內原 README。這批歷史證據不代替新編碼的正式原生驗收。

```powershell
python tools/verify_capture_precision.py pm/Nest-Egg-BG/attachments/BG-54-capture-precision/raw.zip
```

重跑專項時先獨立執行 CPU 場景；原生批次透過 GPU 鎖串行，輸出到新絕對資料夾：

```powershell
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/test_capture_precision.tscn -- --out=<新絕對資料夾>
python tools/comfyui/gpu_lock.py -- python tools/run_capture_precision.py --godot C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --out <新絕對資料夾>
```

## 紅綠及原生結果

| 證據 | 結果 |
|---|---|
| CPU 已知 RGBAH／RGBAF 暗色 ramp，原流程 | 12／4；8 個暗部色階，最大誤差約 0.0494 |
| 相同測試來源，修正後公開入口 | 12／0；49 個色階，最大誤差 0.0039086／0.0038998；alpha、尺寸、來源 bytes、LDR bytes 保持 |
| 原生既有灰階回歸 | HDR 與 LDR、中間灰、八個暗色樣本、透明度、尺寸、公開擷取與直接編碼一致；exit 0，無 SCRIPT ERROR／引擎 ERROR |
| 原生當舖 1280×720 | 11／0；世界、暫停、任務各同一份浮點 readback 分別輸出舊／新 PNG；exit 0，無 SCRIPT ERROR／引擎 ERROR |
| 原生當舖 1920×1080 | 14／0；實際輸出尺寸斷言通過，三頁同上；exit 0，無 SCRIPT ERROR／引擎 ERROR |
| Exposure 專項（工作樹含 BG-53） | 238／0，約 20 秒 |
| 原選擇器受影響範圍（工作樹含 BG-53） | 6 組、3,893 項、0 新失敗、0 已知失敗、812 秒、exit 0 |

CPU 紅綠測試來源 SHA 均為 `ddfef7c6e1b63653e6a9115b4fc59d3c055a101969df526d679df75962e3d070`；負控制保留原編碼本體，只將 viewport 取得來源替換為已知 Image。`cpu-red-first` 是早一版測試，最終相同來源比較使用 `cpu-red`／`cpu-green`。

原生觀察節點 ALWAYS、真正 Level 明設 PAUSABLE。manifest 記錄前後同一玩家／鏡頭身分與位置、鏡頭中心／畫布變換、遊玩及霧時間相同，並核對世界與角色不能 process；不只斷言 tree.paused。第一次要求 1920 的工具被視窗設定還原為 1280，已保留在 `invalid-requested1920-actual1280.zip`，**不計入 1080p 驗收**；正式 `native-1920` 是修正啟動尺寸後重新執行。

背景產品來源 SHA `19c8834ada9bc5c1c0a7bb4af1038359a1c8ed17b2ce0b0a1d1fc040e02eaa02`，未修改。新擷取工具 SHA `390789818b405f341a6a0a24a880971353349c8c09dc907e9fd9d8538d98addd`；舊版 SHA `3a41272cf893fd32f7a4db93d4843f46ebee9dffb8881487f172b123466e05f3`。

## 回歸來源界線

六組選擇為 `main,DevMenuSuite,ExposureSuite,MeleeSuite,MeleeWeaponsSuite,ReadabilityTargetsSuite`，原命令基準 `96373764ba4a58be138df609cbc2302620dfe3ef`，兩 shards。測試當時使用共享 union 工作樹：同時有 BG-54 擷取守門、BG-53 對比幾何守門與修正，**不是精準 BG-54 單票 HEAD 的來源一致證明**。來源及邊界收據在 `BG-54-run-boundaries.json`、`BG-54-exposure-union-source.gd.txt`，各 shard 原 log 保留。

原 filters／threshold 未改。shard 1 關閉時有 1 個 CanvasItem RID、9 個 ObjectDB instances、5 個 resources 診斷，不能將總回歸描述為 0 ERROR 或乾淨釋放；原測試政策下退出碼為 0。獨立 CPU 12／0 與上述原生專項則各自驗證擷取修正。

## 視覺與正式物件重拍

六張新圖（世界、暫停、任務，各兩種解析度）逐張檢視。相同 raw 的舊任務／暫停圖有明顯有機色帶，新圖保持柔和當舖背景；root 另實看 1280 前後及真正 1920 新圖。公開精選為 `../../images/BG-54-{quests-1280,quests-1920,pause-1280}-{before,after}.png`，ZIP 保留全部原圖。

BG-47 以同版新工具重新執行三輪正式物件原生流程，normal 106／0（17 圖）、fallback 68／0（5 圖）、warehouse 4／0（2 圖），helper 與素材來源 before／after SHA 穩定；fallback 15 次刻意 loader ERROR 另保留，不代稱 0 ERROR。24 張原圖由負責者逐張檢視、root 另實看五張精選。原始來源見 [BG-47 新封包](../BG-47-native-2026-11-11/bg54-recapture-raw.zip)，SHA-256 `b9a4ead3145b32b628cbf80dbd5e5cbf51bfbee5567419cd66f93c6bfca2d28e`；這是新原生擷取，不是舊 PNG 重新轉色。

舊 NE-223 ALWAYS 探針及錯誤圖片／日誌仍保留於原附件；本次修正不補造實體手把、孤立效能或人工整章驗收。
