# 已有整輪存檔的 prepared durable writer

本階段只新增 RunSaveStore 的低層資料／磁碟 API。既有 read、write、新遊戲 marker 恢復與 Main 路徑維持原行為，沒有啟用 atomic story capability。Main 的 guard、Level 共用 `_area` 引用、世界物件安裝、通知／dirty-save coordinator 仍依 STORY_ATOMIC_INSTALL_PLAN 待後續實作。

`prepare_existing_write(raw)` 回傳獨立的 `PreparedExistingWrite` 或具體 error。只接受可完整驗證的 supported primary；primary 缺漏／損毀即使有健康 backup 也拒絕，呼叫端須先透過既有恢復流程建立可用槽。`.newrun`（檔案、目錄或 symbolic/reparse entry）或 `overwrite_authorized` 一律拒絕，不恢復、不代表新遊戲授權。primary／bak／tmp 都有固定大小、檔案種類、完整 bytes checksum 與版本保護；存在而不能讀懂的 bak／tmp 亦拒絕，保留原件供診斷。沒有掃目錄或讀取任意 suffix。

候選先經 RunSnapshot.prepare 的有界正規化，再用 Progression.prepare_install 的現行 canonical transaction proof、StoryItems.prepare_install 的 custody proof、GameState.prepare_install 的 state／declared flag types／difficulty proof。progression／checkpoint／level-start、story 的已宣告版本均須有效。GameState 準備物的獨立 flags 用於補齊既有宣告 defaults／還原整數型別，成為相同的 normalized disk/install target；不改 live flags。沒有複製帳本 predicate、金額或資源 fingerprint；不呼叫 store.validator、作者 Callable 或 trusted bool。候選 getter 只給有界獨立副本，future coordinator 必須準備及安裝同一正規化結果。completion 只檢查現行 Story scene identities；不借用需要 idle presentation 的 whole-run Story bundle來阻擋正在完成的場景。

`preflight_existing_write(prepared)` 核對 owner、原始與 globalized path、one-shot、payload checksum、三份 source file profile、marker 與授權。`commit_existing_write(prepared)` 的同 owner 嘗試消耗一次機會，包括 stale 拒絕；錯 owner 不得消耗另一 owner 的準備物。成功前回傳 typed `DurableWriteOutcome` 的 `committed=false`。既存已驗證 tmp **先 unlink 目錄項再新建檔**，flush／close／bytes digest 回讀驗證後，移除 old bak、primary→bak、tmp→primary。最後 rename 成功當刻先設 sticky `committed=true`，再到 probe seam 或返回。此方案沒有 postcommit cleanup；不得把不存在的 backup cleanup 當測試或在之後改回未 commit。

失敗窗口：temp／backup removal／primary rotation 失敗時 primary 仍是完整 old；tmp→primary 失敗嘗試 bak→primary 回滾，回滾失敗則 `requires_recovery=true`，保留完整 old bak 與候選 tmp。既有 reader 不採 unmarked tmp；fresh process 在成功 rename 前讀 old，在成功後讀 new。legacy new-run 的 false／marker 恢復歧義不套用此 API，故它拒絕 marker／overwrite 授權。後續 primary 腐敗仍依既有政策讀上一份完整 backup，本層不保證持久單調性。

固定 protected I/O methods 與四個 typed phase seam 僅供可信測試 subclass 做真 filesystem 故障與 barrier，正式 base seam 無動作。API 不接受執行 handler 或作者指定 stage。呼叫端保證同一 main thread 的獨占 writer／服務 guard；profile 是 stale 檢查，沒有宣稱 OS 跨程序 lock，最後核對後外部程序介入仍不受此 API 防護。Godot flush 與成功 rename 是程序 crash 邊界，沒有宣稱斷電 fsync 保證。

## 既存 filesystem alias 保護

第一稿只比較 lexical path／bytes，漏掉既存 `.tmp` 與 primary 的 hardlink：FileAccess.WRITE 會在 rotation preflight前截斷同一個 inode。這是已修正的實際 blocker，不能把 prepare 前 alias 當成外部 TOCTOU。

現在每個固定 source entry 先 `DirAccess.open(parent)`（失敗拒絕），再 `is_link(entry)`，最後才 `file_exists`；symbolic/reparse（含 dangling）一律拒絕，目標及 entry 均不動。primary／bak 的 `is_equivalent=true` 額外保守拒絕；`false` 不是 physical independence proof，API fallback／查詢無法判定時不據此宣稱兩者独立。核心安全不依賴 false：primary 從不以 WRITE 開啟，backup 只 unlink 自己的目錄項，tmp 的既存 regular entry 一律 unlink 後確認不存在，再開 WRITE 建新 inode。這也保護 tmp↔primary、tmp↔bak、tmp↔外部檔案的 hardlink；unlink／再次open失敗時 primary、bak 仍完整。已有 tmp 的版本／schema拒絕全在 unlink 前完成。

API 出處是 [Godot 4.7 DirAccess 文件](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)，unlink機制另核對官方 [Windows driver source（4.6）](https://github.com/godotengine/godot/blob/4.6/drivers/windows/dir_access_windows.cpp)、[Unix driver source（master）](https://github.com/godotengine/godot/blob/master/drivers/unix/dir_access_unix.cpp)；Windows symbolic entry 的刪除語義見 [Microsoft DeleteFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-deletefilew)。source/API證據不等同於本機 4.7.2 binary測試。

## 已發布版本盤點

fixed proof涵蓋實際RunSnapshot持久資料的全部已宣告版本：Codec envelope與run version／release；story version1；progression version（current/checkpoint/entry）及各自story_transactions ledger；StoryItems custody；QuestMapState.VERSION（navigation）；Loadout.SNAPSHOT_VERSION（runtime/checkpoint/level-start loadout）。navigation及loadout的declared欄位必須valid integer且等於owner現行constant，不能接受999之後讓legacy restore靜默清空／當舊欄位讀。version缺漏依既有legacy policy保持可準備，不猜一個舊declared schema；loadout目前constant2且無來源宣告version1 schema可準備。WorldState／area、ConsumableBag、dynamic runtime／cinematic_context沒有已宣告版本，不增加臆測guard。helper對candidate和primary/bak/tmp均寫真future navigation／三處loadout envelope並確認拒絕不改source。

驗收來源階段：helper 保留原 RunSaveSuite 及 silent helper，新增真檔案版本／stale／alias／one-shot／typed fault regressions；獨立 Node probe 不載 Main，以 external barrier+kill 驗四個精確磁碟窗與全新程序 all-components read。原 runner、selector、known-failure filter 不變。CPU grammar 檢查不等於 Godot 型別／執行或 crash 驗收，native evidence 由 root 執行後補記。

舊 loadout 的 total `ammo` 且缺 `mag` 走現行 Loadout.restore 的 legacy 分支；RunSnapshot.prepare 卻會補 `mag=[]`，因此本 writer 不具備保值遷移能力。三處 raw loadout 在正規化前一律具體拒絕 `requires_legacy_loadout_migration`，candidate 及 primary/bak/tmp 同樣保護，保留原 bytes。version 缺漏且已用 `mag` 格式仍可依既有政策準備；不以直接 Loadout.restore smoke 宣稱整輪舊 ammo 保值。既有 legacy read/write bodies 不在本輪修改。

## Probe 操作契約

每個窗使用全新且不存在的 canonical absolute `ne-story-durable-*` 目錄；不能位在 res://／user:// 下，不提供 cleanup／刪除模式。`seed` 建立實際舊槽及 expected-old/new（相同 Codec envelope）與綁定絕對目錄的 probe-owner；已有目錄一律拒絕。

啟動 Node 場景 `res://tools/story_durable_write_probe.tscn`，依次傳：

1. `--mode=seed --save-dir=C:/tmp/ne-story-durable-<unique>`，等 EOF／exit0。
2. `--mode=write --phase=temp_closed|backup_removed|primary_rotated|primary_committed --save-dir=<same> --barrier-timeout-ms=15000`。外部 controller 讀 `<same>/barrier.json` 核對 pid、slot、phase（enum 0..3），強制 terminate 該 pid，確認 EOF／終止；不能正常 quit、WM_CLOSE 或 Main._quit。timeout 只接受 1000..30000，未被 kill 的 writer 必定 exit3，不能當 crash 測試通過。
3. 前三個窗新程序 `--mode=read --expect=old --save-dir=<same>`；最後一個窗 `--expect=new`。檢查每個 all-component field、整份 normalized envelope及共用 ledger/custody proof，exit0 才通過。reader 不安裝 live owner，也不重存／補寫槽，沒有上一程序 last_outcome 可參考。

同一四窗再各用全新seed目錄驗 existing hardlink variant：seed EOF後root CPU `os.link(slot, slot + '.tmp')`（native PowerShell HardLink亦可），先記錄真 `os.path.samefile(slot,tmp)==true`／native檔案ID，再執行原 `--mode=write --phase=...`／external kill。準備允許已驗證且版本current的tmp hardlink，必先unlink重建才open WRITE；前三窗 fresh old、postcommit fresh new。不能以lexical不同或CPU機制測試代稱這四個Godot crash窗已跑。

probe fixture 使用實際七份 transaction resources 中的 order+paid（含零元 order receipt）、現行 item catalog、真 scene id、upgrades／abilities／equipped／pawned／player loadout。它不提供 production producer 或 world adapter 的證據。四窗須 serial 使用 root 分配的 engine slot，前一程序結束後才能啟動下一程序。

## 真 alias probe 與 failed/skip 規則

每組重新 seed／EOF，root用原生 filesystem 操作在同一已綁定隔離目錄建立下面拓樸，再執行 `--mode=alias_check --alias=<kind> --save-dir=<same>`；probe會用實際 `DirAccess.is_equivalent`／`is_link`確認fixture，無alias時測試失敗，不能以傳參數充當存在證據。

| kind | root 建立的真拓樸 | 必須結果／後續 fresh read |
|---|---|---|
| tmp_primary | `slot.json.tmp` hardlink到`slot.json` | TEMP_CLOSED原primary/bak bytes仍old；commit true；fresh `--expect=new` |
| tmp_backup | tmp hardlink到bak | 同上，whole old backup保留；fresh new |
| tmp_external | 先把primary完整copy為固定`external.json`，tmp hardlink到external | external全bytes不變，commit true；fresh new |
| primary_backup | unlink seed bak entry，再bak hardlink到primary | preparation明拒、四固定source entries全部不變；fresh old |
| tmp_primary_open_fail | tmp hardlink到primary；test subclass在成功unlink後建立tmp directory，使真FileAccess.WRITE失敗 | committed false、oldprimary/bak不變；fresh old |
| tmp_symlink | tmp symbolic link到primary（或完整external） | preparation明拒、entry/target不變；fresh old |
| tmp_dangling | tmp symbolic link到固定不存在的target | 不依file_exists真假判斷target；READ不能open且is_link=true，preparation拒絕、target未建立；fresh old |

root的 Windows hardlink 可用原生 `New-Item -ItemType HardLink`（或 CPU Python os.link），僅在上述新隔離目錄操作，保留native stdout／fresh-process raw logs。helper亦用真正 `DirAccess.create_link` 測 primary/bak/tmp/newrun/dangling symbolic entries；Windows若缺elevation／Developer Mode，明印 `SKIP ... not validated`，不能計作全驗。hardlink模式不可skip為通過，必須由root真正建立並在Godot binary及fresh reader驗證。reviewer的Windows CPU unlink機制驗證是獨立佐證，沒有替代native引擎矩陣。

## CPU source freeze

root 的首次 Godot import 已 natural EOF／exit0，完整 log 無 SCRIPT／Parse／Compile／ERROR。首次 RunSaveSuite 350 checks、7 failures，均是 fault stage 1..7 的 whole-old 比對；其餘 outcome／source guards／live observers 檢查通過，五個 symbolic cases 因權限／API1 明記 SKIP、未驗。raw 保留於 `C:/tmp/st3-durable-target/shard_0.log` 及 `C:/tmp/st3-durable-target-console.log`。CPU trace 發現期望值直接 prepare 記憶體 seed，略過 reader 的 Codec JSON parse 邊界；[Godot JSON source](https://github.com/godotengine/godot/blob/master/core/io/json.cpp) 的 int／float序列化（尤其0與0.0）不同，RunSnapshot 保留部分 nested 欄位型別。helper 改以獨立 seed envelope 經 decode／prepare 建立完整 old 期望，仍比較整份 normalized envelope，另加 primary 或 bak 的精確原始 old bytes 保留斷言。Store、probe、原 runner／filter 均未改；有界 component診斷供 root 新一輪驗證此根因，尚未宣稱修後native通過。

2026-10-10：四份 GDScript 經 gdparse（CPU grammar）exit0；既有 Store 全部原方法 bodies 保留，RunSaveSuite 只增加一行 invocation。alias修正後新增 genuine symlink helper、root external hardlink probe模式、unlink後真open failure，以及明確 raw normalizations／versionless legacy、navigation／三處 loadout declared versions／raw legacy-ammo拒絕 regression。Windows linked entry 的 file_exists可能只反映link attributes，helper記錄link拓樸而不讀dangling bytes，probe以READ open驗dangling fixture；沒有宣稱symbolic權限測試已驗。沒有由實作代理啟動 Godot，尚未宣稱 native import、semantic types、Suite 或 forced-process crash／alias 通過。root 需先完整 import／檢查 SCRIPT/Parse/Compile log，再 RunSaveSuite、原 tools/run_tests_changed.sh selector/filter，以及上述獨立程序矩陣；raw failed logs須保留，任何 semantic/runtime fix 重新 source review。


## Root 原生驗證與交付

2026-10-10，基準29d45a8ee95e2cd8da864a8116bf9ccf47ec1d38，Godot 4.7.2 Windows。最終 editor import 正常exit0，完整log無SCRIPT／Parse／Compile／ERROR。RunSaveSuite 364項、0失敗、自然exit0；診斷實際確認原350／7失敗是navigation、progression、state、story、version數字型別的JSON邊界差異。獨立seed roundtrip後仍保留完整envelope比對，加上精確原始舊bytes斷言；原失敗完整紀錄保留。

原 tools/run_tests_changed.sh 實際選出7組，2555項、0新失敗、0已知失敗，165秒、自然exit0；未改selector／runner／filter／已知失敗。三行原始ERROR為既有缺角色／缺回饋參數容錯案例，完整保留，無腳本／解析／編譯錯誤。

另以實際獨立Node在TEMP_CLOSED／BACKUP_REMOVED／PRIMARY_ROTATED／PRIMARY_COMMITTED寫flushed barrier；root核對真native PID、父程序及命令行後Windows強制TerminateProcess。四個正常布局＋四個既存tmp→primary真hardlink窗口共8組，每組重新seed／kill／新程序read；提交前完整old，最後rename後完整new，均自然read exit0，不走Main._quit、不正常關窗，也不利用記憶體outcome重寫槽。TEMP_CLOSED真samefile已由true轉false，舊primary/bak精確bytes保留。

5組原生真hardlink／fault拓樸通過：tmp→primary、tmp→bak、tmp→external、primary↔bak拒絕、unlink後真FileAccess.WRITE失敗；每組均由另一全新程序讀回完整預期存檔。2組root symbolic link建立因WinError1314、5組Suite symbolic API1明記SKIP，均未驗證／未算通過；沒有提權或繞過Windows權限。

交付僅啟用可由後續coordinator呼叫的既有整輪prepared磁碟writer；正式Main仍走原既有存檔方法、故事capability未啟用，world／Level `_area`／通知／request／dirty-save接線仍以原子安裝方案為準。舊total-ammo缺mag的整輪已明拒，遷移能力另需處理；不宣稱新版章節或整輪legacy遷移已完成。純來源／磁碟API沒有新增遊戲畫面，因此圖證不適用，保留完整process輸出、源碼diff、baseline與SHA供重現。

完整驗證證據：pm/ST/attachments/ST-3-durable-write/manifest.json。process_controller.py保存本次Windows實驗原腳本與隔離路徑，重現時先指定當地worktree／Godot／全新output位置；原已綁seed目錄不可重用、不可用正常quit代替forced termination。這是process crash實驗，不宣稱斷電fsync或外部程序並行writer安全。
