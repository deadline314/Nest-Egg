# NE-231：一次交易服務驗證

基準 a52e57ea47e775f9aefc229eca8f712dc8a0183e，Godot 4.7.2，原有選测工具 44 組、單程序。
最終自然退出 0，33,631 檢查、0 新／已知失敗、0 腳本錯誤，759 秒。
raw 全文保留；65 項 fixture／既有錯誤與 2 項退出錯誤分類另列，不宣稱無 ERROR。
退出診斷：6 Area2D RID、7 CanvasItem RID、25 ObjectDB、13 resources。

同指紋但保存金額不符的真回歸：183 檢查／2 失敗，修正後 183／0；兩轮无腳本／引擎 ERROR 或退出資源警告。原始失敗不刪除。
此前受影響測試的廣播生命週期失敗由 ST-3 獨立修正，之後基準重驗；保留 earlier-changed-console.log。
source-sha256.json 記錄 15 份實際受測程式與資源，manifest.json 區分原始位元組與倉庫 LF 校驗。

此階段沒有正式故事呼叫或玩家 UI／美術異動，所以沒有新增遊戲截圖。尚未代表任何章節已扣款、發款或已完整通關。

最新主線整合：在另一台電腦的重裝機槍手修復 `6ea4c6ec8` 上重排本交付，15 份受測來源 LF SHA 不變。重新匯入自然退出 0、0 腳本／引擎 ERROR；補驗 Economy／DeathReaction／RigMesh／RigActions／Posture 五組，3,055 檢查、0 新／已知失敗、48 秒、自然退出 0。這是新素材後的局部整合驗證，不將先前 44 組改稱在新基準執行。原始輸出見 latest-*。
