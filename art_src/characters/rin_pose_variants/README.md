# 凜蹲／跪姿素材小樣

NE-222，2026-10-09。已批准的s33原圖與正式角色素材未覆寫。
這裡是新姿勢的來源、12件可見部件與組合工具；**不是已通過的遊戲動畫**。

## 來源與可重跑步驟

- `source.json`：原底層、批准原圖的SHA-256，參考裁切範圍。
- `manifest.json`：Qwen模型、提示詞、種子、尺寸、參考圖、原始輸出雜湊與候選狀態。每張原始PNG另外內嵌完整ComfyUI graph。
- `crouch_layout.png`／`kneel_layout.png`：姿勢草圖；只作生成參考，不算解剖或骨架通過。
- `01_candidates/`：4401／4402未達到姿勢，拒收；4403／4404為姿勢候選。原始圖與job快取保留。
- `02_masks/`：SAM普通蹲姿遮罩及原始graph。它誤切鞋跟，沒有拿來當最終透明材質；切圖改用既有的邊框連通背景分割。
- `04_refinement/`：4405只修跪姿衣料；依`poses.json`目標區域取用RGB，輪廓alpha及區域外像素仍取4404。不是新的整張定稿。
- `poses.json`：人工分割範圍、source-space支點、腰部對齊依據、清除鞋帶小片的範圍及檢視用調整。
- `03_parts/`：未縮圖、未轉正的RGBA部件、遮罩、歸屬圖、支點、bbox及雜湊。普通蹲5件；跪姿7件。

從repo根目錄執行：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/rin_pose_parts.py
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/test_rin_pose_parts.py
```

兩個命令均為離線CPU步驟，不啟動模型。生成重跑沿用`comfy_api.qwen`、原始graph與manifest；輸出另存新的候選目錄，不覆蓋這些歷史原圖。採用何種候選由來源／實機檢查決定，seed不代表批准。

GPU預覽先確認沒有生成工作，必要時由Session 1透過既有啟停腳本停止ComfyUI，再使用共享鎖：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1920x1080 --rendering-method forward_plus res://tools/rin_pose_candidate.tscn -- --facing=1 --out=C:/absolute/right.png
```

換`--facing=-1`看另一面向；`--zoom=1`看較小的顯示尺度。預覽使用現有頭、上半身、手、武器與材質，加上候選的獨立Skeleton2D／Bone2D鏈。只供姿勢外觀與來源對照，沒有改玩家控制或動畫器。

## 檢查界線

離線檢查已涵蓋：12件都有實際像素，沒有游離連通片，所有source alpha像素被認領；裁切尺寸／支點還原、區域外像素保留、重跑位元組一致，以及無效分割不覆寫前次輸出。這些不是接點逐格或人體外觀驗收。

**普通蹲的遠腿與後鞋只見部分，隱藏底層尚未完整。** source-space骨長也未與正式共用骨架一致；預覽會列出差值，不能用這組候選骨長直接取代正式值。檢視用後鞋旋轉／位移只表示美術接地提案，不算腳踝綁定或不變骨長通過。

腰部使用正式上衣實際alpha跨度對齊，不能把候選圖中心當成腰支點。仍須驗證腰部、髖、膝、踝的全部接邊、遮擋底層、近遠側／圖層、服裝花紋、normal／glow及原生Forward+。未製作站→蹲→站或站→跪→射擊→站，不宣稱動畫／手感已改善。候選不得由正式角色配方自動採用。
