# NE-80 CPU/headless 回歸

固定起點：`89b16e63d39ca18a7385d930a744f09c28846d61`。獨立 scratch clone，分支 `codex/session1-cloud-ne80-art-regression`；沒有假稱使用命名 Nest-Egg 雲端環境。官方 Godot `4.7.2.stable.official.ed1daf0bf`，headless Dummy renderer／Dummy audio。沒有啟動 ComfyUI、沒有原生圖片、沒有 Compatibility 或 Forward+ 驗收。

## 實際範圍

- 正式 heavy_gunner skin、16 骨、22 部件及真實 minigun；所有引用來源 SHA256 見 [baseline.json](baseline.json)，官方 ZIP 校驗、解出 binary SHA512、版本見 [engine.json](engine.json)、[官方 SHA512](official-SHA512-SUMS.txt)及版本原始日誌。
- 票內八動作：待機、跑、瞄準、蹲、跳、格擋、硬直、倒下，另加步行。空手／minigun、面向 ±1 各 660 固定 60Hz 格，共36段。活動段10秒包含完整呼吸／sway與數個步態週期；跳包含起跳／頂點／下落／落地，硬直含受擊／恢復，倒下含完整0.9秒與安定。每段逐格做裝甲1→.5→0→1，入口／出口亦檢查；另四段240格起步／停步／轉向／瞄準掃描。
- 檢查骨與部件有限變換、正非零肢體骨長、固定 authored offsets／rests、實際父子節點與 joint transform；直接掃描骨子節點檢查每個 logical slot 唯一可見、原圖層不變。正式外觀没有 `under` 替代件，脱甲底層是原有非裝甲軀幹／骨盆／四肢，必須持續可見；不以空陣列當成底層通過。
- 核對真正的 weapon anchor、Skeleton2D 下的 Weapon 掛載、資料 grip／foregrip／muzzle、兩手0.025世界像素握點與實際槍口變換、空手及死亡武器隱藏。CPU握點不證明手指、袖口或材質圖像正確。
- 真正 Level／Player／HeavyGunner 自然預熱→掃射13發→散熱，Player 消耗真實手槍子彈：閉甲14→14、散熱14→12。只有Player生命999及位置受到控制，這段沒有強制敵人FSM／HP／裝甲。其後兩面向各三狀態的720格為明示的受控專屬動作取樣，從真實敵人的 `_drive_rig` 入口驗掛點／槍口，不計自然戰鬥或操作手感。
- 七種負控制：軀幹掛錯骨、手骨長改10%、隱藏真底層、加入未登記的重複可見slot、NaN bind、錯面向、武器錯掛點；同一檢查器逐項拒絕且還原後重驗通過。沒有新增 runtime 保護、generic框架、放寬門檻或 known_failures。

[CPU部件帳本](cpu-part-ledger.json)只記錄資料／綁定／可見性，不是人體／像素接點帳本通過。

## 原始結果與診斷

| 執行 | 結果 | 證據 |
|---|---|---|
| spec／joints、parts／normal | 0錯誤、0警告／OK，exit0 | spec.*、parts.* |
| 專用suite首輪 | 25,508 checks、0 failures，exit0 | focus-first.* |
| 原註冊表10套基線 | 8,902 checks、0 failures，exit0 | baseline-dependencies.*及四份原始shard |
| 最終11套局部 | 34,410 checks、0新／已知失敗，exit0，54秒 | affected.*及四份原始shard |
| 本次base CI | completed／success，run38061051932 | ci-final.json；不表示未push的新commit已跑CI |

完整命令、cwd、選定環境、stdout／stderr／exit碼見每份 `*.command.json`。平行runner自己的stdout／stderr分開保存；每個Godot shard按原工具的 `2>&1` 保存合併原始stream，沒有刪除ERROR。大份首次import及無效啟動日誌以gzip保留原始bytes，可 `gzip -dc` 解讀。[結果解析](results.json)列出實際執行套件與負控制。

所有成功執行沒有SCRIPT ERROR。三個既有ERROR在原註冊表基線 `baseline-dependencies-shards/shard_1.log` 與最終 `affected-shards/shard_3.log` 完全一致：RigActionsSuite故意呼叫 `no_such_action`，HitReactionSuite故意給 `test_missing_part` 無效hurt_parts及不存在EnemyVfx。其原backtrace與各suite結束／check數均保留；沒有新的非負控ERROR。

`run_tests_changed.sh` 因實際入口 `tests/smoke_test.gd` 新增一行而選ALL；沒有 `tests/smoke.gd`。第一次shell exec攔截回傳而未退出，落到 `--only=ALL`，且在import完成前啟動，出現新類別及未匯入資源錯誤；以130中止，明確無效、不算通過。修正攔截改為exit3，公開 `changed-selector-guarded.*`；不修改正式runner、不跑完整套件。之後以明列11套 `--only` 執行。

依賴：HeavyGunnerArtDeliverySuite；HeavyEnemiesSuite（正式FSM／護甲／戰鬥）；CharactersSuite（資源與外觀）；RigMeshSuite／PoseMeshSuite（部件與網格契約）；AnimAuditSuite（原幾何門檻）；RigActionsSuite（專屬動作及死亡優先）；HitReactionSuite／DeathReactionSuite（受擊與最後一擊）；ProtagonistMotionSuite／LocomotionSuite（共用IK及真實步態）。完整測試交CI。基線執行時原tracked註冊表與既有程式完全等同固定base，只存在尚未註冊的新測試檔及證據。

## 重跑

在完整匯入且版本／官方SHA校驗通過的checkout：

```bash
export NE80_GODOT_BIN=/absolute/path/Godot_v4.7.2-stable_linux.x86_64
export GODOT="$PWD/pm/Nest-Egg/attachments/NE-80-cloud-art-regression/headless-godot.sh"
LOG_DIR=/absolute/new/logs tools/run_tests_parallel.sh --only=HeavyGunnerArtDeliverySuite,HeavyEnemiesSuite,CharactersSuite,RigMeshSuite,PoseMeshSuite,AnimAuditSuite,RigActionsSuite,HitReactionSuite,ProtagonistMotionSuite,DeathReactionSuite,LocomotionSuite 4
```

若跑selector，必須先檢查ALL並攔下完整套件；實際安全攔截命令已保存在command.json。所有預期suite必須有 `SUITE_TIME` 與非零checks；SCRIPT ERROR／新的非負控ERROR均失敗，不只信runner的exit0。

## root／NE-224 驗收

1. 核对最新main、patch／commit與固定來源、原始log和實際scope；若合併NE-79註冊衝突，保留兩個suite各自的一行，不能覆寫其他Session。
2. 整合後只在有相關變更時重跑受影響局部；新commit的CI紅優先處理。
3. 兩面向、遊戲／過場倍率、八動作與完整切換的全彩人體、全部接點、一像素縫、裝甲／底層／手指／實際可見武器，均仍待原生驗收。
4. Forward+ normal／glow／HDR2D、真正玩家操作手感、自然完整戰鬥與硬體效能仍由主Session按NE-224驗收。此次沒有native，不以CPU矩陣、部件帳本或示意圖代替。

NE-80維持進行中，既有複合外觀條件沒有因CPU子成果新增勾選。NE-181歷史腰髖像素通過也不推定其他接點或最新全身通過。
