# 角色製作流程：從一張透明背景的側面圖到 Godot

固定操作流程見 [character-art-pipeline Skill](../../.agents/skills/character-art-pipeline/SKILL.md)，全部件接合、動畫與實機驗收見 [rig-animation](../../.agents/skills/rig-animation/SKILL.md) 及其詳細驗收文件。本文的歷史尺寸、10px 重疊與披肩式外套記錄描述舊成果，不代表目前合格標準；接點連一個像素的缺口都不能給過。

貼圖密度由 spec 的 `tex_px_per_wp / illustration_px_per_wp` 決定，不固定縮成 4 倍或 8 倍。高解析定稿須保留有效來源細節，重算尺寸、pivot、texture_scale、normal、glow 後核對實際載入尺寸；背包子視窗也須按螢幕實際像素渲染。只改 metadata 或放大既有小圖不會增加細節。

局部握持手採不同來源密度時，spec 的 `native_grips` 記錄來源 PNG／SHA、原生尺寸、wrist pivot 及 `texture_scale`；其重建腳本登記到 recipe `source_rebuilds`。切件步驟先驗證來源再保留 PNG 位元組，不縮回舊部件尺寸；原來 grasp、骨架與掛點不變。遊戲只在握持切換時使用該貼圖密度，收槍、持盾、動作與死亡會還原休息手的貼圖、pivot、scale 與 offset。來源 alpha、零件所有權、CPU 重建、接縫及實際 Forward+ 載入分開驗收；不以擷取器手動改 sprite 代替正式載入。

> 來源：2026-10-03 使用者要求把「產出角色原圖 → 拆零件 → 放進 Godot」整條流程寫成腳本，並說明每一步的輸入輸出、零件放在哪裡、日後怎麼替換。凜（NE-17）是第一個依此流程製作的角色。

## 0. 一句話

Qwen Image 2.1 直接畫出**透明背景的側面全身圖** → SAM 3.1 用文字提示分出各部位 → 被擋住的部位請 Qwen 補全（只取缺口）→ 依關節切成零件 → 輸出零件圖、骨架與角色定義 → Godot 匯入。

```
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py            # 全部（已存在的 Qwen 圖不會重畫）
... --from parts --to preview                                                   # 只跑一段
... --only design --seed 34                                                     # 換一個種子畫新造型，再 --from pose
... --list                                                                      # 印出步驟與輸入輸出
```

設定檔：`tools/comfyui/recipes/<角色>.json`（造型提示詞、種子、工作資料夾）與 `tools/comfyui/specs/<角色>_side.json`（分群、關節、零件掛載）。工作資料夾 `art_src/characters/<名稱>/`（有 `.gdignore`，Godot 不會匯入；中間產物都在這裡，可以直接打開看）。

## 1. 需要的東西

| 項目 | 位置 | 備註 |
|---|---|---|
| ComfyUI（CUDA） | `D:\ComfyUI` | 腳本會在沒啟動時自己啟動。環境變數 `COMFYUI_DIR` 可改位置 |
| Qwen Image 2.1 Uncensored（int8） | `models/diffusion_models`、`text_encoders`、`vae` | 見 `ART_PIPELINE.md` |
| SAM 3.1 | `models/checkpoints/sam3.1_multiplex_fp16.safetensors` | [Comfy-Org/sam3.1](https://huggingface.co/Comfy-Org/sam3.1)，1.75GB |
| SAM 3D Body | `models/detection/sam_3d_body_dinov3_bf16.safetensors` | [Comfy-Org/sam-3d-body](https://huggingface.co/Comfy-Org/sam-3d-body)，2.83GB，只用來預測關節當參考 |
| Godot | 環境變數 `GODOT` | 預設 `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` |

## 2. 步驟、輸入、輸出

`work` ＝ 配方裡的 `work`（凜是 `art_src/characters/rin2/`）。

| # | 步驟 | 工具 | 輸入 | 輸出 |
|---|---|---|---|---|
| 1 | `design` | Qwen Image 2.1，文生圖，原生 RGBA | 配方的 `design.prompt` | `work/01_design/design_s<種子>.png`、**`work/base_rgba.png`**（透明背景側面全身圖，832×1216） |
| 2 | `pose` | SAM 3D Body | `base_rgba.png`（墊灰底） | `work/keypoints.json`、`work/02_pose/overlay.png`。肩、肘、腕、髖、膝、踝的預測位置，用來填 spec 的 `joints` |
| 3 | `parts` | SAM 3.1 ＋ Qwen 編輯 | `base_rgba.png`、spec 的 `groups` `stages` `parts` | `work/sam/`（遮罩）、`work/04_stages/A.png`（剝層圖）、`work/05_groups/<群組>*.png`、**`work/06_parts/<零件>.png`**（每個零件一張，座標與原圖相同）、`06_parts/ownership.png`（檢查用） |
| 3b | `refine` | `refine_parts.py` | `06_parts/*.png`、spec 的 `refine` | **`work/07_refined/<零件>.png`**（同座標）。移除遠側腿與靴（Qwen 畫成一整條藍綠剪影）、把 Qwen 補全時畫在大腿上的口袋線抹平、半透明邊緣的白色光暈改成內側顏色、游離碎屑與零星白點／洋紅點、輪廓階梯鋸齒；另有 `erase` 多邊形可手動清掉特定碎片 |
| 3c | `damage` | `make_damage.py` | `04_stages/D.png`、`07_refined/<零件>.png`、spec 的 `damage` 與 `damage_of` 零件 | **`work/07_refined/<零件>_dmg.png`**：撕裂衣物底層，輪廓用完整零件的、顏色取自 D 圖 |
| 4 | `textures` | `cut_layers.py` | `07_refined/*.png`（沒有就用 `06_parts/`）、spec 的 `joints` `bones` `parts` | **`art/characters/<id>/parts/<零件>.png`**（＋`_glow.png`）、`art/characters/<id>/character.json`、`art/rigs/humanoid_tall.json` |
| 5 | `normals` | Godot `tools/art/paint_normals.tscn` | `parts/*.png` | `parts/*_n.png`（法線貼圖，打光用） |
| 6 | `import` | Godot `--headless --editor --quit` | `art/characters/<id>/` | `.godot/imported`。**必須在 normals 之後**，否則新的法線貼圖不會被匯入 |
| 7 | `preview` | Godot `tools/rig_preview.tscn` | 角色 | `work/08_preview/{poses,closeup,head,damage}.png` |

每一步結束，腳本把輸出清單寫進 `work/manifest.json`。

**透明來源核對**：本 repo 的 `build_character.py` 已在既有 Qwen 提示詞前後加上 RGBA／透明背景說明，`comfy_api.py` 也已接 Qwen Image 2.1 VAE；不用重複加提示詞。官方工作流說明 VAE 支援四通道 alpha，可直接生成透明背景圖（[Comfy-Org：Qwen Image 2.1](https://github.com/Comfy-Org/docs/blob/main/tutorials/image/qwen/qwen-image-2-1.mdx)）。提示詞與工作流只說明預期，交付仍須檢查實際 PNG：分開記錄 RGBA 模式、alpha 分布與人物 bbox，並把原圖以最近鄰原尺寸分別合成黑、灰、白底檢視，也要在實際 Forward+ 場景檢查最終貼圖。alpha=0 的 RGB 值不表示有可見雜點；alpha=1 的洋紅點及帶色半透明邊緣則要看合成後是否形成彩邊，不可只看棋盤格或 `RGBA` 字樣判定透明品質。來源 alpha、SAM 遮罩所有權、最終貼圖外觀及動畫接合是不同檢查；任一項通過都不代替其他項。沿用 `refine.speckle: 30`（`components` 最小連通像素數）與 `alpha_floor: 40` 等既有設定做指定零件清理，不把它們當成容許碎片／孔洞的新驗收門檻；一像素裂縫仍失敗。

**參考圖的透明通道與編輯尺寸（2026-10-10）**：`LoadImage` 把 RGB 和反向 alpha 分成兩個輸出，不能只將 RGB 接到 `TextEncodeQwenImage21`。現有 API 在每個參考槽以 `JoinImageWithAlpha` 合回 RGBA，再交給 Qwen：文字編碼器按 alpha 合成白底，VAE 保留四通道。參考編輯快取已區分這個工作流版本，舊 RGB-only 編輯結果不視為新圖命中；文生圖快取不變，既有定稿不自動重跑或覆寫。真節點 Load→Join→Save 的合成測試保留透明／不透明範圍與 RGB，但浮點合併再存 uint8 可令部分 alpha 相差 1，不能宣稱全部 RGBA byte-exact；精確保留的來源必須另走原圖／遮罩契約，不由模型或 PNG 回存替代。這個輸入修正不保證生成後 alpha、輪廓或解剖合格。

編輯時 `w`／`h` 不決定畫布：取樣 latent 來自第一張參考圖。`resolution>0` 按約 resolution² 面積與長寬比縮放，再取 32 的倍數；`resolution=0` 保留第一張參考的尺寸並取 32 的倍數。例如 864×1408 在 1024 參考解析度得到 800×1312，必須記錄實際輸出，不以 requested_canvas 當來源尺寸。需要局部像素鎖定時先定義原尺寸編輯遮罩，使用實際已存在、相容的 mask／合成節點並逐像素驗證外部 RGBA；Qwen 編碼器本身沒有硬遮罩、depth 或 keypoint 輸入，文字「只改這裡」及參考草圖不能作硬約束證據。[官方節點契約](https://docs.comfy.org/built-in-nodes/TextEncodeQwenImage21)。

### 第 3 步細節：怎麼分、怎麼補

文字遮罩快取綁定目前 RGBA 灰底參考的 SHA-256、階段、提示、SAM 模型、threshold／refine，並核對遮罩 PNG 的 SHA-256 與原生尺寸。灰底每次由当前 RGBA 重建；未變的來源可重用，來源或遮罩改動、缺鍵或壞鍵只使受影響遮罩失效。生成失敗保留舊 PNG、撤銷其有效鍵並停止，不拿舊圖繼續交付；新結果全部驗證後才替換。快取可追溯不代替所有權、解剖或動畫驗收。離線重現檢查為 `python tools/comfyui/test_mask_delivery.py`。

1. **分群**（spec `groups`）：SAM 3.1 對每個文字提示（"hand"、"chrome robotic arm"、"jacket"、"ponytail"、"head"、"boot"、"thigh holster"、"torso"、"skin"、"black stockings leg"）給一張遮罩。前面的群組優先；沒被任何遮罩認領的零星像素分給最近的群組。
2. **補全**：只有**被別的東西擋住**的群組需要。
   - 手臂（肘被夾克袖子擋住）：把殘缺手臂裁出來當第一張參考圖，手臂附近的原圖當第二張，請 Qwen 補成完整一條。
   - 身體（被手臂、夾克、槍套擋住）：同上，請 Qwen 補成完整的身體與腿。
   - 夾克（被手臂擋住）：**剝層**。把整張圖交給 Qwen「移除義肢、手、槍套，並補完它們後面的東西」（階段 A），夾克的完整版 ＝ 階段 A 上 SAM 的夾克遮罩。
   - 補全結果**只取缺口**（被前面群組遮住的範圍），其餘一律用原圖的像素；階段圖取像素時只用完全不透明的部分並往內縮 3px，避免 Qwen 重畫邊緣的淡色描邊變成光暈。
   - 馬尾、頭、手、槍套、靴子不補全，零件就是原圖用 SAM 遮罩摳出的像素。
3. **切開**：義肢與身體各自在關節處切成零件（spec `parts` 的 `y`），並多留 10px 重疊，關節轉動時才不會露縫。

## 3. 零件在 Godot 的位置與掛載

全部在 `art/characters/rin/`，由 `character.json` 描述；骨架在 `art/rigs/humanoid_tall.json`（`character.json` 的 `rig` 欄指向它）。

2026-10-09：凜已改為保留来源密度23.78貼圖像素／世界像素（原圖也是23.78，k=1）。貼圖縮放0.04205，切圖、支點、normal／glow與眨眼座標同步重建；身體骨架和武器掛點資料未變。對話頭像直接由280×280來源裁切輸出256×256，與遊戲使用相同來源覆蓋層，不再略過已核對的修補。歷史20密度與固定128頭像只描述舊交付；來源、載入尺寸及原生UI畫面見NE-222。

| 零件圖 `parts/<名稱>.png` | 掛在哪根骨頭 | 圖層 z | 說明 |
|---|---|---|---|
| `hair_back_1`、`hair_back_2` | `hair_1`、`hair_2` | −9 | 馬尾上半、下半；跟著彈簧骨飄動 |
| `pelvis` | `hip` | 0 | 骨盆、臀、絲襪上緣 |
| `torso` | `chest` | 1 | 白色連身衣含頸部與裸肩 |
| `leg_upper`、`leg_lower`、`foot` | `leg_front_*`／`foot_front`（z 3）與 `leg_back_*`／`foot_back`（z −5，亮度 0.62） | | 前後腿共用同一張圖 |
| `holster` | `leg_front_upper` | 4 | **配件**：大腿槍套 |
| `torso_dmg`、`pelvis_dmg`、`thigh_dmg`／`calf_dmg`（含後腳）| 與完整零件同骨頭 | 完整零件 z−1 | **破損底層**：撕裂衣物版的身體，平時被完整零件蓋住，衣物飛走後露出來 |
| `armor_jacket` | `chest` | 4 | 穿著的短外套本體，肩領固定於胸骨；來源只取局部衣物，不替換已批准的臉與身體 |
| `jacket_sleeve_upper`、`jacket_sleeve_lower` | 前後側各自的上臂／前臂 | 9／−6 | 按各段來源軸分割，肘部保留35來源像素重疊；上段`root_attach`將袖根接至胸骨 |
| `jacket_hem` | `coat_1` | 4 | 連續衣襬，`bend_partner: coat_2` 綁定兩段彈簧鏈；`root_attach` 固定根部，與本體保留 15 原圖像素的真實布料重疊，活動量限制在短外套範圍 |
| `head` | `head` | 5 | 臉、前髮、耳環 |
| `arm_upper`、`arm_lower`、`hand` | `arm_front_*`／`hand_front` | 8～10 | 右手機械義肢；原圖金屬粉紅反光保留，不作洋紅雜點刪除 |
| `arm_left_upper`、`arm_left_lower`、`hand_left` | `arm_back_*`／`hand_back` | −7～−6 | 獨立左側人體手臂，亮度0.62；不複製右側機械手 |
| `hand_grip`、`hand_left_grip` | 上述兩個手部slot | 同原手 | 握持附件換貼圖，不增加第三個可見手；source-space掌心握點經同一切圖變換匯出，與腕支點分開 |

每張圖旁邊還有 `<名稱>_glow.png`（霓虹發光層，加法混合）與 `<名稱>_n.png`（法線）。`character.json` 的 `textures` 記錄每張圖的尺寸與**支點**（旋轉中心），`parts` 記錄掛載（骨頭、z、亮度）。

**配件（夾克、槍套）**各自掛在骨頭上。槍套綁在大腿上，跟著 `leg_front_upper` 轉；夾克下擺與頭髮用彈簧骨做次級動態。

**次級動態參數（資料，不寫在程式裡）**：骨架檔 `art/rigs/humanoid_tall.json` 的 `springs`（來源是 spec 的 `springs`，`cut_layers.py` 寫進去）。每一項：`bone` 彈簧骨；`rest` 靜止角度（夾克下擺要 0，才與原圖一致）；`gain` 跟隨移動的倍率（越大飄越遠）；`trail`／`lift`／`wind` 往前跑向後飄、上升下落、微風各自的倍率（預設 1）；`stiffness`／`damping` 彈簧硬度與阻尼（硬度高回彈快，阻尼高晃得少）；`min`／`max` 角度上下限。沒有 `springs` 的骨架（`humanoid.json`）用程式內的預設值。檢查：`rig_preview.tscn -- --chars=rin --cloth`（站、跑、上升、下落、蹲、仰射並排）。

**肢體偏移**：spec `bones` 的 `dx` 是骨頭相對關節的水平位移。圖是從同一張側面圖切出的，近側（前）手腳必須是 0，否則會和骨盆、夾克、衣服對不齊，切口沿線出現方框；遠側（後）手腳用負值讓兩條腿分得開。

**切口保留真實材質**：spec `parts`有`y`的零件，切口那一側不另留透明邊，但必須保留第一與最後已畫好的像素列；不可為了避開法線亮邊而向內裁掉來源重疊。離線回歸用逐列顏色及alpha核對。正常輪廓的描邊若被SAM漏掉，先核對原圖材質與遮罩，恢復可追溯的來源像素；不可把衣物顏色塗進皮膚、金屬或背景。

**登記局部來源**：recipe的`source_rebuilds`在textures前恢復已核對的source overrides。腳本須位於角色來源目錄，先驗證全部輸入與輸出hash再寫入；凜登記外套及獨立左右手。不必為重切或法線重跑生成、SAM和全角色補全。腕部校準以原圖接頭邊界為據，setup後骨長固定；掌心偏移用於IK與物件掛載，武器材質握點不變。

## 3b. 受傷時衣物脫落

遊戲內原有的裝甲脫落機制（`character.json` 零件的 `armor_order`，小的先掉；同一個 order 的零件算同一步；生命比例 → 還剩幾步）。凜把它用在衣物受損層上，每一步 20%，不拋出整張身體或衣物圖：

| 步 | 切換受損外觀的部位 | 底下露出來的 |
|---|---|---|
| 1 | 夾克（領口、上半、兩段下擺） | 身體 |
| 2 | 連身衣胸口（`armor_torso`） | 撕裂的胸口 |
| 3 | 連身衣下半（`armor_pelvis`） | 撕裂的腰臀 |
| 4 | 絲襪大腿（前後腳） | 撕裂的大腿 |
| 5 | 絲襪小腿（前後腳） | 撕裂的小腿 |

底層來自兩張 Qwen 編輯圖（spec `stages`）：**C** 把夾克、義肢、手、槍套整個移除並補完後面（身體完整可見），**D** 再把 C 的衣物撕裂（連身衣破洞與擦傷、絲襪大洞與脫線，仍留有碎布遮住胸口與下腹、絲襪殘片留在大腿與小腿）。兩張都保持姿勢與比例（和原圖對位誤差 0 像素），`make_damage.py` 再用完整零件的輪廓套上 D 的顏色。換破損樣子：在 spec 的 stage `D` 換 `seed` 或 `prompt`，刪掉 `04_stages/D.png` 後重跑 `--from parts`。

預覽：`rig_preview.tscn -- --chars=rin --damage --zoom=3.0`（加 `--bare` 不拿武器、手臂垂下，看得到上半身）；遊戲內截圖情境 `rin_damage`。

## 4. 日後怎麼替換

**換單一零件（手繪或重畫）**
1. 打開 `art/characters/rin/parts/<名稱>.png` 當底，**維持尺寸與支點位置不變**（支點在 `character.json` 的 `textures.<名稱>.pivot`），畫好覆蓋同名檔。
2. 想讓日後重跑流程時不被蓋掉，同時存一份到 `work/overrides/<名稱>.png`（`textures` 步驟會自動複製過去；尺寸不符會警告並略過）。
3. 發光層同理覆蓋 `<名稱>_glow.png`。
4. 重新產生法線並匯入：
   ```
   godot --headless --path . res://tools/art/paint_normals.tscn -- --only=rin
   godot --headless --editor --quit --path .
   ```
5. 用預覽檢查：`godot --path . res://tools/rig_preview.tscn -- --out=<絕對路徑>.png --chars=rin`（加 `--closeup`、`--head`、`--damage` 看特寫與受傷）。

**換整個造型**：`--only design --seed <新種子>`（或改配方提示詞），再 `--from pose`；必要時依 `keypoints.json` 與 `ownership.png` 調 spec 的 `joints` 與切線。

**新增角色**：複製 `recipes/rin.json`、`specs/rin_side.json`，改 `id`、`work`、提示詞、`joints`，執行 `build_character.py`。

## 4b. 遊戲內大小與瞄準

- 凜的整體縮放（spec `scale`）是 1.15：站姿身高約 56 世界像素，和其他人形（54～60）一致；碰撞框 12×44、受擊框約 10×40 沒有動（頭會探出碰撞框 12 像素，其他人形也是這樣）。關卡最矮的通道淨高 4 格（64），兩關都沒有非蹲不可的地方。
- 瞄準起點（肩膀高度）不是寫死的數字：由骨架的武器掛點量出（`CharacterRig.anchor_height()`），換縮放或換骨架準星都會跟著手上的槍同高；子彈從畫面上的槍口射出。
- 檢查工具：`screenshot.tscn -- --scenario=rin_fit`（各動作畫上碰撞框、受擊框、瞄準起點、槍口與瞄準方向，另有最矮通道站姿與蹲姿）、`rin_light`（三種光影）、`rin_perf`（同屏 N 個角色的處理時間與繪製呼叫數）、`rin_damage`（受傷）。

## 5. 已知限制

- 關節位置（spec `joints`）是依 SAM 3D Body 的預測再人工微調；換新角色時要看 `overlay.png` 調一次。
- 只有近側的手腳有圖，遠側用同一張圖調暗（骨架原本的做法）。
- 舊流程的腳本（`cut_parts.py`、`cut_rig_parts.py`、`gen_character_passes.py`）保留，新流程只借用 `cut_rig_parts.py` 裡的 `frame()` 與 `glow_layer()`。

## 6. 新增一個角色（敵人與 NPC）

不用手寫 JSON：範本幫你產生配方與規格，關節由流程從圖量出來，錯誤在慢的步驟開始前就擋下。

```
# 1. 產生配方與規格（armored＝有可破壞裝甲的士兵，civilian＝NPC，沒有裝甲）
python tools/comfyui/new_character.py --id sniper --name 狙擊手 --height 56 --glow r --weapon sniper     --appearance "a sniper in a dark green-grey skin-tight suit with a hood mask and a single scope eye ..."
# 2. 一鍵跑（會依序畫圖、量關節、分件、清理、法線、匯入、預覽）；先只跑到 pose 看關節對不對
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/sniper.json --to pose
#    看 work/02_pose/joints.png；不對的關節直接在 specs/<id>_side.json 填數字（填過的不會被蓋掉）
D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/sniper.json --from parts
# 批次：幾個角色接著跑，其中一個失敗不影響其他的
... build_character.py --recipe a.json b.json c.json        或  --all
```

**輸入**：`recipes/<id>.json`（`height` 站立身高世界像素、`scale`、`armor` 裝甲順序、`glow`／`glow_parts` 發光色字母 c m r o y g 與要發光的零件、`design.prompt` Qwen 提示詞與種子）。**輸出**：與凜相同（零件圖、`character.json`、骨架 `art/rigs/<id>.json`、法線、預覽）；每個角色有自己的骨架檔，骨頭長度與比例由立繪量出，所以不同體型的角色不需要改動畫程式。

**裝甲**：armored 範本把裝甲做成獨立零件：肩甲、前臂護甲、護膝、胸甲，破壞順序就是 `armor` 的順序（預設肩 → 臂 → 膝 → 胸，一步 = 一組，前後側的同一種護甲一起飛走）。做法是請 Qwen 產生「移除所有裝甲、補完底下的內襯」的 `P` 階段圖，身體零件從 P 圖補，裝甲零件從原圖用 SAM 摳出。SAM 找不到時換 `spec.groups.<群組>.sam` 的提示詞；不需要的裝甲從 `armor` 拿掉。

**檢查**：`check_spec.py`（流程會自動跑）指出具體位置，例如 `spec.parts.torso.from: unknown joint 'wiast'`；有錯該角色就停在慢的步驟之前，不會產生壞掉的檔案。貼圖步驟先寫到暫存資料夾，全部切完才換掉舊的，失敗時保留舊貼圖。

**遠側的腿**：側面圖裡遠側腿常被畫成一整條暗色剪影，會跟著前腿走。提示詞已要求「遠側的腿藏在近側腿後面」；仍出現時在 spec 的 `refine.far_side` 設定（顏色與零件，見 `refine_parts.py`）。

## 7. 零件切不對：現象、怎麼查、怎麼修（NE-90）

先跑檢查，再看預覽。`python tools/comfyui/check_parts.py [角色 ...] [--normals]` 逐張貼圖找內部孔洞、游離碎片、空的或幾乎空的發光層、缺法線、支點離零件太遠，並指出是哪個零件；流程跑完 `textures` 步驟時會自動跑一次，印成 `WARN part texture ...`。預覽用 `rig_preview.tscn -- --chars=<id> --npc --loop=<循環> --loop-pose=<姿勢>`（NPC 的站、坐、靠牆、蹲、說話、聆聽、揮手、工作循環）與不加參數的八種動作。

| 現象 | 原因 | 怎麼查 | 怎麼修 |
|---|---|---|---|
| 某個零件整塊不見、動作時手漂在半空（護理師坐姿前臂缺一段） | SAM 提示詞只抓到袖子，漏了裸露的前臂與手，`arm_lower` 在 `06_parts` 是空的，`character.json` 就沒有這個貼圖 | `06_parts/ownership.png` 看手臂區塊；`check_parts.py` 報「貼圖不存在」；`textures` 步驟印 `WARN empty part` | 換 `groups.arm.sam` 的提示詞（"arm sleeve" 加 "arm"，手用 "hand"），用 `sam_masks.py` 先試遮罩看範圍 |
| 圍裙、工具包、大衣下襬變成一大塊跟著手臂甩（阿婆、老陳、老 K） | 這些東西被歸到手臂群組（SAM 的 "sleeve" 把衣襬或圍裙一起吃進去），手臂動它們就跟著動 | `ownership.png` 裡手臂顏色蓋到身體上；預覽手臂擺動時整片布料跟著轉 | 把手臂群組限縮到袖子與手臂（提示詞改成 "sleeve"、"arm"），圍裙、工具包、大衣放進 `body` 群組的 `sam`（例如 "apron"、"tool belt"、"brown coat"） |
| 身體零件在手臂原本的位置是破洞或殘影，手一動就露出背景 | 手臂擋在身體前面，身體沒有補全 | `05_groups/body.png` 看手臂位置；`check_parts.py` 報孔洞 | 加 `P` 階段：請 Qwen「刪掉近側整條手臂，衣服留下空袖孔」（civilian 範本也要加 `stages` 與 `groups.body.complete`），身體群組 `sam` 加 "bare shoulder"（或 "armhole"） |
| 補全後手臂的黑輪廓還留在身體上，變成一條虛線 | 補全只取缺口，原圖手臂邊緣的輪廓線不在缺口內 | 零件放大 2 倍看軀幹上有殘留的深色細線 | `groups.body.complete.trim`（把手臂邊緣外擴 N 像素改取階段圖）與 `mask_close`（先把 SAM 遮罩裂縫閉合） |
| 腿旁邊浮著一片沒有連到腿的布（切割者之外的敵人，手臂擋住大腿的位置） | 階段圖 P 只拿掉了裝甲、手臂還在，所以手臂後面沒有東西可補 | `check_parts.py` 報「游離碎片」，零件放大 2 倍看腿旁是否有一片沒連上的布 | `groups.body.complete.fill_behind`（列出擋住的群組）：缺口那幾列用兩側身體顏色連成漸層補起來 |
| 零件圖放大有孤立小亮點或細縫 | 兩條輪廓線之間夾著幾像素的透明洞 | `check_parts.py` 報「內部孔洞」 | `refine.fill_holes`（`parts`、`max_area`）：比 `max_area` 小的洞用周圍顏色補滿；大的洞通常是真的（頭髮空隙、袖孔），不要補 |
| 孤立的小碎片（衣襬尖端被切線切成另一塊） | 零件切線剛好穿過衣襬 | `check_parts.py` 報「游離碎片」 | `refine.erase`（多邊形，原圖座標）清掉，或調 `parts.*.y` 切線 |
| 發光層是全透明的空檔（老 K 的頭與軀幹） | `spec.glow` 列了零件，但該零件沒有夠亮的霓虹色（金色滾邊的亮度與飽和度不到門檻） | `check_parts.py` 報「發光層」；打開 `*_glow.png` 全黑 | 把零件從 `spec.glow` 拿掉；要保留就調低 `spec.glow_threshold`（`sat`、`val`），並用較寬的色彩字母（例如 "oy"）。`cut_layers.py` 現在不會寫出全空的發光層，也不會留舊檔 |
| 深色衣物在暗處糊進背景（夜班工人、老 K） | 原圖衣服太暗 | 遊戲內光影或 `rig_preview` 看不到輪廓 | 把亮度寫進 `spec.parts.<零件>.uses[].tint`（遠側的肢體照 0.62 倍），不要手改 `character.json`（重建會被蓋掉）；霓虹反光衣這類本身很亮的零件不要乘，否則 HDR 泛光會把它燒成白色 |
| 重建後對話頭像的衣領顏色變了 | `make_portrait.py` 以前把所有有 `tint` 的零件都當成遠側肢體跳過 | 頭像放大看衣服 | 只跳過名稱含 `_back` 且有 `tint` 的零件，前側零件的亮度會一併帶進頭像 |

**改過規格之後**：只重跑受影響的步驟（`--from parts` 會清掉 `05_groups`／`06_parts`／`07_refined` 重新分；階段圖 `04_stages` 不會重畫，要換就刪掉對應檔再跑）。零件尺寸與支點是由立繪量出來的，重新分割後會變，骨架（骨頭長度）不受影響；`character.json` 的差異用版本控制看即可。

## 8. 兩條腿、兩隻鞋：只切近側那一條（NE-152）

側面立繪裡兩條腿並排、兩隻鞋都在圖上，但骨架的前後腿**共用同一組貼圖**（遠側那條只靠亮度區分）。所以腿部零件（`leg_upper`、`leg_lower`、`foot`）必須各自只含**一條腿的一段**；SAM 用 "legs"、"boot" 的文字提示會把兩條腿、兩隻鞋切進同一個零件（腳零件裝了兩隻鞋、大腿含另一條腿或手，小腿只剩一小片）。

規格新增 `near_leg` 區塊，`make_parts.py` 用它在 `body`、`boot` 之外多切一個「近側腿」群組，三個腿零件的 `group` 改成 `near_leg`：

```json
"near_leg": {
  "pos": [[x, y], ...],        近側（最前面、沒被擋）那條腿的大腿、小腿、鞋上的點（原圖像素）
  "neg": [[x, y], ...],        遠側腿與另一隻鞋上的點
  "close": 9, "grow": 0,       閉合半徑；grow＝再外擴幾像素（吃掉輪廓與邊緣光，但不會吃到遠側腿）
  "fill": ["hand", "arm"],     擋在腿前面的群組（這些像素改用旁邊的布料漸層補）
  "cover": [{"pos": [[x, y]], "neg": []}],   不屬於任何群組、卻擋在腿前的東西（被 SAM 當成身體的手）
  "extra": ["apron"],          掛在腿上的衣物（圍裙、長大衣）的 SAM 提示詞，不是腿但要跟著腿的貼圖
  "cover_limbs": true,         false＝手或前臂擋住的地方留缺口，不用漸層補（布料底色未知時漸層看起來像一塊板子）
  "exclude": ["armor_chest"]   要從腿裡再扣掉的群組
}
```
腿零件的 `y` 照舊是切線：`leg_lower` 到腳踝、`foot` 從腳踝切線以下（`foot.y`），鞋底平整貼在零件最底邊，支點在腳踝。靴子與褲管的分界不一定是水平的（深色高筒靴、白襪），所以用 `foot_y`（腳零件的上緣）指定，不靠 SAM 的 "boot" 遮罩。

**怎麼挑點**：先用 `sam_masks.py` 的點提示（`segment_points`）試，疊在腿部區域看遮罩有沒有只吃到近側那一條；兩隻鞋重疊時，正向點要打在近側鞋的前、後、鞋底，負向點打在遠側鞋露出來的前端與靴筒；遠側腿大面積露出時，在大腿與小腿中段各打一個負向點。最終 `foot` 遮罩必須是一隻連續的近側鞋，不能把遠側鞋、第二個鞋尖或遠側靴筒切進來；以原尺寸來源 crop 與遮罩邊界核對，並在黑、灰、白底查看單鞋剪影。分開標出 `ankle` 關節、靴筒頂／鞋口與鞋底真實接地列；靴筒頂不是踝點，鞋底接地也不能用陰影、發光或另一隻鞋的像素代替。近遠側手的 `wrist`／`palm` source joints 也要各自校準到其實際腕口與掌心；遮擋或側視看不到的點標記未知，不沿用另一側的座標或鏡像猜點。遮罩吃不乾淨再依序：(2) 在腳踝以下依兩隻鞋的間隙用 `foot_y`／`y` 幾何切；(3) 只對那條腿的裁切小圖用 Qwen 編輯模式做「只保留近側腿與鞋」，不重畫整個角色。

點位與來源覆寫：把原圖 SHA-256、正／負點的原圖座標、遮罩檔與遮罩 SHA-256、實際選取的零件輪廓一併記錄。確認分件像素只來自正確那隻手／鞋後，輸出與 `base_rgba.png` 同畫布、同座標的 RGBA override，透過配方 `source_rebuilds` 在 `textures` 前重建；保留原始 PNG 與舊遮罩。重跑至少兩次比對 override 雜湊，並確認目標遮罩外逐位元組不變。重建與雜湊一致只證明來源流程可重現，接點、鞋底接地、手部握持及動態仍須各自驗收。

**亮度**：遠側腿要看得出來，近側腿也不能糊進背景。規格 `parts.*.uses[].tint` 依貼圖實際平均亮度決定（近側目標約 0.2、遠側目標約 0.15，近側最多乘 2.0、遠側最少 0.62，遠側不超過近側的 0.8 倍），改規格後重跑 `textures`。

## 9. 專屬骨頭（NE-89）

人形家族以外的骨頭（砲口、刀尖、可掀開的胸甲）寫在規格 `bones`，流程照常產生骨架與零件掛載：

1. 規格 `bones` 加一筆，父骨頭要先定義：`{"name": "core_port", "parent": "chest", "fixed": [4.0, -10.0]}`（`fixed`＝離父骨頭的位置，骨架像素；也可以用 `"at": 關節`，或接在有 `tip` 的父骨頭後面成為鏈節）。
2. 要讓貼圖跟著專屬骨頭動，把該零件 `uses` 的 `bone` 改成它；骨頭不在原本的支點上時，加 `"offset": [x, y]` 抵銷（例：鉸鏈在胸甲下緣 `fixed: [4, 0.5]`，零件 `offset: [-4, -0.5]`，零件留在原位、轉動時繞鉸鏈）。
3. 跑 `check_spec.py`：專屬骨頭沒有定位、`fixed`／`offset` 不是 `[x, y]`、零件指到不存在的骨頭都會指出確切位置。
4. 專屬動作寫在 `art/rigs/action_poses.json`，用骨頭名稱當 key；敵人資料的 `rig_actions` 把狀態對到動作。預兆線、發光、發射點與判定位置都取同一個骨頭的世界座標（`rig.bone(名稱).global_position`），畫面與判定才不會各走各的。
5. 預覽：`rig_preview.tscn -- --chars=<id> --action=<動作>`；遊戲內：`screenshot.tscn -- --scenario=warden_core`（監管者範例）。


## 衣物受損與可脫落裝甲的區分（NE-222）

`armor_order`控制受損層的顯示順序，不能由此推論整張圖就是可脫落裝甲。包含完整軀幹、骨盆或四肢的衣物零件，應由角色spec設定`armor_debris: false`；切圖流程原樣輸出到character.json。未指定的裝甲角色維持原本的碎片效果。此欄位必須是布林值，錯誤資料需指出角色與欄位並退回原本安全行為。

此修正不需重畫或重新切圖，只更新配方與角色資料；PNG、支點、骨架與受傷／回血順序維持原樣。交付時以實際受傷、回血和致命傷檢查衣物變化與完整身體，再確認真正敵人裝甲仍能飛散。`tools/rig_debris_review.tscn -- --out=<絕對路徑>`保留原生四個致死案例、每例五張影格及碎片數；`--legacy-debris`只作舊錯誤行為的對照，不作修後驗收。

衣物型角色跨越受損階段時，沿用既有非加法粒子場，在各受損部件掛點噴出少量暗色布屑；同一部件最多三片、約0.32–0.48秒淡出，不另加發光環或整件剪影。數量仍尊重既有特效設定；未跨階段、初始化、回血及無效掛點不觸發。原生姿勢網格位於Skeleton根原點，須回查同一slot的身體部件掛點，不能把所有布屑集中在骨盆。這些數值是本專案的克制起點，不是業界通用標準；兩面向、一般／近拍倍率的實際HP事件、過渡畫面、恢復及敵人裝甲回歸分別留下證據。方向參考[Riot Games：Visual Effects](https://www.riotgames.com/en/artedu/visual-effects)的克制、清楚傳達狀態及整體風格一致原則。

## 實際姿勢參考與UV（2026-10-09，NE-222）

`tools/comfyui/rig_reference.tscn`現在包含Sprite及RigPartMesh。`--pose=stand|sit|crouch|lean`啟用實際NPC姿勢，保留近遠側，子骨位置與正式rest一致；預設`reference`仍提供單側製作參考。JSON version 2記錄角色密度、全部骨頭變換、網格的實際頂點／UV／三角形及剛體的像素變換。

舊工具的PNG仍畫出網格，但JSON只記錄9件，漏掉軀幹與四肢的座標。修正後一般完整服裝參考記錄16件，雙側坐／蹲22件。body會顯示既有護甲下層，凜的這些層是受損衣物，不能當完整未受傷立繪。實際輸出及來源雜湊見`art_src/characters/rin_pose_variants/00_bind_reference/`。

`cut_parts.py`對網格採用三角形的UV反算，不將已彎圖当剛體再折一次；直接採樣至目標貼圖，不先縮後放或自動銳化。兩個pass的幾何在任何寫圖前檢查，非法UV／頂點／索引／退化三角形拒絕。近遠側共用來源貼圖時，兩個姿勢不得寫入同一輸出，工具會拒絕，要求各側隔離後交付獨立attachment。這是坐標流程修復，舊工具的最近色填補仍不代表完整隱藏層；正式角色仍按character-art-pipeline及rig-animation全部件驗收。
