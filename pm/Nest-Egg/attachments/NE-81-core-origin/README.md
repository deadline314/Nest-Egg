# NE-81 核心砲世界座標修正

基線 `b4c186ea401dfb29b92e28a0a9c8e7de46f604e3`；2026-10-10 本地 Godot 4.7.2、RTX 4070 SUPER、Forward+ Vulkan。僅修正核心砲發射原點，未更動立繪、骨架、攻擊方向、傷害或時序。

## 根因與範圍

`Enemy._core_point()` 回傳 Enemy 本地座標。核心砲原本直接加上 `global_position`，因此漏掉角色及祖先的縮放、旋轉；現在以 `to_global()` 轉換。弱點光環的本地繪製仍使用本地座標。正常機槍、扇形砲使用既有槍口位置，未改變。

修正最先由雲端 NE-81 組提出，雲端 commit `63f4631c01ed3a7e6e230184642dfe90d3c87c78` 未推送成功（HTTPS clone 缺少 push 憑證）。本地收到完整最小 patch 的文字，核對 UTF-8 LF SHA-256 `e84d08de9a077e4fbf0bd220cfc8302457210dca0191edebefe15887afdb8cd5`，再以正常本地 Git 交付；不是雲端已 merge。原始 `cloud-minimal.patch` 保留兩個雲端診斷腳本內容；它們不作為 CI 註冊測試，也不當作雙面向驗收。正式新增測試已註冊到 `HeavyEnemiesSuite`，固定目標在角色面向側，同時驗證有 rig 與缺少 rig 的安全預設。

## 驗證

| 證據 | 修前 | 修後 |
|---|---|---|
| 正式新增回歸（兩面向 × 有／無 rig × 4 種縮放旋轉，每案兩項） | 32 項／12 失敗 | 32 項／0 失敗 |
| 真實核心砲、兩面向 × 5 種父變換 | 10 案、30 發砲彈 | 10 案、30 發砲彈 |
| 砲彈生成位置距核心世界座標最大誤差 | 36.7649 px | 0 px |
| 原生全身畫面（windup／fired × 1.5／1.8 camera zoom） | 40 張 | 40 張 |
| 原生擷取 harness／ERROR／SCRIPT ERROR | 0／0／0，exit 0 | 0／0／0，exit 0 |

`comparison.json` 保存逐案誤差。純平移與 identity 修前即正確，不宣稱它們重現錯誤。原始 log／JSON 在 `before/` 與 `after/`；80 張 1280×720 PNG 在 `../../images/NE-81-core-origin/`。攝影倍率 1.8 是全身審查構圖；1.5 是遊戲倍率。PNG 沒有縮小、補畫或後製。

`tools/run_tests_changed.sh b4c186ea401dfb29b92e28a0a9c8e7de46f604e3` 選出的 40 組受影響測試用 8 個獨立 headless 程序執行：38,913 checks，0 新失敗，0 已知失敗，166 秒。選擇基準固定在修前 commit，不因交付後工作目錄乾淨而跑空集合。摘要及全部 shard log 在本資料夾。

推送前 rebase 到 `64740049`（包括其他 Session 的 BG-25 局部水流與派工文件）。沒有程式衝突；匯入新增元件後，在合併結果重跑 EnvironmentSuite、HeavyEnemiesSuite、Chapter1MapSuite、SceneSanitySuite：7,949 checks，0 新／已知失敗，62 秒、4 個 headless 程序。`merged-*.log` 保存完整 log；不是完整測試套件。

## 重跑

在獨立 checkout，依專案流程完成匯入後，先跑受影響測試。GPU 生成和原生擷取依既有共享鎖互斥。

```powershell
$env:GODOT='C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
$env:SHARDS='8'
& 'C:/Program Files/Git/bin/bash.exe' tools/run_tests_changed.sh b4c186ea401dfb29b92e28a0a9c8e7de46f604e3
New-Item -ItemType Directory -Force '.godot/ne81-core-origin-native' | Out-Null
Copy-Item 'pm/Nest-Egg/attachments/NE-81-core-origin/native-fixture/*' '.godot/ne81-core-origin-native/'
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- $env:GODOT --path . --rendering-method forward_plus --rendering-driver vulkan --max-fps 60 res://.godot/ne81-core-origin-native/capture.tscn -- --label=after --expected-origin=world --out=D:/NestEggVerification/ne81-core-origin-replay
```

同一 fixture 三個檔案 byte-identical 用於修前／修後，沒有改判斷門檻。修前獨立 checkout 用 `--expected-origin=legacy`；其 harness 通過僅證明重現舊錯誤公式，不代表修前位置正確。fixture 的固定 baseline/variant 文字是原始 provenance，修後判斷由 `expected_origin=world` 與實際砲彈座標決定。正式原生資料保留兩種欄位，不事後重寫原始 JSON。

## 界限

這是 NE-81 的部分修正，票維持進行中。監管者八動作、全部接縫、完整頭目戰、旋轉父節點下瞄準線方向及所有攻擊畫面不由這組原點證據驗收。畫面仍可見既有造型／動作問題；不得用核心砲測試通過代替骨架品質通過。來源檔案與輸出 SHA-256／尺寸在 `manifest.json`。
