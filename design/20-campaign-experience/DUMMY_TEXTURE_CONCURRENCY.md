# 無頭貼圖配置與背景載入

2026-10-26，BG-51。NE-228 的原麵攤 `host_none_read` 功能檢查 7／0、exit 0，但嚴格檢查器發現一個 DummyTexture RID 未釋放，因此整批停止。原輸出與主檔保留；不修改忽略清單、不把退出碼當作通過。

用獨立最小專案，不載入遊戲／autoload、不預載場景，以公開 RenderingServer API 在背景工作建立小貼圖，等工作結束及主線影格後釋放所有唯一 RID。固定每批 1,024、八批共 8,192 次；相同腳本只改工作數：一工作 0 ERROR；四工作 362 個 ERROR、退出仍報 100 個同型 RID。第一次真重現 v2 亦有 139 個洩漏；更早 sync API 不公開造成的解析失敗保留，不列為引擎重現。

固定 Godot 4.7.2 原始碼的 RenderingServerDefault 在呼叫執行緒先配置 RID，再排初始化。DummyTexture 使用預設非執行緒安全 RID_PtrOwner；正式 RD 使用具保護的 owner。修復限 Dummy owner 啟用相同的執行緒安全配置，不移除預載、不序列化整個遊戲、不關閉音訊、原生渲染器、Wayland 或輔助功能。

沿用 NE-280 固定下載、全來源回讀與精確 patch／建置收據。增加第二個獨立來源／patch 雜湊，兩個修補各自驗證原始與修後 bytes，快取須同時符合。既有音訊修補不變。舊的單一 RID 診斷沒有資源身分，不能宣稱已證明其唯一成因；本票以獨立對照及原冷讀再次驗證。

依據：Godot 官方文件 Thread-safe APIs 將 RenderingServer 列為可在背景執行緒使用的 server API；固定版本原始碼 `servers/rendering/rendering_server_default.h`、`servers/rendering/dummy/storage/texture_storage.h` 與 `core/templates/rid_owner.h` 提供本次直接依據。不是把測試錯誤隱藏成正常行為。
