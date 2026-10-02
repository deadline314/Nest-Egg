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

**新增劇情**：在 `data/story/*.json` 加入場景（`mode` 為 `cinematic` 或 `radio`），關卡以 `Story.play(場景 id)` 播放。

**新增劇情道具**：複製 `data/story_items/*.tres` 修改名稱、說明與取得時機（開局、某個劇情場景播完、擊敗頭目，或由程式取得），圖示放在 `art/items/icons/<icon>.png`。道具跟著本輪進度：重開關卡與從檢查點重生都保留，開始新遊戲才重置。
產生暫代圖示（消耗品、劇情道具、武器；不需要 GPU）：`godot --headless --path . res://tools/art/paint_icons.tscn`
產生背包立繪（需要可渲染的環境）：`godot --path . res://tools/art/paint_portraits.tscn`
之後用同名 PNG 覆蓋即可換成手繪像素圖（尺寸見 `core/item_icons.gd`）。

**換成正式音效**：在 `autoload/sfx.gd` 的 `OVERRIDES` 填入 `id → 音效檔路徑`，呼叫端不用改。

## 測試

```bash
GODOT=/path/to/godot tools/run_tests.sh
```

測試會驗證所有資料檔、關卡解析、狀態機、武器配置、骨架與劇本，並實際跑一輪遊戲：移動射擊、撿武器、搭乘機甲、掉坑、
六種敵人 AI、格擋與完美格擋反彈、終結技、每個檢查點、三種難度的頭目戰到過關、死亡畫面。輸出中出現腳本錯誤也會判定失敗。

自動截圖（需要可渲染的環境）：

```bash
godot --path . res://tools/screenshot.tscn -- --out=/absolute/output/dir [--scenario=all|settings|mouse_aim|block|story|inventory]
```
