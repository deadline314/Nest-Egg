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

**怎麼挑點**：先用 `sam_masks.py` 的點提示（`segment_points`）試，疊在腿部區域看遮罩有沒有只吃到近側那一條；兩隻鞋重疊時，正向點要打在近側鞋的前、後、鞋底，負向點打在遠側鞋露出來的前端與靴筒；遠側腿大面積露出時，在大腿與小腿中段各打一個負向點。遮罩吃不乾淨再依序：(2) 在腳踝以下依兩隻鞋的間隙用 `foot_y`／`y` 幾何切；(3) 只對那條腿的裁切小圖用 Qwen 編輯模式做「只保留近側腿與鞋」，不重畫整個角色。

**亮度**：遠側腿要看得出來，近側腿也不能糊進背景。規格 `parts.*.uses[].tint` 依貼圖實際平均亮度決定（近側目標約 0.2、遠側目標約 0.15，近側最多乘 2.0、遠側最少 0.62，遠側不超過近側的 0.8 倍），改規格後重跑 `textures`。

## 9. 專屬骨頭（NE-89）

人形家族以外的骨頭（砲口、刀尖、可掀開的胸甲）寫在規格 `bones`，流程照常產生骨架與零件掛載：

1. 規格 `bones` 加一筆，父骨頭要先定義：`{"name": "core_port", "parent": "chest", "fixed": [4.0, -10.0]}`（`fixed`＝離父骨頭的位置，骨架像素；也可以用 `"at": 關節`，或接在有 `tip` 的父骨頭後面成為鏈節）。
2. 要讓貼圖跟著專屬骨頭動，把該零件 `uses` 的 `bone` 改成它；骨頭不在原本的支點上時，加 `"offset": [x, y]` 抵銷（例：鉸鏈在胸甲下緣 `fixed: [4, 0.5]`，零件 `offset: [-4, -0.5]`，零件留在原位、轉動時繞鉸鏈）。
3. 跑 `check_spec.py`：專屬骨頭沒有定位、`fixed`／`offset` 不是 `[x, y]`、零件指到不存在的骨頭都會指出確切位置。
4. 專屬動作寫在 `art/rigs/action_poses.json`，用骨頭名稱當 key；敵人資料的 `rig_actions` 把狀態對到動作。預兆線、發光、發射點與判定位置都取同一個骨頭的世界座標（`rig.bone(名稱).global_position`），畫面與判定才不會各走各的。
5. 預覽：`rig_preview.tscn -- --chars=<id> --action=<動作>`；遊戲內：`screenshot.tscn -- --scenario=warden_core`（監管者範例）。

