# NE-228 世界文字換行與避讓

真正Main的老K飯熟氣泡與電話亭長路牌，同條件修前32項／7失敗，修改後720p像素33／0、1080p／120%像素33／0、720p／120%平滑34／0。四輪24原圖已逐張看過，0引擎／腳本ERROR及0資源洩漏訊息。真正公開暫停時Main不處理、遊玩時計保持，恢復後文字顯示正常。

原受影響選擇器基準7bf96cfb，60組：checks: 63204, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time 488 s)。兩個修改套件原斷言逐字重建一致，新增14項；原baseline／碰撞契約的helper、runner、selector、filters和known failures不變。第一輪完整受影響63,204項有1個baseline失敗，修產品metadata後475／0，再跑上述最終整輪。舊MapBubbles負控制32項／6預期失敗，只換回該檔，其餘最終排版保留；不稱整套舊版。

圖片研究先看Night in the Woods森林交談、Oxenfree洞穴多選項的有限欄寬、多行和指向；其餘兩作環境圖與Eastward三圖只作構圖。九張官方Steam下載原圖、URL／SHA與官方Godot4.7 TextParagraph.xml皆在raw。官方文件站403後未重試，改讀公開官方引擎XML契約。

v1只拍到短提示，v2真正長路牌才發現HUD目標與黑邊問題；v3修safe_rect但完整回歸仍抓到baseline。v4保留全部原斷言修產品，並使用7bf96cfb的正式暫停政策。所有中途失敗、誤匯入work舊class的快取與錯誤、原生v1–v4、失敗整輪及最終整輪原始shards完整保留。work/.gdignore須保留後才重新匯入，避免快照的同名class變成正式來源。

[validation.json](validation.json)列範圍與結果，[manifest.json](manifest.json)逐檔SHA，[raw.zip](raw.zip)有585檔、36,115,373 bytes，SHA256 `34685d536089e52a2c81b85e2561d6f7669c58e37720ae1c65d994e35b8ab27b`；解壓並核對全部雜湊。source/final與delivery-frozen逐檔核對，source/before來自59c2642e。整合45647196只多NE-246文件與證據，沒有另改測試中的產品。

環境是Godot4.7.2、Forward+ HDR、llvmpipe軟體Vulkan及Xvfb。英文／日文是明示完整長句的排版fixture，暫時隱藏同場原有路牌以便核對；不是全章翻譯驗收。固定玩家物理只用於穩定長牌構圖；本次不稱實體裝置、真人完整流程、所有動作或整票完成。
