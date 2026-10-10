# 返回選單的渲染資源驗收

2026-10-10。重要通訊與第一章正式故事串接的本機驗收，發現真正讀檔、完成 NPC 對話並返回主選單時出現「Attempting to use an uninitialized RID」。錯誤必須消除，不能以流程斷言通過代替原生 log 通過。

## 目前證據

- Godot 4.7.2 ed1daf0bf、Forward+ Vulkan、Intel Arc B580。Native5 行為 55 項通過、1 筆原生 ERROR，因此整輪拒絕。
- 使用同一真 Main、真 NPC、固定檔案寫入器和新程序 Continue 的 Native6 診斷，再次記錄相同錯誤；原有行為斷言全部保留，額外錯誤檢查失敗。
- 錯誤發生於主執行緒一個 draw interval，早於轉場 covered 與第一個舊關卡節點 tree_exiting。舊 Level 當時仍存在；衝刺快照的 active、used、texture leases 均為零。
- 返回選單同時會切換背景預載範圍。尚未定位 RID owner；沒有足夠證據認定預載、殘影、立繪或卸載是根因。Logger 的 script backtrace 為空。

## 交付原則

先用狹小且可重現的原生路徑或原生 stack 定位實際資源使用順序，再修其生命週期。驗收工具不得加等待、強制同步、停用效果或隱藏資源讓錯誤消失。真正產品修補若需更改預載並行策略，必須保留正常非同步載入、畫面完整及明確記憶體上限，並保存修前修後原生 log。

重要通訊的確認、保存拒絕重試、取消與冷讀仍走原有 Source／receipt／固定寫入器。這張票不授予故事完成、全章可玩或正式打包資格。雲端無頭測試與本機 Forward+ 結果分開記錄。
