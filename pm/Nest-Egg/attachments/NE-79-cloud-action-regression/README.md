# NE-79 雲端 CPU 動作回歸

基線：`aeb45f77f5b99ca962786fb28341f1a87fb9ad4f`（fetch 後的 origin/main）。獨立 clone 與分支 `codex/ne79-cloud-action-regression`。本次環境是使用者另行授權的當前 cloud scratch，**不是已核對的 Nest-Egg 命名配置**；未提供 environment_status 或 cloud-environment-runtime 技能。平台 Linux 6.18.44 x86_64 / glibc 2.39。以既有 session 網路/CA 存取 repo 和官方發行，沒有讀取憑證、換身份或登入。讀取成功不代表推送權限。

## 引擎與重跑

官方 [4.7.2-stable 發行](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) 的 `Godot_v4.7.2-stable_linux.x86_64.zip`，以同發行 `SHA512-SUMS.txt` 核對；匹配行保存在 official-sha512.txt。ZIP SHA512：`9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`。實際 `--version`：`4.7.2.stable.official.ed1daf0bf`，完整解壓 executable 146414384 bytes。

跨呼叫保留的 executable 曾變成 127467520 bytes／不可執行並退出 139；原因未確認。交付的 godot 小型 wrapper 是當時使用方式的快照：每次從已核對 ZIP 解壓到私人暫存目錄後直接執行；它不是另一個引擎。重跑者須將 wrapper 的 runtime_root 改成自己的 ZIP 目錄。引擎 binary 不提交。

依官方命令列文件，`--headless` 使用 headless display 和 Dummy audio。本次只測 CPU 節點/矩陣，不產生畫面。若另做軟體畫面需選 `--rendering-method gl_compatibility`；那不代表 Forward+ 或硬體性能。本次沒有做該畫面測試。

在 repo 根目錄設定 GODOT 指向上述 wrapper，XDG_DATA_HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME 指向可寫的私人 scratch 目錄；先執行 `$GODOT --headless --editor --path . --import`。另設 LOG_DIR 為可寫且每輪獨立的 scratch 絕對路徑；runner 自行在其中建立各 shard 的資料目錄。以下為正式 runner 命令（SHARDS=4）：

```sh
BASE=aeb45f77f5b99ca962786fb28341f1a87fb9ad4f
SHARDS=4 tools/run_tests_parallel.sh --only=CharactersSuite,RigMeshSuite,RigActionsSuite,PostureSuite,HitReactionSuite,AnimAuditSuite,LocomotionSuite
# 新套件建立但尚未註冊：重現 selector 選中卻 runner 執行 0 checks。
tools/run_tests_changed.sh "$BASE"
# 註冊後 changed selector 會選 ALL；此次使用 godot-local-only guard 拒絕 --only=list，避免啟動全套。
GODOT=/path/to/godot-local-only tools/run_tests_changed.sh "$BASE"
# 實際最終局部執行，使用真正 godot wrapper：
SHARDS=4 tools/run_tests_parallel.sh --only=CharactersSuite,RigMeshSuite,RigActionsSuite,PostureSuite,HitReactionSuite,AnimAuditSuite,LocomotionSuite,EnforcerArtDeliverySuite
$GODOT --headless --path . --script tests/smoke_test.gd --only=EnforcerArtDeliverySuite
```

註冊實際入口是 `tests/smoke_test.gd`，不是舊指示的 tests/smoke.gd。改此入口觸發現有 select_tests.py RUN_ALL；未擴改 selector/framework。註冊後 changed 命令退出 **1，不是通過**，guard 直接拒絕退出 64；完整測試未執行。`registered-list.log` 證明正式 runner 已列出新 suite。以上局部實跑符合本次不跑全套的限制，但 changed runner 的自動選取仍有此限制。

## 實測結果

| 實跑階段 | checks | 退出碼 | 說明 |
|---|---:|---:|---|
| 修改前七個相關套件 | 5904 | 0 | 0 新/known failures；24 秒 |
| 新檔未註冊、changed runner | 0 | 0 | 未 covered；不接受為通過 |
| 註冊後 changed runner + scope guard | — | 1 | selector ALL，拒跑全套；不是測試通過 |
| 最終八個相關套件 | 6890 | 0 | 0 新/known failures；25 秒 |
| 最終獨立 EnforcerArtDeliverySuite | 986 | 0 | 4.2 秒；無 ERROR/SCRIPT ERROR |

基線與最終局部各有三條 ERROR：既有負控制的 no_such_action、test_missing_part/hurt_parts、EnemyVfx 缺失資料診斷；均保留原始 log，不能稱「全部無 ERROR」。兩輪均無 SCRIPT ERROR、FAIL。最早未 import 完整的嘗試有缺資源 ERROR；預設 /root XDG 的 import 有權限 ERROR 並被中止退出 130。後續可寫 XDG import 無 Godot ERROR，但舊 wrapper 清理 rmdir 失敗使外層退出 1；已修正清理不覆蓋 engine exit。這些不成功嘗試也保留，與完成 import 後的有效基線分開。

## 可觀測 CPU 契約與來源

正式 RigLibrary → CharacterRig → RigInput → HumanoidAnimator；裝備、skin、移動/衝撞速度與 rig_actions 讀 `data/enemies/shield_rusher.tres`，曲線讀正式 enforcer motion profile。左右各 2635 次固定 1/60 秒更新（共 5270），不以低 FPS 截圖或偽造 fixture 代替。

| 範圍 | 實際來源與界限 |
|---|---|
| idle / walk / run | 官方 idle/move；walk 至少兩個 stride 周期；衝撞速度與回 idle |
| jump / dodge | 官方 air/dash input 與曲線；上升、下降、落地、前後 dodge、回 idle。只證明 animator 分支，不宣稱鎮暴員有這些 gameplay |
| attack | 真實 Enemy FSM state 入口與 `_update_rig_action`，使用已登記 brace / stagger_back / skid，各完整 duration 加 30 frames 與回 patrol 淡出。控制 FSM 時間，不宣稱重跑自然戰鬥或完整攻擊判定 |
| hit / die、aim/crouch/block | 正式 hurt/death/preview 分支；不同姿態及轉場；死亡壓過殘留 registered action、藏武器，保留 NE-222 既有優先序修正 |
| 骨骼與翻面 | rest/父子與 child local 位置不改（hip 是 authored root translation）；有限剛性變換、粗略兩身高安全範圍；逐 frame 骨點、盾、活體 muzzle 鏡像 |
| shield / armour / attachments | 真實 shield 與四裝甲組逐階移除、七 plate 可見性；15 個既有底層 body slot 保持同節點可見；實際骨骼子 attachment 計數；不證明 PNG 內沒有多手腳 |
| weapon / muzzle | 真實骨骼相對盾矩陣、前掌 grip <0.025、weapon→muzzle 矩陣 <0.001；未降低既有像素/頂點門檻 |

每方向六種負控制：移動 wrist、縮放 bone、偏移 shield、隱藏底層 torso、偏移 muzzle 一 texel、實際新增手 attachment 節點；只在可丟棄 runtime nodes 施加，確認斷言拒絕後復原。

骨點/finite/slot visibility **不接受人體解剖、全 alpha 接點、源圖多肢、手感或八動作畫面**。裝甲只調正式 visibility ratio，未驗證 HP 傷害、飛散/debris。C3 `e60526a49e` 正面擋盾、蓄力、背擊已交付，不重做。NE-181/NE-222 最新成果仍需 NE-224 本地 Forward+、操作與全 alpha/關節畫面驗收；本票保持進行中、未變更勾選。沒有 GPU、軟體 rendered frame 或新圖片，不建立 cloud 偽截圖。

## 檔案與 raw evidence

本次只新增 suite、最小註冊、本票 Commit-4 與此 evidence 目錄；沒有改 shared rig/animator、素材、enemy、核心武器或其他票，沒有新增 known failures。`results.json` 為摘要；`logs/baseline`、`logs/unregistered`、`logs/affected`、`logs/registered` 保存歷次實際嘗試，最終準據是 `logs/final` 和 `logs/new-suite-final.log`。`manifest-sha256.json` 保存原始檔校驗，不包含自己。

推送前 main 新增 `7e36216690d32381861b554e4d263f6634dd7dfc`（NE-222 來源／分割證據，不改共用 runtime），已 rebase 保留。合併後相同八套件實跑 6890 checks、退出 0、27 秒，仍是三條既有負控制 ERROR、無 SCRIPT ERROR/FAIL；raw 見 logs/post-rebase。第一次合併後嘗試漏設 LOG_DIR，唯讀 /tmp 造成 0 checks 卻退出 0，記錄在 post-rebase-empty-attempt.log，明確不算通過。原始 --help 的尾端空白保留未整理，staged blobs 已逐檔核對 manifest。
