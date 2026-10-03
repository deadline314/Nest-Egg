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
- 角色（`art/characters/**`、立繪、敵人）由別人處理，**不碰**。

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

清單：`assets_src/pipeline/materials.json`，每筆 `{id, source, tile_world, grade{brightness,saturation,tint,contrast,gamma}, normal_strength, lip}`。

- `id` 必須對應 `data/environment/materials/<id>.tres`（腳本會把 `texture_scale` 寫回資料）。
- 解析度 = `texture_scale`（預設 8）× `tile_world`（一次重複涵蓋的邏輯像素）。上限 768 px，超過會報錯。
- 輸出 `<id>_{body,top,side}.png` ＋ `_n.png`（OpenGL 法線，Y+ 向上，與 Godot 2D 相同，直接用）。頂面與側邊由本體裁切並加邊緣斜面。
- 非正方形的無縫貼圖（例如 2:1）會堆疊成正方形，仍然無縫。
- 遊戲端：`TerrainMaterialData.texture_scale`、`EnvZone.interior_scale`（室內牆面貼圖用的是 `*_body.png`，倍率要跟著改）。

## 4. 天空（`process_sky.py`）

清單：`assets_src/pipeline/backdrop.json` 的 `skies`，每筆 `{id, source(HDRI), elevation:[低,高], yaw_deg, grade, horizon_glow, top_fade}`。

- 從 360° 全景切出「地平線以上」的長條，左右天生無縫；**低仰角會切到建築、樹與路燈**，把 `elevation` 下限拉高（城市全景要 ≥ 50°）。
- 輸出 WebP（照片雜訊用 PNG 會好幾 MB）；`BackdropLayer.texture` 已允許 `.webp`。
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

### 套件模型（立面、管線、電線桿：一個 glTF 裡排著很多件）

1. 用 `render_model.tscn` 以大寬度（2400）渲染整個套件，`glow: ["_glass"]`。
2. `kit_cells.py <名稱>` 偵測每一件、輸出編號預覽 `assets_src/work/kits/<名稱>_cells.png` 與 `_cells.json`。**用編號挑件，不要手量座標**。
3. 立面用 `build_facades.py`（清單 `assets_src/pipeline/facades.json`）：一個模組＝一個或多個 cell 左右併排、拉伸到模組尺寸（寬 64、一樓高 40、標準樓層 32、女兒牆 8，× `texture_scale`）。窗戶：玻璃遮罩先膨脹再標記，**整扇窗**（不是每片玻璃）依 `light_chance` 亮或暗、顏色從 `light_colors` 抽、固定亂數種子（重跑結果一致）；保證每個標準樓層至少一扇亮窗（資料承諾有自發光層）。
4. **`light_gain` 要壓低（0.5）**：大面積亮窗在玩家附近會把暗場對比吃掉（貨運站區段玩家對比 1.35 → 0.1），調到 0.5 才回到 1.0 以上。

## 6. 放進遊戲之後必做

1. **重新匯入**：`godot --path . --headless --import`。換掉同名 PNG 後 Godot 仍用舊的匯入快取，不重匯入會看到舊圖、測試也會量到舊尺寸。
2. 看畫面（遊戲很暗，直接截圖看不出材質）：
   - `tools/assets/preview_materials.tscn`：16 種材質各一塊，受光與法線都在，畫法與 `Terrain` 相同。
   - `tools/screenshot.tscn -- --scenario=spots:level_01:<標籤> --brightness=1.0`：關卡實景；`--brightness` 只在拍攝時調亮度並還原。
   - 對照用的「換之前」：`git worktree add --detach <暫存路徑>/base HEAD`，在裡面匯入並拍同樣的點；`tools/assets/compare.py` 把前後並排。
   - `tools/assets/contact_sheet.py`：渲染出的道具貼圖（反照率＋法線）一覽。
3. **暗場可讀性量測**：`godot --path . res://tools/readability_check.tscn -- --level=level_01`。角色（玩家）與背景的對比不能掉。亮窗、亮牆、亮道具都會拉低它；掉了就降亮度或 `light_gain`。先用沒動環境的版本量一次基準：第一章「屋頂巷弄」在換素材之前就低於門檻（與角色美術有關），別把它算在環境素材頭上。
4. `python tools/assets/check_assets.py`：`art/environment` 總量 ≤ 60 MB、單檔 ≤ 1.5 MB、每個清單來源都有 CC0 授權紀錄。
5. 完整測試：`GODOT=<路徑> tools/run_tests.sh`。**要跑 20～30 分鐘，只在全部素材都定案後跑一次**；跑的時候不要改 `art/`、`data/`、`game/`、`tests/`，否則結果作廢。
6. 舊的暫代圖產生器 `tools/art/paint_environment.tscn` 會覆蓋同名檔案；清單裡有的項目它會自動略過，但新增項目時記得把 id 放進清單。

## 7. 風格與調色

- 寫實素材比原本的像素美術亮、彩度低、細節多，必須壓亮度、偏冷、保留法線細節；亮度以「原本那張的平均亮度」當目標（原材質平均亮度約 0.15～0.3）。
- 窗光、霓虹靠自發光層與加法光；牆面本身要暗，讓角色與霓虹有對比。
- 夜景色盤：深藍紫底、洋紅與青色點綴，見 `core/palette.gd`；不要讓背景比角色搶眼。
- 寫實背景與動漫賽璐璐角色的畫風落差由 NE-66（統一調色與光影整合）處理；落差太大時保留材質與天空，道具改回手繪輪廓。

## 8. 尚未做、做法還沒驗證的部分

遠景天際線與中景樓群（NE-61）、樹木與植被（NE-64）、過場動畫舞台（NE-65）、貨運站與設施道具（NE-63）。預期做法：樹與道具走 §5 的單件道具流程（樹的多個 LOD 變體要用 `crop` 切開）；遠景用 HDRI 的城市全景切天際線帶、以亮度遮罩去背、窗光抽成 `_glow`；過場舞台沿用同一批天空與背景。實作時回來更新這份 Skill。

## 9. 驗收清單

- [ ] 來源都在 `LICENSES.json`，且是 CC0
- [ ] `check_assets.py` 通過
- [ ] 重新匯入後預覽畫廊與實景截圖看過，前後對照已存到 `pm/Nest-Egg/images/`
- [ ] 暗場可讀性量測沒有比基準更差
- [ ] 完整測試套件全部通過
- [ ] 票上的驗收條件逐條打勾、補 Commit 段落
