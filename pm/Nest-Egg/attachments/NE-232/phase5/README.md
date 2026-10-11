# NE-232 第五階段：三份累積候選包（2026-10-12）

來源提交：`bc6355e97c6c25ba95f825827d9c41a6a65282b4`（已在 origin/main）。工具：`tools/release/campaign_build.py` 的 `prepare → import-stage → export --candidate`，引擎與模板為官方 4.7.2（模板 SHA-256 與工具內建值相符）。

| 目錄 | 版本 | 收錄 | Windows 單檔 | Linux 單檔 | 乾淨啟動回報的章末 | 未驗收原因數 |
|---|---|---|---|---|---|---|
| ch1 | `2026.10.12-ch1-candidate` | 序章、第一章 | `NestEgg-2026.10.12-ch1-candidate-through-ch1_kasa.exe` 286,321,472 bytes<br>`0c4a0b14d03027db3e4edd5011fbf2f4fd79b6c5d7ecd6936e99cd9fbfa6474c` | `NestEgg-2026.10.12-ch1-candidate-through-ch1_kasa.x86_64` 250,572,400 bytes<br>`77b34d79f0b79d746481f9ad9d6fff69aa3ff6b66a044072fc160518e4c2d464` | ch1_pawnshop_dawn.tres | 9 |
| ch2 | `2026.10.12-ch2-candidate` | 序章、第一章、第二章 | `NestEgg-2026.10.12-ch2-candidate-through-ch2_heron.exe` 286,321,472 bytes<br>`839b3b6239c2a740a4a8aa35e6e9f54edc09fb3bb428a801befdddfc41b581f5` | `NestEgg-2026.10.12-ch2-candidate-through-ch2_heron.x86_64` 250,572,400 bytes<br>`0cfef49b69e9943fe5104d72befe6f72193bf6333b2fa824ece2cd64096b202e` | ch2_rooftop.tres | 12 |
| ch3 | `2026.10.12-ch3-candidate` | 序章、第一章、第二章、第三章 | `NestEgg-2026.10.12-ch3-candidate-through-ch3_clearwater.exe` 286,321,488 bytes<br>`fc2f98eb366ae2a55b3473d418865b12972932c7cce7603cbfeceb6b9de35314` | `NestEgg-2026.10.12-ch3-candidate-through-ch3_clearwater.x86_64` 250,572,416 bytes<br>`8c0a578e3a461e0ef84625c460c0238b4a01f9a9b5d5a0dd93ee24d4bbe61952` | （最後一章，停在完成卡） | 15 |

每個目錄：
- `export-manifest.json`：種類 `campaign-candidate`、`is_release=false`、版本、存檔槽、章節清單、兩個產物（大小、校驗碼、項目數、最大 15 項、4 GiB 限制）、Linux 乾淨啟動結果、`native_windows_launch_verified=false`、全部未驗收原因。
- `SHA256SUMS`：兩個產物的校驗碼。
- `clean-launch-linux.log`：Linux 單檔獨自在空資料夾以 `--headless -- --edition-info` 啟動的完整輸出（遊戲回報的收錄範圍）。
- `prepare-summary.json`：隔離來源的檔案數、大小、資源閉包（0 缺漏）與章節就緒狀態。
- `import-receipt.json`、`source-manifest.sha256`：匯入紀錄與來源清單的校驗碼（完整清單 1.5 MB，不入庫）。

另外在乾淨資料夾以 Forward+（軟體 Vulkan llvmpipe）啟動三份 Linux 單檔截主選單（`images/NE-232-candidate-ch*-menu.jpg`），版本號與收錄範圍顯示正確；容器沒有音效裝置，log 中唯一的錯誤是 ALSA 開不了輸出裝置。序章至第一章另跑 300 影格開到主選單，exit 0、無腳本錯誤。

發行包本身不提交；Windows 原生啟動與遊玩依 `design/20-campaign-experience/RELEASE_PIPELINE.md` 的步驟由本機原生驗收。
