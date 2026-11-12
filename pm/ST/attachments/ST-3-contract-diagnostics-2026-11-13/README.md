# ST-3：故意損毀契約的精準診斷驗證

發布後的原 CI 在巡邏員反例停止：遊戲正確拒絕被改壞的結果，十項狀態／磁碟斷言全過，但新增的具體錯誤訊息讓舊零診斷工具拒收。現在只有受信任呼叫端明列的故意篡改情境可要求對應完整訊息出現一次；其他情境仍要求零診斷。比對保留原完整行與總數，僅去除行首尾空白；摘要上限不參與授權。

缺少、重複、錯場景、額外 ERROR／SCRIPT／資源洩漏仍拒絕，結果 JSON 自報的允許清單不會生效。未修改遊戲 GDScript、章節資料、契約或共用測試 filter。

## 真實結果與界線

- 既有 Ubuntu／WSL 單元測試 20 項全部實執行通過，零跳過。Windows 原九項 POSIX skip 的紀錄另保留。
- Root 獨立四個自報欄位注入控制通過；不修改凍結的正式測試來源。
- 原選擇器及 changed 入口皆正常結束，選出零 Godot 組；本次修改為七個 Python 工具檔。
- 五支原 CLI 共 98 個子程序，只有 22 個明確反例宣告精準訊息。實際本機批次在 29 個通過後，第 30 個正控出現 DummyTexture／Image／ObjectDB 退出診斷，整批按原規則拒絕並停止；沒有冒稱本機 98 全過。
- 單次未修改 helper 的同情境對照為 26／0、零診斷；不抹去前紅，也不能據此判定洩漏原因或宣稱已修復。Windows stock 與原 CI 的既有安全 Linux 引擎不同，原 CI recipe 已包含 DummyTexture 執行緒保護。

完整回歸以新 main 的原安全 CI 最終結果為準，完成框先重新保留驗收。沒有新增退出診斷例外、重新跑到碰巧變綠或下載／改造引擎。

## 可攜原件

`python original/verify.py` 只核對原 SHA／CRC、來源及真實結果，不啟引擎。它明確保留 `local29green1red` 與 `full98_completed=false`。`original/raw.zip` 包含原 CI ZIP、明標的 connector decoded job log、所有本機原始 log／命令／退出碼／存檔及修前紅。

Root 的發布位置重讀紀錄見 `root-verification.json`；獨立自報欄位控制及精準來源核對同目錄保留。這不是新的原生畫面／手把／效能驗收。
