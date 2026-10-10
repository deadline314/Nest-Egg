# NE-222：步行軀幹診斷與原定稿保留

本段僅交付新增需求與當前來源／步態基線，沒有替換角色部件。使用者指出挺胸使走路不自然，同時要求保留既有立繪。原定稿 s33 與 base_rgba 的 SHA 均為 `401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9`。

## 來源與路徑

軀幹目前為 200×336、pivot [55,306]、density 0.04205，掛於 chest；完整及受損版本、外套須一起檢查。正式外套來自配方登記的 rin_worn_coat 重建與 overrides/refined 優先來源，非舊 rin2/07_refined/jacket.png。`walk-diagnosis.json` 記錄兩者及 runtime 的獨立 SHA。

關卡 PlayerVisual 與移動的 CutsceneActor 都進 HumanoidAnimator 步行分支。JSON中的胸骨角度是公式推算，並非執行中骨頭讀數；70/150速度的 lean 項約4.28度，返家段局部速度21.56/150約1.32度，尚須加上慣性、瞄準及軀幹疊加。不能由公式推定外觀正確。

## 原生基線的範圍

兩張1280×720 PNG使用Godot4.7.2、RTX4070SUPER、Forward+／HDR2D、共享GPU鎖，原尺寸未插值。用現有 rig_preview 的八個步態取樣：70及21.56、run-speed150、zoom2.2。兩者均使用現有素材及預覽武器。

這是相同骨架的速度診斷，不是實際關卡操作或完整返家過場，不包含另一面向／起停／全接點驗收。文件1440×1000預覽是實際Godot渲染當前RIG_QUALITY補記，亦不是遊戲修後畫面。全票保持進行中，新步行條件未勾選。

## 重跑

在專案根目錄執行：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' pm/Nest-Egg/attachments/NE-222-walk-torso-review/walk_torso_review.py
```

只寫入私有 `.godot/ne222-rin-walk-torso-review/`，不寫正式素材。原生基線使用GPU鎖，各自提供新輸出位置：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://tools/rig_preview.tscn -- --chars=rin --gait --speed=70 --run-speed=150 --zoom=2.2 --out=D:/NestEggVerification/new-walk-baseline.png
```

第二張把速度改21.56，保留其他條件。來源診斷與截圖不能替代分件、美術或遊戲驗收。實作採Spine官方的[attachment切換](https://en.esotericsoftware.com/spine-attachments)做法作參照：姿勢需要的圖形另備部件，保持同一slot/bone，只讓適用版本可見。專案已有pose_parts，需驗證完整/受損成對、切換還原及其他caller，沒有在本段新增執行時切換。
