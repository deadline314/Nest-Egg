# NE-223：首次顯示字形與原生開啟耗時

這份證據對應首次顯示任務頁仍有長格的實際缺口。舊版真正安靜時段的 1080p 首次任務為 **41.839 ms**，獨立 33 ms gate 失敗；保留原報表、原始樣本與失敗。候選在 720p／1080p 各 16 輪，**160 次 UI 操作全部 <=33 ms**，最大 **26.849 ms**。引擎正常退出只代表探針功能檢查，不代替耗時 gate。

產品只改原有首次載入準備：在隱藏頁釋放前，依當下真字型、字級、viewport oversampling 準備實際文字字形。未掛畫面的暫存 Canvas RID 當次釋放；透明描邊不預製。沒有常駐第二個任務畫面、預載整份字庫或改全域設定。正常開頁仍讀當時進度與裝置。

## 安靜時段的絕對結果

原生 Godot 4.7.2、Forward+／Vulkan、RX 9070 XT。每個程序獨立 APPDATA／LOCALAPPDATA，未封存 profile。原有工具要求關閉 VSync；報表的 `vsync:false` 是要求值，不當成額外量過實體顯示器。此表是輸入至下一次 `frame_post_draw`，包含排程／送交繪製，並非純 GPU 時間或實體輸入延遲。

| 開啟 | 720p 首次／後15輪最大 ms | 1080p 首次／後15輪最大 ms |
|---|---|---|
| 暫停 | 6.714／5.726 | 7.039／5.675 |
| 任務 | 20.804／18.906 | 21.177／18.557 |
| 區域地圖 | 26.419／11.720 | 26.849／11.305 |
| 世界地圖 | 23.478／18.205 | 24.423／19.336 |
| 返回區域 | 13.025／11.944 | 13.113／12.418 |

每解析度 16 輪、80 個 UI 樣本，另保留16個閒置樣本及16個 retained 樣本。讀取器逐樣本檢查、重算首次／暖開中位／p95／最大，不把平均值換成門檻。32 輪玩家、鏡頭、canvas、遊玩及霧時間 before/after 完全相同，Level 為真正 PAUSABLE，玩家與鏡頭不能處理。返回後節點恆1077、區域地形快取恆1，重用同一份地形貼圖且重建數0。

第0至15輪 retained 靜態記憶體增量為720p **558,564 B**、1080p **559,316 B**；含工具持續保留的觀察陣列，不能稱整體 RAM／VRAM 或無任何洩漏。明示 oversampling 的字形快取會保留啟動當下的一份尺寸，直到 Font 資源釋放；不能假稱全由 viewport 尺寸切換自動回收。此準備僅首次載入一次，未按每格或拖動視窗重做。

## 因果定位與真正負控制

- 原隱藏排版已有邏輯字級，但真正1080p首次任務前後，主字型33px字形127→200、27px字形9→77。快取查詢為 TextServer 唯讀觀察，不修改字形。
- 相同原產品與相同來源的額外隱藏建立控制，首次任務39.265ms；只增加實際尺寸預製為20.725ms，真正開頁33px字形199→199。兩者皆共享負載、4輪，**只用來定位，不當正式效能驗收**。原診斷原型還準備透明 fallback 描邊，額外1MiB，正式候選已避開。
- 同一擴充的正式 QuestMapSuite、相同424項：在獨立程序內把實際 PauseMenu Script 載入保存的舊版 bytes，424／1；候選424／0。唯一負控制失敗是實際 viewport 尺寸字形未在隱藏建立期準備。沒有改磁碟產品，也不是歷史 checkout。原版runtime SHA與raw原檔一致，兩輪磁碟來源均保持，無SCRIPT ERROR。
- 額外本機 QuestMap＋UiScreens 933／0 初輪只保存stdout；缺角色的預期容錯ERROR在stderr，旋轉後另取到的73B Godot log也不完整。**不把這兩個檔案當完整乾淨引擎紀錄**；以後續424項 merged logs與正式 affected收據為準。

## 來源座標與不能作的推論

每個原生程序自己都保存 source-before／after、逐 byte 相等及原始來源快照。最初quiet→最終quiet的共同守衛來源有兩處差異：本次暫停頁修正，以及父任務鏡頭調校。最終另多守衛 project.godot、真正camera資料與兩個字型檔。**不能把整個before→after差額全歸因字形，也不能聲稱兩輪整棵來源相同。** 正式結論是當前候選的絕對33ms gate；單因素控制另以同來源兩輪證明。

候選兩份固定源：

- `ui/pause_menu.gd` SHA256 `0dbeb47f25fdd933bdb03052acc97748132676259f4f0f487485dde63f804db9`
- `tests/suite/test_quest_map.gd` SHA256 `846fa7a952fb9a79e803992d4414356f88fca3c57faa35a710fa5e7e5212a022`

鏡頭共同守衛：舊 `b247b15222cebc7fb5c74e04e48f56d81cebbf748a055f71eeccc5afda5e21a3` → 新 `c2975c0d8fcb8d2556673b8c177536742d9b61fc4422713249d85ed13290e37c`。最終正式 affected 隔離基準是已發布 `56bb233db929973adf380a4631066a4c8b79dc58`，只覆蓋上述兩份凍結源；原有7份不被測試引用的NE256私有文件保留，不能聲稱工作樹只有兩個檔案。

工具直接安排新遊戲的真當舖 Level，從真正輸入入口操作暫停、任務、區域／世界與分層返回；**不是從Main走完序章，也不是整章通關、真人操作或實體手把驗收**。畫面有當舖背景及新遊戲序章任務是此fixture的刻意起點，不代表已驗自然故事流程。PNG保持原生bytes，未重畫；新版鏡頭與背景相位不同，不作修前後全像素相等宣稱。實體手把一條仍未勾，票保持進行中。

## 原始檔與重算

`raw.tar.xz`：2032個原始成員、10,266,688 B，SHA與每成員SHA／size見 `archive.json`、`members.json`。不含使用者存檔或profile。成員路徑：

- `runs/ne223-quiet-native/`：真正舊版quiet、失敗41.839ms。
- `runs/ne223-quiet-native-after/`：最終quiet兩解析度16輪、全部原始PNG。
- `runs/ne223-quiet-native-font-diagnostic/`：實際字形快取唯讀觀察。
- `runs/ne223-quiet-native-glyph-control/`、`...glyph-prime/`：同來源共享負載單因素控制。
- `work/ui-comparison/{original,candidate}/`：424項真回歸原版／候選完整 merged logs。
- `work/before-product/`、`work/freeze-product-v1/`：原件與候選bytes。
- `work/`：當時的原生caller、原探針副本、診斷腳本／場景與命令收據；原始stdout-only／編譯失敗亦保留。

離線只需Python3及Pillow，從附件目錄執行：

```text
python -B verify_archives.py
```

外層 `verify_archives.py` 與 `verify_quiet.py` 是交付入口；包內同名檔是當時快照。先驗整包SHA、每一成員bytes及安全路徑，再解到TemporaryDirectory；不執行包內程式。用同一33ms reader重算舊quiet預期exit1／新quiet預期exit0、實際凍結、所有summary、節點及cache，以及424負控制與字形定位數據。`portable-verification.json`保留本機原始重算輸出。

原生重現需完整專案與Godot，不是直接執行解壓根目錄。先使用對應已發布版本，將包內 `work/run.py`、診斷gd／tscn按原相對路徑放回 `work/ne223-quiet-native-20261117/`，確認caller的ROOT、OUT、完整source guard及GPU lock路徑適用；每輪換獨立APPDATA／LOCALAPPDATA，依各process-receipt.command原CLI跑。原命令的絕對D路徑是當時來源座標，不能宣稱冷clone未調路徑即可執行。正式產品效果用原有 `tools/quest_map_perf_probe.tscn`，診斷不得混作產品新旗標。

保留的未採用／無效準備：`--check-only --script`沒載入autoload，雖exit0卻有Settings SCRIPT ERROR，後改真scene編譯；第一版glyph micro未設UiKit theme，觀察錯字型，後版才有效；初次產生的正式runner含不正確Windows字串路徑，在正式啟動前修正為forward slash。這些準備不算有效通過，不刪原始失敗。

正式15組的完整兩shard logs、原始命令、退出碼、全來源before/after及7私有文件保留收據另見 `official.tar.xz` 與 `official.json`。父獨立review另加，未改寫上述raw。


## 正式受影響測試的自然結果

原 `tools/run_tests_changed.sh 56bb233db929973adf380a4631066a4c8b79dc58`、SHARDS=2：**15組、8,436項、0新／0已知失敗、403秒、自然exit0**。14,478份受守衛runtime／tools／tests／binary assets before=after，兩候選SHA與freeze完全一致。兩份完整shard log含原有缺資源、損毀故事契約等容錯負測試ERROR；無SCRIPT ERROR，沒有改錯誤過濾或選測範圍。原有7份NE256私有檔status完全保留，tracked僅兩凍結修改。

精確組別：ApplyPanelSuite、Chapter1MapSuite、ClipEditorSuite、CombatHudSuite、CutsceneSuite、DevMenuSuite、QuestMapSuite、ReadabilityTargetsSuite、SoundLabSuite、SoundStageSuite、StageCoverageCharactersSuite、StageCoverageWeaponsSuite、StageCoverageWorldSuite、UiScreensSuite、main。

`official.tar.xz`為623,028 B／17成員；`official.json`保存整包與每一成員SHA／size。來源清單保留完整before/after，另附兩份候選、原selector／runner／既有filter／known-failure檔bytes。正式reader重算兩shard檢查數合計與15組唯一覆蓋，核對自然退出、全來源保持、7私有檔status，以及7張公開PNG與封存原圖SHA一致。
