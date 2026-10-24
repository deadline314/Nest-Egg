# 發行閉包的類別名稱核對

最新來源035731f0的隔離準備原本把Main成員`_radio_completion`誤判為已排除相容腳本的全域類別，導致非必要拒絕。只有真正class_name宣告才建立全域類別符號，Godot名稱區分大小寫；檔名不是隱含全域類別。既有直接引用、UID、動態目錄與正式章節門檻保持。

原工具82項：80通過、2個Windows專屬skip；追加兩項後84項／1失敗／2skip，修後82通過、2skip。真正已排除的MissingWriter類別仍由同一檢查拒絕，非只刪除拒收機制。

同一immutable Git來源兩次實際隔離準備：8,542檔、220,543,967bytes；全部files記錄逐項相同。閉包issue由一個誤判變0，正式匯出就緒仍false。after的source_worktree_dirty=true明示工具變更，不把它說成完全未修改工作目錄；遊戲來源仍從指定Git提交取出。此批不匯出、不驗Windows原生啟動，不代勾母票。

[原始回歸、兩份完整清單與工具前後來源](raw.zip)、[SHA](manifest.json)。沒有遊戲畫面變更，不以無關截圖充數。
