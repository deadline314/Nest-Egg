# 鎮暴員袖口與單手套分件修復

正式素材已採用既有原圖與補全圖重新分割的前臂、單手套，以及對應法線、尺寸和 pivot。手套不再混入大腿，袖口補回來源中漏分的布料；沒有重畫角色、移動骨架或降低接縫門檻。

來源、SAM 工作流、遮罩與逐像素歸屬保留在 [wrist_repair](../../../../art_src/characters/enforcer/wrist_repair/README.md)。兩次隔離重建、五項負控制、正式貼圖／法線與資料比對見 [source-replay.log](source-replay.log)。

## 實測範圍與結果

- 固定程式基準：`3c053d316fc4da97b00887c2cbbed60b19a12334`；修前接點基線沿用 Commit-10 的 `fcd9ea756` 素材。骨架與動畫器保持相同。
- Godot 4.7.2、Forward+、RTX 4070 SUPER；ComfyUI 停止，使用共用 GPU 鎖。八動作、兩面向、1.0／3.4 倍率、每組 120 格，共 53,760 個十四接點樣本。
- 修前 8,711 個失敗，正式修後 1,287 個失敗；7,424 個失敗已消除，**逐筆比對沒有新增失敗樣本**。
- 手腕七個非死亡動作：0／6,720 失敗。死亡手腕 256、肘部 208、頸部 813、膝部 10 個失敗樣本仍保留為失敗；**整體美術與動畫尚未通過**。
- 受影響測試固定基準執行 38,913 checks、0 新／已知失敗，160 秒，無 SCRIPT ERROR。選擇器受工作目錄其他候選影響選到 42 組，實際執行 40 組；未註冊的 EnemyArtDeliverySuite、WatchdogQuadrupedSuite 不算已執行。本次差異獨立選出的 LayerOrderSuite、NpcAnimationSuite、RigActionsSuite、RigMeshSuite 均已實際執行。
- 正式材質匯入與規格／部件／法線檢查通過；各六十四張修前、正式修後 1536×1400 原生截點供整體外觀檢查。截點不取代逐格十四接點結果。
- 完整測試由 CI 負責；目前 GitHub 帳務限制使最新 main job 未啟動，不能宣稱 CI 通過。

[verification.json](verification.json) 記錄完整數量，[report.json.gz](report.json.gz) 保留失敗座標與影格，[frames.json](frames.json) 保留取樣布局，[native-frame-manifest.json](native-frame-manifest.json) 保留全部 1,920 張原生影格的 SHA-256。全部原生圖保留在本 Session 的 `.godot/ne90-wrist-native/frames-enforcer-formal-all14/`；票內附代表原生圖，未以放大或其他部件遮蔽改變判定。

## 重跑

CPU 重跑不寫正式素材：

```powershell
$env:PYTHONUTF8 = '1'
& 'D:/ComfyUI/.venv/Scripts/python.exe' pm/Nest-Egg/attachments/NE-90-enforcer-wrist/verify.py
```

依實際 Python／Godot 路徑調整命令；先確認 ComfyUI 沒有生成工作且顯示記憶體足夠，再擷取正式材質：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://tools/rig_joint_audit.tscn -- --chars=enforcer --frames=120 --out=<絕對輸出目錄>
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/check_joint_frames.py <絕對輸出目錄>
```

目前接點 checker 應退出 1；這是真實未通過結果。整體六十四截點可使用同目錄 `whole-character.tscn -- --out=<絕對輸出目錄>`，走相同 GPU 鎖。

採用方式參照 [Godot cutout animation](https://docs.godotengine.org/en/stable/tutorials/animation/cutout_animation.html) 的階層與 pivot 檢查，以及 [Spine mesh attachments](https://esotericsoftware.com/spine-meshes) 的來源／網格分工；來源漏分先修正材質，不以任意移動骨架掩蓋缺口。
