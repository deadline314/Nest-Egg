# NE-222：姿勢專用部件的替換支援

本段交付共用介面；没有把未通過的跪姿圖放進正式角色，也没有串接玩家動作。介面見 [POSE_PART_ATTACHMENTS.md](../../../../design/12-cast-redraw/POSE_PART_ATTACHMENTS.md)。做法參考 [Spine attachments](https://esotericsoftware.com/spine-attachments) 的每槽單一附件與 [新姿勢製作流程](https://eu.esotericsoftware.com/blog/Rigging-new-poses-tutorial) 的新部件／既有骨架；不宣稱等同其網格權重功能。

## 本次證據

- 固定基準 `7d22ad9226c29a931f8d9214d21919a3537d289a`，乾淨驗證 checkout 執行 `tools/run_tests_changed.sh 7d22ad92`：41,177 checks，零新增／已知失敗，212 秒。選取套件與八份完整 shard log 保留。完整測試交 CI。
- 專項四套：2,779 checks，零失敗、無 SCRIPT ERROR。錯誤來源、尺寸／支點、骨頭、法線、損傷底層配對、重複槽與眨眼頭部均有負控制；無效整組保留原角色。同 main 的四套基線有相同三種預期負測試 ERROR；基線 233、候選 221 個 ObjectDB 退出警告，完整保留，不宣稱零警告。
- 原生環境為 Godot 4.7.2、RTX 4070 SUPER、Vulkan Forward+／HDR 2D，使用共享 GPU 鎖且 ComfyUI 已停止。三欄為 base／selected／cleared；六列為右向護甲 1／0.5／0、左向護甲 1／0.5／0。PNG 原生 960×1560，未放大擷取。
- 含既有網格的對照中，清除替換後六列逐 byte 還原；骨頭、槽、normal／glow 通過。但 selected／base 的相同來源比較六列失敗，骨盆差異 15／45／39 像素，左右對稱，alpha 不變，靴子沒有差異。替換件為 Sprite，基線骨盆為 RigPartMesh。另做 canonical-rest 對照仍失敗；沒有將失敗改判通過，也未確定所有細部成因。
- 獨立同幾何控制只在合成 fixture 設定 `limb_bend=false`，不改正式皮膚或全域開關；base／selected 同為 Sprite。92 checks、零失敗、退出 0，六列 base／selected／cleared 的 RGBA 逐 byte 一致，normal／glow、損傷底層、翻面與二十骨身份／rest 通過。
- 同條件 CPU 對照：十名凜、3,000 格、三次前後交替。既有角色未配置替換件時，網格動畫平均 2,181.4 → 2,278.0 µs／格，增加 4.43%，477 頂點不變。不是渲染 FPS 或新姿勢效能驗收。

`mesh-comparison-failed.*`、`rest-comparison-failed.*` 為失敗證據。首次 rest 試作有縮排解析錯誤，修正後重跑另存；該次不作通過依據。同幾何控制不能代替網格、人體、逐格接縫、握槍、遊戲與完整起落驗收。

## 重跑原生控制

從 repo 根目錄，先確認沒有生成工作且 ComfyUI 常駐模型已釋放：

```powershell
$env:COMFYUI_DIR = 'D:/ComfyUI'
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method forward_plus res://pm/Nest-Egg/attachments/NE-222-pose-parts/capture_rigid_control.tscn -- --out=C:/absolute/pose-parts-control
```

改用 `capture.tscn` 重現不同幾何的比較，預期六項 selected／base 不一致；不能當作素材合格。SHA-256 見 `manifest.json`。
