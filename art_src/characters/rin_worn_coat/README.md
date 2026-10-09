# NE-222：穿著的短外套來源

保留凜已批准的 s33（832×1216；hash 見 manifest），只替換外套與衣袖。這是已存在的局部編輯快取，沒有重新生成整個人。原始 Qwen 輸出、工作流、job、seed 22261、對位資料、SAM 遮罩與精修來源保留在 source；原始編輯結果的其他人物像素不進遊戲。

固定肩领由 armor_jacket 綁胸骨，連續衣袖綁上臂／前臂且袖根跟胸骨接合。衣襬保留 15 原圖像素重疊，使用既有 RigPartMesh 的 root_attach 與 bend_partner，沿 coat_1／coat_2 小幅擺動。其他身體骨長與 weapon anchor 不變；coat_1／coat_2 的來源位置和彈簧參數由 rin_side.json 重現。外套、袖子與衣襬仍屬同一個衣物損傷階段。

在專案根目錄，用實際 Python 執行：

```powershell
python art_src/characters/rin_worn_coat/rebuild.py
python tools/comfyui/check_spec.py --recipe tools/comfyui/recipes/rin.json --joints
python tools/comfyui/build_character.py --recipe tools/comfyui/recipes/rin.json --from textures --to import
```

rebuild 先驗證所有來源、批准原圖及三張輸出 hash，再寫入 rin2 的來源覆蓋層；cut_layers 使用 overrides/refined 作為優先來源。不依賴失效的旧披肩部件名稱，也不必重跑 design／SAM／補全。繼續完整精修時，來源覆蓋層仍優先於一般精修輸出。

3840 個衣襬接點樣本（八狀態、左右面向、1×／3.4×、120 格）沒有孔洞或斷開。完整原生 alpha 影格保存在 NE-222-worn-coat-hem-audit.zip，可解開後用 check_joint_frames.py 重驗。這個結果只涵蓋衣襬接點；肩袖、手腕與人物全彩輪廓仍須分別驗證，不能以此宣稱全部件通過。原生對照與 CPU 量測在 NE-222 本次 Commit 記錄中。
