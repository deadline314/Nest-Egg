# NE-154 母票驗證材料

開啟 [可播放串接對照](index.html)。狀態仍為進行中：本次交付獨立音訊驗證與一項實際退化修正；沒有冒充從主選單完整通關，也沒有人工試聽結論。

## 測試版本與已完成成果

- 原基準：`28ef95c7`（NE-196 已合入主線）；最新驗證已 rebase 至 `319eaf87`（ST-3 的選項／存檔／死亡畫面）。本次僅新增 `music.json.map.levels.level_02.boss`，不改第一章事件、地圖、產生器、動畫或 VFX。
- 正式入口為 `game/main.gd` 的 `ch1_pawnshop`。讀取九個新第一章區域及保留的 `level_01`／`level_02` 共十一份正式 LevelData，用實際 `Music.resolve_cue` 對每個區段列出 calm／safe／combat／boss 的檔案。
- [coverage.json](coverage.json) 含關卡與 layout SHA256、portal／next_level 圖，以及正式入口可達性。九個新第一章區域可達，第二章不可達；舊 `level_01.next_level` 仍指向 `level_02`。這是資料圖核對，未冒充完整遊玩。
- 129 個音效 id：125 個由正式檔案供應；四個通用 `empty`／`reload_start`／`reload_mid`／`reload_done` 留作既有合成退回。八把正式槍械各自的發射與五類操作均解析到正式檔案。這四個退回 id 不代表目前正式武器使用合成音效；不重做已完成子票。
- Sfx bank、Music.validate 錯誤皆空，failed_files 空。147 個實驗室位置、275 個輸出檔案與 CC0 登記、來源標題、變體／加速檔、雙章槍聲／落腳／電話／短曲材料已在 [NE-196](../NE-196/README.md) 交付。
- 缺檔／錯格式／半組變體／加速檔失效／不存在 cue 的退回由原有 AudioSuite、MusicSuite 故障 fixture 驗證，輸出具體檔案及引用；沒有刪除正式素材來製造故障。完整測試日誌與摘要在 `tests/`。

## 真實串接修正

保留的舊第二章擴建後，arena 入口在 hangar、頭目位置在 tower_white；頭目光影 override 不改 `zone_changed`。兩個位置都無回收者曲目的區段路由，因此真實 Reclaimer 的 `boss_started` 取到 `boss_warden`，不是只看實驗室所假設的 reclaimer_arena 區段。

新增關卡級 `level_02.boss = boss_reclaimer`，沿用既有正式素材、音量、交叉淡出入與預設路由。修改前已寫 [共用配置區段交接](music-config-scope.md)，保留 Session 3 的 ch1_* 配置。

新增正式關卡 arena → 頭目生成 → boss_started 的整合檢查：修前 225 checks／1 failure（第二章曲目錯誤），修後 225 checks／0 failures；第一章舊入口的看守者曲仍正確。`Music.current_state()` 是底層 calm／combat 狀態，頭目旗標另在錄音資料的 `boss_active` 表示；不把 state 字串當作頭目觸發證據。

[playback.json](playback.json) 的七段錄音都是實際 Master 混音器輸出，含 track_started／音效事件與毫秒。五段為修前真實關卡抽查（新第一章倉庫 combat、舊第一章 combat／boss、舊第二章 combat／boss），另有同一正式第二章頭目觸發方法的修前／修後對照；修後錄音、截圖及 coverage 報告在 ST-3 合入版重新取得。正常速度錄音在 60 FPS 上限的無頭 Dummy 混音器取得；可測非空，不能替代使用者判斷曲風、樂句或好聽與否。

## 截圖與限制

三張實際截圖在 `pm/Nest-Egg/images/NE-154-*`，包含第二章入口及修前／修後 Reclaimer 場景。Forward+ 使用 llvmpipe 軟體 Vulkan，透過既有共享 GPU 鎖；無硬體 GPU，畫面有直接載入時的章名與對話提示。截圖僅證明配置／場景，聲音驗收另用錄音。軟體渲染慢，不能用來判定實機音畫同步。渲染另存 `render-before-trace.json`／`render-after-trace.json`，不與正常速度錄音混用。

本環境無音訊輸出裝置，所以未實際聽到聲音、未調換原選擇、未勾主觀試聽。捕捉離開有 ObjectDB 警告（五段流程 199、頭目無頭 6／軟體渲染 6；正式關卡 MusicSuite 14），未宣稱零洩漏。Forward+ 自動尋找 ALSA 裝置失敗後使用 Dummy；可播放檔案來自混音器，沒有宣稱本環境能播給人聽。

CI 的 GitHub Actions API 回覆 403 Forbidden，按本次指示停止，沒有重試或繞過；本地測試不冒充 CI 結果。

## 等待條件與重現

等 Session 3 的最新第一章／序章事件與正式第二章出口合入 main，再從主選單沿正式進程玩到第二章結束，覆核路由、事件與聲音喜好。使用者須實際試聽 NE-196 短曲完整性、單發重複感、連射尾音、落腳及電話重疊；本次不改其動畫或事件時間。

`coverage_audit.gd.txt`、`flow_capture.gd.txt`、`boss_capture.gd.txt` 保存本次只讀／捕捉腳本。可將 .gd.txt 還原到本地 `.godot/`，用獨立 .tscn 掛載；`boss_capture.tscn.txt` 已給對應場景。Godot 4.7 範例：

```bash
godot --headless --path . res://.godot/audio_parent_boss.tscn -- --out=/tmp/ne-parent --mode=boss --revision=<實際版本>
LOG_DIR=/tmp/ne-parent-changed SHARDS=6 tools/run_tests_changed.sh 28ef95c7
LOG_DIR=/tmp/ne-parent-full SHARDS=8 tools/run_tests_parallel.sh
```

截圖移除 `--headless` 並加 `--screenshots`，先使用共享 GPU 鎖。捕捉直接定位玩家、提高生命、跳過過場；combat 抽查明確觸發既有敵人的 alert，boss 抽查跨過正式 arena 觸發，沒有手動發送 boss_started。只讀覆蓋報告需在輸出後補上圖可達性分析；本次報告含該分析。

## 測試過程中的失敗

在原基準加本次修正、同時執行 6+8 組程序及匯入時，完整套件出現三項失敗：爆炸額外 11.76 ms 超過 6 ms、ducking 恢復、壓力模式敵人數。失敗摘要保留於 `tests/parent-full-final-summary.txt`。未改測試門檻或 known_failures。rebase 後三個相關套件同一程序重驗為 734 checks／0 failures；爆炸增量 1.39 ms（3.66−2.27），壓力模式另一次獨立重驗 69 checks／0 failures。這些診斷通過不取代最新完整套件。

最新整合版（`319eaf87` 加本次修正）在沒有其他測試／匯入／截圖／生成工作時執行完整套件：76 組、45,363 checks／0 new／0 known，197 秒。摘要與八份原始 shard log 已附，證明最新完整套件通過；保留先前失敗與診斷記錄，未更改 known_failures。完整測試條件可勾選，正式進程完整通關仍未勾選。

附錄測試輸出僅整理行尾空白，保留全部檢查數字、失敗與警告訊息。

推送前已再 rebase 至 `4d380e5e`，遠端增量只含 NE-222 的骨架技能文件、票與圖片；沒有遊戲／音訊／測試改動。遊戲版本與 319eaf87 完整測試相同，合併文件及 diff check 已核對。
