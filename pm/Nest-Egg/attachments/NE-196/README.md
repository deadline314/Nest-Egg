# NE-196 音訊審查材料

開啟 [可播放審查頁](index.html)。需保留整個 repository 的相對路徑；正式素材播放器引用 `audio/`，混音器錄音在 `media/`。所有素材沿用既有 CC0 來源，[技術資料](technical.json) 記錄實際檔案雜湊、來源、場景、增益與事件時間。

本環境沒有音訊輸出裝置，因此沒有人工試聽結論。審查頁的 147 個實驗室位置經過「遊戲內實際聲音」播放路徑；真實關卡抽查另外載入最新第一章屋頂、電話巷、倉庫及保留的第二章 `level_02`。這些是腳本輸入抽查，跳過過場、提高生命，並未從主選單完整通關。

本次修正 10 首曲目的曲名與授權包。修前／修後的正式音訊、位置選擇、加工參數、音量與增量快取位元組相同；同一段播放材料代表兩版聲音，不宣稱調音改善。音高微調的單發複本與離線保持音高的 1.25／1.5／2x 加速檔分開列出，不能把微調複本算成獨立錄音來源。

## 建議試聽順序

1. 搜尋 `shot_`：逐把比較原速變體，接著比較兩章的 1x／2x 實際連射錄音；確認尾音和重複感。2x 是本次執行中注入超頻倍率，未改正式能力。
2. 搜尋 `phone-final`：在最新第一章電話巷，以互動按鍵完成通話，對照三聲撥號與話筒動作。早一版捕捉的按鍵嘗試沒有觸發，保留為未通過；直接通話處理與修正捕捉按鍵的結果另列，不冒充同一次成功。
3. 搜尋 `movement`：屋頂混凝土、第二章金屬的落腳、跳躍及落地；原始事件表有毫秒、物理影格、位置與落地狀態。
4. 搜尋 `P-BGM-002`／`P-BGM-003`：播放完整 12 秒的通關／死亡短曲，判斷是否停在樂句中間、有無安靜前奏。訊號數值不能回答音樂句子完整與否。
5. 逐類展開其餘位置：命中、角色、機關、介面、環境與場景音樂，確認喜好。

## 技術與主觀結論的界線

- 兩首短曲都是 12 秒，均有可測起音及尾端淡出；保留原先使用者選擇的段落，未因數字就換曲或移動片段。
- 電話三段錄音約 0.179／0.193／0.205 秒，動畫事件相隔約 83／100 毫秒，存在片段重疊。通話的拿起、撥號、話筒錄音、掛上實際事件另附時間；是否需要縮短或換錄音由可播放材料審查，不更動角色動畫或事件時機。
- 正式檔案的 OGG 解碼峰值可能略高於編碼前的 -1 dBFS 目標；審查頁提供逐檔峰值，不把編碼前的限制當成解碼後保證。
- Forward+ 畫面由 llvmpipe 軟體 Vulkan 取得，不能用其慢影格速度判定正常實機同步；正常速度錄音由 60 FPS 上限的無頭混音器取得。
- 捕捉離開時出現 Godot ObjectDB 警告（實驗室 4、關卡 272、電話抽查 154 個）；局部測試無新失敗。沒有宣稱捕捉執行完全無警告或已驗證記憶體無洩漏。
- 原始素材與候選預聽快取未下載；實驗室截圖因此顯示候選預聽缺失。正式播放與本審查材料可播放，沒有把成品偽裝成原始候選。

## 重現

使用 Godot 4.7，為每次捕捉指定獨立的 XDG_DATA_HOME。以下工具不寫遊戲配置：

```bash
godot --headless --path . res://tools/audio/audition_capture.tscn -- --out=/tmp/ne-lab --revision=<基準主線>
godot --headless --path . res://tools/audio/audition_capture.tscn -- --out=/tmp/ne-game --mode=game --revision=<基準主線>
godot --headless --path . res://tools/audio/audition_capture.tscn -- --out=/tmp/ne-phone --mode=phone --revision=<基準主線>
python tools/audio/export_audition.py --out pm/Nest-Egg/attachments/NE-196 --capture /tmp/ne-lab /tmp/ne-game /tmp/ne-phone --base <基準主線>
```

截圖另外以 Forward+ 執行相同情境並加 `--screenshots`，先使用共享 GPU 鎖。此 Session 的 Linux 相容橋接只讓既有 Windows `msvcrt.locking` 呼叫使用 fcntl 同一鎖檔，放在 `/tmp/ne-audio-session/locked.py`，未修改 ComfyUI 工具或啟停服務。
