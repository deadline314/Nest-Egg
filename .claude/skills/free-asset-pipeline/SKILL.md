---
name: free-asset-pipeline
description: 把免費（CC0）高解析度素材換進 Nest Egg 場景的完整流程：找來源、下載並登記授權、把材質／3D 模型／HDRI 天空加工成遊戲規格（含法線與自發光）、放進資料、調色、驗收。要新增或替換地形材質、建築立面、場景道具、天空、背景、樹木，或要找免費素材時使用。不處理角色、敵人、立繪。
---

# 免費素材替換流程

背景與決策見 `design/11-free-assets/DESIGN.md`；票在 `pm/Nest-Egg/` 的 NE-56～NE-67。這份是**照著做就能動**的操作手冊，每一條都是做過、踩過才寫的。

## 0. 原則

- **只收 CC0**。授權不明、CC-BY、CC-NC、「免費但禁止再散布原檔」（多數 itch.io 免費包）一律不放進專案。
- 主力來源：**Poly Haven**（材質、3D 模型、HDRI 天空，`api.polyhaven.com`，免金鑰）與 **ambientCG**（材質，`ambientcg.com/api/v2`，免金鑰）。Kenney、OpenGameArt 只在缺特定物件時挑用，逐件確認授權。
- 原始下載檔放 `assets_src/raw/`（不進版控，可重抓）；進版控的是加工後的 `art/**`、`assets_src/manifest.json`、`assets_src/pipeline/*.json`、`assets_src/LICENSES.json`。
- **所有加工都由清單驅動、可重跑**。不要手改 `art/environment/**` 裡的成品圖——改清單（調色、裁切）再重跑，否則下次重跑就被蓋掉。
- 調色參數只放清單（JSON），不寫進程式。
- 角色（`art/characters/**`、立繪、敵人）由別人處理，**不碰**。使用者可能同時在改角色美術：驗證環境素材時，用乾淨的 git worktree（見 §6）量測，別把角色變動算進環境素材的帳。
- **不要把照片等級的現實場景放進遊戲**（使用者 2026-10-03：「超突兀」）：真實城市天際線（含看得出地名與招牌的）、實景照片一律不用，`process_backdrop.py` 的 `pano_skyline` 保留但不要用在遊戲裡。遠景、中景用 `city_blocks` 以立面模組組出風格一致的樓群。可用的照片素材僅限抽象的天空與雲（暴雨雲、夜空），且要先調暗調色；不確定時先問。
- **使用者的美術偏好（2026-10-03）**：盡量少用純矩形、方形、單純弧形（半圓頂、拱窗、膠囊窗）；多一點裝飾、特效與動畫。實作上：樓群用階梯、斜屋頂、人字屋頂、切角、尖塔輪廓，屋頂放天線、水塔、碟型天線、通風管與信標；窗戶用切角八邊形加窗格；牆面加電路走線、LED 指示燈、水管、冷氣機、攝影機；窗光邊緣柔化；窗光會閃、信標會明滅、植物會搖。

## 1. 環境

- Python 需要 `pillow numpy scipy opencv-python-headless`（`python -m pip install`）。
- Godot 4.7，路徑慣例 `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`（或設環境變數 `GODOT`）。
- **Windows 的 python 看不懂 Git Bash 的 `/c/...` 路徑**：在專案根目錄用相對路徑執行腳本。
- 工具都在 `tools/assets/`，每支腳本開頭的 docstring 有用法。

## 2. 下載與登記授權

1. 在 `assets_src/manifest.json` 加一筆：`{"id": "ph_tex_xxx", "source": "polyhaven"|"ambientcg", "kind": "texture"|"model"|"hdri", "asset": "<來源網站上的 id>", "use": "用途", "res": "2k"}`。id 慣例：`ph_`／`acg_` ＋ `tex`／`mod`／`hdr` ＋ 名稱。
2. `python tools/assets/fetch_assets.py [--only ID ...]`：下載到 `assets_src/raw/<id>/`，授權（作者、CC0、出處網址）寫進 `assets_src/LICENSES.json`。單項失敗只記錄、不中斷。
3. 找素材：Poly Haven 的 `https://api.polyhaven.com/assets?t=models|textures|hdris&c=<分類>`；`hidden_alley` 是賽博龐克小巷套件（公寓與工廠立面、路燈、冷氣機、電箱、電線桿、鐵閘、捲門），夜景 HDRI 分類是 `night`、純天空是 `pure skies`，ambientCG 用 `full_json?q=<關鍵字>`。
4. 挑素材前先看縮圖或實際渲染：材質要**可無縫平鋪**（腳本會量接縫）；模型要確認是單件還是「套件」（多件排在一起，見 §5）。

## 3. 地形材質（`process_material.py`）

清單：`assets_src/pipeline/materials.json`，每筆 `{id, tile_world, normal_strength, grade, cel{kind, pal, ...}}`。**NE-108 起 16 種全部是程式繪製的賽璐璐畫風**（平塗色塊、深色墨線、硬邊兩色陰影、由左上打光的亮邊與暗邊），不再從 Poly Haven／ambientCG 的 PBR 照片裁切（舊的 `source` 路線程式還在，沒有 `cel` 區塊的項目仍走它）。

- 畫法在 `tools/assets/cel_tile.py`：`Tile` 同時畫顏色與高度圖（高度圖算出法線），所有圖形環繞邊界所以**天生無縫**（接縫量測對線條規律的圖會誤報，例如格柵 `seam 14.99`，以拼 2×2 的實際畫面為準）。`kind`：`plates`（鋼板格：地板、牆板、鉚釘、散熱孔、色帶）、`bricks`、`corrugated`（波浪鋼板，可加鏽斑）、`slabs`（混凝土板、污漬、裂縫，可加塗裝標線）、`asphalt`、`gravel`（屋頂瀝青碎石）、`grating`（格柵）、`glass`（帷幕玻璃）、`rust`。新增種類就在 `PAINTERS` 加一個函式。
- 色盤在 JSON（`pal`：`ink` 墨線色、`tones` 數個底色、`light` 亮邊色、其餘依種類），種子由 `id` 決定，重跑結果一致。色盤直接寫成最終顏色（`grade` 預設不調）；環境光會再壓暗，所以每種材質都要比夜景背景亮、但不搶眼。
- 頂面與側邊：本體裁切後加一條墨線外框、一條冷白亮邊、下半部硬邊變暗（`build_top_cel`／`build_side_cel`）。
- `id` 必須對應 `data/environment/materials/<id>.tres`（腳本會把 `texture_scale` 寫回資料）。解析度 = `texture_scale`（預設 8）× `tile_world`；上限 768 px，超過會報錯。
- 輸出 `<id>_{body,top,side}.png` ＋ `_n.png`（OpenGL 法線，Y+ 向上，與 Godot 2D 相同，直接用）。法線太平就調高 `normal_strength`（有機形狀如柏油、混凝土、鏽蝕用 14～24，規則鋼板 8）。
- 遊戲端：`TerrainMaterialData.texture_scale`、`EnvZone.interior_scale`（室內牆面貼圖用的是 `*_body.png`，倍率要跟著改）。

## 4. 天空（`process_sky.py`）

清單：`assets_src/pipeline/backdrop.json` 的 `skies`，每筆 `{id, width, height, top_fade, cel{seed, palette, bands, wave, stars, orbs, layers, horizon_glow}}`。**NE-111 起 7 張天空全是程式繪製的賽璐璐畫風**（`tools/assets/cel_sky.py`，欄位說明在檔頭 docstring）：硬邊色帶漸層、平塗的雲（雲底較暗的第二色、亮邊）、星星／月亮／太陽、階梯式地平線光暈。圖形都以 ±寬度環繞繪製或用整數個正弦週期，所以左右天生無縫。沒有 `cel` 區塊的項目仍走舊的 HDRI 路線（`source`、`elevation`、`grade`）。

- 輸出 WebP；cel 天空是無損 WebP（平塗色塊只有十幾～幾十 KB）。`BackdropLayer.texture` 已允許 `.webp`。
- 夜空亮度以舊成品的平均亮度為上限（暴雨夜 0.15、城市夜空 0.17），藍天（過場動畫用）可以亮。
- 舊的 HDRI 路線：從 360° 全景切出「地平線以上」的長條；**低仰角會切到建築、樹與路燈**，把 `elevation` 下限拉高（城市全景要 ≥ 50°）。
- 遠景天際線（`process_backdrop.py` 的 `pano_skyline`）：同一個 HDRI 取一段（`span_deg`、`elevation`），接縫處交叉淡化、上緣淡出；亮處（窗光、霓虹）另存 `_glow.webp`。中景樓群（`city_blocks`）用已建好的立面模組疊樓，兩排前後（每排寬度加總剛好一個 tile，左右無縫；寬於一個模組的樓用多個模組並排）、輪廓用 `shape_mask`（階梯／斜屋頂／人字／切角／帶尖塔／側塔／雙塔／針尖／斜切）、每棟有墨線外框、左亮右暗的硬邊明暗，越遠的排用 `haze` 混合偏藍（越淡越偏藍）；屋頂雜物是賽璐璐畫的天線（頂端純紅信標）、水塔、碟型天線、通風管、煙囪、招牌（霓虹）、風管、屋頂雜物貼在**該欄的屋頂線上**（不是整棟的最高點，否則斜屋頂上的雜物會漂浮）。
- 遊戲端：`EnvironmentTheme.sky`（`BackdropLayer`），`LevelBackground` 把它做成慢速視差層壓在程式天空上；缺圖退回程式天空並記錄路徑。
- **背景會被環境光（`CanvasModulate`）與 `background_tint` 壓暗**：圖在遊戲裡看起來比預期暗很多。`BackdropLayer.tint` 可以大於 1（HDR），例如 `Color(1.4, 1.35, 1.5, 1)`。亮度先在圖裡調出細節（對比 1.5～2），tint 只做微調；tint 拉太高只會得到一整片飽和的色塊。

## 5. 3D 模型 → 2D 貼圖

### 單件道具（`build_props.py`）

清單：`assets_src/pipeline/props.json`，每筆 `{id, model(manifest id), crop[x0,y0,x1,y1 比例], fit:"height"|"width", yaw, pitch, glow:[材質名正規式], glow_color, glow_through, render_width}`。

1. `render_model.tscn`（Godot）用正交鏡頭渲染：反照率（含柔和光）、鏡頭空間法線（`_n`，已轉成 Y+ 向上）、可選的自發光遮罩（`_glow`）。
2. 腳本裁切、調色、修邊，寫 `art/environment/props/<id>{,_n,_glow}.png`，並改 `data/environment/props/<id>.tres` 的 `size`（沿 `fit` 的那一軸保持原值，另一軸跟著模型比例）、`light_offset`（等比縮放）、`has_glow`。
3. 道具以**底邊對齊地面**，所以比例改變不會讓它陷進地裡；有 `platform`（單向平台）的道具要保持原本比例，不要直接換。
- 自發光：`glow` 填**發光材質的名稱**（先看 glTF 的 `materials[].name`）。寫實模型的燈泡多半靠 emission 屬性而不是貼圖顏色，所以發光層用單色（`glow_color`）。燈泡包在玻璃裡時加 `glow_through: true`，否則被塗黑的玻璃蓋住。
- **踩過的坑**：`glow` 的正規式 `window` 會連窗框材質一起中（窗框材質叫 `..._windows`），玻璃要用 `_glass`。

- **新增道具**：`props.json` 的項目加 `new: {display_name, category, sway, ...}` 與 `anchor.size`，首次執行會建立 `.tres`；`aliases` 可以不做新圖、只新增一份資料沿用既有貼圖（例如半透明的前景樹）。`anchor` 記住原本尺寸，重跑不會越縮越歪。
- 植物會搖：`PropData.sway`＋`sway.gdshader`（頂端位移、依位置錯開相位、同幅度共用一份材質），不需要每影格腳本。前景植物放在**沒有敵人與危險物的欄**（既有擺放檢查會抓）。

### 建築立面（NE-109 起全部程式繪製的賽璐璐畫風，不再用 Poly Haven 立面套件渲染）

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
- 寫實背景與動漫賽璐璐角色的畫風落差由 NE-66（統一調色與光影整合）處理；落差太大時保留材質與天空，道具改回手繪輪廓。

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
- **窗光抽取**：`glow` 規則（`neon` 高亮高彩度、`beacon` 純紅、`screen` 亮面、`warm` 暖光窗、`console`…）從生成圖抽出發光層；純紅像素會被改成純紅，窗光生命著色器才會讓它明滅。
- **動畫都是 `PropData` 欄位＋著色器**（清單的 `data` 寫進 `.tres`）：`sway`＋`sway_hang`（懸掛物頂端固定）、`glow_life`（信標明滅、區塊閃爍）、`glow_scan`（螢幕掃描帶）、`ripple`（水窪漣漪）、`steam`＋`steam_offset`（只在畫面內冒蒸汽）、`flicker`；舞台圖層有 `pulse`（柔光脈動）與 `motes`（塵粒）。新增動畫先看有沒有欄位可用，沒有再加欄位，不要寫每影格腳本。
- **舞台圖要對齊地板**：`bg(name, dy=…)` 位移到圖中的地板線等於舞台的地板（角色腳底 y≈ 250～292）；圖偏暗時用 `modulate` 大於 1 提亮（HDR）。
- **啟動與卡死自動重試（NE-116）**：不要手動敲啟動指令或手動殺程序。`powershell -File tools/comfyui/start_comfyui.ps1`（`-Restart`、`-Stop`、`-Safe`）用固定參數啟動並等到伺服器可用才回傳。生成工具經 `comfy_api.run()` 呼叫時，伺服器沒開會自動啟動；**伺服器沒回應、一段時間沒有任何進度（預設 300 秒，冷啟動 900 秒）、log 出現顯示記憶體不足、系統記憶體持續耗盡（低於 0.4 GB 超過 90 秒）**時，自動重啟並重送該工作，最多 3 次（`COMFY_MAX_RETRIES`）。記憶體不足後重啟會改用 `-Safe`（每個工作後卸載模型，慢但穩）。重試用完會丟 `ComfyFailure` 並把工作寫進 `assets_src/work/comfy_failures.log`，`qwen_props.py`／`qwen_scenes.py` 遇到就停止，不會無限等待。同一組種子、提示詞、尺寸、參考圖的圖已經生成過就直接重用，重跑批次只做沒做完的。同一時間只允許一個生成端（檔案鎖）。自我檢查：`python tools/comfyui/selftest.py [--kill-at N | --freeze-at N --stall-s 25]`。
- **GPU 與記憶體**：預設參數**不加** `--disable-smart-memory`（2026-10-04 實測：模型常駐，小圖每張 18 秒，加了會每張 49 秒且每張從硬碟重讀約 16 GB，硬碟滿載）。第一次載入模型要 2～3 分鐘，那段時間系統可用記憶體會掉到接近 0，這是正常的尖峰，不要在這時候同時開別的重度程式。ComfyUI 跑的時候不要同時開 Godot 截圖／匯入（12 GB 顯示記憶體會 OOM）；**用完請 `start_comfyui.ps1 -Stop`**，它常駐會佔用約 13 GB 記憶體。
- **清單檔會被執行中的工具改寫**（記住新錨點）：批次還在跑時不要編輯 `qwen_props.json`，等它結束。
- 匯入後 `.import` 檔沒有對應圖的孤兒要刪掉（會讓關卡載入時噴 ERROR）。

## 9. 還沒做的部分

統一調色與光影整合（NE-66）；白房間那排「小腳」仍是多邊形（NE-113）；舊的四個過場舞台（NE-112）與室內道具（NE-114）仍是寫實風或舊圖；道具法線品質（NE-115）。地形材質、立面、遠中景、天空（NE-108、74、76）與樹木（NE-110）已是賽璐璐畫風。

## 10. 驗收清單

- [ ] 來源都在 `LICENSES.json`（CC0 素材），或在 `qwen_*.json` 留有提示詞與種子（生成素材）
- [ ] `check_assets.py` 通過
- [ ] 重新匯入後預覽畫廊與實景截圖看過，前後對照已存到 `pm/Nest-Egg/images/`
- [ ] 暗場可讀性量測沒有比基準更差（基準＝乾淨 worktree 在 HEAD 量一次）
- [ ] 相關測試套件通過（`--only=EnvironmentSuite,CutsceneSuite,ChapterCutscenesSuite,PropsSuite`；使用者明說要才跑完整套件）
- [ ] 票上的驗收條件逐條打勾、補 Commit 段落
