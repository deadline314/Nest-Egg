# NE-231 近戰成長限定階段

此交付只補近戰選購與量測證據，不覆寫既有 Commit-1 故事交易 ledger，不更動跨章收益、Main／Story、進度或保存服務。五種可選招式與 price_list 報表接點已在 NE-237 獨立交付。

五招80／100／140／120／100，共540選购；全部改裝910，最低必要準備570（原改裝370＋補給200）。章節靜態888→64%是資料對帳，並非實走序章／第一章、無刷錢通關或所有章節收入的驗收。shop截圖使用公開購買、測試信用點1000，不能假裝錢是正式故事路線賺得。

[NE-237證據](../NE-237/README.md)含完整受影響suite、固定基準、失敗／成功 raw、runtime差異、所有圖片／來源hash及100組真傷害量測。頭目三難度擊退／暈眩全零；短連段不被購買取代，長柄升級樣本DPS略降而鎖定增加，追加是有代價的招式選擇。

購買結果的公開snapshot／restore契約實跑；严格安裝缺近戰子資料夾型錄，NE-230真退出續玩依賴保留，不以fixture代稱真存檔。NE-231整票跨章路线／所有武器防禦成長與真續玩條件保持進行中／未勾，主session既有故事ledger內容原樣保存。

截圖是NE-237真Forward+原圖的逐位元副本，非新生成或假介面；原renderer为Godot4.7.2 Forward+／llvmpipe軟體Vulkan／DummyAudio，無實體手把／硬體HDR或人工試聽聲明。

NE-237來源交付：`90a73316ef4a74f1bc78c487937f796be0b7d47b`；NE-236自然晚目標：`700f1dd8a931b4f1d88d68f13614b9da4256edf1`。


## 本階段局部驗證

固定基準90a73316，commit之前執行 `tools/run_tests_changed.sh 90a73316ef4a74f1bc78c487937f796be0b7d47b`：文件／證據階段合法沒有runtime組，exit0，[完整輸出](changed-console.log)，不拿空diff冒稱runtime測試。實際另跑Economy／Progression：[摘要](economy-console.log)／[raw](economy-shard-0.log)，412 checks、0 new/known failures、exit0，10秒。[範圍與原ledger前綴校驗](scope-receipt.json)、[本階段差異](source.diff)、[來源與圖片hash](sha256.json)。

原引擎與容錯診斷保留，exit0不代表無ERROR。runtime沿NE-237的65組55,932與最後近戰298實跑來源，這次沒有新runtime改動。
