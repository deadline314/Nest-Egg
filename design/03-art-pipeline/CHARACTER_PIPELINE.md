# 角色製作流程：從一張透明背景的側面圖到 Godot

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

### 第 3 步細節：怎麼分、怎麼補

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

| 零件圖 `parts/<名稱>.png` | 掛在哪根骨頭 | 圖層 z | 說明 |
|---|---|---|---|
| `hair_back_1`、`hair_back_2` | `hair_1`、`hair_2` | −9 | 馬尾上半、下半；跟著彈簧骨飄動 |
| `pelvis` | `hip` | 0 | 骨盆、臀、絲襪上緣 |
| `torso` | `chest` | 1 | 白色連身衣含頸部與裸肩 |
| `leg_upper`、`leg_lower`、`foot` | `leg_front_*`／`foot_front`（z 3）與 `leg_back_*`／`foot_back`（z −5，亮度 0.62） | | 前後腿共用同一張圖 |
| `holster` | `leg_front_upper` | 4 | **配件**：大腿槍套 |
| `torso_dmg`、`pelvis_dmg`、`thigh_dmg`／`calf_dmg`（含後腳）| 與完整零件同骨頭 | 完整零件 z−1 | **破損底層**：撕裂衣物版的身體，平時被完整零件蓋住，衣物飛走後露出來 |
| `jacket` | `chest` | 4 | **配件**：披在肩上的夾克上半（含洋紅襯裡）；袖子不另外拆，手臂圖層比夾克高，夾克像披在肩上、手臂從裡面滑出來 |
| `jacket_hem_1`、`jacket_hem_2` | `coat_1`、`coat_2` | 4 | **配件**：夾克下擺，兩段彈簧骨（`coat_1` 掛在胸骨的下擺根部，`coat_2` 掛在 `coat_1` 底下），跑步向後飄、上升下垂、下落掀起 |
| `jacket_collar` | `neck` | 4 | **配件**：脖子旁的遠側翻領（原本是夾克上獨立的一塊，spec 用 `blob: "rest"` 分出） |
| `head` | `head` | 5 | 臉、前髮、耳環 |
| `arm_upper`、`arm_lower`、`hand` | `arm_front_*`／`hand_front`（z 8～10）與 `arm_back_*`／`hand_back`（z −7～−6，亮度 0.62） | | 金屬義肢 |

每張圖旁邊還有 `<名稱>_glow.png`（霓虹發光層，加法混合）與 `<名稱>_n.png`（法線）。`character.json` 的 `textures` 記錄每張圖的尺寸與**支點**（旋轉中心），`parts` 記錄掛載（骨頭、z、亮度）。

**配件（夾克、槍套）**各自掛在骨頭上。槍套綁在大腿上，跟著 `leg_front_upper` 轉；夾克下擺與頭髮用彈簧骨做次級動態。

**次級動態參數（資料，不寫在程式裡）**：骨架檔 `art/rigs/humanoid_tall.json` 的 `springs`（來源是 spec 的 `springs`，`cut_layers.py` 寫進去）。每一項：`bone` 彈簧骨；`rest` 靜止角度（夾克下擺要 0，才與原圖一致）；`gain` 跟隨移動的倍率（越大飄越遠）；`trail`／`lift`／`wind` 往前跑向後飄、上升下落、微風各自的倍率（預設 1）；`stiffness`／`damping` 彈簧硬度與阻尼（硬度高回彈快，阻尼高晃得少）；`min`／`max` 角度上下限。沒有 `springs` 的骨架（`humanoid.json`）用程式內的預設值。檢查：`rig_preview.tscn -- --chars=rin --cloth`（站、跑、上升、下落、蹲、仰射並排）。

**肢體偏移**：spec `bones` 的 `dx` 是骨頭相對關節的水平位移。圖是從同一張側面圖切出的，近側（前）手腳必須是 0，否則會和骨盆、夾克、衣服對不齊，切口沿線出現方框；遠側（後）手腳用負值讓兩條腿分得開。

**切口不留透明邊**：spec `parts` 有 `y` 的零件（在關節處切開的），切口那一側不留透明邊，法線貼圖（會把每個透明邊緣做成圓邊）才不會沿切口打出亮邊。

## 3b. 受傷時衣物脫落

遊戲內原有的裝甲脫落機制（`character.json` 零件的 `armor_order`，小的先掉；同一個 order 的零件算同一步、一起飛走；生命比例 → 還剩幾步）。凜把它用在衣物上，每一步 20%：

| 步 | 飛走的零件 | 底下露出來的 |
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

