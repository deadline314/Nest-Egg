# NE-279 本機原生補證

2026-11-11。基底 `4d30c799be7ca89de36d745a1a798092d658dc3c`；本票回顧相關產品與探針來源未修改，指紋在 [receipt.json](receipt.json)。本輪沒有把未操作的實體手把條件勾選，票維持進行中。

Godot `4.7.2.stable.official.ed1daf0bf`，原生啟動日誌確認 `Vulkan 1.4.359 - Forward+ - AMD Radeon RX 9070 XT`。所有程序使用各自隔離的 `APPDATA`、`LOCALAPPDATA`、`XDG_DATA_HOME`，沒有讀寫玩家原使用者目錄。原生擷取透過共用 GPU 鎖依序執行；同機其他專案曾執行工作，本輪沒有量測效能或宣稱全機空閒。

| 驗證 | 結果與界線 |
|---|---|
| `UiScreensSuite` | 460 checks，0 failures，125.3 秒；涵蓋回顧自然結束、略過、外部關閉、原清單捲動／焦點、主選單與暫停入口、鍵鼠和合成手把。2 條缺角色 ERROR 是既有故意損毀測試，符合 `tools/test_filters.sh`，不是乾淨無 ERROR 的原生程序 |
| `codex_replay_probe` capture，1280×720／1920×1080 | 各 140 PASS，0 FAIL、0 ERROR；三語、空清單、回顧與敗北頁、暫停入口與回看返回。已看過三段故事是明示樣本，不能當正式章節通關 |
| `prologue_replay_probe` skip | 28 PASS，0 FAIL、0 ERROR；從正式 Main 開新局，略過序章，圖鑑取得開場資格，再重看與返回 |
| `prologue_replay_probe` continue-skip | 27 PASS，0 FAIL、0 ERROR；另一程序讀取前次真正保存的主檔，經正式暫停圖鑑回看，保留原焦點、暫停、故事／經濟／物品／探索及主備份 bytes |
| `codex_replay_probe` seed → replay → verify | 三個獨立程序，共 9 PASS，0 FAIL、0 ERROR；明示信用點 137 的隔離完整存檔樣本，主備份在三輪間 SHA-256 一致。這一份樣本與正式 Main 路線是不同證據 |

原始 stdout／stderr、隔離主檔與備份、每程序主備份雜湊在 [raw.zip](raw.zip)。初次啟動時工作目錄類別快取未完成，兩個程序在進入測試前因找不到全域類別而失敗並被精確停止；`initial-cache-*.log` 原樣保留，不列入通過數。共用完整匯入完成後，以上同條件重跑均成功；沒有改測試門檻、旗標或錯誤篩選規則。

六張三語／解析度原圖及正式 Main 圖已逐張檢視。名稱、說明、操作和返回均未裁切，焦點與單一選中列可辨。原圖位於本票 `images/NE-279-native-*`，各檔 SHA-256 見收據。沒有後製、替換背景或遮掉原 UI。共用模糊背景目前出現有機色塊，未正常呈現當下場景，與本輪 NE-223 原圖相同；這批清單、回看與存檔驗證不代表該背景已完成視覺驗收。

重跑命令（在 repo 根目錄，每次先把三個使用者資料環境變數指到自己的隔離目錄）：

```powershell
& $godot --headless --path . res://tests/smoke_test.tscn -- --only=UiScreensSuite
& $godot --headless --path . res://tools/codex_replay_probe.tscn -- --mode=seed --out=<隔離存檔目錄>
& $godot --headless --path . res://tools/codex_replay_probe.tscn -- --mode=replay --out=<相同隔離存檔目錄>
& $godot --headless --path . res://tools/codex_replay_probe.tscn -- --mode=verify --out=<相同隔離存檔目錄>
python tools/comfyui/gpu_lock.py -- $godot --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/codex_replay_probe.tscn -- --mode=capture --size=1280x720 --out=<720p原圖目錄>
python tools/comfyui/gpu_lock.py -- $godot --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/codex_replay_probe.tscn -- --mode=capture --size=1920x1080 --out=<1080p原圖目錄>
python tools/comfyui/gpu_lock.py -- $godot --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/prologue_replay_probe.tscn -- --mode=skip --save-dir=<Main隔離存檔目錄> --out=<原圖目錄>
python tools/comfyui/gpu_lock.py -- $godot --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/prologue_replay_probe.tscn -- --mode=continue-skip --save-dir=<相同Main隔離存檔目錄> --out=<原圖目錄>
```

`$godot` 為 `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`。首次 UiScreens 亦經 GPU 鎖啟動，因為該程序為無頭，之後三個無頭樣本程序不再占用 GPU 鎖；收據保留實際命令，不把等待鎖的時間解讀為遊戲成本。原生程序均退出 0，日誌沒有腳本錯誤、ERROR 或退出資源洩漏。
