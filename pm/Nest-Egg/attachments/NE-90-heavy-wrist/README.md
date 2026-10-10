# NE-90 重裝機槍手前臂分件修復

正式前臂恢復原圖袖口，並接回既有上臂的受限肘部底層。只更新單一前臂 diffuse、normal 及尺寸／支點；上臂、手、骨架、其他部件保持原資料。配方已登記來源重建，不重跑生成或整體切圖。

## 來源重跑

在 repository 根目錄執行：

~~~powershell
$env:PYTHONUTF8 = '1'
& 'D:/ComfyUI/.venv/Scripts/python.exe' 'pm/Nest-Egg/attachments/NE-90-heavy-wrist/verify.py'
~~~

公開 verifier 建立兩份臨時來源副本，以四份釘選原始 RGBA 及排他 owner masks 重建 22,108 個可見像素。兩次輸出一致，diffuse／normal 位元組及像素與正式素材相同，162×230、pivot [64.15,21.87] 與正式資料一致。五項來源損毀、遺漏／多餘 owner、1px 孔洞及遮罩損毀負控制通過；驗證不寫正式素材。完整紀錄見 [verify.log](verify.log) 及來源 [owner-manifest](../../../../art_src/characters/heavy_gunner/wrist_repair/owner-manifest.json)。

## 正式原生結果

Godot 4.7.2、Forward+、RTX 4070 SUPER；ComfyUI 停止，GPU 工作透過共用鎖序列執行。八動作、兩面向、1.0／3.4 倍率、每動作 120 格，共 1,920 張 3584×128 原生 PNG、53,760 接點樣本；每格所有 28 個 cell 均有非空材質。十四接點失敗由 9,694 降至 827，消除 8,867 個失敗；逐筆角色／接點／動作／倍率／面向／影格比對新增失敗為 0。沒有提高透明度或缺陷面積門檻。

仍拒收：頸 392、手腕 24、前肘 333、膝 54、肩 24。七個非死亡動作的手腕 6,720 樣本為 0 失敗；抬槍前肘、死亡及其他接點未通過，不能推定整票或實際戰鬥驗收完成。較早的四接點候選為 356／15,360，本次以正式全十四接點 827／53,760 為準。

完整失敗帳本見 [report.json.gz](report.json.gz)，逐格條件見 [frames.json](frames.json)，原生 PNG 雜湊見 [nativeframe-manifest.json](nativeframe-manifest.json)，比較見 [verification-native.json](verification-native.json)。完整 1,920 張 PNG 保留在本 Session `.godot/ne90-wrist-native/frames-heavy-formal-all14/`；公開封包附兩張未縮放原生接點圖及六張修前／修後全身截點。全身相同 1536×1400 視窗、光照、倍率 14，避免抬槍被裁掉；每輪模擬 1,920 格、擷取 64 張，不能代替全部接縫與實際戰鬥。

~~~powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://tools/rig_joint_audit.tscn -- --chars=heavy_gunner --out='<absolute-directory>'
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/check_joint_frames.py '<absolute-directory>'
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://pm/Nest-Egg/attachments/NE-90-heavy-wrist/whole-character.tscn -- --out='<absolute-whole-directory>'
~~~

checker 預期退出 1，表示保留未修缺陷，不是工具執行成功便視為素材通過。

## 局部測試

固定基準 `62c6cb30fb5e7e5ad8a12774625ba624b08377de`，在專用 detached worktree 只套用本票四份正式檔後，實際執行 `tools/run_tests_changed.sh`，避免其他未交付候選擴大測試範圍。LayerOrderSuite、NpcAnimationSuite、RigActionsSuite、RigMeshSuite 實際執行，共 2,942 checks，0 新／已知失敗，11 秒，無 SCRIPT ERROR。四份 shard、選擇器／runner 與首次匯入紀錄保留於 [affected-tests](affected-tests/)；退出資源與預期負控制訊息原樣保留。

完整測試交由 CI；基準 main 的 run 38008971510 因 GitHub 帳務／額度限制未啟動 job，未假稱通過，未修改已知失敗清單。

合併最新 main `a52e57ea47e775f9aefc229eca8f712dc8a0183e` 的廣播變更後，四個本票套件再跑 2,942 checks／0 failures；新增廣播退出回歸 DeathReactionSuite 154 checks／0 failures、36 秒，均無 SCRIPT ERROR。誤用未註冊 `DeathReactionsSuite` 的空集合命令不計通過；原錯誤紀錄保留私有測試目錄，公開只列實際執行套件。
