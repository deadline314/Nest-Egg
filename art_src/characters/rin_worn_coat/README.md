# NE-222：穿著的短外套來源

保留凜已批准的 s33（832×1216；hash 見 manifest），只替換外套與衣袖。這是已存在的局部編輯快取，沒有重新生成整個人。原始 Qwen 輸出、工作流、job、seed 22261、對位資料、SAM 遮罩與精修來源保留在 source；原始編輯結果的其他人物像素不進遊戲。

固定肩領由 armor_jacket 綁胸骨；袖子按各自的上臂、前臂來源軸切成兩段，肘部保留source rows385–420的35像素重疊，袖根跟胸骨接合。SAM漏掉的深藍描邊只從原J圖的一像素邊界恢復，保留原RGB及alpha；色彩與來源條件、實際533個來源像素及輸出hash記錄於manifest。不得用任意擴張顏色填縫。

衣襬保留15原圖像素重疊，使用既有RigPartMesh的root_attach與bend_partner，沿coat_1／coat_2小幅擺動。武器材質掛點不變；手腕的另一次來源校準詳見rin_hands。coat_1／coat_2的位置和彈簧參數由rin_side.json重現。外套、袖子與衣襬仍屬同一個衣物損傷階段。

在專案根目錄，用實際 Python 執行：

```powershell
python art_src/characters/rin_worn_coat/rebuild.py
python tools/comfyui/check_spec.py --recipe tools/comfyui/recipes/rin.json --joints
python tools/comfyui/build_character.py --recipe tools/comfyui/recipes/rin.json --from textures --to import
```

rebuild先驗證所有來源、批准原圖及四張輸出hash，再寫入rin2的來源覆蓋層；配方source_rebuilds於textures前自動重建。舊單張袖子只在hash符合登記值時移除；其他來源不動。cut_layers使用overrides/refined作為優先來源。不必重跑design／SAM／補全。繼續完整精修時，來源覆蓋層仍優先於一般精修輸出。

Commit-17的3840個衣襬樣本（八狀態、左右面向、1×／3.4×、120格）沒有孔洞或斷開；它是該次版本的歷史證據，完整原生alpha影格在NE-222-worn-coat-hem-audit.zip，可用check_joint_frames.py重驗。肩袖、手腕、肘和人物全彩輪廓須按最新版本分別重驗，不能以舊衣襬結果宣稱全部件通過。原生對照與CPU量測在NE-222的Commit記錄中。
