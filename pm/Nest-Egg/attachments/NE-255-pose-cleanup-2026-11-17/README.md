# NE-255：姿勢模型乾淨退出

全新角色流程在 SAM3D 已輸出70點後仍出現 ModelPatcher.__del__ 的 ON_DETACH traceback，退出碼卻為0。局部模型仍留在 ComfyUI 的生命週期，晚於回呼模組清除才解除。工具現在在成功、無人物及推論例外出口使用原卸載 API，釋放本程序參照並回收循環；沒有修改或重啟共用8188服務，也沒有忽略錯誤。

| 檢查 | 原版 | 修後 |
|---|---|---|
| CPU生命週期（成功、無人物、推論例外） | 3項／3失敗 | 3項／0失敗 |
| 9070 XT 真 SAM3D | 70點，exit0但有退出traceback | 70點，exit0，無traceback |
| 同來源點位與overlay | 相同70點 | JSON及PNG原始位元組完全相同 |

CPU回歸已加入既有美術CI。原始失敗、成功、輸入、兩份工具及輸出均保留，verification.json逐檔記錄SHA-256。這是模型生命週期驗證，不是新角色全動作或接點驗收；NE-255的新讀者成品條件仍須依實際結果判斷。

```powershell
python tools/comfyui/test_pose_keypoints.py
& 'D:/ComfyUI/.venv-rocm/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'D:/ComfyUI/.venv-rocm/Scripts/python.exe' tools/comfyui/pose_keypoints.py --image pm/Nest-Egg/attachments/NE-255-pose-cleanup-2026-11-17/input.png --out <新輸出.json> --overlay <新輸出.png>
```

使用同一來源，不覆寫既有人工校準點位。此次兩輪不加手部精修，保留原預設推論。原始網路線索僅作調查：[ComfyUI官方問題中的相同退出診斷](https://github.com/Comfy-Org/ComfyUI/issues/17370)；真正根因判斷依本機程式、可重現退出與釋放後的同輸出對照，不把其他推論競態當成此問題。


獨立審查另移除清參照及循環回收作負控制，最初替身沒有循環、只驗到卸載；測試已補真正循環與例外出口的本地參照檢查。最終原版3／3失敗、移除釋放的控制3／3失敗、正式版3／0；保留所有原測試與兩個負控制日誌。原受影響挑選在精準隔離候選執行，無遊戲套件需要跑，原始輸出為selected-tests.log。目錄附件原樣保存，不經Git換行轉換。
