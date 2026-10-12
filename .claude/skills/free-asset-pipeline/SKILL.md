---
name: free-asset-pipeline
description: 把場景素材換進或新增到 Nest Egg 的完整流程：找來源與授權（CC0）、下載、把材質／3D 模型／HDRI 天空加工成遊戲規格（含法線與自發光）、沒有免費素材時用本機 Qwen 生成、場景包（每個場景的背景與專屬物件）、放進資料格式、全域調色與光影預設、暗場可讀性與效能驗收，以及踩過的坑。要新增或替換地形材質、建築立面、場景道具、天空、背景、樹木、場景背景或光影預設，或要找免費素材時使用。不處理角色、敵人、立繪。
---

# 免費素材替換流程

背景與決策見 `design/11-free-assets/DESIGN.md`；票在 `pm/Nest-Egg/` 的 NE-56～NE-67。這份是**照著做就能動**的操作手冊，每一條都是做過、踩過才寫的。

## 0. 原則

- **只收 CC0**。授權不明、CC-BY、CC-NC、「免費但禁止再散布原檔」（多數 itch.io 免費包）一律不放進專案。
- 主力來源：**Poly Haven**（材質、3D 模型、HDRI 天空，`api.polyhaven.com`，免金鑰）與 **ambientCG**（材質，`ambientcg.com/api/v2`，免金鑰）。Kenney、OpenGameArt 只在缺特定物件時挑用，逐件確認授權。
- 原始下載檔放 `assets_src/raw/`（不進版控，可重抓）；進版控的是加工後的 `art/**`、`assets_src/manifest.json`、`assets_src/pipeline/*.json`、`assets_src/LICENSES.json`。
- **所有加工都由清單驅動、可重跑**。不要手改 `art/environment/**` 裡的成品圖——改清單（調色、裁切）再重跑，否則下次重跑就被蓋掉。
- 調色參數只放清單（JSON），不寫進程式。全域調色見 §7。
- 角色（`art/characters/**`、立繪、敵人）由別人處理，**不碰**。使用者可能同時在改角色美術：驗證環境素材時，用乾淨的 git worktree（見 §6）量測，別把角色變動算進環境素材的帳。
- **不要把照片等級的現實場景放進遊戲**（使用者 2026-10-03：「超突兀」）：真實城市天際線（含看得出地名與招牌的）、實景照片一律不用，`process_backdrop.py` 的 `pano_skyline` 保留但不要用在遊戲裡。遠景、中景用 `city_blocks` 以立面模組組出風格一致的樓群。可用的照片素材僅限抽象的天空與雲（暴雨雲、夜空），且要先調暗調色；不確定時先問。
- **使用者的美術偏好（2026-10-03）**：盡量少用純矩形、方形、單純弧形（半圓頂、拱窗、膠囊窗）；多一點裝飾、特效與動畫。實作上：樓群用階梯、斜屋頂、人字屋頂、切角、尖塔輪廓，屋頂放天線、水塔、碟型天線、通風管與信標；窗戶用切角八邊形加窗格；牆面加電路走線、LED 指示燈、水管、冷氣機、攝影機；窗光邊緣柔化；窗光會閃、信標會明滅、植物會搖。

## 1. 環境

- Python 需要 `pillow numpy scipy opencv-python-headless`（`python -m pip install`）。
- Godot 4.7，路徑慣例 `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`（或設環境變數 `GODOT`）。
- **Linux 雲端容器（沒有 GPU）也能量測與截圖**：下載 `Godot_v4.7-stable_linux.x86_64`；`apt-get install mesa-vulkan-drivers`（軟體 Vulkan）；`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/…`。第一次匯入整個專案要 20 分鐘以上（背景執行、不要設逾時被殺，中斷後重跑會接續）。**拉到別人新增的 `class_name` 檔案後要再跑一次 `godot --headless --editor --quit`**，否則會出現 `Identifier "…" not declared`、`Nonexistent function 'exists' in base 'GDScript'` 這類假的腳本錯誤。軟體渲染下數字會與實機不同（尤其每影格耗時），對比量測可用、效能只能同機對照。
- `pip install pillow numpy opencv-python-headless` 後 `python3 tools/assets/*.py` 在 Linux 也能跑；重跑加工腳本後 PNG 的壓縮編碼可能與進版控的不同（像素相同），用 `git checkout art` 還原，只提交像素真的變了的圖。
- **Windows 的 python 看不懂 Git Bash 的 `/c/...` 路徑**：在專案根目錄用相對路徑執行腳本。
- 工具都在 `tools/assets/`，每支腳本開頭的 docstring 有用法。

## 2. 下載與登記授權

1. 在 `assets_src/manifest.json` 加一筆：`{"id": "ph_tex_xxx", "source": "polyhaven"|"ambientcg", "kind": "texture"|"model"|"hdri", "asset": "<來源網站上的 id>", "use": "用途", "res": "2k"}`。id 慣例：`ph_`／`acg_` ＋ `tex`／`mod`／`hdr` ＋ 名稱。
2. `python tools/assets/fetch_assets.py [--only ID ...]`：下載到 `assets_src/raw/<id>/`，授權（作者、CC0、出處網址）寫進 `assets_src/LICENSES.json`。單項失敗只記錄、不中斷。
3. 找素材：Poly Haven 的 `https://api.polyhaven.com/assets?t=models|textures|hdris&c=<分類>`；`hidden_alley` 是賽博龐克小巷套件（公寓與工廠立面、路燈、冷氣機、電箱、電線桿、鐵閘、捲門），夜景 HDRI 分類是 `night`、純天空是 `pure skies`，ambientCG 用 `full_json?q=<關鍵字>`。
4. 挑素材前先看縮圖或實際渲染：材質要**可無縫平鋪**（腳本會量接縫）；模型要確認是單件還是「套件」（多件排在一起，見 §5）。

## 3. 地形材質（`process_material.py`）

清單：`assets_src/pipeline/materials.json`，每筆 `{id, tile_world, normal_strength, grade, cel{kind, pal, ...}}`。**BG-1 起 16 種全部是程式繪製的賽璐璐畫風**（平塗色塊、深色墨線、硬邊兩色陰影、由左上打光的亮邊與暗邊），不再從 Poly Haven／ambientCG 的 PBR 照片裁切（舊的 `source` 路線程式還在，沒有 `cel` 區塊的項目仍走它）。

- 畫法在 `tools/assets/cel_tile.py`：`Tile` 同時畫顏色與高度圖（高度圖算出法線），所有圖形環繞邊界所以**天生無縫**（接縫量測對線條規律的圖會誤報，例如格柵 `seam 14.99`，以拼 2×2 的實際畫面為準）。`kind`：`plates`（鋼板格：地板、牆板、鉚釘、散熱孔、色帶）、`bricks`、`corrugated`（波浪鋼板，可加鏽斑）、`slabs`（混凝土板、污漬、裂縫，可加塗裝標線）、`asphalt`、`gravel`（屋頂瀝青碎石）、`grating`（格柵）、`glass`（帷幕玻璃）、`rust`。新增種類就在 `PAINTERS` 加一個函式。
- 色盤在 JSON（`pal`：`ink` 墨線色、`tones` 數個底色、`light` 亮邊色、其餘依種類），種子由 `id` 決定，重跑結果一致。色盤直接寫成最終顏色（`grade` 預設不調）；環境光會再壓暗，所以每種材質都要比夜景背景亮、但不搶眼。
- 頂面與側邊：本體裁切後加一條墨線外框、一條冷白亮邊、下半部硬邊變暗（`build_top_cel`／`build_side_cel`）。
- `id` 必須對應 `data/environment/materials/<id>.tres`（腳本會把 `texture_scale` 寫回資料）。解析度 = `texture_scale`（預設 8）× `tile_world`；上限 768 px，超過會報錯。
- 輸出 `<id>_{body,top,side}.png` ＋ `_n.png`（OpenGL 法線，Y+ 向上，與 Godot 2D 相同，直接用）。法線太平就調高 `normal_strength`（有機形狀如柏油、混凝土、鏽蝕用 14～24，規則鋼板 8）。
- 遊戲端：`TerrainMaterialData.texture_scale`、`EnvZone.interior_scale`（室內牆面貼圖用的是 `*_body.png`，倍率要跟著改）。

## 4. 天空（`process_sky.py`）

清單：`assets_src/pipeline/backdrop.json` 的 `skies`，每筆 `{id, width, height, top_fade, cel{seed, palette, bands, wave, stars, orbs, layers, horizon_glow}}`。**BG-4 起 7 張天空全是程式繪製的賽璐璐畫風**（`tools/assets/cel_sky.py`，欄位說明在檔頭 docstring）：硬邊色帶漸層、平塗的雲（雲底較暗的第二色、亮邊）、星星／月亮／太陽、階梯式地平線光暈。圖形都以 ±寬度環繞繪製或用整數個正弦週期，所以左右天生無縫。沒有 `cel` 區塊的項目仍走舊的 HDRI 路線（`source`、`elevation`、`grade`）。

- 輸出 WebP；cel 天空是無損 WebP（平塗色塊只有十幾～幾十 KB）。`BackdropLayer.texture` 已允許 `.webp`。
- 夜空亮度以舊成品的平均亮度為上限（暴雨夜 0.15、城市夜空 0.17），藍天（過場動畫用）可以亮。
- 舊的 HDRI 路線：從 360° 全景切出「地平線以上」的長條；**低仰角會切到建築、樹與路燈**，把 `elevation` 下限拉高（城市全景要 ≥ 50°）。
- 遠景天際線（`process_backdrop.py` 的 `pano_skyline`）：同一個 HDRI 取一段（`span_deg`、`elevation`），接縫處交叉淡化、上緣淡出；亮處（窗光、霓虹）另存 `_glow.webp`。中景樓群（`city_blocks`）用已建好的立面模組疊樓，兩排前後（每排寬度加總剛好一個 tile，左右無縫；寬於一個模組的樓用多個模組並排）、輪廓用 `shape_mask`（階梯／斜屋頂／人字／切角／帶尖塔／側塔／雙塔／針尖／斜切）、每棟有墨線外框、左亮右暗的硬邊明暗，越遠的排用 `haze` 混合偏藍（越淡越偏藍）；屋頂雜物是賽璐璐畫的天線（頂端純紅信標）、水塔、碟型天線、通風管、煙囪、招牌（霓虹）、風管、屋頂雜物貼在**該欄的屋頂線上**（不是整棟的最高點，否則斜屋頂上的雜物會漂浮）。
- 遊戲端：`EnvironmentTheme.sky`（`BackdropLayer`），`LevelBackground` 把它做成慢速視差層壓在程式天空上；缺圖退回程式天空並記錄路徑。
- **背景會被環境光（`CanvasModulate`）與 `background_tint` 壓暗**：圖在遊戲裡看起來比預期暗很多。`BackdropLayer.tint` 可以大於 1（HDR），例如 `Color(1.4, 1.35, 1.5, 1)`。亮度先在圖裡調出細節（對比 1.5～2），tint 只做微調；tint 拉太高只會得到一整片飽和的色塊。

## 5. 3D 模型 → 2D 貼圖

### 單件道具（`build_props.py`，CC0 模型加工）

既有 16 件模型道具已改為賽璐璐版本，保持原成果。`props.json` 現在新增一件 Kenney CC0 草叢示例；合適的低多邊形風格模型可沿用這條 3D→2D 流程，支援 glTF／GLB。新素材先找合授權且風格合適的 CC0，再考慮 §8；本次多 Session 的 ComfyUI 生成／啟停只由指定生成 Session 操作。

清單：`assets_src/pipeline/props.json`，每筆 `{id, model(manifest id), crop[x0,y0,x1,y1 比例], fit:"height"|"width", yaw, pitch, glow:[材質名正規式], glow_color, glow_through, render_width}`。

1. `render_model.tscn`（Godot）用正交鏡頭渲染：反照率（含柔和光）、鏡頭空間法線（`_n`，已轉成 Y+ 向上）、可選的自發光遮罩（`_glow`）。
2. 腳本裁切、調色、修邊，寫 `art/environment/props/<id>{,_n,_glow}.png`，並改 `data/environment/props/<id>.tres` 的 `size`（沿 `fit` 的那一軸保持原值，另一軸跟著模型比例）、`light_offset`（等比縮放）、`has_glow`。
3. 道具以**底邊對齊地面**，所以比例改變不會讓它陷進地裡；有 `platform`（單向平台）的道具要保持原本比例，不要直接換。
- 自發光：`glow` 填**發光材質的名稱**（先看 glTF 的 `materials[].name`）。寫實模型的燈泡多半靠 emission 屬性而不是貼圖顏色，所以發光層用單色（`glow_color`）。燈泡包在玻璃裡時加 `glow_through: true`，否則被塗黑的玻璃蓋住。
- **踩過的坑**：`glow` 的正規式 `window` 會連窗框材質一起中（窗框材質叫 `..._windows`），玻璃要用 `_glass`。

- **新增道具**：`props.json` 的項目加 `new: {display_name, category, sway, ...}` 與 `anchor.size`，首次執行會建立 `.tres`；`aliases` 可以不做新圖、只新增一份資料沿用既有貼圖（例如半透明的前景樹）。`anchor` 記住原本尺寸，重跑不會越縮越歪。
- 植物會搖：`PropData.sway`＋`sway.gdshader`（頂端位移、依位置錯開相位、同幅度共用一份材質），不需要每影格腳本。前景植物放在**沒有敵人與危險物的欄**（既有擺放檢查會抓）。

### 建築立面（BG-2 起全部程式繪製的賽璐璐畫風，不再用 Poly Haven 立面套件渲染）

- `build_facades.py`（清單 `assets_src/pipeline/facades.json`）直接畫圖，不依賴任何外部圖檔：牆面平塗（`cel_facade.py` 的 `plaster`、`brick`、`corrugated`、`slab`、`panel`、`curtain`）、墨線窗框、硬邊雙色陰影（光從左上）、切角八邊形窗加窗格與窗台；一個模組的畫布同時畫顏色、高度（轉成 `_n` 法線）與自發光（`_glow`）三層。尺寸：寬 64、一樓高 40、標準樓層 32、女兒牆 8（× `texture_scale`）。
- 清單每個立面：`pal`（色票）、`wall`（牆面種類與參數）、`window`（預設窗格：cols、rows、w、h、y、chamfer、panes、grill、blind…）、`decor`（管線、冷氣機、陽台、LED、走線、攝影機、警示燈的機率）、`body`／`ground`／`cap` 的**變化清單**（每項深度合併蓋過立面預設；變化數量就是 `.tres` 陣列長度，腳本自動改寫 `.tres`，並刪掉多餘舊圖）。一樓用 `items`：`shutter`（鐵捲門，可 `hazard`、`lamp`）、`door`（門、舷窗、招牌）、`shop`（櫥窗加條紋雨棚）、`window`、`vent`。女兒牆 `kind`：`parapet`、`saw`（鋸齒屋頂）、`pediment`（山牆）、`stepped`（階梯），`clutter` 放天線、通風管、碟型天線、水塔、桅桿。
- 每個標準樓層至少一扇亮窗；整扇窗依 `light_chance` 亮或暗、顏色從 `light_colors` 抽，乘 `light_gain`（0.5）；一樓大面積燈光再乘 item 的 `gain`（預設 0.7）。固定亂數種子（模組名稱的 crc32），重跑結果一致。**信標一定要畫純紅**（`decor.beacon`、天線頂端、攝影機 LED），窗光生命著色器才會讓它明滅。
- 牆面裝飾在 `decor.py`：水管、冷氣機、攝影機、警示燈、陽台、電路走線、LED 列、警示條紋，全部是墨線加硬邊陰影，並用 `Canvas.occ` 避開窗戶。
- 亮度基準：以舊版立面的平均亮度（約 0.12～0.19）為上限；調 `pal`，不要調 `light_gain` 以外的程式。
- 立面模組左右可無縫相接（形狀會環繞），上下以樓板線與硬陰影相疊。
- 其他套件模型（管線、電線桿）若還要用：`render_model.tscn` 以大寬度（2400）渲染整個套件、`glow: ["_glow"]`，再用 `kit_cells.py <名稱>` 偵測每一件、輸出編號預覽，用編號挑件，不要手量座標。立面已不走這條路。

## 6. 放進遊戲之後必做

**不要預設跑完整測試套件**（使用者的明確偏好，耗時且對單一票沒必要）：只跑相關套件，例如 `godot --path . --headless res://tests/smoke_test.tscn -- --only=EnvironmentSuite,CutsceneSuite`（`--only=` 接 `tests/suite/` 裡的類別名，逗號分隔），再加上預覽、截圖與暗場可讀性量測。使用者明說要全跑才跑。

1. **重新匯入**：`godot --path . --headless --import`。換掉同名 PNG 後 Godot 仍用舊的匯入快取，不重匯入會看到舊圖、測試也會量到舊尺寸。
2. 看畫面（遊戲很暗，直接截圖看不出材質）：
   - `tools/assets/preview_materials.tscn`：16 種材質各一塊，受光與法線都在，畫法與 `Terrain` 相同。
   - `tools/screenshot.tscn -- --scenario=spots:level_01:<標籤> --brightness=1.0`：關卡實景；`--brightness` 只在拍攝時調亮度並還原。
   - 對照用的「換之前」：`git worktree add --detach <暫存路徑>/base HEAD`，在裡面匯入並拍同樣的點；`tools/assets/compare.py` 把前後並排。
   - `tools/assets/contact_sheet.py`：渲染出的道具貼圖（反照率＋法線）一覽。
3. **乾淨環境**：`git worktree add --detach <暫存路徑>/mine_wt HEAD`，把自己改的環境相關檔案複製過去（`art/environment`、`data`、`core`、`game/level`、`tools`、`assets_src`；複製後刪掉沒有對應圖檔的孤兒 `.import`），在裡面匯入、量測、截圖。工作目錄裡的角色美術被別人改動時，量測會被拉低（本次第一章六個區段，工作目錄全掛、乾淨環境全過）。
4. **暗場可讀性量測**：`godot --path . res://tools/readability_check.tscn -- --level=level_01`。角色（玩家）與背景的對比不能掉。亮窗、亮牆、亮道具都會拉低它；掉了就降亮度或 `light_gain`。先用沒動環境的版本量一次基準：第一章「屋頂巷弄」在換素材之前就低於門檻（與角色美術有關），別把它算在環境素材頭上。
5. `python tools/assets/check_assets.py`：`art/environment` 總量 ≤ 60 MB、單檔 ≤ 1.5 MB、每個清單來源都有 CC0 授權紀錄。
6. 若使用者要求完整測試：`GODOT=<路徑> tools/run_tests.sh`（本機約 4 分鐘；跑的時候不要改 `art/`、`data/`、`game/`、`tests/`，否則結果作廢）。
7. 每一步的視覺產出都用 SendUserFile 給使用者看，並存到 `pm/Nest-Egg/images/` 寫進票。
8. 舊的暫代圖產生器 `tools/art/paint_environment.tscn` 會覆蓋同名檔案；清單裡有的項目它會自動略過，但新增項目時記得把 id 放進清單。

## 7. 風格與調色

- 寫實素材比原本的像素美術亮、彩度低、細節多，必須壓亮度、偏冷、保留法線細節；亮度以「原本那張的平均亮度」當目標（原材質平均亮度約 0.15～0.3）。
- 窗光、霓虹靠自發光層與加法光；牆面本身要暗，讓角色與霓虹有對比。
- 夜景色盤：深藍紫底、洋紅與青色點綴，見 `core/palette.gd`；不要讓背景比角色搶眼。
- **調色只有一份算法、一份全域資料（NE-66）**：`tools/assets/grade.py` 是唯一的調色實作（gamma、saturation、contrast、brightness、tint）；各加工腳本先套用清單項目自己的 `grade`，再套用 `assets_src/pipeline/grade_master.json`（`all` 全部、`kinds` 的 `material`／`facade`／`backdrop`／`sky`／`prop`／`scene` 各類別）。預設全是「不變」。要整批調亮度、彩度或色調：改 grade_master.json，重跑對應腳本。**自發光層不套用全域調色**（它是發光，不是反照率）。新增加工腳本時呼叫 `grade.grade_asset(a, entry_grade, kind, pivot, use_master)`，不要再複製一份調色函式。`python tools/assets/grade.py --check` 驗證資料。
- **光影預設才是「夜與晝」的控制**：圖本身的調色只決定素材長什麼樣，區段的環境光、背景色調、霧、角色補光在 `data/lighting/*.tres`（見 §11）。素材太暗先看光影預設，不要先改圖。
- 寫實背景與動漫賽璐璐角色的畫風落差已用賽璐璐重做（BG-1～5、10）解決；新素材一律走賽璐璐路線（程式繪製或 Qwen 的 `cel` 風格），照片等級素材不放進遊戲。

## 8. 沒有免費模型的部分：用本機 Qwen Image 生成（2026-10-03 起）

CC0 庫找不到的道具（吊車、龍門吊、控制台、堆高機、閘門、販賣機、看板、霓虹、麵攤…）、整張室內場景（過場舞台）、近景剪影條帶，改用本機 ComfyUI 的 **Qwen Image 2.1 非審查版（int8 ConvRot）** 生成。來源是自己的提示詞與種子，沒有第三方授權問題，但**提示詞與種子必須留在清單**（可重現）。啟動與重試見下方「啟動與卡死自動重試」；`tools/comfyui/comfy_api.py` 的 `qwen()` 是唯一入口。

工具與清單（全都由清單驅動，重跑只重新處理）：

| 工具 | 清單 | 產出 |
|---|---|---|
| `tools/assets/qwen_props.py` | `assets_src/pipeline/qwen_props.json` | `art/environment/props/<id>{,_n,_glow}.png`，並改 `.tres`（大小、發光、動畫欄位） |
| `tools/assets/qwen_scenes.py` | `assets_src/pipeline/qwen_scenes.json` | 過場舞台背景 `art/environment/stages/*.webp`（1536×864，亮點抽成 `_glow.webp`）、近景條帶 `backdrop/fg_*.webp` |
| `tools/assets/stage_defs.py` | （程式內） | `data/cutscene/stages/*.json`：背景圖＋脈動柔光＋塵粒＋顆粒 |
| `tools/assets/procedural_props.py` | — | 水窪、地面警示線（模型畫不好的貼地小東西，程式畫） |
| `tools/assets/qwen_matte.py` | — | 去背、法線、發光遮罩的共用函式 |

做法與踩過的坑：
- **透明背景用官方模板，不要白底去背**：提示詞套 `This is an RGBA image with transparency. <主體>. The image has alpha channel and the background is transparent.`（工具自動套），模型直接寫出真正的 alpha，支架、纜線之間都是真透明。編輯模式（給參考圖）也能用同一模板。輸出若沒有透明（alpha 最小值 > 0.98）工具會報錯，換種子重來。
- **畫風：賽璐璐**（使用者 2026-10-03 決定，和凜、肖像同一國）。提示詞風格段（`styles`）寫「Anime cel-shaded … Cyberpunk Edgerunners：平塗、乾淨深色描邊、硬邊雙色陰影、冷白輪廓光」。**踩過的坑**：只寫夜景色調會得到全紫的圖，在深藍紫背景裡糊成一片、龍門吊幾乎看不見；要求「固有色（鏽褐、鋼灰、褪紅、青綠、暖黃）、明顯比深藍夜景亮」，並用 `grade` 略提亮。寫實版（Poly Haven 模型風）和動漫角色落差大，不採用；是否採用某種畫風要先用「同一批道具放進遊戲畫面」的前後對照來決定，不要只看單張圖。
- **視角**要寫「正射、側面或正面立面、沒有透視、沒有地面與投影」。
- **尺寸依真實高度**：`fit: meters` ＋ `height_m`（公尺）× `px_per_meter`（30；凜 1.7 m ≈ 44 px 碰撞高）。販賣機 1.9、閘門 2.5、長椅 0.85、水塔 3.8…；遊戲內太小的道具（20～30 px）描邊和細節都看不到。超大型道具與有平台的道具用 `fit: keep`。
- **比例**：模型畫出的物件有自己的自然比例，不要硬拉成舊暫代圖的框。其他 `fit`：`height`／`width`（另一軸跟著圖）、`area`（自然比例、面積約等於原本，高度限制在 0.75～1.3 倍）、`keep`（拉伸，只在比例差 30% 內用，超過工具會警告）。提示詞裡寫「tall and narrow」會得到很瘦的東西，寫比例（「about five wide to seven tall」）。
- **有單向平台的道具**（逃生梯、麵攤、雨棚）：`platform_align: true`，工具偵測圖裡第一條粗橫條（甲板、雨棚），再用透明邊框等比例補到平台資料的位置，平台碰撞不用改、關卡可站位置不變；`"contain"` 則把整張圖等比例放進原本的框內（不拉伸）並把甲板對到平台。模型畫出的比例和框差太多時用 `contain`，不要用 `keep` 硬拉。
- **去雜訊**：`alpha_floor`（拉高可去掉模型畫的牆面陰影暈），工具自動刪掉小於最大塊 1% 的零碎透明度殘片，避免它們把外框撐大。
- **編輯模式（給參考圖）吃顯示記憶體**：1536×864 級的參考圖曾讓 ComfyUI OOM 卡死；清晨版舖子改成 1152×648 生成再放大就穩了，逃生梯類改成純文生圖。編輯模式的工作排在批次最後。
- **不要叫模型「沒有人」**：負面描述會被無視（第一版老 K 的舖子畫進兩個小孩）。改正面描述：「a completely deserted and uninhabited place where nobody is present, the floor strip is bare and empty」。
- **編輯模式做變體**：清晨版舖子用 `ref` 指向夜晚版原圖，構圖一致、只改光線。
- **管線不用模型畫**：直管、橫管、設施管線（三管束）又長又細，模型會把它畫彎或畫不出 1:10 的比例，改用 `python tools/assets/cel_pipes.py` 程式繪製（尺寸同資料，每邏輯像素 8 px），自帶法線。
- **法線（BG-8）**：`qwen_props.py` 的法線不再由亮度推算，而是 `tools/assets/depth_normals.py` 從輪廓推算高度：`pillow`（預設：平整面、圓角邊，門、箱、機器、床）、`cylinder`（直立圓柱：油桶、水塔、燈柱、樹幹、鍋）、`cylinder_h`（橫向圓柱：管線）、`dome`（整體圓鼓）、`flat`（只有極薄的邊，看板、塗鴉、刻痕牆）。每個道具的輪廓放在 `qwen_props.json` 的 `normal_profiles`（沒列的用 `normal_default`），單一道具要微調用該項的 `"normal": {"profile": ..., "relief": ..., "detail": ..., "gate": ...}`；`"profile": "legacy"` 保留舊的亮度推算。明暗細節有「閘門」（`gate`），小於閘門的亮度差不算，所以平面不會出現假凹凸。**不需要下載模型**（使用者 2026-10-04 決定不下載深度估計模型）。改了輪廓表後用 `python tools/assets/qwen_props.py --no-gen` 全部重算（用快取的原圖，不開 ComfyUI）。對照工具：`godot --path . res://tools/assets/preview_prop_lighting.tscn -- --ids=a,b --old-normals=<舊法線資料夾> --out=<png>`，上排舊法線、下排新法線，同一組側光。
- **伏筆物件要放大貼圖**：身高刻痕牆、蠟筆畫、窗外照片等有小字或小人影的，在清單用 `"texture_scale": 12～16` 讓細節看得清楚（`.tres` 的邏輯尺寸不變）。
- **窗光抽取**：`glow` 規則（`neon` 高亮高彩度、`beacon` 純紅、`screen` 亮面、`warm` 暖光窗、`console`…）從生成圖抽出發光層；純紅像素會被改成純紅，窗光生命著色器才會讓它明滅。
- **畫面顆粒只給特殊情境（BG-27）**：一般關卡的光影設定（`data/lighting`）與一般舞台都不加顆粒；回憶、訊號干擾這類情境才用，光影設定要填 `grain_reason`、舞台的 grain 圖層要填 `reason`，否則資料檢查不通過。
- **動畫都是 `PropData` 欄位＋著色器**（清單的 `data` 寫進 `.tres`）：`sway`＋`sway_hang`（懸掛物頂端固定）、`glow_life`（信標明滅、區塊閃爍）、`glow_scan`（螢幕掃描帶）、`ripple`（水窪漣漪）、`steam`＋`steam_offset`（只在畫面內冒蒸汽）、`flicker`；舞台圖層有 `pulse`（柔光脈動）與 `motes`（塵粒）。新增動畫先看有沒有欄位可用，沒有再加欄位，不要寫每影格腳本。
- **舞台圖要對齊地板**：`bg(name, dy=…)` 位移到圖中的地板線等於舞台的地板（角色腳底 y≈ 250～292）；圖偏暗時用 `modulate` 大於 1 提亮（HDR）。
- **啟動與卡死自動重試（BG-9）**：不要手動敲啟動指令或手動殺程序。`powershell -File tools/comfyui/start_comfyui.ps1`（`-Restart`、`-Stop`、`-Safe`）用固定參數啟動並等到伺服器可用才回傳。生成工具經 `comfy_api.run()` 呼叫時，伺服器沒開會自動啟動；**伺服器沒回應、一段時間沒有任何進度（預設 300 秒，冷啟動 900 秒）、log 出現顯示記憶體不足、系統記憶體持續耗盡（低於 0.4 GB 超過 90 秒）**時，自動重啟並重送該工作，最多 3 次（`COMFY_MAX_RETRIES`）。記憶體不足後重啟會改用 `-Safe`（每個工作後卸載模型，慢但穩）。重試用完會丟 `ComfyFailure` 並把工作寫進 `assets_src/work/comfy_failures.log`，`qwen_props.py`／`qwen_scenes.py` 遇到就停止，不會無限等待。同一組種子、提示詞、尺寸、參考圖的圖已經生成過就直接重用，重跑批次只做沒做完的。同一時間只允許一個生成端（檔案鎖）。自我檢查：`python tools/comfyui/selftest.py [--kill-at N | --freeze-at N --stall-s 25]`。
- **GPU 與記憶體**：預設參數**不加** `--disable-smart-memory`（2026-10-04 實測：模型常駐，小圖每張 18 秒，加了會每張 49 秒且每張從硬碟重讀約 16 GB，硬碟滿載）。第一次載入模型要 2～3 分鐘，那段時間系統可用記憶體會掉到接近 0，這是正常的尖峰，不要在這時候同時開別的重度程式。ComfyUI 跑的時候不要同時開 Godot 截圖／匯入（12 GB 顯示記憶體會 OOM）；**用完請 `start_comfyui.ps1 -Stop`**，它常駐會佔用約 13 GB 記憶體。
- **清單檔會被執行中的工具改寫**（記住新錨點）：批次還在跑時不要編輯 `qwen_props.json`，等它結束。
- 匯入後 `.import` 檔沒有對應圖的孤兒要刪掉（會讓關卡載入時噴 ERROR）。

### 關卡固定物件用程式畫（BG-21）

門、梯子、提示牌、開關箱、可擊碎牆、閘門這類又小又規則、還要能平鋪的東西，不走 Qwen：`python tools/assets/cel_fixtures.py [--sheet <png>]` 用程式畫到 `art/environment/fixtures/`（每世界像素 8 貼圖像素），畫完跑 `texture_import.py` 再匯入。遊戲端用 `FixtureArt.attach(物件, id, 左上角, 世界尺寸, 是否平鋪)` 墊在物件後面；會發光的狀態燈、符號不畫進貼圖，由物件自己用自發光疊上去。新貼圖比原本的亮線暗，互動物要留一條淡亮線（梯子扶手、提示牌螢幕），暗處才找得到。清單與缺口見 `design/20-campaign-experience/FIXTURE_ASSETS.md`。

### 場景燈具（BG-36）

場景燈（關卡地圖上的 `*`）用的是畫出來的燈具，和擺設同一套流程，另外多一份款式資料：

- 圖：`assets_src/pipeline/lamp_fixtures.json`（`python tools/assets/qwen_props.py --pipeline lamp_fixtures [--only lamps__<款式>] [--no-gen]`）。提示詞要寫「燈是亮的、發光部位是畫面最亮的地方」；`height_m` 填真實高度；`light_from_glow: true` 讓光從發光部位的中心出發（工具算出 `light_offset`）；`glow` 依燈色選規則（冷白用 `white`、暖色燈泡 `bulb`、紅燈籠 `red_lantern`、霓虹 `neon_tube`…），暖色規則會把黃色的支架也算進去時改用 `white`。
- 款式：`data/environment/lamp_fixtures.json` 每款一筆：`mount`（ceiling 吊天花板、wall 裝牆上、pole 立桿、ground 落地）、`pole`（周圍沒有天花板與牆時能不能掛桿子：`arm` 掛在橫臂下、`post` 鎖在桿子上）、`pole_at`、`shaft`、`radius`、`energy`、`emit`（長條發光面的寬度比例）、`aim_x`（光錐偏向）。
- 每個區域用哪幾款：該區光影設定（`data/lighting/*.tres`）燈風格的 `fixtures`，至少兩款；戶外的區域要有能立桿或掛桿子的款式，不然整區只剩備用的路燈。
- 看結果：`godot --path . res://tools/lamp_gallery.tscn -- --out=<絕對資料夾>` 拍每一款亮與熄滅（含掛桿子的樣子，旁邊的白條是主角身高）；`tools/scene_tour.tscn` 拍實景；`tools/light_pool_probe.tscn` 量光池。
- 使用者的標準（2026-10-11）：戶外的燈約 4 公尺高（關卡地圖上離地 8 格左右），不要三倍主角高的桿子；光錐與光暈**不能有邊線**（`LightShaft` 預設給玩法用的光錐比較飽滿的橫切面，照明用的燈設 `crisp = false`）；不要在光裡放模仿光線的粒子，粒子要有理由（快壞的燈打火才掉火花）。
- 踩過的坑：燈具要畫在擺設那一層（`WorldLayers.PROPS`），預覽工具的牆也要放在背牆層，否則燈具被牆蓋住只看得到光；冷白的燈照在紅磚牆上看起來很暗（紅牆不反射藍綠光），紅牆的區域以暖色款式為主；發光層疊加強度太高會把整個燈具糊成一團白，維持在 1.2 左右。

### 會動的器材與依劇情換樣子的擺設（BG-37、NE-240）

- **有活動零件的器材拆開生成**：機身一張、活動零件一張，由程式接在一起轉動。提示詞要正面描述機身沒有那個零件（「the armless body of …, one empty axle socket on its left side and one on its right side … the machine has no arms at all」），零件單獨畫成水平、樞紐在左端（「one single … lying perfectly horizontal, a pivot ring at the left end … at the right end」）。左右對稱的零件用同一張圖鏡像。序章訓練器就是這樣做的：清單 `assets_src/pipeline/training_fixtures.json`，接點、燈號位置與三個姿勢的角度在 `data/environment/training_art.json`，新增器材只改這兩份資料。
- **狀態用燈號表示，不整件變色**；燈畫在器材上真的會裝燈的地方（籠燈、感應頭、支架接頭），不要浮在物件上方。三種狀態除了顏色，形狀或亮滅也要不同（空心圈、實心加緩慢起伏的光暈、實心加勾），色覺辨識才不會只靠一種顏色。起伏一個來回 1 秒以上，不閃。
- **命中的閃光不要用一顆圓蓋住物件**：改用小的四芒星，畫在實際接觸的位置。
- **看結果**：`godot --path . res://tools/training_art_probe.tscn -- --out=<絕對資料夾> [--quality=low|high] [--fallback]`，每一站拍三種狀態、晃動與出手，量狀態燈的全白比例（門檻 2%）與本體亮度；`--fallback` 拍沒有圖時的簡單畫法當修前。動作要用實際秒數等，不要用影格數（原生畫面每秒幾百格，等 50 格手臂只轉了一點點，拍到的是半路的姿勢）。
- **擺設跟著劇情旗標換樣子**：地圖的道具項目加 `"react": "<id>"`（關卡產生器 `a.prop(..., react='<id>')`），內容寫在 `data/environment/prop_reactions.json`：狀態燈依旗標換色、出紙口送出一張紙。進關卡時旗標已成立就直接是結果，不重播；只管畫面與聲音，不寫旗標。連續畫面：`screenshot.tscn -- --scenario=prop_reaction`。
- **換樣子、開度指針與自帶的光（BG-41～45）**：反應還可以寫 `swap`（旗標成立時整件換成另一件：收起的梯子換成放下的、關著的配電盤換成打開的；`align` 選同底邊或同頂邊，`offset` 再位移幾個像素）、`dial`（一根開度指針慢慢轉過去，閥門類用）、狀態燈的 `light_at`（光從擺設中間出發，燈的顏色照在整件擺設上）。兩個狀態的圖分開生成時，`height_m` 要讓**共同的部分一樣大**（箱體、梯身），不是讓兩張圖一樣高：打開的配電盤多了一片門板，整張照原高度放會比關著的箱體大四分之一。連續畫面：`screenshot.tscn -- --scenario=mechanism_states`（每個旗標成立前後各一張；主角要站在機關左邊幾格，鏡頭往前偏，機關才在畫面中間；敵人要停住，不然受擊的紅屏會蓋住畫面）。
- **暗處的互動物件要自己帶光**：場景本來就暗的區域（廣場、泵室、門禁大廳壞掉的燈下），新擺設放進去只剩輪廓。會亮的東西（崗亭、爐火、烘燈、視窗）在清單的 `data` 加 `light_color`、`light_radius`、`light_energy` 並設 `light_from_glow`；機關用狀態燈的光。能量 0.5～0.9、半徑 50～90 就夠，紅光照在藍灰的圖上很暗，預設狀態要用偏橘的紅。
- **出入口換成擺設（貨梯、梯子）時**把出入口樣式設成 `hidden`，同時確認擺設在實際光影下看得到，否則玩家找不到出口。

### 擺進關卡時踩過的坑（2026-10-12）

- **Windows 上跑關卡產生器要加 `PYTHONUTF8=1`**（`PYTHONUTF8=1 python tools/level/build_ch1.py`）。不加會在寫到一半時因 cp950 編碼中斷，留下半套輸出。產生器在 Windows 寫出的是 CRLF，`git status` 會把整章的檔案都列成已修改；內容沒變的用 `git diff --quiet -- <檔>` 判斷後 `git checkout -- <檔>` 還原，只留真的有變的。
- **掛在牆上的擺設要寫 `support='wall'`，而且那一格後面真的要有牆**：沒寫會被當成浮空（`prop_floating`）、落在背牆的窗洞上會是 `prop_wall_missing`，兩種都只記一行警告就略過不擺。擺完看巡覽的 log 有沒有「支撐無效」。
- **燈會被光影風格抽成壞掉的**：每份光影設定有 `dead_chance`（市集 0.15、設施 0.4），依燈的位置決定，同一格每次都一樣。新加的燈沒亮先查這個（讓燈亮著要換一格），不要以為是資料沒寫進去。
- **燈不是越多越好**：燈距小於光池直徑時光池連成一片，光池量測的倍數會掉到 1 左右（序章試貨區 7 盞是 1.04，5～6 盞、重點區之外間距 20 格以上是 3～8）。燈跟著「玩家要看的東西」放，其他地方留暗。
- **燈正下方的地面邊緣對比會掉**：牆被照得越亮，地面那條亮邊相對就越不明顯（序章有一格從 3.9 掉到 0.98）。巡覽 `--player` 的取樣點在每格中央，燈避開那裡或往旁邊移兩三格就回到門檻以上。
- **`ground` 擺設落在該欄「由上往下第一個站得住的面」**：那一欄上方有平台就會落在平台上，不是地面。要放地面就挪開一欄，或用 `y` 指定列。
- **擺設要對準互動點**：`x` 是左邊那一欄，寬的擺設用 `dx`（世界像素）把中心對到互動點那一格的中間；`dy` 可以微調掛牆的高度。窗台離地約 1 公尺、告示離地 1.3～1.6 公尺，用列數換算（一格 16 像素約 0.53 公尺）。
- **發光規則 `warm` 會把黃黑警示條紋當成燈**（貨梯底座亮成一排黃色短線）：有警示條紋的擺設改用只取燈色的規則（例如只取高亮度、低彩度的冷白）。
- **帶 `--quality` 的巡覽不要中途停掉**：它開始時把光影品質寫進玩家的設定檔、結束時才還原，中途停掉會把設定留在「低」，之後所有原生截圖（包括別的工作階段的）都是低品質。真的停了就檢查 `%APPDATA%/Godot/app_userdata/Nest Egg/settings.cfg` 的 `light_quality`（2＝高）。停背景批次時連同它啟動的 Godot 一起確認，否則腳本會接著跑下一步。
- **這台機器（Arc B580）生成一張道具約 2 分鐘**：採樣只要 40 秒，其餘是文字編碼器與主模型輪流載入。11 張約 20 分鐘，期間可用記憶體會掉到 1 GB 以下，不要同時跑 Godot 或測試。

### 閃爍的燈與供電狀況（BG-35）

- 燈的狀態（穩定、接觸不良 `loose`、快壞了 `dying`）與閃法在 `data/environment/lamp_flicker.json`：閃法是一串字母，一個字母 0.1 秒，`a` 全暗、`m` 正常亮度。改完跑 `python tools/assets/lamp_flicker_patterns.py --show`。**任何一秒內亮度明顯變化不能超過 3 次**（光敏安全），超過的閃法遊戲載入時不採用並記錄；所以「暗、亮、暗」之後要接一秒以上不變。
- 區域要不要閃由燈風格的 `supply` 決定（`stable`、`worn`、`low`；資料裡的 `cycle` 是亮著的燈依序輪到的狀態）。新的電力不足區域（下水道、機房）只要在該區的光影設定填 `supply = &"low"`。
- 設定的「減少閃光」打開時改用 `calm`（緩慢起伏，一個來回至少 2 秒）。新增任何會閃的東西都要有這條退路。
- 快壞的燈的電流聲是音效 `lamp_buzz`（整關共用一個聲道，跟著最近的那盞）。
- 驗證：`godot --path . res://tools/lamp_flicker_probe.tscn -- --out=<絕對資料夾> --level=<關卡> [--reduce-flashes]` 連拍並統計；`tools/ch1_readability_check.tscn -- --lamps=dim` 在燈最暗時量可讀性。
- 踩過的坑：量測工具的視窗會吃到鍵盤與滑鼠，使用者同時在玩遊戲時主角會被移動，工具會回報「取樣無效」，重跑即可；讀設定不要每盞燈每影格讀，接設定改變的訊號後重讀一次。

### 牆上的影子（BG-34）

- 角色（有腳下接觸陰影的）自動會依光源在背牆上投影。**擺設要投影就在它的 `.tres` 加 `wall_shadow = true`**：只給離牆站著的（推車、桌椅、木箱、機車、盆栽）；貼在牆上的（鐵捲門、門、招牌、水管、告示）不要加，會像浮在牆前面。自己會發光的擺設（`light_radius` 大於 0）即使加了也不投影。
- 沒有背牆的地方（露天的天空）不會有影子；影子只在光影品質中、高出現。
- 影子在槍燈與矮的燈下最明顯，高處的吊燈主要落在腳邊。要看效果：`godot --path . res://tools/wall_shadow_probe.tscn -- --out=<絕對資料夾> --level=<關卡> --mode=lamp,gun,perf,reenter`（每張都有影子開與關；`perf` 量 12 個敵人的耗時）。
- 新的光源只要用 `LightKit.create_point_light`（預設會登記）就會讓角色投影，不用另外接。

### 近戰武器的圖與刃光（NE-260）

- 清單 `assets_src/pipeline/melee_weapons.json`（提示詞、種子、`span` 武器座標的範圍、`grip_zone` 握把範圍、`glow` 發光規則、`glow_tint`、`light` 刃光）。`python tools/assets/melee_art.py [--only <id>] [--no-gen]` 生成並寫出 `art/weapons/melee/<id>.png`、`_glow.png` 與 `data/weapon_art/melee.json`，同時重畫掉落物（`art/items/world/<id>.png`）與已有專屬檔的背包圖示。**掉落物與圖示不要再用 `tools/art/build_world_items.py` 生成**（清單裡標了 `derived`，那支工具會略過），否則手上和地上會是兩把不同的武器。
- `span` 決定圖在遊戲裡多長：握把在 0、刃尖朝 +x，圖的寬度剛好蓋住這一段。要換圖就換提示詞與種子，不要改 `span`（招式的距離是照它調的）。
- 模型會把「發光的刃口」畫成銀色：用 `glow_tint` 把發光層染成武器的顏色。提示詞要寫「handle at the left end, tip at the right end」，工具仍會檢查並自動左右翻轉。
- 新增一把近戰武器：清單加一項、跑工具、匯入；沒有圖的武器會退回程式畫的線條，不會壞，也沒有刃光。
- 驗收：`godot --path . res://tools/melee_art_probe.tscn -- --out=<絕對資料夾> [--tag=名稱]`，每把拍待機、每一段招式、蹲、空中、衝刺、掉落物與圖示，並量刃光亮度、暗處敵人被照亮多少、主角頭部全白比例（門檻 2%）、減少閃光有沒有生效。

## 9. 場景包：每個場景的背景與專屬物件（BG-11）

大綱（`design/13-story-v2/OUTLINE.md` 第 5 節）的每個場景有一張背景圖與一包專屬物件，放在共用道具庫之外：

| 項目 | 位置 |
|---|---|
| 背景圖（1536×864 WebP，亮點另存 `_glow.webp`；已畫好光影，所以只乘光影預設的背景色調，不再乘環境光） | `art/environment/scenes/<場景 id>.webp`，清單 `assets_src/pipeline/scene_bgs.json`（`python tools/assets/qwen_scenes.py --pipeline scene_bgs`） |
| 專屬物件（`<場景 id>__<物件名>`，與共用道具同樣有 `_n` 與 `_glow`） | `art/environment/scene_props/<場景 id>/`，資料 `data/environment/scene_props/<場景 id>/*.tres`，清單 `assets_src/pipeline/scene_props.json`（`python tools/assets/qwen_props.py --pipeline scene_props`） |

- 新增場景：在兩份清單各加項目（提示詞、種子、`fit`／`height_m`、`normal` 輪廓），生成後 `godot --headless --editor --quit` 匯入。素材量有獨立上限（`check_assets.py`：共用 60 MB、場景包 160 MB）。
- 預覽：`screenshot.tscn -- --out=<資料夾> --scenario=scene_packs [--scene=<id>] [--lighting=<預設 id>]`，每個場景一張，並印出物件數與缺圖清單。
- 尚未生成圖的場景在量測時標示「待背景」，不算失敗。

## 10. 驗收清單

- [ ] 來源都在 `LICENSES.json`（CC0 素材），或在 `qwen_*.json` 留有提示詞與種子（生成素材）
- [ ] `python tools/assets/check_assets.py` 通過（大小、授權、調色資料、每件道具都有法線與標示的發光層）
- [ ] 重新匯入後預覽畫廊與實景截圖看過，前後對照已存到 `pm/<專案>/images/`
- [ ] 暗場可讀性量測（§11）沒有比基準更差，光影品質「高」與「低」兩檔都量
- [ ] 新的光影預設或場景背景：在對應表加一行並跑光影預設場景量測（§11）
- [ ] 相關測試套件通過（`--only=EnvironmentSuite,CutsceneSuite,ChapterCutscenesSuite,PropsSuite`；使用者明說要才跑完整套件，完整測試由 CI 負責）
- [ ] 換掉整批素材時做同機前後對照（§12）
- [ ] 票上的驗收條件逐條打勾、補 Commit 段落

## 11. 光影預設與可讀性量測（BG-13、BG-14）

- **光影預設**是 `data/lighting/<id>.tres`（`LightingProfile`：環境光、背景色調、霧、泛光、調色、光源色、角色最低亮度 `character_floor`、輪廓光）。新增只加資料檔；大綱 5.1 的章節畫面進程已建好白天、晴天、洪水夜、塔內等 11 組。欄位說明在 `data/scripts/lighting_profile.gd`，設計在 `design/08-lighting/DESIGN.md`。
- **兩個量測，共用 `tools/contrast_probe.gd`**（對比 = (內 − 外) / (外 + 0.02)，取亮部與剪影較大者；門檻玩家 0.6、地面邊緣 1.0、敵人 0.45）：
  - 區段量測：`godot --path . res://tools/readability_check.tscn -- [--level=level_01] [--quality=low]`，兩章每個區段。
  - 預設量測：`screenshot.tscn -- --out=<資料夾> --scenario=lighting_scenes [--lighting=<id>] [--scene=<id>]`，把玩家與敵人放在場景背景前，對應表 `data/lighting_preview/scenes.json`（預設 → 場景背景）。多印一欄「空處」（沒有角色處的背景起伏）當雜訊底線。
- **亮度分三級（BG-33）**：環境光亮度低於 0.20 是暗、0.35 以上是亮、中間是一般。暗的區域要靠槍燈與場景燈，沒被照到的敵人看不清楚是刻意的；亮的留給安全區與特殊場景。新的區域先決定它是哪一級，再用 `tools/light_pool_probe.tscn` 確認燈下比光池外亮 2 倍以上、用可讀性量測（主角的槍燈朝著敵人）確認看得到。量測工具會每一格把瞄準方向設回朝右：滑鼠在視窗上動一下瞄準就會跑掉，數字會忽高忽低。
- **主角和敵人的補光可以分開**：`enemy_fill_scale`（0.5～1）是敵人補光占角色補光的比例。牆面是中間調的室內，主角要亮（靠白頭髮）、深色的敵人要暗（靠剪影），共用一個值兩邊一定有一邊不過；把敵人的比例調到 0.7 左右。背景很暗的場景維持 1。`readability_check --detail` 看敵人是「暗側」不夠才用這招。
- **調整順序**：先調 `character_floor`（角色補光，資料）；背景太亮或太暗才動 `background_tint`；最後才碰環境光。亮背景（白天、塔內）角色是深色剪影，天生清楚；暗的室內與廠房最容易不足（本批調到 0.5～0.56）。
- **踩過的坑**：
  - 量測框要蓋到角色的頭頂：主角換成骨架後高 58 像素，框還停在 44 像素時白色的頭髮在框外，主角一直被當成暗色剪影量（BG-17 修正；敵人的框維持不動，數字才能和先前的紀錄對照）。`readability_check --detail` 會印出亮部、暗部、周圍與兩側對比，先看是哪一側不夠再調。
  - 取樣點不能站在會把角色推開的東西上（雷射柵欄、尖刺）：工具會回報「取樣無效」，要換欄。
  - 量測框裡角色只占一部分，白天背景下用中位數量「身體比周圍暗」量到的是背景，所以背景夠亮時改用暗部百分位；背景很暗時分母趨近 0，黑對近黑會被放大成高對比，所以維持中位數。不要為了過關改量測，先看截圖。
  - 對比在角色亮度「剛好跟背景差不多」時最低（V 字形）：只加一點補光反而更糟，要嘛不動、要嘛明確推到亮部一側。
  - 閃爍與脈動的燈會讓單次量測忽高忽低，取樣要涵蓋至少一個週期（現為 16 張）；頭目機庫的敵人對比在相同設定下仍會落在兩種狀態，不是設定問題。
  - 預覽時要把關卡自己的後牆、裝飾與前景藏起來（`lighting_scene_scenario.gd`），否則量到的是地形剪影而不是場景背景。
  - 暗場景背景圖本身已經很暗（背景色調再乘就更暗），看不清楚時先查原圖亮度，不要硬拉 tint。

## 12. 效能與記憶體：前後對照的做法（NE-66）

- **用同一台機器、同一份腳本、同樣的關卡位置**量替換前後：`git fetch --shallow-since=<日期> origin main` 補回歷史，`git worktree add /tmp/baseline <替換前的提交>`，複製 `.godot/` 進去加速匯入，兩邊各跑一支量測腳本（每影格耗時、`RenderingServer.get_rendering_info` 的繪製呼叫與貼圖記憶體）。
- **軟體渲染下解析度要縮小**（`--resolution 320x180`）才看得出差異；1280×720 每影格都是同一個固定值（約 133 ms），沒有比較意義。
- **看三個數字**：繪製呼叫、每影格耗時、貼圖記憶體；也量關卡畫面上節點的貼圖估算（寬 × 高 × 4）找最大的幾張。2026-10-04 的結果：替換後繪製呼叫下降、每影格耗時略增、環境貼圖記憶體約 6 倍（見 BG-17）。
- **不要用「截圖時的卡頓」當結論**：截圖瞬間有 100 ms 以上的卡頓。
- 整批量測的負載基準與光影品質三檔的差異見 `design/08-lighting/DESIGN.md` 的「戰鬥負載實測基準」。

## 環境匯入成本（BG-17）

- 原圖與世界尺寸保留，以 Godot 內建無損匯入的 `process/size_limit` 降低貼圖解析度。參數集中在 `assets_src/pipeline/texture_import.json`：以明確世界矩形繪製的道具採受限半解析度，道具至少保留每世界像素 4 貼圖像素；使用區域取樣的地形、前景剪影、立面、舞台與場景整圖保留原尺寸；舞台引用的道具由原尺寸中介資料補償世界大小。視差背景由既有資料記錄原始寬度，依匯入比例補償縮放，保留平鋪尺寸、底邊及擺位。每支加工工具完成後自動套用，直接新增環境圖時匯入前跑 `python tools/assets/texture_import.py`，`check_assets.py` 會拒絕漏套用的圖。只處理環境，不改角色、UI 或舞台家具位置。
- `tools/environment_probe.tscn -- --level=level_01 --quality=low --out=<folder>`：三個固定位置、五隻靜止敵人、固定種子、關閉 vsync，截圖在計時結束後保存。修前／修後／替換前使用同機、同解析度、相同腳本。記錄 renderer 程序貼圖配置與環境匯入 payload（含法線、實際尺寸、格式及 mipmaps），不能以 PNG 大小或未壓縮估算冒充 GPU 記憶體。軟體 Vulkan 明確標示，不與實體 GPU 舊數字直接互比。
- 實體顯示卡上的量法（2026-10-11，Arc B580）：替換前、修改前、現在三份 checkout 各自匯入，同一支 `environment_probe` 複製過去，照「甲—乙—乙—甲」的順序各跑兩次取平均。`--no-characters` 把主角與敵人拿掉，只量環境；含角色的數字會混進角色骨架的耗時，不能拿來判斷環境。`--hide=<類別>` 逐項關掉（背景、雨、霧、擺設…）找出是哪一項在花時間，這個模式只當診斷。顯示記憶體用 Windows 效能計數器的 `GPU Process Memory` 取樣。要單看貼圖解析度對畫面的影響，用同一份程式開兩個 checkout，其中一份把環境貼圖的 `process/size_limit` 全設 0 重新匯入，同位置拍照比對；和舊提交比會混進光影與地圖的改動，看不出來。
- 在低解析度下耗時主要是腳本與繪製指令數，不是貼圖取樣：每影格重畫的東西（雨、粒子）要合併成一次繪製、只處理還活著的部分。
- GPU 工作使用 `python tools/comfyui/gpu_lock.py -- <command>`。鎖跨 linked worktree 共用並支援 Windows／Linux；鎖不卸載模型，ComfyUI 啟停與生成遵循本次 Session 分工。

舞台圖層僅補充來源寬度 metadata，渲染時補償匯入比例；原始家具位置、圖層順序與既有 scale 資料不變。重建舞台資料後，匯入前再執行同一匯入政策，素材檢查會指出缺少的 metadata。

環境渲染路徑目前均為 linear／nearest（沒有 mipmap sampler）；匯入政策因此不配置未使用的 mipmaps。肖像 UI 的 mipmap 取樣不在環境政策內。未來新增環境 mipmap sampler 時須同步政策與同機畫面／記憶體驗收。細長圖縮圖取整若使來源長寬比偏差超過 1%，保留原尺寸。

### 貼圖只留用得到的（BG-32）

- 貼圖快取（`RigLibrary`、`LitTextures`）在換區域與過場結束後會放掉「除了快取以外沒有人在用」的環境貼圖（`TextureRelease`）。**用繪製指令（`draw_texture_rect` 之類）畫貼圖的節點，一定要自己把貼圖存在成員變數裡**：繪製指令只記貼圖的編號、不算有人在用，沒留著就會被放掉，畫出來變成白色方塊（背牆曾經整面變白、加上泛光是一整條白光）。`Sprite2D`、`TextureRect` 的 `texture` 屬性本身就是留著，不用另外存。
- 資料檢查只想知道貼圖在不在、多大時用 `RigLibrary.texture_size(path)`，不要用 `optional_texture`（會把貼圖留在快取裡；啟動時的檢查曾經因此把所有過場舞台圖都留在記憶體）。
- 預載（`AssetPrefetch`）只留現在這個區域的鄰居與它會播的過場用得到的圖；張數上限要裝得下一個區域所有的鄰居，否則走回隔壁時還是得當場重載。
- 量測：`godot --path . res://tools/texture_route_probe.tscn -- [--dwell=300]` 照出入口的順序走一圈，印出每一站的環境貼圖用量、過場舞台圖有沒有殘留、進入時最長的一格、畫面上純白的比例（超過 5% 報錯）。同一支腳本複製到舊版本的 checkout 就能量修前。計時要修前修後交替跑，每次差異可以到 20 毫秒。
- 引用計數怎麼算：`dict[path].get_reference_count()` 會多算一份暫時的引用；先存進區域變數再量，「快取一份＋區域變數一份＝2」才是沒有別人在用。

## 可重現的新 CC0 素材示例（NE-67）

本示例沿用既有 3D→2D→PropData 路線，新增荒地草叢；不替換已定稿的大批素材、不動地圖或舞台家具。Kenney 官方 Starter-Kit-FPS 的 3D 模型及貼圖明確採 CC0，軟體的 MIT 不拿來當美術授權。`manifest.json` 的 `kenney_mod_grass_small` 固定完整 commit 與兩份檔案 SHA-256，fetcher 驗證快取及授權陳述，不能用浮動 main 或授權不明的來源。

1. 選素材並驗證該版本 README 的 **Assets included … CC0 licensed** 陳述；確認模型是草叢而不是程式碼，外部 `Textures/colormap.png` 一併列入。
2. 在 `assets_src/manifest.json` 依 `kenney_mod_grass_small` 格式登記 official `KenneyNL/<repo>`、40 字 revision、asset ID、kind=model、files 的 path/dest/SHA-256。
3. 在 `assets_src/pipeline/props.json` 依 `kenney_sedge` 登記 **新的 id**、model、anchor.size、new.display_name/category/sway、fit、yaw、grade。`build_props.py` 支援 glTF／GLB；沒有模型時失敗，不套用殘留舊 render。
4. 執行以下完整命令（`GODOT` 指向 Godot 4.7；Linux 的 render 命令用 `python tools/comfyui/gpu_lock.py -- xvfb-run -a python tools/assets/build_props.py --only kenney_sedge`；截圖同樣將 Godot 包在 `xvfb-run -a` 內）：

```sh
python tools/assets/fetch_assets.py --only kenney_mod_grass_small
python tools/comfyui/gpu_lock.py -- python tools/assets/build_props.py --only kenney_sedge
python tools/comfyui/gpu_lock.py -- "$GODOT" --headless --editor --quit
python tools/assets/check_assets.py
python -m unittest discover -s tools/assets -p test_fetch_kenney.py
python tools/comfyui/gpu_lock.py -- "$GODOT" --audio-driver Dummy res://tools/screenshot.tscn -- --scenario=asset_pipeline --out=<絕對截圖目錄>
SHARDS=8 tools/run_tests_changed.sh <本票提交前的固定基準>
```

輸出 `art/environment/props/kenney_sedge.png`、`kenney_sedge_n.png`、`data/environment/props/kenney_sedge.tres`，套用既有全域 grade 與 BG-17 匯入政策。尺寸沿 anchor 的高度 18 個世界像素保持，寬度按 silhouette 比例；沒有假冒發光層，低檔關法線、高檔開法線，搖動共用材質。

`asset_pipeline` 在真實第一章市集地圖建立三個 PropNode，拍新增前／低／中／高檔。這是遊戲實景整合預覽；不把驗收用坐標寫進正式 map。正式擺位交 Session 3：`PropLibrary.find(&"kenney_sedge")` 與 `PropNode.setup(data, top_left, flip)`；沿用 `PropData.size` 底邊貼地即可。

需要另外確認新對話自動叫用 Skill。不能在同一個對話重跑命令後聲稱已通過「開新對話」驗收。請使用者開新對話貼原測試提示「幫我換一個新的路燈素材」，檢查 Skill 是否被叫用、是否先選 CC0、是否在保留擺位的情況下加工／匯入／截圖與跑相關測試；本草叢示例證明加工與遊戲接點，沒有證明新對話或另一種路燈來源。
