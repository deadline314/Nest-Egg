# NE-230 還原通知順序驗證

2026-10-10。來源基線 eadc5f8，最後整合主線 cd0d454f6。九個更動來源在測試前後 SHA256 一致。

- 真 RunSaveSuite：374 檢查，0 失敗。
- 原選測工具：65 組，42226 檢查，0 新／已知失敗，0 SCRIPT ERROR，1190 秒，自然退出 0。
- 最新主線整合 main／RunSave／MeleeWeapons：1954 檢查，0 新／已知失敗，135 秒，自然退出 0。
- 原生 Godot 4.7.2 Forward+／Intel Arc B580：兩次各 7 檢查，0 失敗，真 Continue 的第一個錢包觀察者讀到已恢復的 Level、player、NPC state、故事與錢包，並驗證重入路由被阻擋。原始短測無 ERROR 或退出資源診斷。
- 截圖為實際還原順序情境，沒有以直接旗標／定位模擬完整章節通關。所有 probe 使用明確的隔離存檔槽。

原受影響 raw 及最新整合 raw 都保留。原 runner/filter 判定通過不等於 raw 無 ERROR：fixture／既有引擎錯誤和出口 RID／ObjectDB／resource 訊息分列 summary.json，未改 filter 或 known_failures。

RAM 以一個引擎程序測試，native 重驗前可用約 3.17 GiB。系統 GPU 效能計數器不可用（00000422），總 VRAM 無法量測；不聲稱 VRAM 為零或已通過效能驗收。本證據只驗還原原子觀察順序，正式序章、主線結果與跨版發行另行驗收。

完整性：integrity.json 列附件與 PNG 的實際 SHA256／bytes；source-before.json、source-after.json 列確切來源。未納入 Godot 自動產生的其他 import/uid。
