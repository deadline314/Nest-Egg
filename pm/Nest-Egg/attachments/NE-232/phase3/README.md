# NE-232 Commit-3：跨平台工具探針

2026-10-10；工具階段，NE-232保持進行中，正式章節ready仍false。原Commit-1／2、原始失敗與有效工具產物沒有覆蓋。工作分支 `codex/cloud-release-platform` 由正式fetch的main建立，交付前rebase到 `01af65b05d015141a0ee2ae18797f6dc397ecc81`；其中NE-230還原順序變更完整保留，沒有修改任何owner的遊戲來源。

## 正式重現與真計數

從repo根目錄執行：

```text
python -m unittest discover -s tools/release -p "test_*.py" -v
```

Linux可把 `python` 換成 `python3`。原49項確實是 `test_campaign_build.py` 的37項＋`test_campaign_release.py` 的12項，repo沒有 `test_chapter_release.py`。新增10項後現在是47＋12＝59；[完整方法清單](test-inventory.json)。本次Linux實際 **57通過、2skip、0failure／error**，[原始unit log](unit.log)。兩個skip是Windows專屬真junction，不能算通過。只選 `-p test_campaign_build.py` 會跑47項，未包含原12项。

本機主session回報舊37項為35正常、2個WinError1314，原始log保存在本機 `C:/tmp/ch1-runtime-checks/release-unit-local.log`。這是主session的實際回報；雲端沒有讀該路徑，也沒有宣稱重現Windows真權限錯誤。

Windows缺symlink權限時只有真連結建立的WinError1314轉明確skip，其後的拒絕assertion保持原樣。Linux或其他Windows錯誤繼續失敗；此窄條件也有CPU回歸。Linux兩個真symlink案例本次通過。Windows另以系統內建PowerShell在測試temp建立真junction，核對父目錄與staging路徑拒絕，移除junction本身且不遞迴target；沒有提升權限或改系統設定。junction在雲端Linux明確skip，尚無本機Windows真執行結果。lstat reparse屬性拒絕的CPU案例通過，不依賴 `Path.is_junction()`。

## 平台選擇與資料隔離

探針在Windows只原生執行 `.exe`，Linux只執行 `.x86_64`，未知OS／非x86_64 host在輸出建立前拒絕。新增Windows／Linux的完整probe流程CPU回歸：僅mock引擎程序，實際使用檔案、有效ELF／PE＋PCK與真正inspector核對payload；檢查乾淨目錄只有對應一檔，且只記錄實際host的native結果。這些CPU案例不構成Windows原生啟動證據。

任何native錯誤、exit0但缺資料斷言都留下failure與log，沒有成功manifest／checksum。先寫回歸並證明修正前選錯執行檔及漏reparse拒絕：[回歸red log](regression-red.log)；[初始測試harness log](regression-initial.log)也保留，不藏掉早期失敗。

官方4.7.2 [Windows OS原始碼](official/os_windows.cpp)確認資料／設定使用APPDATA、快取使用LOCALAPPDATA；[URL與checksum回執](official/receipts.json)。只在子程序設為本次建置 `user/roaming`、`user/local`，Linux保留XDG隔離。真Python子程序驗證這些路徑及proxy／CA sentinel保留、父程序環境完整不變；[修正前appdata失敗](appdata-red.log)與最終unit log可核對。官方editor舊路徑另一次讀取404，已如實留receipt且未重試；沒有使用它作實作依據。

`native_launch` 記錄host、架構、執行檔、log及 `tool fixture only` 範圍。probe receipt的 `native_linux_fixture_launch_verified`、`native_windows_fixture_launch_verified` 分別記錄；既有 `native_windows_launch_verified` 是Windows fixture欄位的相同值。PCK inspector的同名欄位仍false，它只驗bytes。`is_campaign_product`、`chapter_acceptance_verified`始終false。

## 實際官方匯出

官方4.7.2同版模板重跑，新目錄 `/workspace/work/ne232/tool-probe-platform-1`。完整[probe manifest](probe/probe-manifest.json)、[命令stdout](probe/command.log)、[匯入](probe/import.log)、[Linux匯出](probe/export-linux.log)、[Windows匯出](probe/export-windows.log)、[Linux真程序](probe/native-linux.log)與[checksum](probe/checksums.sha256)。四次引擎命令均exit0、無ERROR／SCRIPT ERROR；Linux乾淨目錄JSON、目錄掃描與後章樣本斷言通過。

| 真fixture | bytes | SHA-256 | native證據 |
|---|---:|---|---|
| Linux | 73,522,720 | `60afb5a95560fb5e6f61b9fe1ea333977b3da2ab57c82f7c02e4b0533b63e688` | Linux真程序通過 |
| Windows | 109,271,792 | `f65cfbcd184fc8dbce5c6885caf8469ca7cf178b2b088f95854327bfceceb2ae` | 僅跨平台匯出／完整性，本機native未驗 |

兩檔PCK仍格式4、各10 entries，全payload MD5與SHA-256通過。新的manifest `native_launch.target=linux`，Windows兩個native欄位均false。官方模板provenance與checksum保持原要求，不使用未知來源。

本機Windows可沿[發行工具指令](../../../../../design/20-campaign-experience/RELEASE_PIPELINE.md)以真官方editor及同版templates、全新 `--out` 執行probe。成功後應有 `native-windows.log`、`.exe`單獨啟動，Windows fixture為true、Linux fixture為false；驗收內容仍只限工具。禁止以CPU模擬或跨平台匯出代填此結果。

## 來源與產品界線

新link／reparse檢查對既有隔離來源及生成cache重新校驗，6,957個原始輸入完整，[verify log](existing-stage-verify.log)；該來源明確仍是原 `eadc5f8f`，沒有冒稱最新main的完整章節建置，也沒有重複保留整份來源。[影響選測](changed.log)以最新 `01af65b0` 為baseline，exit0、無受影響遊戲套件；本次純CPU工具與文件，無GUI／Forward+截圖。

最新main的release仍固定 `demo-0.1`，production backend仍None，各章規格仍draft；原readiness／公開owner接點阻擋未移除。正式序章到CH1及後章仍等實際production流程與通關證據，不產占位包。大binary留在雲端work，Git只含工具、文件及證據。[命令exit code](commands.json)、[受測工具checksum](tested-tool-source.json)，全部附件雜湊見 `evidence.sha256`。
