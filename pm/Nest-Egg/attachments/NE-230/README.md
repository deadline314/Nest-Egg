# NE-230 整輪續玩驗證

最終來源基準：`2c90b9e2593fe47c00cd7aec1bff08f96e5da780`。原 `SHARDS=2 tools/run_tests_changed.sh HEAD` 完成 80 組、54073 檢查／0 新失敗／0 已知失敗／0 SCRIPT ERROR，592 秒、自然退出 0；raw 退出資源診斷及 cp950 選測警告未刪除。

- `final-console.log`、`final-shard-{0,1}.log`：最後完整 raw。
- `final-summary.json`：斷言、filter 對應 ERROR、退出 ERROR／WARNING 分類及未啟動 CI 註記。
- `latest_*.log`：最新主線 124 項真 Forward+ 接點回歸與匯入；UI 各8、unit82、route11、choice5＋6、end3＋1。
- `integrated_{write,read}.log`、`integrated_retry_{write,read}.log`：首次 BG-23 整合的真獨立程序，逐項整輪資料與實際檢查點／成長／裝備恢復。最新 HUD 沒有改存檔 schema，必要接點已另重驗。
- `bounds-{1280,1600}.json`：原生視窗控制項實際邊界；四張 PNG 在票的 images 目錄。
- `source-sha256.json`：19 檔來源凍結校驗；`parser.json`：16 檔 GDScript 解析紀錄。
- `selector-utf8.log`：只以 UTF-8 唯讀重跑原 selector 確認 ALL，未改 filter／selector。
- `first-all-console.log`、`first-all-failure-shard-1.log`：第一輪章際 fixture 的1新失敗及2SCRIPT ERROR完整 raw；最終修正不是 known failure。
- `integrity.json`：本附件、來源／票／設計及四張 PNG 的 SHA256／CRC32／位元組數。

其餘初期失敗與持久世界、跨區、死亡、瞄準 probe 原始輸出完整保留於 `C:/tmp/ne230-evidence/`，命名與結果見 RUN_SAVE。這些資料不當成正式序章／新第二、三章通關或實體手把驗收。

圖片的編輯器 `.png.import` 快取不提交。`integrity.json` 的 `bytes`／`sha256`／`crc32` 記錄本機原件；`repository_*` 記錄 Git 依既有 `.gitattributes` 正規化為 LF 後的提交內容。原始 log 的行尾與結尾空行仍保存在本機原件，未修剪內容；因此原件與 Git 文字檔的位元組校驗可能不同。
