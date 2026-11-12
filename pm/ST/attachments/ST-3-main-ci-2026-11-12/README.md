# 已發布主線的完整 CI

受驗來源為 `5a363c4e29c186661eba364cc2bbee3cee374178`，已包含 ST-2 旁白翻譯、ST-9 死亡次數及 ST-3 事實有效性修復。兩次各自執行完整工作流程：

| 原始工作流程 | 結果 |
|---|---|
| [推送 CI](https://github.com/deadline314/Nest-Egg/actions/runs/43220021833) | 88 組、99,000 檢查，0 新／0 已知失敗，507 秒 |
| [排程 CI](https://github.com/deadline314/Nest-Egg/actions/runs/43221750729) | 88 組、99,000 檢查，0 新／0 已知失敗，681 秒 |

兩次實際保存、原進度冷讀、音訊退出及其他工作流程步驟均通過。完整遊戲 log 的 DummyTexture 檢查各為 6 份／0 診斷。

`original.zip` 是原樣保存的 GitHub 工作流程 metadata 與 `gh run view --log` 顯示輸出，並非未上傳的各分片原始引擎 log。成功工作流程沒有上傳那些原始 log，故不以此宣稱全部資源類別零洩漏、所有負向資料案例零 ERROR、硬體效能或真人整章通關。任務來源資料化及一般故事結果保存仍各自驗收。

執行 `python verify.py` 可離線核對 ZIP CRC、逐檔 SHA、來源 commit、兩個事件、原彙總及關鍵步驟。文件回寫不改遊戲來源，不重跑無變動的本機完整套件。
