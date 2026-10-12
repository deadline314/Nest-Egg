# 跨區預載的生命週期與驗證

BG-23，2026-10-10。使用者要求持續注意本機 RAM／VRAM、避免一次常駐大量圖片。此工作控制遊戲自己的資源預載，不新增本機 ComfyUI 的 RAM 閾值或自動停止機制。

## 已查核的問題與來源

基準 `c147c8dba` 的 `AssetPrefetch` 只發出 `ResourceLoader.load_threaded_request()`，沒有任何 `load_threaded_get()` 接點；`clear()` 只清除路徑記錄，不能回收引擎的載入請求。單次 160 張上限不能限制跨房間累計常駐。

[官方背景載入文件](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)要求完成後領取結果，且提醒未完成時領取會阻塞。[Godot 4.7.2 ResourceLoader 原始碼](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource_loader.cpp)顯示使用者請求 token 在領取完成結果後才移除。退出的 265 個物件警告與此生命週期有關是待驗證假設，不能直接宣稱全部由它造成。

## 實作契約

- 保留區域／相鄰區域／過場的既有路徑收集規則，只有一個預載服務。資料遺失時指出資源路徑並略過。
- 初始候選值：同時背景載入最多 4 張、等待路徑最多 512 個、服務持有的完成貼圖最多 64 張與 128 MiB 估算量。這些是專案起始預算，經實際關卡測量調整，不是業界標準。
- 快取預算只計服務額外持有的貼圖，不假裝是整個遊戲／驅動的 RAM 或 VRAM 上限。大於單份預算的貼圖完成後交還正常資源管理，不為保住快取而提高上限。
- 在獨立影格檢查狀態，只領取完成／失敗請求；不在遊戲影格呼叫會等待尚未完成的領取。完成快取有可驗證的淘汰規則，淘汰不釋放仍由現有場景使用的資源。
- 清除、回主選單與換輪時停止排入舊區域；已經發出的請求必須在完成後領取，不能丟掉追蹤。暫停時仍可回收，管理節點不隨每個區域累積。
- 提供只讀的待載數、進行中數、快取數及估算量供工具驗證。不得為測試修改原錯誤過濾器或已知失敗名單。

## 驗證

先在隔離程序對一份真正貼圖證明「請求完成但未領取」與「領取後」的狀態差異。再驗缺圖、重複路徑、清除途中、失敗請求、容量超限、暫停回收、反覆換區與回主選單。記錄反覆跨區後的服務計數、程序工作集與退出警告，區分服務估算量、真實 RAM 與 GPU 指標；改善一種指標不等於其他指標已過。

實際 Forward+ 畫面確認區域背景、法線、發光與角色沒有缺圖或閃換。局部選擇器選出的測試全過後才結案。BG-17 的貼圖格式與取樣成本保持原 owner，不把它的未提交修改帶入本票。

## 服務接點與實作邊界

沿用 `warm_level(data) -> int`、`warm_neighbors(data) -> int`、`request(paths) -> int` 與 `clear()`。整數回傳新接受的非同步請求數，排隊不等待；同路徑仍回傳 0。主選單的 `warm_level` 建立新的預載範圍並清除上一輪額外快取；每區的 `warm_neighbors` 為所有鄰居／過場共用一個範圍，切區丟棄舊待載但保留有界 LRU。鄰居收集使用私有資料解析，不逐個呼叫會重設範圍的 public `warm_level`。同範圍重複暖機不重排。

管理節點延後安裝到 SceneTree root，首次請求在它進樹後才派送，避免立即退出時產生尚未有 owner 的 token。全專案只有一個 ALWAYS pump，有工作才 process；每影格逆序檢查四個固定槽，不呼叫 dictionary.keys()。清除保留最多四個舊槽，後續領取不放入新世代快取；同一路徑若在新範圍再次需要，只更新槽的世代並復用請求，沒有再次增加原生 user_rc。只有整個 SceneTree 退出時會領取並等待自己的最多四個槽；一般遊戲影格只領取 terminal status。這與引擎本來等待所有背景載入的退出流程一致，不等待其他呼叫者的請求。

`stats() -> Dictionary` 回傳只讀快照：queued、inflight、inflight_limit、cached、retiring、estimated_bytes、requested_total、collected_total、failed_total、evicted_total、scope。既有 `_requested` 診斷欄位保留相容，只記目前有界的 queue／active／cache。貼圖估算為寬×高×RGBA8×完整 mip chain；不讀回 GPU、不為估算另解碼像素，不代表實際格式、整個遊戲 RAM 或 VRAM。淘汰只放掉服務的引用，不釋放場景仍持有的貼圖。

optional `_n`／`_glow` 只有存在才加入候選，正常缺少可選層不噴警告；明確請求的缺圖／主要素材缺失與載入失敗指出具體路徑。佇列滿時指出首個略過路徑，不繼續大量派送。

## 隔離對照工具

`tools/run_prefetch_probe.ps1 -Mode <unclaimed|claimed|failure|service|campaign|shutdown> -OutputPath <絕對目錄>` 每次使用新的 APPDATA／LOCALAPPDATA；探針驗證實際 user data 路徑，任何中斷不寫真人存檔。unclaimed／claimed 對同一張真正手槍貼圖分別不領取／領取，觀察 terminal status、領取後 INVALID status 與退出 RefCounted 警告差異，不能僅憑 265 的數字判定。

failure 只在隔離 user:// 產生刻意損毀的資源，完整保留原生載入錯誤並驗證失敗後 token 已移除；不是遊戲測試錯誤過濾例外。service 反覆三輪八個正式區域的相鄰預載並清除。campaign 透過真 Main 路由走兩輪八區與返回主選單，Story.auto_skip、獨立存檔，不宣稱人工通關；Forward+ 保存街道／倉庫／復原館與主選單前後實圖。shutdown 在 pump 已建立後留下真正 active token 直接退出，驗證退出回收。

工具保存完整 stdout／stderr、服務快照、引擎 static memory／render texture monitor，另以原生 PID 量 Windows working set／private bytes（每 200ms）。引擎計數、程序 RAM 與服務估算分開保存；headless 的 GPU 監測不能代替 Forward+。截圖使用現有 HDR Capture.image，不另寫色彩轉換。

## Dummy backend 的非同步限制

[4.7.2 Dummy TextureStorage](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/dummy/storage/texture_storage.h) 的 `RID_PtrOwner<DummyTexture>` 未啟用 thread-safe；[同版 RID owner](https://github.com/godotengine/godot/blob/4.7.2-stable/core/templates/rid_owner.h) 的模板預設為 `THREAD_SAFE=false`。這支持配置／釋放競態的推論，並非已修引擎。獨立 `cycle` 探針不使用預載服務或快取，四槽對四張正式武器貼圖反覆 request／get／放掉引用 1,000 次，在 Dummy 重現 wrong RID／null texture 與退出 RID 錯誤；同工具 Dummy 單槽及 Forward+ 四槽各 2,002 checks、無 ERROR 或漏物件。

服務因此只在 `DisplayServer=headless` 的 Dummy backend 宣告有效並行量 1，真實 renderer 保持 4。無頭仍發出真正背景請求、檢查 terminal status 後領取，沒有停用或改為 blocking load。下一次派送前放掉完成結果的區域引用。Dummy 清除遇到自己的 active request，將原有快取短暫移到 retiring，完成後再釋放，避免 clear/free 與自己的 allocation 並行；cached+retiring 仍不超過 64，兩者估算合計仍不超過 128 MiB。這只能協調本服務自己的請求，不能保證任意第三方的並行配置。固定四槽的上限及退出所有權不變。

完整[最小四槽失敗 log](../../pm/Nest-Egg-BG/attachments/BG-23-cycle-dummy-four-engine.log)與[原 Dummy 換區失敗 log](../../pm/Nest-Egg-BG/attachments/BG-23-dummy-service-failed-engine.log)保留，不修改 registry／filter／known failures。刻意損毀資源模式只允許該檔案的兩行精確原生診斷，原始 stderr 全留；任何 SCRIPT ERROR 或不相干 ERROR 仍令工具失敗。工具同步保存 live stdout／stderr、總 log、原生 PID 工作集；工具錯誤／超時會結束自己的程序樹，不留下背景 Godot。

## 實際驗證紀錄

目前匯入、單組與原生對照基準為 `1be7bb0cf9bc4e994c5b9cf851d8071eb0c5b23d`、Godot 官方 4.7.2 `ed1daf0bf`、Intel Arc B580。正式工具新 UID 僅 `tools/prefetch_lifetime_probe.gd.uid = uid://cf832aakcvr17`；四份其他既有工具／projectile 的匯入生成 UID 不納入本票。

| 檢查 | 結果 |
|---|---|
| Headless import | exit 0，無腳本錯誤 |
| Chapter1MapSuite | 1,374 checks／0 new／0 known，57 秒；含 clear 途中、同路徑重用、paused 回收、LRU、估算、飽和、retiring／反覆 clear |
| 同貼圖 unclaimed／claimed | 3／5 checks，未領取退出漏 1 個零參照 RefCounted；領取後 status INVALID、無漏物件 |
| 故意損毀／active shutdown | 5／2 checks，exit 0；失敗 token 已領取，退出只等自身請求 |
| 三輪八區相鄰預載 | Forward+／Dummy 單槽各 81 checks，零 ERROR、零 missing optional warning、零退出漏物件；領取 3,282／3,285 次 |
| 同版受控 Main 路由兩輪八區＋返回主選單 | 舊版 108／新版 127 checks，零 ERROR；舊版 438 未領取 token 對應退出 438 零參照 RefCounted，新版 2,493 次均領取、退出無漏物件 |

受控路由使用獨立存檔與真 Main／Level，清 pending_portal、自己鎖物理世界；依真 layout.floor_below／apply_floor_snap 核對腳底，取景與可見動畫自然穩定。兩版使用同一工具與同構圖，舊 core 未改，舊版只加[觀察 adapter](../../pm/Nest-Egg-BG/attachments/BG-23-baseline-adapter.txt)，不領取它的 token。這是預載生命週期的受控換區，不能稱為人工通關。10 張[前後實圖](../../pm/Nest-Egg-BG/images/BG-23-after-street.png)包含主選單前後、街道、倉庫與復原館；根代理已目視角色貼地、背景／牆面／道具／復原設備與角色完整。初次 adapter 未清入口／穩定轉場的失敗保留 `C:/tmp/bg23-baseline-campaign-v4`，未修改地圖或正式輸入。

| 同構圖兩輪八區的觀察量（MiB） | 舊版 | 新版 |
|---|---:|---:|
| Windows native PID peak WorkingSet | 653.28 | 662.08 |
| Windows native PID peak private bytes | 1,201.48 | 1,211.82 |
| 引擎 render texture monitor 峰值 | 319.36 | 308.29 |
| 返回／退出階段 render texture monitor | 315.45 | 302.13 |
| 退出階段引擎 MEMORY_STATIC | 132.56 | 132.96 |
| 預載服務額外快取估算峰值 | 無此機制 | 52.33 |

OS RAM 在此短路由小幅增加，不能宣稱整個遊戲記憶體下降。最新前後比較包含其他 owner 的 rig／盾面程式整合，不是單變數 RAM 因果實驗；相同正式 JSON／PNG 與取景只能支持畫面完整及此路由的實際觀察。引擎 texture monitor 也不是 OS／驅動實測 VRAM；場景及其他資源管理者的引用不由本服務回收。服務專用三輪換區的 peak WorkingSet 為 native 504.35／Dummy 288.41 MiB，最高 cache 64、估算 38.58 MiB、queued 245／248、active 4／1，各輪 clear 後 cache／queued／active 歸零。[原生對照完整 log](../../pm/Nest-Egg-BG/attachments/BG-23-baseline-engine.log)、[新版完整 log](../../pm/Nest-Egg-BG/attachments/BG-23-current-engine.log)、相同前綴 JSON 與 working-set JSON 可交叉核對。這已證明本票的受控舊請求漏物件因果；原 NE-229 的 265 個警告未逐件比對，不泛稱所有既有退出警告都解決。兩版仍有相同驅動 registry／RGB8 轉 RGBA8 警告及 verbose 的 38 個 StringName 診斷，原文保留；改善針對自有背景請求的 RefCounted／RID。

最終整合基準為 `fcd9ea756a07fcb72c4486ecb4065ccad6c441f7`。refresh import exit 0；`SHARDS=1 tools/run_tests_changed.sh HEAD` 使用未更動的 selector，選 Chapter1MapSuite、Chapter2Suite、DeathReactionSuite、InputFeelSuite、UiScreensSuite 五組，1,872 checks／0 new／0 known／141 秒／exit 0，無 SCRIPT ERROR。完整[最終 console](../../pm/Nest-Egg-BG/attachments/BG-23-final-console.log)與[單 shard 原 log](../../pm/Nest-Egg-BG/attachments/BG-23-final-shard-0.log)保留，包括原有刻意的缺骨架／缺立繪／缺輸入參數 ERROR，沒有新增過濾例外。core／probe hashes 在測試與 capture 期間均未變。

最終 current 實圖與 127-checks 受控主流程亦重跑於 `fcd9ea756`，涵蓋最新 CharacterRig；baseline 保持 `1be7bb0cf` 的舊預載。根代理最後目視三張 latest Forward+ 並核對五組結果；本票完成。

## 主線載入不等磁碟：背景暖檔（BG-50，2026-10-12）

**問題**：使用者回報第一章街道與倉庫戰鬥時偶爾突然停一下。原生 4.7.2 的預載是主線每一格同步載一張隔壁區域的貼圖（上面「實作契約」的主線策略）；單張載入不能中斷，檔案不在作業系統的檔案快取裡（剛開機、剛更新版本、或機器上別的工作在搶磁碟與處理器）時，主線就停在那裡等磁碟。

**量測**（`tools/frame_time_probe.tscn`：機器人在正式關卡實際跑、跳、開槍，關垂直同步記錄每一格的間隔；2560×1440 全螢幕、Arc B580；第一章街道 14 秒，進區後排了 255 張）：

| 情況 | 超過 16.7 毫秒的格 | 超過 33.3 毫秒的停頓 | 最長一格 | 單張貼圖載最久 |
|---|---|---|---|---|
| 主線直接載，檔案沒被快取、機器忙 | 56 | 10 | 79.6 ms | 65 ms |
| 不預載 | 1 | 0 | 22.3 ms | — |
| 主線直接載，檔案已在快取 | 2 | 0 | 30.4 ms | 4.0 ms |

停頓全部來自「主線等磁碟」；檔案已經在快取時，同樣 255 張幾乎沒有影響。

**做法**：
- 讀檔搬到背景執行緒：貼圖排進佇列後，一個背景工作把它實際的匯入檔（`.import` 紀錄的那個檔）整個讀過一遍，內容丟掉，只為了讓系統把它放進檔案快取。這一步不碰 ResourceLoader、不建立任何渲染資源，所以沒有原本主線策略要避開的執行緒問題。
- 主線每一格仍然最多載一張，但只載背景已經讀過的；最前面一批都還沒讀好就這一格不載。等一張超過 3 秒（背景沒回應）照舊由主線直接載，佇列不會卡住。
- 上一格比最近的平均長六成以上時，這一格不載，不把載入疊在已經慢的那一格上。
- 換範圍（`clear`、換區）把暖身紀錄一起清掉，背景正在讀的那一批讀完就算了，不會載到取消的貼圖。
- 只有主線策略而且有畫面時才暖身；無頭執行與其他後端維持原本的行為。

**做不到的**：主線那一格還是要解碼並把貼圖交給顯示卡（實測單張最久 3～8 毫秒）；處理器被別的工作佔滿時，這一段與遊戲本身都會變慢，這不是預載能解的。換區那一下的整關載入（1～3 秒，發生在轉場畫面裡）沒有動。

**另外量到、這次沒有處理**：主角與鏡頭每秒更新 60 次、沒有內插；在更新率不是 60 整數倍的螢幕（例如 200 Hz）上，每一步會被顯示 3 格或 4 格，忽長忽短。這是移動順不順的問題，不是停頓，要動到角色與戰鬥的更新方式，另外評估。

