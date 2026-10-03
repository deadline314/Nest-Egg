# 角色動畫系統：動畫器、專屬動作、NPC 動畫

> 來源：2026-10-03 使用者要求替重畫後的敵人與 NPC 加入合適的動畫，並問「特殊角色可不可以用不同的骨架，有自己的攻擊方式與動畫」。零件圖與動畫是分開的：動畫只改骨頭角度，不管零件圖長什麼樣，所以零件有問題（NE-90）不會卡動畫。

## 1. 三層

| 層 | 內容 | 在哪裡 |
|---|---|---|
| 骨架 | 骨頭名稱、階層、靜止位置；每個角色自己的檔（長度由立繪量出） | `art/rigs/<id>.json` |
| 動畫器 | 每影格算出各骨頭的目標角度，套用、FK、手臂 IK、彈簧骨 | `game/rig/humanoid_animator.gd`（戰鬥用）、`npc_animator.gd`（NPC 用） |
| 動畫資料 | 姿勢、循環、專屬動作的角度與時間 | `art/rigs/npc_animations.json`、`art/rigs/action_poses.json` |

選動畫器：`CharacterRig.setup(皮膚 id, 動畫器名稱)`；沒指定時看外觀定義（`character.json`）的 `animator`，再沒有就是人形。登記表是 `CharacterRig.ANIMATORS`（名稱 → 類別，類別要繼承 `HumanoidAnimator`）。特殊角色（專屬骨頭、專屬動作）在登記表加一行、寫一個子類別，不需要動其他角色。

## 2. 人形動畫器（戰鬥）

待機、跑、跳、落下、蹲、衝刺、格擋、硬直、倒下，雙手 IK 握武器並跟著瞄準方向，頭髮與衣襬用彈簧骨。輸入是 `RigInput`：`velocity`、`aim_dir`、`crouching`、`blocking`、`staggered`、`dead`、`recoil`（開槍後座力）、`hurt`、`action`／`action_t`（專屬動作）。次級動態參數放在骨架檔的 `springs`。

## 3. 專屬動作（敵人的招式）

敵人招式在某個狀態下播放一段骨頭動作，資料在 `art/rigs/action_poses.json`：

```
"slam": {"weapon_angle": 1.1, "duration": 0.35, "skip_ik": true, "blend": 30, "keys": [
  {"t": 0.0, "bones": {"arm_front_upper": -2.9, ...}},
  {"t": 0.5, "bones": {...}, "hip_y": 4}]}
```

- `keys`：依進度 t（0～1）排列；每個 key 只寫要動的骨頭，沒寫的沿用前後 key 的值，相鄰 key 之間緩動內插。
- `skip_ik`：手臂完全依動作角度（不握武器，武器跟著前手；`weapon_angle` 可固定武器角度）。
- `blend`：進出動作的淡入淡出速度。
- 角度：弧度，面向右的骨架空間，骨頭靜止時朝下，負值＝往前／往上抬。

敵人資料把狀態接到動作：`EnemyData.rig_actions = {"leap_windup": "windup_overhead", "leap": "slam"}`；進度 = 在該狀態停留的時間 / `duration`（到 1 之後停在最後一格）。敵人腳本不需要改，只在需要時覆寫 `_rig_aim()`（槍口方向）與 `_rig_state(input)`（蹲下、透明度等）。開槍的後座力：`Enemy._shoot` 已經設定 `recoil`；自己發射子彈的招式在發射時設 `_rig_input.recoil = 1.0`。

目前登記的動作：`windup_overhead`（雙手高舉）、`slam`（砸下）、`windup_slash`（刀臂舉到身後）、`slash`（揮斬）、`launch`（發射後仰）、`brace`（蓄力沉腰）、`stagger_back`（受創後仰）、`vent`（散熱仰頭）。已接上的敵人：監管者、鎮暴員、重裝機槍手、火焰兵、切割者、回收員。

預覽：`rig_preview.tscn -- --chars=<id> --action=<名稱> [--zoom=倍率]`（進度 0、20%…100% 並排）。

## 4. NPC 動畫器

沿用人形動畫器的骨架計算與彈簧骨，只換「目標角度怎麼算」。角色在走、跑、跳、蹲（人形的蹲）、格擋、倒下、持武器或瞄準時仍交給人形動畫器（過場裡的演員常常這樣用）。資料在 `art/rigs/npc_animations.json`：

- `poses`：`stand`（雙手自然下垂）、`sit`、`lean`（靠牆）、`crouch`（蹲）。
- `overlays`：`talk`（點頭與手勢）、`listen`（微微偏頭）、`wave`（揮手），開關時淡入淡出。
- `loops`：每個角色專屬的工作循環，目前有 `stir` 攪鍋、`wipe_hands` 擦手、`hammer` 敲打、`tablet` 看平板、`sort_gear` 整理器材、`cough` 咳嗽、`pull_blanket` 拉被子、`typing` 打字、`yawn` 打哈欠、`read_note` 看紙條、`glance` 張望、`hold_child` 抱孩子。一條循環＝一組靜態骨頭角度加幾條正弦（`mean`、`amp`、`period`、`phase`），`gate` 讓它只在一個週期的某段時間發生（例如每 8 秒咳 1.6 秒），track 的 `gated`／`inv` 決定跟著 gate 出現或消失。

用法：
- 場景人物：NPC 資料（`data/npcs/*.tres`）的 `pose`（stand／sit／lean／squat）、`loop`、`loop_scale`；靠近時聆聽、對話時說話，程式自動處理。
- 過場：actor 步驟的 `pose`、`loop`、`loop_scale`、`speaker`（劇本講話者 id；說這個人的台詞時，這個演員點頭比手勢，其他演員聆聽）。
- 預覽：`rig_preview.tscn -- --chars=<id> --npc [--loop=名稱 --loop-pose=stand|sit|lean|squat]`。
- 動作資料有錯（骨頭不存在、循環名稱不存在）時記錄具體位置並退回待機，不會崩潰；NPC 資料的循環名稱會被驗證。

## 5. 新增特殊角色的步驟（NE-89 的目標）

1. 規格（`specs/<id>_side.json` 的 `bones`）加專屬骨頭、零件掛上去。
2. 寫一個繼承 `HumanoidAnimator` 的動畫器（或只覆寫 `_body_pose` 加幾根骨頭的角度），在 `CharacterRig.ANIMATORS` 登記名稱，外觀定義 `animator` 填這個名稱。
3. 專屬招式：在 `action_poses.json` 加動作（可以用專屬骨頭），敵人資料的 `rig_actions` 接狀態。
4. 測試：`tests/suite/test_rig_actions.gd` 會檢查動作資料引用的骨頭與敵人資料引用的動作、狀態都存在。
