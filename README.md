# Nest Egg（巢中之卵）

全年齡賽博龐克橫向捲軸動作射擊遊戲，使用 Godot 4.7 製作。目前完成 **第一章「雨夜」**（完整一關 + 頭目 + 劇情）。
所有美術與音效目前都由程式產生（暫代素材），可以直接執行。

## 執行

1. 安裝 [Godot 4.7](https://godotengine.org/download)（標準版即可，不需要 .NET）
2. 用 Godot 開啟本資料夾的 `project.godot`，按 F5

> 渲染器使用 Forward+ 並開啟 HDR 2D 泛光。若顯示卡不支援 Vulkan，可在
> 專案設定 → Rendering → Renderer 改為 `gl_compatibility`（會失去泛光，其餘正常）。

## 操作

| 動作 | 鍵盤滑鼠 | 手把 |
|---|---|---|
| 瞄準 | 滑鼠（360°） | 右搖桿 |
| 射擊 | 左鍵 | RT |
| 格擋 | 右鍵（按住） | LT |
| 換武器 | 滾輪、1～4 直選 | RB／LB |
| 換彈 | R | R3 |
| 快速使用醫療針 | Q | 十字↑ |
| 背包（暫停） | Tab、I | Back |
| 衝刺（無敵） | Shift | B |
| 跳躍（按久跳更高） | Space、W | A |
| 蹲下／從平台落下 | S（＋跳躍） | 十字↓ |
| 近戰／終結技 | F | Y |
| 搭乘／離開機甲 | E | X |
| 暫停 | Esc、P | Start |

所有按鍵都可在 **設定 → 按鍵** 重新綁定（每個動作 2 個鍵盤／滑鼠欄位 + 1 個手把按鈕，衝突時自動互換），音量在 **設定 → 音量**；設定存於 `user://settings.cfg`。

## 第一章「雨夜」

沉港市的雨從不停。為了替弟弟存下船票與手術費，傭兵「凜」接下掮客老K的委託：闖進天穹集團的設施，取回 NEST-07 資料碎片。

| 區段 | 內容 |
|---|---|
| 屋頂巷弄 | 開場過場；移動、射擊、格擋教學 |
| 霓虹市集 | 散射砲；保全、鎮暴員、監視蜂；雨棚平台 |
| 貨運站 | 機甲「壁壘」；貨櫃上的砲台、自爆蟲群、擲彈兵 |
| 集團設施入口 | 室內；雷射柵欄、尖刺、擲彈兵、貫穿光束 |
| 頭目機庫 | 監管者 WARDEN 兩階段頭目戰 → 結尾過場 → 章節結算 |

- 劇情分兩種：**過場**（暫停遊戲、黑邊、逐字顯示，Esc 跳過）與 **無線電**（畫面上方，不中斷戰鬥）
- 5 個檢查點，死亡後從最近的檢查點繼續；三種難度都可完整通關
- 劇本在 `data/story/chapter_01.json`，世界觀與角色見 [劇情設計](design/04-story/STORY.md)

## 遊戲內容

- **3 種難度**：輔助／標準／硬核（生命、殘機、敵人節奏都由資料調整）
- **8 種武器**：6 種實彈（手槍、衝鋒槍、突擊步槍、霰彈槍、榴彈發射器、機甲加農砲）與 2 種能量武器（貫穿光束、電磁軌道砲），有彈匣與換彈
- **消耗品與劇情道具**：醫療針、護盾電池；航的照片、存款晶片、委託單、NEST-07 資料碎片
- **背包**（Tab／I，開啟時暫停）：武器與彈藥、消耗品、劇情道具、角色狀態四個分頁，高解析像素風與動畫
- **1 台機甲**：獨立血量、不同操作手感，被擊毀時彈出駕駛
- **6 種敵人 + 1 頭目**，每種都有不同的攻擊方式與應對方式（見下表）
- **敗北圖鑑**：每種死因解鎖一張卡片並附攻略，取代原作的成人向收集要素
- **教學看板與世界提示**：靠近道具／載具／看板時浮現一句重點說明；選單與 HUD 有精簡 tooltip

| 敵人 | 攻擊 | 應對 |
|---|---|---|
| 天穹保全 | 紅色瞄準線（先追蹤後鎖定）→ 單發 | 線變亮時蹲下或跳躍；殘血可終結 |
| 天穹鎮暴員 | 正面能量盾；蓄力衝撞 | 跳過或衝刺穿越後打背後；誘導撞牆會暈眩失盾；爆炸無視盾牌 |
| 監視蜂 | 頭頂盤旋 → 停頓閃爍 → 俯衝 | 斜上射擊；看到閃爍就橫向衝刺 |
| 哨戒砲台 | 有限轉速雷射追蹤 → 鎖定 → 高速彈 | 鎖定瞬間換位，或用掩體切斷雷射 |
| 自爆蟲 | 高速追擊、貼近引爆 | 遠距離擊破；被擊破的爆炸會炸傷其他敵人 |
| 天穹擲彈兵 | 拋物線砲彈 + 地面落點警示圈 | 離開紅圈；貼近壓制（近距離無法開砲） |
| 頭目 監管者 WARDEN | 點射／跳躍震波／扇形彈幕／召喚（第二階段） | 每招都有預兆；震波落地後核心外露受雙倍傷害 |

## 手感設計（參考業界做法）

- **移動**：土狼時間、跳躍緩衝、可變跳躍高度、頂點滯空、下落加重力、天花板邊角修正、衝刺無敵、擠壓伸展、落地揚塵
- **射擊**：槍口閃光 + 動態光源、HDR 發光子彈與拖尾、彈殼、砲管視覺後座、方向性鏡頭後座、後座力
- **打擊**：頓幀（hitstop）、命中閃白、方向性火花、擊殺光爆、破防標記與終結技
- **鏡頭**：前瞻、垂直死區（小跳不晃）、trauma 震動模型（強度平方 + 噪聲）
- **公平性**：所有敵方攻擊都有預兆，敵人瞄準採「先追蹤、後鎖定」，給玩家反應時間

手感參數集中在 `data/player/player_tuning.tres` 與各武器 `.tres`，在編輯器 Inspector 直接調整即可。

## 專案結構

```
autoload/      全域服務：Settings、InputBindings、EventBus、GameState、DefeatCodex、Story、Fx、Sfx、ProjectilePool
core/          可重用框架：StateMachine、HealthComponent、Hurtbox、ContactHitbox、WeaponSystem、LightKit、Palette
art/           骨架、角色零件、武器、頭像（PNG + JSON）
data/          所有遊戲數值（.tres）、關卡地圖、劇本、圖鑑卡片（JSON）
game/          遊戲物件：player、enemies、vehicles、projectiles、pickups、hazards、level
ui/            HUD 與各畫面（主選單、暫停、失敗、過關、圖鑑），ui/inventory 是背包（分頁、卡片、詳情面板）
tests/         無頭冒煙測試
tools/         開發工具（測試腳本、自動截圖、美術繪製、關卡產生器）
design/        設計文件（決策與理由）
pm/            票券（需求、驗收、交付紀錄）
```

## 架構重點

- **資料驅動**：武器、敵人數值、難度、玩家手感、關卡都是資源檔；新增內容大多不用改程式
- **元件化戰鬥**：`HealthComponent` + `Hurtbox`（可設格擋 `guard` 與傷害倍率）+ `ContactHitbox`，玩家／敵人／載具／陷阱共用
- **背包**：分頁是獨立的 `InventoryPage`，清單分頁共用 `CardListPage`（卡片＋詳情面板，資料轉成 `InventoryEntry`）；新增分頁只要繼承並在 `InventoryScreen._create_pages()` 加一行
- **事件匯流排**：HUD、圖鑑、統計只透過 `EventBus` 溝通，遊戲物件被移除也不會出錯
- **狀態機**：`StateMachine` 以 Callable 註冊狀態，所有敵人與頭目共用
- **效能與記憶體**：子彈物件池（有上限）、單節點粒子場（固定容量環形緩衝）、固定數量光源池、地形矩形合併、靜態繪製分塊（光源只重繪附近區塊）、畫面外敵人休眠
- **容錯**：資源遺失或格式錯誤時會記錄錯誤並退回安全預設值，不讓遊戲崩潰；關卡解析的問題會列出具體位置

## 角色美術（骨架綁定）

人形角色（主角、敵兵、頭目）都是「骨架＋零件圖片」：動作由程式驅動，美術只要畫零件。
目前的零件圖是程式繪製的暫代美術；要換成正式美術（例如 ComfyUI 產出），依
[美術交付規格](design/03-art-pipeline/ART_PIPELINE.md) 畫好同尺寸、同支點的 PNG 覆蓋即可。

- 重新產生暫代圖／對位參考圖：`godot --path . res://tools/art/paint_assets.tscn -- --guides`
- 預覽所有角色與動作：`godot --path . res://tools/rig_preview.tscn`

## 擴充指南

**新增武器**：複製 `data/weapons/*.tres` 修改數值（子彈規格在 `data/projectiles/`），在關卡 `legend` 指定一個字元即可放置。

**新增敵人**：
1. 在 `game/enemies/` 新增腳本 `extends Enemy`，實作 `_setup_states()`（用 `fsm.add()` 註冊狀態）與 `_draw_body()`；需要時覆寫 `_guard()`、`_draw_overlay()`、`_on_defeated()`
2. 新增 `data/enemies/xxx.tres`，`behavior` 指向該腳本
3. 在 `data/codex/defeat_cards.json` 加入對應死因卡片（測試會檢查）

**新增 / 修改關卡**：`data/levels/level_01_map.json` 每列一個字串、可直接編輯；字元說明見 `data/scripts/level_data.gd`。教學看板文字在 `level_01.tres` 的 `hints`，劇情觸發點（地圖上的 `&`）對應 `story_triggers`。
第一關地圖由產生器以區段組合而成，並自動檢查每段都跳得過去：`python3 tools/level/build_level_01.py`（改區段後重跑即可覆寫 JSON）。

**新增光影設定**：複製 `data/lighting/*.tres` 修改環境光、背景色調、霧與泛光，再到關卡資料的 `lighting_zones` 指定「從哪一欄開始套用、過渡幾欄」。事件用 `EventBus.lighting_override_requested` 暫時覆蓋（停電、警報），`lighting_override_cleared` 結束。發光的東西（子彈、霓虹、危險物）請呼叫 `LightKit.mark_emissive(self)`，否則會被環境光壓暗。光源預算與品質：場景光源（`LightKit.create_point_light` 預設會加入預算群組）由 `LightBudget` 管理，上限與品質檔位見 `core/light_quality.gd`；新的光影效果請依 `LightQuality` 的查詢函式決定要不要啟用。暗場可讀性：每份光影設定要有 `character_floor`（角色最低亮度），`LightingProfile.validate()` 會檢查；改完光影後執行 `godot --path . res://tools/readability_check.tscn`（需要可渲染環境）量測每個區段的玩家與地面亮邊對比。法線貼圖：角色零件與地形面板旁放同名的 `<名稱>_n.png`，由 `LitTextures.load_texture` 組成 CanvasTexture；缺檔時改用平面貼圖並記錄一次提示。自動產生：`godot --headless --path . res://tools/art/paint_normals.tscn`（會覆蓋同名的 `_n.png`；換成手繪法線貼圖後，請用 `-- --only=rin,weapons,materials` 指定要重畫的範圍）。輪廓光由 `LightingController` 的一盞平面點光源提供，顏色與強度在光影設定的 `rim_color`／`rim_energy`；低品質檔位不使用法線貼圖。設計見 [光影設計](design/08-lighting/DESIGN.md)。

**新增劇情**：在 `data/story/*.json` 加入場景（`mode` 為 `cinematic` 或 `radio`），關卡以 `Story.play(場景 id)` 播放。過場每段至多 6 句、通訊每段 1～2 句，講者要有頭像（`tools/art/paint_assets.tscn -- --only=portrait_<id>` 可產生暫代頭像），啟動時 `Story.validate()` 會檢查。新章節：新增 `chapter_XX.json`、把路徑加進 `Story.CHAPTER_PATHS`，場景 id 用章節前綴（`c2_…`）避免重複，關卡資料的 `chapter` 指向該章。

**新增敵人**：複製 `data/enemies/*.tres`（數值、`ability_*` 依行為解讀）；要新行為就寫一個繼承 `Enemy` 的腳本（預兆用 `_start_telegraph`、護盾由基底處理）。每個攻擊來源（`contact_source_id`、子彈的 `source_id`、程式裡改過的來源）都要在 `data/codex/defeat_cards.json` 有卡片，測試會檢查。迷彩獵手用 `LightKit.light_level_at()` 判斷被燈照到。

**新增可破壞物與機關**：在 `data/props/` 複製 `BreakableData`（箱子、油桶、玻璃：血量、大小、爆炸、掉落）或 `MechanismData`（升降梯、閘門、開關、電力開關），再在關卡資料的 `legend` 把一個字元對應到它，就能在地圖上擺。開關與閘門用相同的 `channel` 連動；電力開關的 `channel` 是電力區域 id。要在檢查點存取狀態的新物件，加入 `WorldState.GROUP` 並實作 `state_key()`／`capture_state()`／`restore_state()`。會消耗電力的物件用 `PowerGrid.is_powered(self)` 判斷。

**新增義體能力與補給點**：義體能力複製 `data/abilities/*.tres`（種類 OVERCLOCK／EMP、耗電、冷卻、持續、範圍、價格），需要新種類時在 `CyberSystem` 加一個分支；背包的「義體」分頁自動列出、解鎖與裝備，預設使用鍵 C。補給點是 `data/shops/*.tres`（`ShopData.stock` 是消耗品清單，價格取自 `ConsumableData.price`），關卡 legend 把字元對應到它；操作 E 開啟貨架（`ShopScreen` 繼承背包畫面，只有一個分頁）。

**新增武器改裝**：在 `data/upgrades/` 複製 `WeaponUpgradeData`（效果種類、幅度、價格、說明），背包的「改裝」分頁會自動列出每把攜帶武器可買的項目；改裝只改彈匣、散佈、換彈，不改傷害與射速。信用點（`Progression.credits`）來自地圖上的信用點堆（legend 對應 `CreditPileData`）、敵人的 `credit_value`、箱子的 `credit_drop`。成長進度（信用點、改裝）跟著檢查點，狀態快照見 `Progression.snapshot()`。

**新增收集品與隱藏房間**：文件與錄音就是 `category` 為文件／錄音的劇情道具（`chapter`、`body` 全文不超過 220 字、可選 `play_scene` 撿到時播通訊，取得時機固定 MANUAL），在關卡 legend 把字元對應到它就會變成可撿的收集品；已收集的不再出現，每章的總數由資料決定，背包與結算畫面會顯示進度。隱藏房間就是用裂縫牆（`data/props/cracked_wall.tres`）或開關閘門封起來的一間小室。

**新增劇情道具**：複製 `data/story_items/*.tres` 修改名稱、說明與取得時機（開局、某個劇情場景播完、擊敗頭目，或由程式取得），圖示放在 `art/items/icons/<icon>.png`。道具跟著本輪進度：重開關卡與從檢查點重生都保留，開始新遊戲才重置。
產生暫代圖示（消耗品、劇情道具、武器；不需要 GPU）：`godot --headless --path . res://tools/art/paint_icons.tscn`
產生背包立繪（需要可渲染的環境）：`godot --path . res://tools/art/paint_portraits.tscn`
之後用同名 PNG 覆蓋即可換成手繪像素圖（尺寸見 `core/item_icons.gd`）。

**換成正式音效**：在 `autoload/sfx.gd` 的 `OVERRIDES` 填入 `id → 音效檔路徑`，呼叫端不用改。

## 測試

```bash
GODOT=/path/to/godot tools/run_tests.sh
```

測試分成冒煙測試（`tests/smoke_test.gd`）與功能套件（`tests/suite/test_*.gd`，繼承 `TestSuite`，新功能的測試放這裡，在 smoke_test 的 `_run` 登記一行即可）。
測試會驗證所有資料檔、關卡解析、狀態機、武器配置、骨架與劇本，並實際跑一輪遊戲：移動射擊、撿武器、搭乘機甲、掉坑、
六種敵人 AI、格擋與完美格擋反彈、終結技、每個檢查點、三種難度的頭目戰到過關、死亡畫面。輸出中出現腳本錯誤也會判定失敗。

自動截圖（需要可渲染的環境）：

```bash
godot --path . res://tools/screenshot.tscn -- --out=/absolute/output/dir [--scenario=all|settings|mouse_aim|block|story|story_ch2|props|inventory]
```
