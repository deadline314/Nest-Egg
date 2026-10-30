# 累積章節發行

NE-232；2026-10-10。先保留可重現的來源與驗收門檻，再交付各章的實際 Windows 單檔。現有第二章舊關卡與第一章未完成分支，不能當成新版章節已完成的證據。

## 正式包的門檻

每份規格列出連續的序章到末章、正式入口、末章出口、故事來源及逐章驗收紀錄。章節尚未完成時只能稽核，不能建置正式包。NE-233／234／235 分別承接真實逐章試玩、手把、畫面、音訊及乾淨目錄啟動；工具的成功不替代這些驗收。

新版本不能覆蓋舊版本。輸出目錄名稱包含版本、末章與来源 SHA；來源必須為乾淨提交，報告保存每個輸入的大小與 SHA-256，校驗以串流計算，圖片不解碼進 RAM。來源大圖、字幕、票據、測試和開發工具不入包；Godot 的 `.import` 規格和腳本 UID 是必要來源，匯入快取在隔離建置目錄重產。

## 資源邊界

目前角色零件、動作、音效、道具與升級有依編號組合路徑或掃描目錄的載入方式，不能只取 `main.tscn` 的靜態依賴。先以明列的執行期根目錄保留這些資源，逐一核對內文中的固定 `res://` 引用，格式化的路徑另外列為人工檢查項。這是保守資源邊界，尚不表示精確剔除所有未使用的素材。

必須保留目前 `Story.CHAPTER_PATHS` 的全部載入來源，直到故事 owner 在原始產生器和載入清單移除舊故事。不能為了縮小包而靜默刪除還會被程式讀取的檔案。開發選單的可選清單 `tools/dev_tools.json` 在正式版缺省，沿用現有停用行為。

## 匯出與平台

Godot 的 [匯出設定](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) 需包含 JSON 等非資源資料；[命令列匯出](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) 需同版本模板。Windows 使用 x86_64 並嵌入 PCK；官方的 [Windows 限制](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html) 約為整個 EXE 3.89 GB、PCK 約 3.75 GB，實際模板會影響容量，因此以最終產物量測判定，不能只量來源大小。

本機已找到 Godot 4.7.2 的 Windows release 模板，2026-10-10 量得 109,268,480 bytes；模板存在不代表實際匯出或乾淨目錄啟動通過。Linux 可做來源與產物檢查；Windows 實際啟動及硬體操作需另有證據。新存檔版本／release identity、最後一章關閉後續路由的接點，待 NE-230 與正式章節整合後實作，不能靠刪檔使入口失敗來假裝收尾。

## 隔離來源與下一階段（2026-10-10）

發行工具下一階段從指定的完整 Git commit 讀取已追蹤來源，不能把 ignored／untracked 素材或工作樹暫存變更混入產品。僅建立一份執行期 staging，保留全部仍載入的故事與整個動態資料目錄、腳本 UID 和匯入規格；不複製既有 `.godot` 快取。隔離目錄先記錄原始輸入雜湊，再由同版本官方 Godot 重新匯入。來源 staging 是工具證據，不是已驗收章節包。

來源閉包保守保留 runtime roots。音效實驗室四個開發類別及其 UID 可排除，但必須確認保留的腳本／資源沒有引用這些類別或路徑。未知動態格式引用、必要 UID／匯入規格缺漏、引用到排除檔案均阻擋；不能靠略過引用或納入開發大圖求通過。每個已知動態 loader 的目錄覆蓋列在工具契約；新增 loader 需重新審查。

章節 readiness 不能只相信一個 `accepted` 字串或空白證據檔。連續章節須有真正入口／出口、非零正式主線任務、故事結果 producer、對應票完成與有效驗收內容。目前 production backend 仍回傳 `None`，存檔 release 固定為 `demo-0.1`；沒有公開可選累積末章／release identity／跨包相容介面。工具如實報告此 owner 缺口，不改 Main、Story 或存檔，不產生貌似有接線的 release JSON。正式 export 保持拒絕直到這些公開契約及逐章證據交付。

工具可另外建立有明確 fixture 標記的小型匯出探針，實測官方模板、JSON／目錄載入、嵌入 PCK、逐項串流完整性與 Linux 無專案啟動；此探針不是 Nest Egg，也不代稱 Windows 原生啟動。每次輸出用新目錄，失敗保留 log／部分產物，沒有成功 manifest。Windows 大小以版本原始碼、真模板及真產物量測為準，既有約數不可直接當硬閾值。

## 初期工具交付（Commit-1 歷史界線）

先提供唯讀來源稽核：依明列邊界統計檔案、串流校驗、固定引用缺漏、動態引用清單、已載入故事、任務數與逐章 readiness。資料有問題須指出來源位置。四個章節節點初始保持 draft；沒有假定序章、第二、第三章已正式可玩。

初始掃描會包含 `core/` 中未由正式遊戲呼叫的音效實驗室輔助類別；其中來源素材目錄與音訊位置文件也會列為字串引用。報告明確標記為字面引用範圍，不能把這些列當成玩家流程已發生資源錯誤。下一階段需要以實際依賴閉包剔除開發輔助類別並核對動態載入，不能直接把開發大圖放入正式包，也不能未查證就略過任意缺漏。

## 已交付工具（Commit-2）

保留 Commit-1 的 `campaign_release.py` 與12項原測試。新增 `campaign_build.py`、`pack_integrity.py`、`build_policy.json` 及失敗情境測試。以全部執行期 data／scene／shader 為根，再追蹤 project autoload、固定 script／UID 引用與全域類別相依；不是只追主場景。隔離來源排除音效編輯器及沒有任何上述依賴的檢查類別，沒有改動 Main、Story、存檔、地圖、戰鬥或角色來源。

```
python3 tools/release/campaign_build.py prepare --source <完整40字元SHA> --through ch1_kasa --version <版本> --out-root <repo外的新目錄>
python3 tools/release/campaign_build.py import-stage --stage <prepare輸出> --godot <官方4.7.2實際binary> --templates <已核對官方模板目錄>
python3 tools/release/campaign_build.py verify-stage --stage <prepare輸出>
python3 tools/release/campaign_build.py export --stage <prepare輸出>
python3 tools/release/campaign_build.py probe --out <全新探針目錄> --godot <官方4.7.2實際binary> --templates <已核對官方模板目錄>
python3 -m unittest discover -s tools/release -v
```

`prepare` 來源永遠取 Git commit tree；`source_worktree_dirty` 只是當時工具工作樹觀測，不表示 dirty 檔案被取進 staging。manifest 記錄版本、累積末章、來源 SHA、每檔大小／SHA-256、排除原因、動態覆蓋、逐章及 owner 阻擋理由。root 的 icon 匯入規格也保留；沒有 committed UID 的既有腳本只在隔離 editor 匯入後產生 UID，另列生成紀錄。未能解析且沒有有效 path fallback 的必要 UID 則阻擋。

所有原始輸入在匯入後逐檔保持相同雜湊；新 `.godot` 快取及 sidecar 另由 import integrity 清單與校驗碼封存。額外來源檔、任意新程式、失去對應來源的 sidecar、原始 UID 改動或快取損毀均拒絕。import/export log 逐行檢查：exit 0 但有 `SCRIPT ERROR`、`ERROR:`、parse error 也失敗。資料／設定／快取以每次建置的 XDG 目錄隔離，保留 inherited proxy／CA，不寫玩家存檔。正式命令审查與來源就緒是兩道獨立門檻。

`export` 現在是 fail-closed 的正式產品入口，會留下 `export-blocked.json`，沒有繞過開關，也不把探針 preset 冒作產品 adapter。NE-230 的可選累積末章／release identity／save compatibility 接點和正式章節 producer/acceptance 未交付前，保持阻擋；未來須沿實際公開介面補 adapter。發行版本 metadata 不修改目前固定的 `demo-0.1` 存檔契約。

## 官方版本及產物實測（2026-10-10）

官方 [godot-builds 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) 的非 Mono模板 archive 為1,281,349,702 bytes，官方 release API digest 與實測 SHA-256 同為 `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`。只解出 `version.txt`、Linux與Windows x86_64 release 模板；版本為 `4.7.2.stable`。Linux模板73,519,416 bytes、Windows模板109,268,480 bytes；工具固定這次核對的模板 checksum，未知來源不能以自填 provenance 取得通過。

重新讀取官方[匯出設定](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)、[命令列](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)、[Windows匯出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)。JSON以非資源 include filter 保留，先在隔離目錄 `--import` 再 `--headless --export-release`，用自訂的同版官方 release template、x86_64、embed PCK。

另讀4.7.2版本的 [PCK reader](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/file_access_pack.cpp)、[PCK writer](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform.cpp) 與 [Windows export](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/export/export_plugin.cpp)。這版真正的 Windows 檢查拒絕總執行檔 `>= 0x100000000`（4 GiB），不是固定3.75GB PCK額度。工具量最終 EXE／PCK、核對 footer／header／engine版本、UTF-8安全路径、目錄及payload範圍、重疊、MD5與SHA-256；以1MiB區塊讀資料，不整份讀圖片或包進RAM。拒絕未知、encrypted、sparse及delta格式。也用真 sparse file 驗證4GiB邊界拒絕。

工具探針實際為PCK格式4；Linux單檔73,522,720 bytes、Windows EXE109,271,792 bytes，兩個PCK均10 entries，全項完整性通過。Linux真新程序在只有執行檔的乾淨目錄載入JSON、掃描目錄并載入後章樣本，exit0、無ERROR。Windows僅完成Linux上跨平台匯出與bytes檢查，`native_windows_launch_verified=false`，必須交回Windows真機另驗。這兩個檔名均明標 `NE232_TOOL_PROBE`，不是任何章節包。

首次未隔離XDG／普通沙盒探針雖exit0，Godot log有家目錄與IPC ERROR，工具正確拒絕；原始log保留。後續探針及真來源匯入都走正常單次命令審查，没有修改全域或thread權限、proxy、CA或網路政策。最終來源／工具／失敗證據见[Commit-2索引](../../pm/Nest-Egg/attachments/NE-232/phase2/README.md)。

## 跨平台探針與連結測試（Commit-3）

探針仍匯出兩種官方 x86_64 單檔，但原生啟動依實際 host 選擇：Linux只執行 `.x86_64`、Windows只執行 `.exe`；其他 OS／架構拒絕。乾淨啟動目錄只放該平台一個執行檔。必須 exit0、無引擎錯誤且印出 JSON／目錄／後章样本斷言才記錄成功。兩個平台的 native fixture 欄位各自記錄，不把Windows執行代稱Linux原生通過，也不把 fixture native 通過代稱章節包。PCK檢查本身仍只證明 bytes，不設定原生啟動欄位。

官方4.7.2的 [Windows OS路徑](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/os_windows.cpp)以 `APPDATA` 作資料／設定根、`LOCALAPPDATA` 作快取根。Windows子程序除XDG外，這兩者分別指向本次建置 `user/roaming`、`user/local`；不修改父程序、玩家存檔、proxy／CA或任何全域設定。既有 `native_windows_launch_verified` 在probe receipt中代表該receipt明標的fixture，與新增 `native_windows_fixture_launch_verified` 同值；正式章節驗收仍false，pack inspector的同名欄位仍false。

測試明確區分真檔案系統能力及模擬分支。Windows建立真symlink若回WinError1314，僅該真symlink案例skip並列出原因；Linux與其他錯誤仍須執行／失敗，拒絕斷言不刪除。Windows另在暫存目錄建立不需symlink權限的真junction，核對輸出父目錄與staging reparse拒絕；Linux記錄Windows專屬案例skip。拒絕涵蓋lstat的reparse屬性，不依賴Python是否提供 `Path.is_junction()`，不提升權限或修改系統設定。

原Commit-2總數49是 `test_campaign_build.py` 37項＋`test_campaign_release.py` 12項，沒有 `test_chapter_release.py`。正式總命令為 `python -m unittest discover -s tools/release -p "test_*.py" -v`；Windows可用 `python`，Linux可用 `python3`。新增回歸後依實際run／skip分別記錄，不把skip算通過。Windows本機舊log由主session保存在 `C:/tmp/ch1-runtime-checks/release-unit-local.log`，雲端不宣稱讀取或重現該WinError。

Commit-3共59項，雲端Linux為57通過、2項Windows真junction明確skip；Windows平台選擇與資料隔離的CPU回歸不代稱Windows原生執行。最新真探針和完整失敗／成功紀錄見[Commit-3證據](../../pm/Nest-Egg/attachments/NE-232/phase3/README.md)。

## 版本身分接上遊戲（Commit-4，2026-10-11）

NE-230 已公開版本契約：遊戲從 `data/release/campaign.json`（章節順序、名稱、新遊戲起點）與 `data/release/edition.json`（`through`）決定自己是哪個累積版本、存檔目錄與章末。`prepare --through <章>` 只在隔離 staging 改寫 `edition.json`（加上版本與來源提交），倉庫檔案不動；manifest 的 `edition` 欄記錄版本識別、原始與 staging 的校驗碼，`verify-stage` 以 staging 值核對，之後被改動就拒絕。

readiness 改為實際核對契約，不再寫死「NE-230 尚未交付」：三個契約檔都在提交內、`campaign.json` 的章節順序與 `campaign_specs.json` 一致；每章末區關卡的 `chapter` 欄位要等於該章 id，否則章末會接錯，列為該章問題。剩下的阻擋是故事產出端交接與各章驗收（NE-233～235），工具如實保留。

`export` 仍維持 fail-closed：正式產品 adapter 要等章節驗收證據與 4.7.2 官方模板在同一次建置中可用時才接，不以工具探針代替。

## 正式／候選匯出與乾淨目錄啟動（2026-10-12）

`export` 現在真的會建出單檔，分兩種：

- **正式包**：`export --stage <prepare 輸出> --godot <4.7.2> --templates <核對過的模板>`。只有收錄的每一章都已驗收（規格標 accepted、驗收票「完成」且全部勾選、有提交的驗收證據）、版本契約正確、資源閉包 0 缺漏時才放行；否則照舊留下 `export-blocked.json` 並拒絕。原本無條件附加的「產出端未交接」阻擋已拿掉，改由上述實際條件判斷。
- **候選包**：加 `--candidate`，給本機原生驗收用。`prepare` 的版本必須以 `-candidate` 結尾（遊戲內版本名稱看得到），清單標 `campaign-candidate`、`is_release=false`，所有章節未驗收的原因原樣記在 `readiness_blockers`，不能當成發行版。

兩種都：從已匯入並封存的隔離來源複製一份工作目錄給 Godot 匯出（驗證過的來源不被改動，工作目錄匯出後刪除）；同一個 stage 已匯出過就拒絕，舊版永遠不被覆蓋；Windows `.exe` 與 Linux 單檔都嵌入 PCK，逐項串流校驗，版本設定與章節清單在包內的雜湊必須等於 stage 紀錄，包內每一項都必須是驗證過的來源或 Godot 對它的轉換產物（`.godot/`、`.remap`、`.import`），開發目錄與文件類副檔名由 `pack_integrity` 拒絕；記錄大小、SHA-256、最大的 15 項與 4 GiB 限制。

依建置主機選擇原生單檔（Linux x86_64 用 Linux 檔，Windows AMD64 用 `.exe`），複製到只有它自己的空資料夾，以 `--headless -- --edition-info` 啟動：遊戲自己讀包內資料，回報收錄的章節、各章區域數、章末區域（下一區屬於未收錄章節、停在完成卡）、通往未收錄章節的出入口數與存檔位置。工具核對回報的末章、收錄章節與 campaign 順序一致、沒有收錄範圍外章節的區域、新遊戲起點在包內，任一不符就失敗。這證明該主機的單檔能在沒有編輯器與專案檔的目錄無頭啟動並讀到正確範圍；畫面、手把與完整遊玩仍依下方步驟另驗。其他平台只核對包內容，不嘗試執行。

每份包都帶著全部章節的資料（故事來源與動態載入目錄必須完整），但未收錄章節的區域由遊戲拒絕載入：章末停在完成卡，通往未收錄章節的出入口只提示不進入；三份包因此大小相近。日後若要縮小，需先讓故事與動態載入能依版本裁切，不能直接刪檔。

輸出：`artifacts/NestEgg-<版本>-through-<末章>.{exe,x86_64}`、`export-manifest.json`（版本、末章、存檔槽、來源提交、引擎、章節清單、兩個產物、原生乾淨啟動結果、未驗收原因）、`SHA256SUMS`、每一步的 log。發行包不提交進 repo。

### Windows 原生驗收步驟（待本機原生驗收，Arc B580 那台）

1. 在 Windows 取得同一份候選包（自行用本工具建，或拿雲端建好的 `.exe`），先用 `certutil -hashfile <檔案> SHA256` 對照 `SHA256SUMS`。
2. 建一個空資料夾，只放那一個 `.exe`，雙擊啟動；不能有 Godot 編輯器、專案資料夾或其他 `.pck`。
3. 主選單看得到版本名稱（例如「序章至第一章」與 `-candidate`），開始新遊戲能進入序章。
4. 玩到該版本最後一章的章末：出現完成卡，同一行寫「本版本收錄到這裡，進度已保存」，不會載入下一章的區域。
5. 確認存檔在 `%APPDATA%\Godot\app_userdata\Nest Egg\runs\through-<末章>\slot-1.json`，且沒有寫到其他版本的資料夾。
6. 關閉程式再開一次，主選單能從存檔續玩（真的關閉程序，不是同一個程序內返回選單）。
7. 若有前一章的包：用前一章的包玩到章末後，開新一章的包，主選單出現接續提示，續玩直接進入新一章入口；再開回舊的包，只提示該用哪一版、不修改新存檔。
8. 鍵鼠與實體手把各走一次開始／繼續、戰鬥、對話、商店、地圖、死亡與章末。
9. 每一步截圖，記錄 Windows 版本、顯示卡、體積與 SHA-256，寫回 NE-232 與對應章節驗收票；未做的步驟不勾。

## 2026-10-24：全域類別符號與檔名

發行閉包排除某個非global腳本，不代表其檔名是Godot全域類別。只有已解析的class_name參與類別引用拒收，且按原大小寫與底線比較；Main的_radio_completion成員可與已排除相容檔同名。直接資源引用、UID、真正缺少的全域類別與未驗收章節仍保持原拒收。用同一來源的隔離清單逐項比較，不能只看總檔數。


## 2026-10-30：候選包依主機啟動

`native_clean_launch` 記錄實際平台、架構、無頭版本回報及日誌雜湊；`linux_clean_launch`／`windows_clean_launch` 各自標示是否真的執行。非本機平台為 `verified=false` 並附原因。Windows 無頭版本回報成功仍不把 `native_windows_launch_verified` 或 `chapter_acceptance_verified` 改成 true，這兩項保留給完整原生驗收。非 Linux／Windows x86_64 主機會在建立 artifacts 前拒絕，不留下不可重試的半成品。啟動失敗保留兩個原始產物與失敗紀錄，不產生成功清單。
