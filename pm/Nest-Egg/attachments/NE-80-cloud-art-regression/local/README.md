# 主 Session 本機接收與局部驗收

雲端因缺 GitHub push 身份保留 `25218ce6276dca9c2b94d6bd18ce0f4592c3b047`，沒有宣稱合併。root 接收 15 個獨立命令的 base64 段，核對 170,836 字元、gzip 128,126 bytes SHA-256 `0553b2a45c7c724b308eb6289f966c5ba92b967a290ec2d1e8afa83f7fdb84f1`；解出完整 patch 360,646 bytes SHA-256 `21ee70e18faab7a236e9f96a4c8e5750ad01ea95ae8b98d1f5ef8139826314ed`。

獨立 root 驗收 checkout `D:/NestEggVerification/ne79-cloud-f7c108f3`，本次 NE-80 分支從最新 `79e0fa53e3c0b1fbe210c21cc189f4e900117508` 起。三方套用保留 NE-79 與 NE-80 兩個 suite 註冊，審讀新增套件與所有證據。原雲端 manifest 的 52 個檔案逐 bytes 核對不變，全部 JSON 可解析；root 證據另放本目錄，不改寫雲端 log。

## 本機局部測試

官方 Godot `4.7.2.stable.official.ed1daf0bf`，GPU 鎖下匯入完成。Headless 的 12 個局部正式套件包含雲端原 11 個及 NE-79 新登記套件，**35,396 checks、0 新／known failures、exit 0，65 秒**。全部 suite 均有實際 SUITE_TIME，新重裝套件重現 `NE80_COMBAT closed=1 vent=3 final_hp=12 shots=13`。

```powershell
$env:GODOT='C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
$env:LOG_DIR='D:/NestEggVerification/ne79-cloud-f7c108f3/.godot-transfer/local-evidence/NE80-suites'
& 'C:/Program Files/Git/bin/bash.exe' tools/run_tests_parallel.sh --only=HeavyGunnerArtDeliverySuite,HeavyEnemiesSuite,CharactersSuite,RigMeshSuite,PoseMeshSuite,AnimAuditSuite,RigActionsSuite,HitReactionSuite,ProtagonistMotionSuite,DeathReactionSuite,LocomotionSuite,EnforcerArtDeliverySuite 4
```

[完整本機结果](affected-tests.log)、四份 `shard_*.log` 均保留。三條 ERROR 與原雲端基線相同：`no_such_action` 與 `test_missing_part` 的兩個錯誤資料負控，沒有 SCRIPT ERROR／FAIL。這次没有跑完整測試，也不修改 known_failures。

## 原生診斷

root 以現有 `tools/rig_preview.tscn` 拍攝 Forward+、RTX 4070 SUPER、1280×720 的八姿勢與七階裝甲預覽。共享鎖、Comfy 已停止，兩次 exit 0、無 ERROR。這些是單格診斷，不能據此勾選逐格接縫、完整人體、光照或操作手感。

初版仰射槍管超出畫面、裝甲最右列槍管遭裁切，原 PNG 與 log 以 `rejected-clipped-*` 保留。正式重拍八姿勢 zoom=1.5、裝甲 zoom=1.2，root 查看全頭／手／腳／槍管均在畫面內。較小展示倍率只為完整診斷布局，不表示來源貼圖被縮小或新人體已驗收。倒下仍不能作自然趴／仰躺通過證據。

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . res://tools/rig_preview.tscn -- --chars=heavy_gunner --zoom=1.5 --out=<絕對 PNG 路徑>
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . res://tools/rig_preview.tscn -- --chars=heavy_gunner --damage --zoom=1.2 --out=<另一絕對 PNG 路徑>
```

![本機八姿勢診斷](../../../images/NE-80-cloud-local-eight-poses.png)

![本機裝甲可見性診斷](../../../images/NE-80-cloud-local-armour.png)

本票維持進行中，全部原生接點、操作與整合仍按 NE-224 原门檻驗收。
