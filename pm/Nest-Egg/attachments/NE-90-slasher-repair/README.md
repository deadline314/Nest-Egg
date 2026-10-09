# NE-90 切割者：近側手部與單靴修補證據（partial）

這是局部交付證據，不代表切割者整體素材已完成。CPU 重建資料、native Forward+ capture、測試紀錄分開呈現。

## Native Forward+ captures

`before` 與 `after` 各有 72 張截圖：9 個動作狀態 × 2 面向 × 4 個取樣 frame。原始輸出位於 [`images/NE-90-slasher-hand/before`](../../images/NE-90-slasher-hand/before) 與 [`images/NE-90-slasher-hand/after`](../../images/NE-90-slasher-hand/after)。代表畫面：

- Before：[idle，右向](../../images/NE-90-slasher-hand/before/idle_face1_frame0.png)、[lunge，左向](../../images/NE-90-slasher-hand/before/lunge_face-1_frame119.png)
- After：[idle，右向](../../images/NE-90-slasher-hand/after/idle_face1_frame0.png)、[lunge，左向](../../images/NE-90-slasher-hand/after/lunge_face-1_frame119.png)

每個 tag 記錄 2,160 個 rig frame（9 狀態 × 2 面向 × 120 frame）；`trace.json` 中每 frame 的兩個 wrist 座標均為 finite。這是數值有限性檢查，不是 2,160 格逐格視覺驗收。`walk` 使用 60、`run` 使用 150 的輸入速度，是比例探針，不是實戰或戰鬥測量。

已記錄的 native 執行環境是 Godot 4.7.2 Forward+、NVIDIA GeForce RTX 4070 SUPER；before-v2 與 after log 都報告 2,160 frames，且沒有 SCRIPT ERROR。較早的 before 初次紀錄包含 `slasher.lunge` action 設定錯誤，已由 before-v2 重拍取代，舊 log 不作為驗收證據。

重新擷取時，scene 只接受 `--tag=before` 或 `--tag=after`；不帶 tag 等同 before，重複 tag 或未知值會退出失敗。tag 只決定輸出名稱，不會切換素材版本。修前須在基準 `9f6438869067f9d155bec2bd6c7d74e1b9e9bfba` 的獨立 checkout 放入此擷取工具後執行；修後在本次修復版本執行，勿以目前版本覆寫歷史修前圖。它不再支援 trial cache 注入。這兩次 capture 的 log 為 [before-v2](logs/ne90-slasher-native-before-v2.log) 與 [after](logs/ne90-slasher-native-after.log)。各自 checkout 使用 GPU lock 的重跑命令：

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . res://pm/Nest-Egg/attachments/NE-90-slasher-repair/slasher-hand-capture.tscn -- --tag=before
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . res://pm/Nest-Egg/attachments/NE-90-slasher-repair/slasher-hand-capture.tscn -- --tag=after
```

## CPU source and cut verification

本次用目前正式 cutter 完整重建該角色，八張 diffuse 及對應 normal 有差異。除手／鞋遮罩和腕點外，其餘來源像素沒有重畫；現行 cutter 的 padding 也更新了軀幹、骨盆、腿與袖子的尺寸／pivot。例如骨盆 155×121→155×126，支點 y=97.39→99.39；上腿 142×246→142×251，支點 y=-9.86→-7.86。頭與護甲 PNG 保持不變；正式輸出與隔離重建逐件比對，不能把這些 padding 更新稱為所有其他 PNG 位元組不變。

[`repro.md`](repro.md) 是 source rebuild 與 runtime diffuse 的摘要；完整 hashes、尺寸、mask 點、component 數、四次命令紀錄見 [`repro.json`](repro.json) 和 [`logs/`](logs/)。portable [`reproduce.py`](reproduce.py) 會向上尋找 `project.godot`，兩次隔離重建只寫到 `.godot/ne90-slasher-final-repro/`，不會寫入附件資料夾。本次已執行一次 portability check，結果成功；四條命令的輸出分別保存在 [run 1 source rebuild](logs/cpu-run-1-source-rebuild.log)、[run 1 cut](logs/cpu-run-1-cut-layers.log)、[run 2 source rebuild](logs/cpu-run-2-source-rebuild.log)、[run 2 cut](logs/cpu-run-2-cut-layers.log)。Normals 與 import 紀錄另見 [normals](logs/ne90-slasher-normals.log) 和 [import](logs/ne90-slasher-import.log)。

基準 PNG source hash 是 `ba9af5139d225d492019c24c261bcd1ba9387d1bca7d10e7fd0fa3f5f1931bf3`。hand 與 foot masks 的正／負 SAM 點各 4/4 通過。foot mask 原有 components 為 12,365、5、1 pixels；沿用既有 30px 規則後保留一個 12,365-pixel component。`ground_y=1192` 的選取區有 4 個 opaque pixels，x=406–409；source alpha ownership crop：[foot-ground-ownership.png](foot-ground-ownership.png)。這些是來源像素與切圖檢查，不等於動畫接地視覺驗收。

兩次 rebuild 的 16 個 source/runtime/semantic 輸出 hashes 一致；正式 hand/foot full-canvas overrides 逐像素相同，12 張正式 diffuse part PNG 逐像素相同，`character.json` 與 `slasher.json` semantic 相同。錯誤 source hash、假全不透明 alpha、以及修改 owned RGB 的負控制都被拒絕。

## 測試與範圍限制

記錄的受影響 suite batch 為 3,363 checks，額外 suite batch 為 684 checks；兩者均為 new failures 0、known failures 0，log 在 [`ne90-changed-tests.log`](logs/ne90-changed-tests.log) 和 [`ne90-slasher-extra-tests.log`](logs/ne90-slasher-extra-tests.log)。專屬 EnemyArtDelivery acceptance gate 尚未單獨註冊並執行；這些 suite 數字不應被解讀成該 gate 已通過。

此 partial 沒有處理或驗收尚可見的 pelvis/leg ghosting 與其他 hand 缺陷；也未涵蓋完整護甲脫落底層、所有 source visual gate 或 combat 行為。因此不應據此把 NE-90 全票標為完成。
