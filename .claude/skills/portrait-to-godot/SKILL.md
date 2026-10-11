---
name: portrait-to-godot
description: 從零做一個新角色或新外觀並放進 Nest Egg 的完整流程：畫立繪、檢查、取關節、分件與補底層、進引擎、檢查站坐蹲與接點、接到遊戲、交付。要新增角色、敵人、NPC、四足或其他生物的外觀，重畫既有角色，或遇到破圖、關節稜角、多一隻手、挺胸、畫風不一致、AI 感太重時，先讀這份。
---

# 從立繪到放進 Godot

這份是入口，照順序做就能把一個角色做進遊戲。每一關寫了「做什麼、看什麼、沒過回到哪裡」。細節在：

- [character-art-pipeline](../character-art-pipeline/SKILL.md)：生成、解析度、分件與精修的規則與各工具的參數
- [rig-animation](../rig-animation/SKILL.md)：骨架、動作資料、逐格稽核
- [visual-verification](../visual-verification/SKILL.md)：實機畫面怎麼拍、怎麼量
- 逐項案例（成因、怎麼提早發現、修法、不能用的掩蓋做法，附前後圖所在的票）：`pm/Nest-Egg/attachments/NE-255-lessons.md`

環境：本機 `COMFYUI_DIR=D:/ComfyUI`、Python 用 `D:/ComfyUI/.venv/Scripts/python.exe`（PowerShell 先設 `$env:PYTHONUTF8='1'`）、Godot 用 `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`。`start_comfyui.ps1` 沒有說明參數（加 `-Help` 也會啟動），建置輸出的「no websocket heartbeat (ModuleNotFoundError)」是正常的。生成一次一張；用 GPU 的 Godot 指令包在 `tools/comfyui/gpu_lock.py -- …` 裡；做完用 `tools/comfyui/start_comfyui.ps1 -Stop` 收掉模型。下面各關寫的 `python` 都指上面那個 venv 直譯器。

## 三類問題的總表

| 類別 | 常見樣子 | 最早在哪一關擋 | 根因在哪裡修 |
|---|---|---|---|
| 立繪上有奇怪的東西 | 站著挺胸、多一隻手、身體旁邊的細線、大腿後多一塊、畫風和別人不一樣、AI 感 | 第 1、2、4 關 | 重畫立繪或底層圖，不靠動畫與遮蓋 |
| 組合後稜稜角角 | 坐下時骨盆露出直線下緣、球狀臀部、肩球甩出袖子 | 第 5 關 | 關節圓蓋、支點位置 |
| 破圖 | 關節轉動時裂開、輪廓線斷成一段一段、零件旁的游離小點、封閉的小洞 | 第 4、5、6 關 | 底層重疊、補全設定、精修步驟 |

不能用的掩蓋做法（每一類都一樣）：調暗、用武器或別的肢體擋住、放寬稽核門檻、把失敗加進已知失敗清單、只挑看不出問題的角度截圖。

## 第 0 關：先決定做什麼

1. 讀票、讀 `design/13-story-v2/WORLD.md` 與角色設定，寫下這個人是誰、在哪裡工作、會做哪些動作。
2. 查故事資料裡既有的 id（`data/story/*.json` 的說話者、`data/npcs/*.tres`、`data/enemies/*.tres`）。外觀的 id 用既有的那個，接上去才不用改別的地方。
3. 人形走第 1 關；四足與其他非人形看最後一節。
4. 已經同意的定稿不覆蓋。要改姿勢或畫法就另開一個來源資料夾，定稿留著當身份參照。

## 第 1 關：畫立繪

1. 寫 `art_src/characters/<id>/01_design/character.txt`：年齡、性別（寫白）、頭身、體型、臉上不對稱的地方、每件衣服與它的磨損。衣服是港區會有的實用衣物；發光的東西最多一小處。會坐下的角色，上衣寫「只到腰帶」，不要有過腰的下襬。
2. `python tools/comfyui/field_design.py --id <id> --seed <n>`。畫風、站姿與收尾的文字是全體共用的，不要在角色描述裡重寫，也不要加「高細節、傑作」這類詞。
3. 已有定稿、只想換姿勢時用參考編輯（例：`art_src/characters/rin_field/01_design/generate.py`）。
4. 換了種子、選定要用的那張，再跑同一個 seed 加 `--adopt`：`python tools/comfyui/field_design.py --id <id> --seed <n> --adopt`。`base_rgba.png` 只在不存在或加 `--adopt` 時才會寫入；沒做這步，下一關仍用舊圖。

通過條件（全部看原圖，並和老 K、護理師並排）：

- 脊椎直立、胸不前挺、腰不後凹；近側手垂在大腿旁；遠側的腳往前半步
- 兩手兩腳、手指數正確，沒有多餘肢體與莫名的線條
- 畫風一致：低彩度、粗黑描邊、兩階硬邊陰影、有磨損與皺褶，沒有噴槍漸層與塑膠光澤
- 性別、年齡、服裝符合設定與世界觀
- 印 alpha 直方圖，並放在黑、灰、白底看背景與邊緣。背景上 alpha 1～3 的薄霧是正常的（`alpha_floor` 會清掉）；要看的是主體有沒有到 250

沒過：改 `character.txt` 或換種子重畫。不要帶著「之後再修」往下走。

## 第 2 關：產生規格

`python tools/comfyui/field_spec.py --id <id> --name <名稱> --height <世界像素> --seed <n> [--portrait] [--glow head:c]`

- 高度：主角約 63，一般成人 54～60，壯漢 62。
- 有外套、圍裙、背上的東西這類分層衣物：從產生的規格往下拆（範例 `tools/comfyui/specs/rin_side.json`）。外套分「上身跟胸、下襬跟骨盆、袖子跟手臂」；垂在腿前的裙片跟前側大腿。
- 手臂的點提示抓得破碎時加 `--arm-text`。
- 建置停在「points_leg_far … mask value」：兩腿同色又重疊，遠側小腿切不出來，加 `--far-foot-only` 只切遠側的鞋。
- 要跑兩次：parts 步驟前跑一次；parts 跑完（有 `sam/points_arm.png`，用 `--arm-text` 時是 `sam/arm.png`）後加 `--force` 再跑一次，肘與腕會移到手臂遮罩的中線。`--force` 會整份重寫規格，手改的內容與 `eye_states` 都會不見，之後要重跑第 3 關的 `make_eye_states.py`。`--force` 之後從 parts 起重跑到 refine（`--from parts --to refine`），新的關節才會進到零件。
- 站立來源（兩腿幾乎並排）的遠側腿：遮罩只切膝蓋以下；大腿的前緣用一條直線切（規格裡大腿零件的 `front_line`），線以前是遠側的髖與大腿，不歸任何零件（遠側腿是近側腿的複本，畫在自己的髖點上）。骨盆也寫 `front_line`：前緣從腰帶下的全寬以 S 形收進髖點高度的那條線，不留方塊。骨盆與大腿之間沒有零件認領的像素歸骨盆（骨盆零件的 `unclaimed`）。這幾項規格工具會自動寫好。遠側的手只有真的露在身體前面時才加 `--far-hand`，預設不切。
- 零件的細突出（鞋帶尖等，畫面上不到一像素）用 `--trim-spikes 零件,零件` 切掉。

## 第 3 關：建置到引擎

```
python tools/comfyui/build_character.py --recipe tools/comfyui/recipes/<id>.json --from parts --to refine
python tools/comfyui/make_eye_states.py --recipe tools/comfyui/recipes/<id>.json      # 有臉的角色
python tools/comfyui/build_character.py --recipe tools/comfyui/recipes/<id>.json --from textures --to import
```

- 新增任何圖片（例如頭像）後先跑一次匯入：`python tools/comfyui/build_character.py --recipe tools/comfyui/recipes/<id>.json --only import`，否則法線步驟會被不相干的錯誤擋下。`--list` 印出各步驟的工具、輸入與輸出。
- `make_eye_states.py` 不在 `build_character.py` 的步驟裡，要自己跑。跑完看 `<work>/eyes/review.png`（一般是 `art_src/characters/<id>/eyes/review.png`：睜眼、半閉、閉眼與遮罩），頭部零件（`07_refined/head.png`）一改就要重跑。
- 有 `damage`（破損衣物）的角色：`--from parts --to refine` 之後要先跑 `--only damage`，`--from textures` 不會跑它。spec 沒有 `damage` 鍵時這一步什麼也不做。
- 貼圖密度：NPC 與敵人每世界像素 20 像素，主角保留來源密度。
- 動作資料 `art/motion/<id>.json` 從相近的角色複製後改數值（NPC 抄體型相近的 NPC，例如 `repairman_chen`；敵人抄同類敵人）。測試（`tests/suite/test_rig_actions.gd` 的 `_test_motion_is_not_shared`）要求：`art/characters` 每個資料夾都有對應的動作檔；任兩個角色在下列 12 個欄位中至少 4 個值不同：`move.stride`、`move.swing`、`move.knee_bend`、`move.hip_bounce`、`move.chest_lean`、`idle.breath_speed`、`idle.hip_bob`、`death.duration`、`death.rotation`、`death.fold`、`look.head`、`hurt.kick`。

## 第 4 關：看底層圖與零件

- 建置停在「stage … still shows …%」：底層圖沒有真的把手拿掉。換提示詞或種子重做那一張，不要繞過這個檢查。（細節：character-art-pipeline「底層圖檢查」）
- 看 `04_stages/*.png`：要拿掉的東西真的不見了，沒有多畫回別的肢體。
- 精修後建置會自動跑 `check_seams.py`，輸出 `WARN seam …`：髖點以下骨盆比大腿寬（`overhang`）、髖點正上方骨盆還凸在大腿前面一塊（`block`）、膝蓋處大腿與小腿的前緣對不上（`front`）、肢體輪廓有缺口或細鬚（`ragged`）、兩節肢體寬度對不上（`step`）、肢體零件沒有接到自己的關節（`detached`，用 `refine.extend`）、髖點到大腿頂端之間骨盆蓋不滿（`hip_gap`，用 `refine.cap_from`）。每一條都放大看，修到沒有；是畫本身的形狀才登記進規格並寫理由：`"seam_checks": {"allow": {"<鍵>": "理由"}}`，鍵是 `overhang`、`overhang:front`、`overhang:back`、`block`、`front:knee`、`ragged:<零件>`、`step:<關節>`、`detached:<零件>`、`hip_gap`。也可以單獨跑：`python tools/comfyui/check_seams.py --recipe … ` 或 `--all`。
- 沒有警告不等於沒問題：`check_seams` 只量它認得的幾種形狀。第 5 關的兩腿分開近拍還是要放大看。
- 舊流程的角色（近側腿是另一個群組、骨盆沒有 `front_line`）用 `refine.taper_front`：`[{"part": "pelvis", "to": "leg_upper"}]`，效果相同。大腿零件比髖部細很多的角色（大腿護甲是另外的零件）不能用，骨盆會被削成一片楔形。
- 把 `07_refined/pelvis.png`、`leg_upper.png` 放在洋紅底上看：骨盆是圓順的一塊、前緣斜斜收進大腿前緣（不是一個方塊），大腿是一條（前緣是直線、不是兩條大腿黏在一起；頂端是工具加的圓蓋，正常），大腿與小腿的前緣在膝蓋連成一條線（正常的樣子：`pm/Nest-Egg/images/NE-218-hip-parts-normal.png`），手的位置與髖部前緣都沒有被咬掉。有缺口先回頭看規格的 `groups`（多出來的遮罩群組會把身體挖掉），不要先用補洞蓋過去。
- 把 `07_refined/torso.png` 放在洋紅底上看：袖窿補色是平的一塊布色，沒有抹進別的顏色。
- 看 `06_parts/ownership.png`：每個肢體各自一色；身體旁邊沒有細線；遠側小腿與鞋有被分出去。
- `python tools/comfyui/check_reassembly.py --spec … --work … [--allow …]`：零件疊回原位和原圖比。預期中的缺口（遠側腿）逐塊看過才登記進 allow 檔並寫理由。allow 檔是 JSON：`{"holes": [[x0, y0, x1, y1], …]}`，每個方框是已審過的預期缺口。
- 建置輸出的 `WARN part texture …`（游離碎片、封閉孔洞、支點離零件太遠）逐條處理。
- `refine` 的寫法（見 `refine_parts.py` 說明）：`inpaint` 是 `[{"part": 零件, "poly": [[x, y], …], "flat": true}]`，把別的東西畫進這個零件的部分用周圍布色的中位數平色重畫，alpha 不變。
- `claim` 是 `[{"part": 零件, "poly": [[x, y], …]}]`，把原圖上沒有任何零件認領的像素（下巴與衣領之間的皮膚）交給這個零件。
- `close_fill` 是清單，每筆 `{"parts": [零件…], "radius": N}`；要讓不同零件用不同半徑，就寫好幾筆。
- 改了 spec 的 `groups` 或 `near_leg` 後，下一次跑 `parts` 步驟會重做有補全步驟、且 `.key` 檔內容不符的群組。沒有 `.key` 檔的舊角色會保留舊圖，要用 `make_parts.py --spec … --work … --only <群組>` 重做（群組名稱要在 `spec.groups` 裡）。

沒過回到：遮罩或群組的問題回第 2 關；底層圖的問題重畫那一張；立繪本身的問題回第 1 關。

## 第 5 關：引擎內近拍

```
python tools/comfyui/gpu_lock.py -- <godot> --path . res://tools/comfyui/rig_reference.tscn -- --skin=<id> --pose=stand|sit|crouch --out=<絕對目錄> --zoom=10
python tools/comfyui/gpu_lock.py -- <godot> --path . res://tools/rig_preview.tscn -- --out=<檔> --chars=<id> [--npc | --weapon=pistol | --weapon= | --damage --bare | --seq=die_front]
```

一定要看的畫面：空手站著不動、坐、蹲、八個動作、NPC 八個姿勢；有衣物脫落的角色看脫落各階段。（細節：rig-animation「空手時的手臂」；character-art-pipeline「進引擎後先看坐、蹲、跪」）
- 單一角色用 `--closeup --zoom=5`；要看髖與膝的細節用 `--zoom=7` 到 `10`（上半身出畫面沒關係）。`--npc` 的八格依序是站、坐、倚、蹲、說話、聽、揮手、工作循環，`--zoom=3.2` 剛好排得下。
- 看不出凸出來的那一塊是哪個零件：加 `--paint`，每個零件塗成一個平色，圖例印在輸出。
- 遠側的手貼著髖前緣露出來、看不到前臂：遠側手臂被身體擋住，正常。手和身體輪廓之間有空隙，或和近側的手並排在同一側，才是問題。
- 站著像挺胸、兩隻手並排在同一側：來源姿勢的問題（回第 1 關），或空手垂放角度（動作資料 `arms.hang`，兩臂不能同角度）。（細節：character-art-pipeline「來源畫成直立站姿」；rig-animation「空手時的手臂」）
- 多一隻手：底層圖殘留（回第 4 關），或衣物零件裡烤進了手臂。（細節：character-art-pipeline「階段圖一張一張看」，拿掉衣袖與拿掉手臂分兩張生）
- 坐下時骨盆露出直線下緣、球狀凸塊：用 `caps` 處理。上層零件的圓盤較大並柔邊，下層較小、硬邊。（細節：character-art-pipeline「關節圓蓋 `parts.<名稱>.caps`」；球狀臀腿的驗收見 rig-animation「蹲姿臀腿輪廓（NE-222）」）
- 肩、腕甩出去：支點沒在圖的轉動中心，量該高度的左右邊界取中心。
- 無袖底層圖的袖窿露出膚色或暗塊：`refine.inpaint`。
- 衣物坐下時直直垂進椅子：把它掛到會動的那根骨頭上。
- 過腰的長下襬（大衣、圍裙）跟著大腿橫出去或像硬板：下襬獨立成零件掛在衣襬骨頭上，大腿改用「衣服只到腰」的底層圖（`near_leg.stage` 加 `stage_color`）。只疊一片下襬而不換大腿，坐下會出現兩層衣服。

`rig_preview` 其他模式（都要加 `--chars=<id>`）：
- `--gait`：並排八格看一個步伐週期（`--speed` 預設 70，`--run-speed` 預設為兩倍）。
- `--closeup`：每個角色一張大的待機站姿（不加 `--npc` 時是兩腿前後分開的戰鬥待機）。遠側腿往後、手擺開，髖部與大腿前緣有沒有缺口在這張最明顯，必看；可以一次放四個角色，頭尾放老 K 與護理師當對照。
- `--seq=start|stop|idle|jump|land|dash|die_front|die_back`：依時間取八格（起步、煞車、待機、起跳到落地、原地落下、衝刺、正面與背面中彈倒下）。
- `--cloth`：放大看站、跑、上升、下落、蹲、仰射時的衣襬、頭髮與槍套。
- `--left`：全部角色朝左（面向、瞄準、速度、倒下方向一起對調）。每個角色朝左也要看一輪。
- `--zoom=N`：指定放大倍率（`--gait` 預設 2.2）。
- 走路的近拍用 `--gait --zoom=N`，同樣看髖部。
- `--damage`：看 `damage` 步驟產生的破損層，先跑 `--only damage`（見第 3 關）。 有會脫落裝甲的角色必看 `--damage --bare` 的最後一格：頭、手還接在身體上，沒有浮起來。

## 第 6 關：逐格接點稽核

```
python tools/comfyui/gpu_lock.py -- <godot> --path . res://tools/rig_joint_audit.tscn -- --out=<絕對目錄> --chars=<id>[,…] [--joints=…]
python tools/check_joint_frames.py <同一個目錄>
```

每一類失敗都放大看過再處理，數字記在票上，沒歸零就不勾「接點」的驗收條件：

- 兩個連通塊：不同群組的零件只是相接（`refine.underlap`，範圍用支點周圍的小圓），或有游離碎片（`speckle`、`trim_spikes`）
- 封閉小洞：兩個零件之間的小凹口（`close_fill`）、補全時削掉的輪廓（`edge_trim: 1`、`keep_rim`）
- 中心沒蓋到：支點落在零件外面，或落在第三個零件（肩帶、背帶）上；移到兩個零件本身蓋得到的地方
- 原圖有、沒有零件認領的像素（下巴與衣領之間的皮膚）：`refine.claim`
- 衣領、袖口的開口是衣物本來的形狀：寫明是哪一類，不改門檻
- 頸後的封閉小洞怎麼判：站姿就有，或洞邊有一條被切斷的皮膚 → 真缺口，在頸根加 `refine.underlap` 小圓。只有抬頭（`aim_up`）時後頸、髮尾與衣領才圍出來，兩邊零件各自完整 → 姿勢圍出的空隙，照實記數、不改門檻
- 稽核預設連同一根骨頭上的其他零件一起畫（穿著的樣子）；`--pair-only` 只畫那一對。兩種都失敗的才是真缺口：`python tools/joint_audit_both.py <pair-only 目錄> <預設目錄>`

## 第 7 關：接到遊戲

- NPC：`data/npcs/<…>.tres` 的 `rig_id`；說話者頭像在 `data/story/*.json`。NPC 的姿勢、說話與揮手疊層、工作循環在 `art/rigs/npc_animations.json`（鍵：`poses`、`overlays`、`loops`；預設的待機在 `life`）。
- 敵人：`data/enemies/<…>.tres` 的 `rig_skin`（人形）或 `creature_skin`（生物）。只換外觀，不改數值、行為與判定框；外形變了而判定框沒變，寫進對應的戰鬥票。
- 主角：`art/characters/rin` 與 `art/motion/rin.json`。
- 不改故事、台詞與關卡配置。
- 只做外觀、還不接遊戲時，`rig_preview --npc` 不需要 `.tres`；這一關可以整關留到接遊戲的票。
- `tools/screenshot.tscn --scenario=place:<關卡>:<欄>:<標籤>:enemies` 拍正式關卡裡的樣子；過場用 `--scenario=cutscenes`。

## 第 8 關：測試與交付

1. `GODOT=… tools/run_tests_changed.sh <本票開始時的 SHA>`，全過。新增外觀會讓區域預載的貼圖變多、動作資料要和別人不同、生物有「每格移動量」的上限，這些測試都會擋。
2. 截圖存 `pm/<專案>/images/`，票上加「問題—改動—驗收」的 Commit 段落，只勾真的通過的條件；接點沒歸零、實機沒看過的都如實寫。
3. 每修好一類問題，把成因、提早發現的方法、修法與不能用的掩蓋做法補進 `pm/Nest-Egg/attachments/NE-255-lessons.md`。
4. 一張票一個 commit，rebase 到最新 main、重跑受影響測試後推送。
5. 建置一次只跑一個角色（兩個同時跑，匯入會互撞）。提交前確認 `art/` 底下沒有 `valid=false` 的 `.import`：`grep -rl "valid=false" art/` 要是空的。

交付前自己先放大看：兩腿分開的近拍與走路週期的髖、膝、肩、肘各放大一次。沒有放大看過的，票上不寫「沒有發現問題」。

每個角色的固定驗收條件：站姿不挺胸；不會看起來像多一隻手；畫風與既有角色一致、符合世界觀；拼接後沒有破圖、沒切好的地方與關節稜角。

## 四足與其他非人形

用零件式生物（`art/creatures/<id>.json`，`PartCreature`），範例是看門狗：`art_src/creatures/watchdog/parts/`。

1. 設計圖：側面站姿，四條腿都看得到、四個腳掌在同一條地面線上。
2. 底層圖：一次拿掉所有會動的肢體，補出被擋住的身體；和設計圖疊著看位置有沒有跑掉。
3. 切件腳本（`build_parts.py`）：身體取底層圖，頭、尾、武器、腿取設計圖原像素；腿依關節折線分段，每段在兩個關節各多留一個圓盤；遠側肢體沿用近側貼圖，壓暗、往前錯開、步態相位相反。
4. 大面積的白色先把亮部壓低，否則場景燈一照整片變白。
5. 法線：`godot --headless --path . res://tools/art/paint_normals.tscn -- --only=creatures`，再匯入。
6. 預覽：`tools/creature_preview.tscn -- --parts=<id> --cell=寬x高 --cols=N --states=idle,walk,… [--bright]`。亮場景與正常場景燈各看一次。
7. 把 id 加進 `tests/suite/test_part_creature.gd` 的清單。腿長的生物步頻要放慢，否則「每格移動量」會超過上限。
8. 槍口可以由外觀提供（零件的 `muzzle`，敵人腳本覆寫 `_muzzle`）；判定框屬於戰鬥，不順手改。
