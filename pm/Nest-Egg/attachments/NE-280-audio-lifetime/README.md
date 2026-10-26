# NE-280：混音資料生命週期

2026-10-26，調查中。ST-10受影響回歸在八程序負載兩次出現音訊執行緒SIGSEGV；原圖演出與單程序通過不代表此問題已解決。

[原始輸出與官方MIT原始碼](initial-evidence.zip)、[逐檔SHA](manifest-initial.json)、[來源與判讀界線](research.json)。Godot官方來源保留原授權標頭；上游議題僅連結與轉述，不重刊全文。

第一輪中止前78.45秒已發生真崩潰；第二輪完整選了83組，因一支崩潰缺結果，只有60,551項結算且另有1項續玩時序斷言失敗，整輪失敗。該時序斷言與音訊問題分開追蹤。原main與最終候選的相同11組單程序都是8,709／0（353／350秒），不能當成重現修復或崩潰已解決。

上游[124217](https://github.com/godotengine/godot/issues/124217)描述同一4.7.2版本的AudioStreamPlaybackBusDetails生命週期競態。實際fault位於StringName複製，其呼叫者的常數指出AudioServer::_mix_step；不是完整符號化堆疊。修補與負載驗證完成後在本附件追加，不改原篩選器、known failures或音效開關。
