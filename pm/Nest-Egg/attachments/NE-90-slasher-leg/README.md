# 切割者大腿部件歸屬修復

大腿補全圖仍帶著遠側手的黑色輪廓，擺腿時會一起移動。使用目前補全階段的 SAM 遮罩移除該手輪廓；不套用原始立繪的近側手遮罩，後者會在重新繪製過的大腿內部挖洞。完整褲腿遮罩也因截斷其他部位而拒收。

來源、點選座標、模型、工作流與 SHA 記錄於 `art_src/characters/slasher/near_hand_repair/far-hand-mask-source.json`。實際套用來源為 `07_refined/leg_upper.png`，遮罩有 4,029 像素，其中 2,243 個來源非零 alpha 像素改成透明；遮罩外 RGBA 與遮罩內 RGB 均保持原像素。

從專案根目錄重跑既有配方，僅重建受影響步驟：

```powershell
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/slasher.json --from textures --to import
D:/ComfyUI/.venv/Scripts/python.exe pm/Nest-Egg/attachments/NE-90-slasher-repair/reproduce.py
D:/ComfyUI/.venv/Scripts/python.exe pm/Nest-Egg/attachments/NE-90-slasher-leg/replay.py
```

第二條指令在私有目錄重建兩次，核對十二張 diffuse、角色資料及骨架，沒有 GPU 或生成作業。舊手／靴覆蓋保持一致。正式切圖會按剩餘材質重新計算畫布寬度 142→119，高度 251、支點与骨架保持不變；不使用私有試作的固定 142 寬裁切。

第三條指令另在隔離目錄故意變更來源一個像素、損壞遮罩雜湊；兩者均在覆寫既有輸出前拒絕。結果為 `ownership-replay.json`，新重跑資料留在 `.godot/ne90-slasher-leg-replay/`。

## 原生證據與判定範圍

`capture.tscn -- --tag=before|after` 使用**當下 checkout**，tag 只是輸出標籤，不能切換版本。before 為 33519c09，after 為其上本次分件修復。兩次均在無 ComfyUI 生成的共享 GPU 鎖內執行，Godot 4.7.2、Forward+、HDR 2D、RTX 4070 SUPER。每次九狀態、兩面向、四個截點，共 72 張 1536×1400 PNG；全部雜湊與 2,160 格手腕有限值 trace 見 `capture-manifest.json` 及圖片資料夾。

原生跑姿對照可確認多餘手輪廓消失與單靴維持。蹲姿截點仍有腳底朝向／接地問題，不是完整姿勢通過。數值 trace 只記錄手腕，不包含全部接點像素稽核；72 張截點不能代替逐格解剖、戰鬥和全部護甲脫落檢查。整票維持進行中。

`affected-tests.log` 固定比較 33519c09，3,363 checks、0 新／已知失敗。選集中的 EnemyArtDeliverySuite 未註冊，沒有把它算成已執行套件。`replay.json` 是本次重跑資料；原 Commit-8 的歷史附件不覆寫。

CI 37985787117 曾出現 standard 頭目 40 秒未進入 dash_recover。兩次局部 ReclaimerSuite 重跑無法重現；最新 main 33519c09 的完整 CI 37987194995 通過，未修改頭目行為或 known_failures，也不宣稱已找到偶發失敗原因。
