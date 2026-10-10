## 主 Session 本地接收與驗收

雲端沒有可用的 push 認證，保留 `f7c108f34f7b0340028e4e525106c9bb8e69709d`，沒有宣稱合併成功。root 在獨立 `D:/NestEggVerification/ne79-cloud-f7c108f3` 接收完整 format-patch：gzip SHA-256 `41e1d022b4e6d9be26f1d6ba765d9a1bb1b1b01eaa16368344665c62db0a9b82`，解壓 patch SHA-256 `4ff2ddf954991d24a198e450e34523bef0e251f9d7bec85c6de02d621cf08b73`，核對後套用並審讀套件。

最新 runtime 基準 `89b16e63d39ca18a7385d930a744f09c28846d61`（含另一 Session 的衝刺殘影），本機 Godot `4.7.2.stable.official.ed1daf0bf`：共享鎖下完成匯入；以下局部正式套件實跑 6,890 checks、0 新／known failures、exit 0。[本機完整結果](affected-tests.log)與四份 shard 原始 log 保留。

```powershell
$env:GODOT='C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
$env:LOG_DIR='D:/NestEggVerification/ne79-cloud-f7c108f3/.godot-transfer/local-evidence/affected-suites'
& 'C:/Program Files/Git/bin/bash.exe' tools/run_tests_parallel.sh --only=CharactersSuite,RigMeshSuite,RigActionsSuite,PostureSuite,HitReactionSuite,AnimAuditSuite,LocomotionSuite,EnforcerArtDeliverySuite 4
```

新套件確實執行（[shard_1.log](shard_1.log)）；四 shard checks 為 479、5,368、660、383。三條 ERROR 與雲端原基線相同，是 `no_such_action`、`test_missing_part/hurt_parts` 和缺失特效的既有負控制，無 SCRIPT ERROR／FAIL。root 首次命令用錯縮短類名，得到零 checks；[該次失敗嘗試](rejected-zero-checks.log)保留且不算通過。最後 rebase 到 `0b6f8253` 只新增 NE-90 的 Python 製作工具與文件，runtime／本套件輸入沒有變更。

root 另外以現有 `tools/rig_preview.tscn` 拍攝原生 Forward+、RTX 4070 SUPER、1280×720 的 [八姿勢診斷](../../../images/NE-79-cloud-local-eight-poses.png)與 [七階裝甲預覽](../../../images/NE-79-cloud-local-armour.png)，capture exit 0、無 ERROR；[八姿勢 log](eight-poses.log)、[裝甲 log](armour.log)。全部透過共享 GPU 鎖、Comfy 已停止。八姿勢只取一格且未逐格接縫驗收；倒地仍可見整體側倒的輪廓，不能接受為自然趴／仰躺。裝甲原預設 zoom=3 造成最右列裁切，該次 [PNG](rejected-clipped-armour.png)及 [log](rejected-clipped-armour.log)保留為拒收證據，最終 zoom=2 保留全列。

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . res://tools/rig_preview.tscn -- --chars=enforcer --out=<絕對 PNG 路徑>
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . res://tools/rig_preview.tscn -- --chars=enforcer --damage --zoom=2 --out=<另一絕對 PNG 路徑>
```

本機證據另列 `local/manifest-sha256.json`，不改寫雲端 raw manifest。這次將 CPU 回歸註冊交付，仍不接受全部八動作外觀、操作手感或整票完成。
