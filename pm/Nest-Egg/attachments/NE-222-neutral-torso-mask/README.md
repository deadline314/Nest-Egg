# NE-222：中性軀幹遮罩試作，未採用

本段保存單次 seed22316 試作及原生比較，**不是步行修復交付，也不是新的定稿**。原 s33、正式軀幹、外套、骨架與動作資料均未替換。試作因青色袖窿／腰部包邊缺失、描邊被硬遮罩截斷、腹部材質與現有腰部不連續而拒收；保留舊外套亦不足以改成自然穿著的行走輪廓。後續必須一起處理相連衣物，而不是換一張軀幹後宣布通過。

## 實際生成與透明資料

[來源目錄](../../../../art_src/characters/rin_walk_torso_22316/)保存 prompt、seed、request／executed graph、RAW／FINAL PNG、建構圖與遮罩。864×1408 是第一張參考圖的實際尺寸，resolution=0；模型、VAE、25步 Euler、CFG1、停用cache皆以執行圖為準。原 s33 SHA為401888dc14dcca469428e4df45c07648e36fd1822497031f8c28213fafc24fd9；正式軀幹SHA為9cb49daa7a166a2f7ed31e44f3995c8e5192446294f5c41d0aa67a40263e3d4f。

本實驗使用已安裝的 VAEEncodeForInpaint 對二值遮罩內採樣，再由 ImageCompositeMasked 合成。白色是編輯區，黑色是原四通道保護區；LoadImage→JoinImageWithAlpha 確實接回 RGBA。保存PNG的執行圖記錄三個實際載入檔的SHA，與提交图核對；Comfy加入的 is_changed 為來源SHA紀錄，不假稱執行圖與 request 原文字完全相同。

RAW具有帶色半透明背景雜點，不能稱為乾淨原生透明角色。FINAL的遮罩外四通道與透明建構底圖逐像素一致，但這是**合成保護**，不能當作模型自行產生乾淨alpha、正確衣物、單部件歸屬或人體通過。硬輪廓也切傷了描線。本機當前Comfy沒有Qwen2.1 Fun控制節點或checkpoint，這次沒有ControlNet／深度／骨點控制。

生成模型實際完成後，首次紀錄檢查因未排除Comfy新增的is_changed欄位而失敗；修正檢查後只讀既有輸出，沒有為了檢查重跑模型。`generate.py` 是後續可重跑版本，原始實際工作流以PNG與executed.graph為準，不把後改腳本說成生成時逐位元組相同的腳本。

## 原生比較的範圍

- Godot4.7.2／RTX4070SUPER／Vulkan1.4／Forward+／HDR2D，共享GPU鎖；Comfy已停止後才執行。兩個程序各exit0，無SCRIPT ERROR。
- 70與21.56兩種速度；每次8個角色：原版／候選、兩面向、1×／3.4×。各取1、1.25、1.5、1.75、2秒附近五張原始1600×1000 PNG，共10張，未再縮放。實際取樣時間在各report。
- 候選只替換既有軀幹RigPartMesh的diffuse／normal／glow及對應密度、支點，沒有新增可見軀幹或修改骨頭。同速原版與候選的rest與各骨transform逐格相同；所有角色bounds在畫布內。
- 原native診斷先誤將軀幹當Sprite2D，該次失敗已排除。公開紀錄只對應修正後v2，`inputs.json`已核對實際執行的capture SHA，沒有沿用v1的舊hash。
- 執行用eb7ac9d5隔離runtime；與27770470的game/core/autoload/art/data/scenes/ui無tracked差異，六個直接輸入另做CRLF→LF內容核對，保留runtime原始bytes的SHA。沒有假稱歷史checkout名稱就是最新main或原始bytes完全相同。
- 候選保持原圖密度：864×1408、pivot[252,1256]、texture_scale0.0105125；新source=舊crop局部座標×4+32。零誤差僅證明提議的坐標映射，**不是肩／頸／腰人體定位已校準**。此候選沒有受損配對。
- 全角色在此視窗仍較小；這些圖只作換件與輪廓診斷，不能通過接縫、人體、正常遊戲或過場演出。沒有逐格全接點量測、效能量測或操作手感驗收。

## 重跑

先設定實際COMFYUI_DIR，使用既有Python依賴：

```powershell
$env:COMFYUI_DIR='D:/ComfyUI'
& 'D:/ComfyUI/.venv/Scripts/python.exe' pm/Nest-Egg/attachments/NE-222-neutral-torso-mask/verify.py
& 'D:/ComfyUI/.venv/Scripts/python.exe' art_src/characters/rin_walk_torso_22316/generate.py --inspect-only
```

verify只核對36個來源／工作流／紀錄／PNG的SHA、來源四通道保護與10張原始擷取尺寸，並拒絕單像素alpha污染、錯誤尺寸、非二值遮罩三種負例。**它通過不會把拒收候選改成合格素材**。正式來源hash在參考輸入核對；本次只有隔離素材、文件及證據，受影響Godot測試應為零，另記實際selector結果。

原生日誌保留實際CRLF換行並由本目錄Git attributes停用文字正規化；交付另外核對index內36個實際Git blob的SHA，防止先加入index的日誌仍存成LF。相同檢查也須在同步後的另一checkout執行，不能只檢查工作目錄。

需要重做原生診斷時，先準備本次基準的獨立runtime checkout並完成匯入；不能用根目錄或包含既有診斷輸出的路徑。prepare_native只寫入該隔離checkout的`.godot/ne222-walk-torso-22316-native/`，由既有工具重建normal／glow，不觸碰角色正式資源：

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' pm/Nest-Egg/attachments/NE-222-neutral-torso-mask/prepare_native.py D:/NestEggVerification/NEW_ISOLATED_RUNTIME
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path D:/NestEggVerification/NEW_ISOLATED_RUNTIME --resolution 1600x1000 --quit-after 900 res://.godot/ne222-walk-torso-22316-native/capture.tscn -- --speed=70 --out=D:/NestEggVerification/NEW_CAPTURE/game-speed/report.json
```

另一輪速度改21.56並用另一個新輸出目錄。再次生成僅在新獨立來源目錄、另定seed／來源紀錄的受影響步驟進行，不能刪掉本段原圖來強迫重跑，亦不能直接把此診斷貼圖登記為正式pose_parts。

## 參照

Spine官方[attachments](https://us.esotericsoftware.com/spine-attachments)提供同slot的部件切換方式；這支持另備行走部件、保留原版的方案，但不替素材品質背書。[Comfy官方Qwen2.1節點](https://docs.comfy.org/built-in-nodes/TextEncodeQwenImage21)的參考編碼與獨立的Union控制分支不同；[上游PR16519](https://github.com/Comfy-Org/ComfyUI/pull/16519)及[模型作者說明](https://huggingface.co/alibaba-pai/Qwen-Image-2.1-Fun-Controlnet-Union/blob/main/README.md)均另需相容實作及控制權重。這些是流程依據，本次沒有安裝或驗證該控制分支。
