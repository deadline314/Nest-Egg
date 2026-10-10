# NE-232 Commit-2：隔離來源與工具匯出證據

2026-10-10；NE-232 維持進行中。這是可靠管線與明標工具 fixture 的交付，沒有正式章節包，也沒有 Windows 原生啟動驗收。原 Commit-1 的工具、12 項測試及附件保持原樣。

實際工作分支 `codex/cloud-chapter-release` 從正式 fetch 的 main 建立，交付前已 rebase 到 `eadc5f8f04bd1bfbdfaaefe489d1127de355a647`。只修改 `tools/release/`、發行設計文件、本票及本目錄；沒有修改 Main、Story、存檔、地圖、章節產生器、戰鬥、BG25 或角色。實作及重現指令見[發行設計](../../../../../design/20-campaign-experience/RELEASE_PIPELINE.md)。

## 真來源

| 項目 | 結果 |
|---|---|
| 不可變輸入 | Git commit `eadc5f8f04bd1bfbdfaaefe489d1127de355a647`；版本 `release-pipeline-check`；累積末章 `ch1_kasa` |
| 隔離 staging | 6,957 檔、189,678,150 bytes；工作樹 dirty 是工具未提交的觀測，沒有取進輸入 |
| 資源閉包 | 0 缺漏；8 個格式化動態路徑有完整目錄覆蓋，9 個目錄 loader 契約核對 |
| 腳本邊界 | 295 個相依腳本保留；4 個音效開發類別及12個無執行期相依腳本與其 UID，共32檔排除 |
| 故事保留 | 五份既有載入故事、93 scenes，全部正式 quests 為0；沒有刪掉後章載入清單 |
| 官方引擎匯入 | `4.7.2.stable.official.ed1daf0bf`，exit 0，log 無 ERROR／SCRIPT ERROR |
| 匯入前後 | 全部6,957個原始檔大小及 SHA-256 相同；5,702個生成檔、154,085,514 bytes 另封存 |
| 缺省 UID | 只在隔離目錄生成既有 projectile 腳本的 UID，原始 UID 不改動 |
| 產品 readiness | false；正式 export exit 1，留下阻擋報告，沒有產品輸出 |

完整清單與原始 log：[source manifest](source/source-manifest.json)、[manifest checksum](source/source-manifest.sha256)、[import receipt](source/import-receipt.json)、[import integrity](source/import-integrity.json)、[integrity checksum](source/import-integrity.sha256)、[完整匯入 log](source/import.log)、[校驗 log](source/verify.log)、[產品阻擋](source/export-blocked.json)與[阻擋 log](source/export-blocked.log)。

這是保守的靜態／目錄契約閉包及真 editor 匯入，不是逐章遊玩。未知動態路徑、opaque script registry、缺必要 UID 或 sidecar、引用排除檔案均拒絕；新的 loader 需審查契約。沒有發明 release metadata 或修改既有 `demo-0.1` 存檔。準備完整產品 adapter 前，必須取得 NE-230 的公開累積末章／release identity／save compatibility 接點和 owner 正式 producer 接線及逐章驗收。`accepted` 字串、空白證據、草稿或來源稽核不構成通關證據。

## 有效工具測試

[完整 unit log](unit.log) **49/49 通過**：原12項加37項新測試。包含真 symlink、immutable dirty／untracked 隔離、同大小損毀、輸出保留、全故事／後章、腳本 transitive classes／UID、未知動態路徑、失效 loader、開發引用、root import、匯入快取及 sidecar 改動、零 exit 但 SCRIPT ERROR、正式 readiness、官方模板偽 provenance、PCK 邊界／重疊／checksum，以及真 sparse file 的4GiB Windows邊界拒絕。

[影響選測](changed.log)以 `eadc5f8f04bd1bfbdfaaefe489d1127de355a647` 為明確 baseline，exit 0，沒有受影響遊戲測試；純 CPU 發行工具不宣稱遊戲完整套件或 Forward+ 畫面通過。沒有 GUI 變更，不製造截圖。[命令與 exit code](commands.json)及[受測工具 SHA-256](tested-tool-source.json)可核對。

## 官方模板與真工具產物

[官方 release archive 與兩個模板 provenance](official-template-provenance.json)：同版4.7.2、官方 archive API digest 與串流量測相同；只解出 Linux／Windows release x86_64 及 version.txt。[官方文件與版本原始碼回執](official-document-receipts.json)記錄 URL、大小及內容 checksum。4.7.2 Windows export 原始碼拒絕最終 EXE `>= 4 GiB`；歷史約3.89GB／3.75GB不得當固定 PCK 容量。

| 明標 fixture | 真體積 | SHA-256 | 本次驗證 |
|---|---:|---|---|
| `NE232_TOOL_PROBE.x86_64` | 73,522,720 bytes | `7789257773c33d70e6d7cd1e9b02f302845a849f0f11854d281b915475fb5535` | Linux真程序、乾淨目錄只有執行檔；JSON、目錄掃描與後章樣本載入通過 |
| `NE232_TOOL_PROBE.exe` | 109,271,792 bytes | `a7fd87b0aca55f202a680b6ec78c2c2d2fe3311382d505a745fed9f35a0253aa` | Linux跨平台匯出及完整性；Windows原生啟動未驗 |

兩檔 PCK 格式4、各10 entries；串流校驗全部payload，Linux PCK 3,292 bytes、Windows PCK 3,300 bytes。固定 JSON SHA 相同，動態後章樣本已在包內。[probe manifest](probe/probe-manifest.json)、[最終 inspector 重新核對](probe/current-inspector.json)、[checksum](probe/checksums.sha256)、[匯入](probe/import.log)、[Linux export](probe/export-linux.log)、[Windows export](probe/export-windows.log)、[Linux乾淨目錄啟動](probe/native-linux.log)均為完整原始紀錄。四次引擎命令 exit 0、無 ERROR。大型 binaries 不放 Git，另提供明標工具探針 ZIP 交回本機；不是 NE-233／234／235。

首次普通沙盒 probe 的 Godot 雖 exit 0，但家目錄／IPC 有 ERROR，工具 exit 1 且沒有成功 manifest：[完整失敗 log](first-failure/import.log)、[failure receipt](first-failure/failure.json)。後續以每建置 XDG 隔離並沿正常單次命令審查完成，沒有修改全域/thread權限、proxy、CA或網路政策。此前隔離 staging 的工具修正與原始報告保留在雲端 work；只退休自建未匯出 staging，沒有覆蓋任何有效包。

所有本目錄證據的串流 SHA-256 見 `evidence.sha256`；引擎產物和章節验收欄位明確分開。
