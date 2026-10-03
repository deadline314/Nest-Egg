# 敵人動畫與受擊手感：業界做法研究

> 範圍：2D 橫向動作遊戲（Katana Zero、Dead Cells、Hollow Knight、Metal Slug、Blasphemous、Cuphead、Huntdown、Gunvolt 一類）的敵人動畫與受擊反應，以及 Godot 4 的落地方式。
> 資料品質說明：公開的第一手資料（GDC、postmortem）對「毫秒級數字」很少給；下面的數字分三種來源——【引】有出處的數字、【經驗】多個來源一致的業界慣例、【建議】本文針對 Nest Egg 的推算值，需要實機調整。第 8 節的 Godot 4.7 API 沒有逐一在 4.7 驗證，動手前先查該版文件。
> 專案現況（讀自 `ANIMATION.md`）：骨架與動作資料是 JSON（`art/rigs/`、`art/motion/`），動畫器是自己寫的 `HumanoidAnimator`（FK、手臂 IK、彈簧骨），受擊 / 倒下已有 `hurt`、`staggered`、`dead`、`stagger_back` 與每個角色自己的死亡倒法。所以下面的建議以「擴充現有資料與動畫器」為主，不是換成 Godot 內建的 AnimationTree。

---

## 1. 受擊反應的分層

受擊手感不是一個動畫，是五六個很短的東西疊在同一個瞬間。每一層都要小，疊起來才像「打中了」。

### 1.1 Hit-stop（凍結影格）

- 目的：讓大腦有時間「看見」命中。Sakurai 的說法是凍結攻擊方與被擊方來強調衝擊力，時間依傷害決定，並刻意壓低上限，因為凍結時會被第三者打（對應我們：玩家在被凍結時不能因此吃虧）。凍結期間角色微幅震動，強度隨時間衰減。【引：Sakurai 專欄整理】
- 數字對照（60fps）：
  - Nuclear Throne：命中暫停只有 10～20 ms，受擊動畫「第一格全白，接著兩格睜大眼」，擊退每影格 3 像素。【引：Vlambeer 訪談整理】
  - 像素動作遊戲 FX 指南：輕擊 2～4 格全停，或 50～70% 慢速 4～6 格；重擊 6～10 格；Boss 大招 12～18 格。【引：gamineai】
  - 格鬥遊戲常見 輕/中/重 = 8/12/16 格；多段攻擊要縮短。【引：Dustloop/Capcom 整理】那是一對一格鬥的節奏，跑槍遊戲照抄會卡手。
  - 研究文獻：hit-stop 的最佳值約 0.1～0.2 秒。【引：scitepress 2024】這是「重擊」的上限，不是每一槍。
- 實作原則：
  - 只凍結「攻擊者 + 被擊者」的動畫與位移，其他東西照跑；不要動 `Engine.time_scale`（會連 UI、音效、粒子一起慢，而且和慢動作、暫停互相打架）。【引：bugnet】
  - 凍結用「不受縮放的時間」計時；多次命中取最大值，不要累加。
  - 高射速武器（每秒很多發）每發都 hit-stop 會變成卡頓：只在擊殺、爆頭、重擊、近戰才做，普通子彈給 0 或 ≤16 ms。
- 【建議】Nest Egg 分級（60fps，毫秒 / 格）：

| 事件 | 時間 | 備註 |
|---|---|---|
| 一般子彈命中 | 0 ～ 16 ms（0～1 格） | 只靠閃白與擊退 |
| 散彈 / 重槍單發 | 33 ms（2 格） | |
| 近戰輕擊 | 50 ms（3 格） | |
| 近戰重擊 / 爆頭 | 67～83 ms（4～5 格） | |
| 擊殺（一般敵人） | 67～100 ms | |
| 擊殺（精英） | 100～117 ms | |
| 破除架勢（poise break） | 100～133 ms | |
| Boss 階段轉換 | ≤ 167 ms | 全遊戲上限，不超過 0.2 秒 |
| 多段 / 連射 | 同一目標 200 ms 內第二次以後減半 | 防止重 |

### 1.2 硬直（Flinch / Stagger）分三階

業界慣例是「輕、重、破防」三階，加上「韌性（poise）」決定哪一階出現。

- 輕硬直（flinch）：只動上半身 / 被擊的部位，0.1～0.2 秒，不中斷移動（或只減速）。擊中就一定有，這是回饋，不是控制。
- 重硬直（stagger）：整個狀態切到 stagger，打斷招式，0.3～0.5 秒，有明確的後仰、擊退。
- 破防 / 倒地（stance break）：韌性歸零，進入較長的暴露窗口，玩家可以追加處決 / 高傷害。Elden Ring 的敵人韌性每秒回復 13 點，歸零時觸發「stance break」並讓大部分敵人進入可處決狀態；重擊與招式中的超級護甲（hyper armor）可以讓動作不被打斷。【引：Elden Ring wiki】
- 韌性設計：隱藏的 poise 值，被打到 0 才會硬直；硬直後短暫停在 0 讓連擊成立，之後進入「超級護甲開始出招」，出招中不損失 poise、出招完才恢復滿值。【引：Kobold's Tale devlog 描述的簡化版】
- 關鍵：招式的「出招中（active）」段給 super armor，「前搖（windup）」段不給——玩家打斷前搖是被允許的獎勵，打斷出招是不被允許的。

### 1.3 擊退曲線

- 擊退要跟「重量」連動：Hollow Knight 的擊退取決於敵人重量，並有「重擊護符」放大擊退。【引：Hollow Knight wiki】
- 做法：初速 v0 依武器重量 × (1 − 敵人重量抗性)，之後用指數衰減（每格乘 0.8～0.9）或 ease-out，持續 6～12 格；不要用固定速度，會像被搬走。
- 擊退距離是「手感」也是「平衡」：太遠會讓玩家追不到，太近沒感覺。輕擊 8～16 px、重擊 24～48 px、擊殺可以更遠（因為不再需要玩家追）。【建議】
- 空中 / 無腳的敵人（飛行、軌道）擊退可以更大，並帶一點旋轉；重型敵人（精英、機甲）擊退 ≈ 0，改靠硬直動畫表現「被打到」。

### 1.4 閃白 / 閃色 shader

- 標準做法：命中第一格全白（或高亮），接著 1～2 格回到正常。「1 到 2 格高對比閃光再回去，太長會讀成暈眩 UI 而不是衝擊」。【引：gamineai；Nuclear Throne 同樣是第一格全白】
- Godot 兩種實作：
  - `modulate` 設成大於 1 的值（`Color(2,2,2)` ～ `Color(10,10,10)`）再 Tween 回 1；因為 2D 是 HDR，超過 1 的值會發光。【引：uhiyama-lab】
  - 或 shader 用 `mix(color.rgb, flash_color, amount)`；amount ≤ 1 時亮度最高就是白色 1.0，不會超過。
- 本專案是 HDR 2D + bloom，所以：**不要用大於 1 的 modulate 做閃白**。用 shader 的 `flash_amount` uniform（0～1）混白，且閃白色不要純白，偏向敵人色系的亮色，峰值亮度 ≤ 1.0。要發光感的特例（電弧、能量盾）才允許 1.2～1.5，並且要實機看 bloom。
- 注意：連續命中要先 kill 舊的 tween（或直接用一個計時器 / uniform 遞減），否則會停在中間亮度。【引：uhiyama-lab】`modulate` 會影響所有子節點，要用 `self_modulate` 或 shader。
- 順帶：閃白用 `instance uniform`（`instance uniform float flash_amount`）可以共用同一個 material，不會每個敵人配置一個 material。

### 1.5 擠壓與拉伸（Squash & Stretch）

- 受擊時沿擊退方向做 1～2 格的小形變：縮 5～10% 垂直、拉 5～10% 水平；0.08～0.12 秒回彈（略微過衝）。【建議；Disney 原則：誇張要克制，位置在骨架上做比整張貼圖縮放自然】
- 本專案有骨架：不要縮放整個 Sprite，改成「骨盆下沉 + 脊椎前傾幾度」，用彈簧骨的過衝補回彈。非人形（觸手、爬行）才用整體縮放。
- 重型敵人幾乎不形變，只做「後仰 + 腳滑 2～4 px」。

### 1.6 畫面震動要克制

- Vlambeer：每次開槍 screenshake +4 像素並快速衰減，相機後座 6 px。【引：Nuclear Throne】
- 近戰震動 4～8 格、短而高頻；爆炸 10～16 格。【引：gamineai】
- 【建議】Nest Egg：一般命中 0；重擊 / 擊殺 1～2 px、60～100 ms；精英死亡 / Boss 轉階段 3～4 px、150 ms；震動用「trauma 平方」衰減（trauma² 乘最大偏移），連續事件取最大值不累加；提供設定可關。

### 1.7 方向性受擊

- 用攻擊方向與敵人朝向的點積決定「前方 / 後方」受擊，播不同的後仰（向後 / 向前撲）。【引：direction-based hit reaction 做法，Unreal 常見】
- 2D 橫向只需要兩個方向 + 上 / 下兩個變體：前、後、上（打頭）、下（打腿）。資料：`hit_react = {front: pose, back: pose, high: pose, low: pose}`，缺則退回 front。
- 打到哪個部位也決定反應：打頭 → 頭向後甩；打腳 → 單腳彈開。有每部位 hurtbox 的話（第 3 節）可以直接用命中的 hurtbox 名稱查表。

### 1.8 在移動動畫上疊加的受擊層

- 原則：受擊是「加性疊加層」，不是整個換狀態。大多數敵人被打時應該繼續走 / 繼續出招，只在被打斷（重硬直）時才切狀態。
- 3D 做法：受擊動畫放獨立 layer、套上半身遮罩，下半身繼續跑。【引：多個 Unreal / Unity 教學】Godot AnimationTree 對應：`OneShot` 節點 + 篩選（filter）只混上半身骨頭；`Add2` 做加性疊加。【引：Godot 文件】
- 本專案是自家動畫器：最簡單的做法是在 `HumanoidAnimator` 最後一步，把 `hurt` 的 0～1 衰減值乘上一組「受擊偏移角度」（每根骨頭一個加性角度，資料驅動）加在目標角度上。不用另外的動畫，不用狀態切換。

### Nest Egg 可採用做法（第 1 節）

- 命中事件集中成一個資料：`hit_feel = {hitstop_ms, flash, shake, knockback, stagger_tier}`，掛在武器 / 招式資料上，敵人只有「重量」與「韌性」兩個數字來縮放。
- Hit-stop 只凍結攻擊者與被擊者（自己的 `time_scale` / 跳過 `_physics_process`），不碰 `Engine.time_scale`；多次命中取 max；普通子彈 ≤16 ms，重擊上限 83 ms，Boss 轉階段上限 167 ms。
- 閃白改用共用 shader 的 `flash_amount`（0～1 混合），峰值亮度不超過 1.0，維持 1～2 格 + ≤100 ms 衰減；不使用 `modulate > 1`，避免 bloom 過曝。
- 硬直三階（flinch / stagger / break）+ 隱藏 poise；招式 active 段給 super armor、windup 段不給。
- 擊退 = 初速 × 重量係數，指數衰減 6～12 格；精英與機甲幾乎不退。
- 受擊用「加性角度偏移層」疊在現有動畫器上（`hurt` 衰減值 × 每角色資料裡的骨頭偏移），輕擊不切狀態。
- 畫面震動只給擊殺與重擊，用 trauma² 衰減，取最大值；提供可關閉設定。

---

## 2. 骨架 2D 的程序動畫與次級動態

### 2.1 彈簧 / 跟隨（Follow-through）

- Disney 原則：主體停下時，頭髮、衣襬、尾巴、鬆垮的部位還會繼續動、各部位速度不同，沒有任何東西同時停下。【引：Disney 12 原則整理】
- Godot 內建 `SkeletonModification2DJiggle`：stiffness（預設 3.0，越高越快回位）、mass（0.75，影響速度與過衝）、damping（0.75）、gravity（預設 (0,6)），每根骨頭可覆寫，可選碰撞。主要用途就是頭髮、衣服邊緣的次級動態。【引：Godot 文件】
- 本專案已經有自己的彈簧骨（`springs` 寫在骨架檔）。直接把「敵人專屬的 stiffness / damping」放進每個敵人的骨架檔即可；觸手與尾巴用同一個參數化，不要另寫一套。
- 受擊時對彈簧骨「注入速度」（衝量）比改角度自然：被打到 → 衣襬 / 尾巴 / 天線多晃兩下，免費得到過衝與餘震。

### 2.2 Verlet 鏈（觸手、尾巴、纜線）

- Verlet：位置 = 位置 + (位置 − 上一個位置)；用「距離約束」保持節點間距，每影格迭代約束數次來增加穩定度。比 Euler 更穩、更便宜、抖動少。【引：Jonathan Whiting verlet rope 文章整理】
- 實作模板（GDScript 概念）：
  - 節點數 8～16；每影格：積分（含阻尼 0.98 左右、重力 / 風）→ 約束迭代 3～6 次 → 根節點釘在骨頭上 → 把位置寫回 `Line2D.points`（或 `Polygon2D` 的骨頭）。
  - 受擊 → 對鏈上各點加衝量（命中點最大、向根部遞減）。
  - 預先配置 `PackedVector2Array`，避免每影格 `append`（效能規則）。
- 渲染：`Line2D` 配 `width_curve` 做粗細漸變、`texture_mode = TILE/STRETCH`；比 Polygon2D 變形便宜。觸手需要立繪貼圖的話，用沿鏈的 Polygon2D 條帶 + 頂點權重，或拆成 4～6 段貼圖掛在 Bone2D 上，由 verlet 驅動 Bone2D 旋轉（既有骨架流程不變）。
- 社群有現成範例（Line2D 做尾巴 / 觸手的程序動畫、CRope2D 等 Verlet 元件）；但這些是第三方，只當參考，核心不要依賴。

### 2.3 多足生物的 IK 與踏步

- 常見做法：每條腿一個步伐感測（射線往下），算出「目標落腳點」＝射線命中點 + 角色速度預測；當目前腳位和目標落腳點的距離超過門檻就踏一步（走弧線）；腿分成對角組，一次只允許一組移動；身體高度取所有腳的平均高度，並對地面法線對齊；再加一點正弦起伏。【引：80.lv 的 Godot 4.5 蜘蛛 IK 範例，3D 但邏輯可直接降到 2D】
- 2D 側視：每條腿用兩骨 IK（Godot 有 `SkeletonModification2DTwoBoneIK`，用餘弦定理，比 FABRIK 輕，只能用於兩根骨頭，文件標示為實驗性）。【引：Godot 文件】超過兩節的腿用 FABRIK / CCDIK。
- 重要：腳落地後就**釘在世界座標**（foot planting），身體移動時腳不滑；只有踏步時才移動，這是避免「滑冰感」的最大單一因素。
- 4.6 起 Godot 重新提供內建 IK（80.lv 文章提到 4.6 的 IK 回歸），但 `SkeletonModification2D` 系列是否變動要在 4.7 文件確認；自家動畫器已經有手臂 IK，建議多足生物沿用同一套 IK 數學，不綁內建類別。

### 2.4 Ragdoll-lite 死亡 / 部分物理

- Godot 2D 有 `PhysicalBone2D` + `SkeletonModification2DPhysicalBones`（`start_simulation` / `stop_simulation`，可只模擬指定骨頭）；文件標示為實驗性，會被修改，而且社群討論顯示 2D 教材很少。【引：Godot 文件、論壇】
- 3D 文件提醒：每根被模擬的骨頭都有成本，太小的骨頭與輔助骨不要模擬（手掌合成一根，不用每根手指）。【引：Godot 3D ragdoll 文件，概念通用】
- 結論：全面 ragdoll 對這個專案不划算（立繪是零件拼接、數量多、要省效能）。建議「ragdoll-lite」：
  - 死亡時只讓 3～5 個部位（頭、軀幹、兩手臂 / 武器）走簡單的 Verlet / 彈簧，帶初速（擊殺方向）、落地後凍結並關閉模擬；
  - 或者用現有的死亡倒法參數（`rotation`、`fold`、`ease`）+ 彈簧骨過衝，再加一點隨機。這已經是有效的 80/20。
- 屍體落地後立刻停止所有模擬（`set_physics_process(false)`），或轉成靜態貼圖（見第 7 節）。

### Nest Egg 可採用做法（第 2 節）

- 次級動態一律走「彈簧參數 + 衝量注入」：受擊、跳躍落地、開火都往彈簧骨加速度；參數放骨架檔，不寫死在程式。
- 觸手 / 尾巴 / 纜線用一個共用的 `VerletChain`（資料：節點數、間距、阻尼、重力、約束迭代次數、根骨名稱、寬度曲線），輸出到 `Line2D` 或驅動 Bone2D 旋轉；預先配置陣列、每影格零配置。
- 多足生物：腿 = 兩骨 IK + 世界座標落腳點 + 對角組輪流踏步 + 身體高度取腳平均；參數（步距門檻、步高、步速、組別）全部資料化。
- 死亡 ragdoll-lite：只模擬 3～5 個部位、落地即停；先用既有 `death` 參數，不引入 `PhysicalBone2D`（實驗性）。
- 視距外或螢幕外的敵人關掉 Verlet / IK 更新（降頻或停用），畫面內同時模擬的鏈數設上限。

---

## 3. Hitbox / Hurtbox 設計

### 3.1 每部位 hurtbox 與傷害倍率

- 頭部 / 弱點倍率：業界常見 ×1.5～×3（GTFO 約 2～3、其他 FPS 常見 2×，不同敵人弱點倍率不同，大型敵人只有 1.5）。【引：GTFO wiki、Deadlock 資料】
- 做法：敵人身上多個 `Area2D`（`head`、`torso`、`weak_core`、`leg`），各自帶 `damage_mult`；子彈命中時記錄命中的 hurtbox 名稱，傷害 = 基礎傷害 × `mult`。
- 2D 橫向的實務：頭部 hurtbox 比視覺略大 2～4 px（容錯），弱點要有「視覺提示」（發光、不同材質、露出的核心），不然玩家不知道要打哪裡。
- 弱點可以是「動態的」：只有在招式 windup / recover 時才露出（散熱、張嘴、開殼）。回應「打斷前搖有獎勵」。

### 3.2 Active-frame hitbox 與動畫綁定

- 攻擊 hitbox 平常關閉，只在動畫的 active 幀開啟；永遠開著會出現「幽靈傷害」。【引：多個 Godot 教學整理】
- Godot：`AnimationPlayer` 的 Method Call Track 在指定時間呼叫 `enable_hitbox()` / `disable_hitbox()`；函式名稱要有意義、函式要輕（不要在單格做大量計算或實例化）；要有 `RESET` 動畫，防止動畫被中斷時 hitbox 殘留開著。【引：uhiyama-lab】
- 在物理中改碰撞形狀用 `set_deferred("disabled", ...)`，避免在物理步中修改。【引：Godot 論壇整理】
- 本專案動作資料是 JSON 的 `keys`（進度 t），沒有 AnimationPlayer。對應做法：在動作資料加 `events` 或 `active = [t_start, t_end]`，動畫器依進度開關 hitbox，與 AnimationPlayer 的 method track 等價且資料化。
- 注意「晚一格」：碰撞偵測可能比動畫晚一個物理影格才生效，active 起點要略提前 1 格或把動作看成「第 N 格的下一個物理 tick 生效」。【引：Godot 論壇「collisions happening 1 frame late」】

### 3.3 預兆（Telegraph）與前搖（Windup）可讀性

- Disney「預備動作（anticipation）」：動作越大、預備越明顯；預備也用來引導觀眾視線，告訴你接下來要發生什麼。【引：Disney 12 原則整理】
- 遊戲中的數字（【經驗】，60fps）：
  - 普通小兵：前搖 12～24 格（0.2～0.4 秒）；
  - 重擊 / 精英：24～48 格（0.4～0.8 秒），前搖中有明顯的反向動作（高舉、後仰、蓄力）；
  - 難以閃避的招（衝撞、範圍）：加上地面 / 身體發光等額外預兆，但亮度要克制（避免過曝）。
- 輪廓要先變：前搖的第一個姿勢要與待機的輪廓明顯不同（武器抬起、身體縮），玩家用剪影就能分辨「下一招是哪個」；顏色 / 閃光是輔助，不是主體。
- 前搖 → active → 收招（recovery）三段比例固定寫在資料裡，收招段是玩家的反擊窗口；收招越長，招式越「重」。

### 3.4 無敵幀（i-frames）

- 玩家：閃避 / 衝刺 / 受傷後給 i-frame（受傷後 0.5～1.0 秒並閃爍）。【經驗】
- 敵人：被擊中後給「同一招不重複命中」（每次揮擊只算一次，記錄已命中目標），比給長時間無敵好；Boss 階段轉換、出場、死亡動畫期間給無敵，防止「打屍體」與跳階段。
- 多段武器（雷射、火焰）用「每目標命中間隔」（例如 0.1 秒）而不是無敵幀。

### Nest Egg 可採用做法（第 3 節）

- 敵人資料加 `hurtboxes = [{name, shape, damage_mult}]`，命中時依名稱計算；頭部 ×1.5～×2、核心 / 弱點 ×2～×3、護甲部位 ×0.5 或免疫。
- 招式資料加 `telegraph / windup / active / recovery` 的時間（秒）與 `active` 區間；動畫器依進度開關 hitbox，動作中斷時用 `RESET` 規則強制關閉。
- 前搖必須有輪廓變化（武器 / 肢體的剪影），發光預兆亮度 ≤ 1.0 或僅用邊緣光，不靠大面積高亮。
- 每次揮擊只對同一目標命中一次（hit-set）；持續傷害用每目標間隔。
- 弱點「露出」由狀態驅動（vent / 張嘴 / 開殼），並用顏色或材質變化提示。

---

## 4. 非人形生物的肢解與損傷狀態

- 業界做法光譜：
  - 可見損傷階段（damage states）：血量跨過 66% / 33% 門檻時換貼圖 / 掉零件 / 冒煙；Boss 常與階段（phase）綁定，如 Hollow Knight 的 Boss 在血量門檻進入第二階段並加入新招。【引：Hollow Knight wiki】
  - 部位破壞：打掉一條腿 → 行動變慢 / 跛行；打掉武器臂 → 失去該攻擊；打掉頭 / 核心 → 直接死亡。
  - 純視覺肢解：擊殺時才把零件飛出去，不影響玩法，成本最低。
- 本專案的立繪就是零件拼接 + 骨架，非常適合：
  - 每個零件已經是獨立 Sprite 掛在 Bone2D 上，「斷肢」＝把該 Bone2D 的 Sprite 從骨架摘下，變成一個獨立的小物體（帶初速 + 重力 + 旋轉），原位置換成「斷口」貼圖或隱藏。
  - 觸手：Verlet 鏈從被打斷的節點開始斷成兩段，遠端那段轉成自由落下的鏈。
  - 爬行 / 多足：斷掉一條腿 → IK 的該腿目標停用、其他腿重新分組、身體傾斜、速度降。
- 損傷階段用資料：`damage_states = [{hp_below: 0.66, swap_parts: {...}, effects: [...]}, ...]`，一律是資料，不寫進程式。
- 克制：飛出的零件 ≤ 3～4 個、存活 1～2 秒或落地即淡出；不要噴一堆粒子（使用者要求克制特效）。
- 弱點與損傷階段聯動：階段 2 才露出核心；打掉護甲板才可以打核心。玩家得到「我打壞了它」的明確回饋。

### Nest Egg 可採用做法（第 4 節）

- 零件摘下（detach part）做成通用機制：`detach(bone_name, impulse)` 把 Bone2D 下的 Sprite 轉成池化的 `DetachedPart`（帶 RigidBody 風格的簡單運動，落地後淡出回收），所有生物共用。
- 損傷階段（66% / 33%）用資料驅動換零件 / 加冒煙 / 加彈簧衝量；每個非人形敵人至少一個可見階段。
- 腿 / 觸手 / 武器臂斷裂影響玩法時（行動變慢、失去招式）要資料化並有測試；只做視覺的先做「擊殺時飛零件」。
- 一次擊殺最多 3～4 個零件、最長 1.5 秒；零件與屍體都走物件池。

---

## 5. 敵人動畫狀態機

### 5.1 狀態

典型：`idle → patrol → alert（發現）→ chase / reposition → windup → attack(active) → recover → stagger → dead`。額外狀態：`stunned / broken`（破防）、`retreat`、`spawn`。

要點：
- 「alert」用一個明確的動作（抬頭、嘶吼、驚嘆號式的姿勢）而不是瞬間切到追擊；它同時是玩家的預警與角色個性的展現。
- `windup / active / recover` 三段由資料決定長度，AI 只決定「何時開始哪一招」。
- `stagger` 可以從幾乎任何狀態進入（依 poise 判定），離開時回到 `alert` 或 `reposition`，不是直接回到被打斷的招式；被打斷的招式有短暫冷卻。

### 5.2 動畫驅動 vs 程式驅動的位移

- 動畫驅動（root motion）：衝撞、撲擊、翻滾這類「位移就是動作的一部分」的招式，位移來自動畫曲線，才不會腳滑。Godot AnimationTree 支援 root motion，能把位移資料另外取出餵給物理。【引：Godot 文件】
- 程式驅動：巡邏、追擊、擊退；動畫只負責「看起來在走」，速度由程式決定，腳步用「依速度調整播放速率」或 IK 落腳點對齊（第 6 節）。
- 本專案：動作資料（`action_poses.json`）已經是「骨頭角度」的動畫，位移由 Enemy 狀態決定。對「撲擊 / 衝撞」招式，在動作資料加 `move = [{t, vx, vy}]` 曲線（資料化的 root motion），讓位移與姿勢同步。
- 簡單原則：位移與姿勢一定要同一份資料決定，否則會「滑」或「跳」。

### 5.3 狀態機的容錯

- 動畫名稱 / 骨頭名稱不存在時記錄具體位置（檔名 + 敵人 id + 欄位）並退回 idle，不崩潰（專案守則）。
- `animation_finished` 這類回呼容易被中斷漏掉；狀態機自己用計時器為準，動畫只是表現。

### Nest Egg 可採用做法（第 5 節）

- 敵人狀態機採固定骨架：`idle / patrol / alert / windup / active / recover / stagger / break / dead`；每個招式在資料裡寫 `windup / active / recover` 秒數、`super_armor_in_active`、`rig_action`。
- 位移招式加 `move` 曲線（資料化 root motion）；巡邏 / 追擊用程式速度，腳步動畫依速度調整。
- 受擊離開 stagger 後進入 `alert` / `reposition`，被打斷的招式冷卻 0.5～1 秒，避免秒回同一招造成「永遠打不斷」或「打斷無意義」。
- 狀態機以計時器為準，動畫只是表現；資料錯誤退回 idle 並記錄敵人 id 與欄位。

---

## 6. 重量與真實感

- 預備（anticipation）與過衝（overshoot）：大動作要有反向的小預備，收招要略過衝再回穩；重量感來自「慢啟動、快打擊、慢收」（Disney：slow in / slow out）。【引：Disney 原則整理】
- 緩動曲線：攻擊的 active 段用 ease-in（加速打下去）+ 極短 hold；收招用 ease-out。不要全部線性。【經驗】
- 重量差異靠三件事，不靠誇張特效：
  1. 前搖長度（越重越長）；
  2. 受擊後仰與硬直時間；
  3. 腳滑（被打退時重型敵人腳底滑 2～4 px 後停住，輕型直接彈開）。
- 避免腳滑（foot sliding）：
  - 腳底速度 = 角色速度時才算「踩住」；走路循環的步幅 × 播放速率要與移動速度對齊；
  - 做不到時用 IK 落腳點釘在世界座標（第 2.3 節），身體前移、腳不動，到達極限才抬腳。
- 停止時要有「煞車」：減速 3～5 格，上半身略前傾再回正；急停不要瞬間切到 idle。
- 受擊「硬直賣重量」：打到重型敵人時，hit-stop 稍長 + 擊退小 + 後仰動作明顯，比打到輕型敵人（hit-stop 短 + 擊退大）更像「重」。
- Metal Slug 的經驗：敵人的動畫很長、很多餘（幾乎沒有遊戲功能），但讓世界活起來；程式組甚至想勸畫師少畫一點。【引：Automaton 訪談整理】這說明「閒置 / 待機的小動作」值得投資，但要在資料與記憶體預算內。

### Nest Egg 可採用做法（第 6 節）

- 每個敵人資料有 `weight`（0～1）與 `poise`，統一換算：前搖秒數、hit-stop 倍率、擊退倍率、硬直時間、腳滑距離；不要每個敵人手調一堆數字。
- 攻擊曲線：windup 用 ease-out 的反向小動作、active 用 ease-in 打下去、recover 用 ease-out；`action_poses.json` 的 key 之間已經是緩動內插，只需要把預備與過衝的 key 補進資料。
- 步行：步幅 × 速度對齊，或腳釘世界座標；停止時加 3～5 格煞車與前傾。
- 每個敵人加 2～3 個待機小動作（呼吸、掃視、抖動、散熱），用現有彈簧骨與 gate 機制就能做，不增加貼圖。

---

## 7. 死亡動畫與回饋

- 擊殺回饋 = 稍長的 hit-stop（67～117 ms）+ 一個向擊殺方向的死亡動作 + 1～2 個零件 / 火花；之後屍體不再互動。
- 慢動作擊殺鏡頭（slow-mo kill cam）要極度克制：只給 Boss 最後一擊 / 劇情擊殺，0.2～0.4 秒、時間縮放 0.3～0.5；研究建議慢動作最佳約 0.2～0.4 秒。【引：scitepress 2024】對一般敵人完全不用，否則清場節奏被拖慢，並讓玩家覺得是在「等」。
- 屍體（corpse）持久性成本：
  - 每個屍體 = 一堆 Sprite + 骨架節點；大量保留會讓繪製呼叫與節點數爆增。
  - 做法：死亡動畫播完後，停止骨架更新與物理，並把整個零件拼接「烤」成單張貼圖（`SubViewport` 一次性渲染 → 靜態 Sprite2D），釋放骨架節點；或限制同時存在的屍體數（例如 8～12 具，最舊的淡出）。Vlambeer 認為屍體 / 彈殼 / 場景物件的持久性讓戰鬥有「發生過」的痕跡，所以不要全部立刻消失，但要有上限。【引：Vlambeer 訪談整理】
- Gibs（碎塊）：用物件池，預先建立 N 個（例如 16～32）零件節點，死亡時取出、設定圖與速度、落地 1～2 秒後淡出並回收；不要 `instantiate()` / `queue_free()`。【引：Godot 粒子 / 池化建議整理】
- 粒子：`GPUParticles2D` 一次性爆發用池，重複使用時呼叫 `restart()`，不要只切換 `emitting`；快速連續的命中要池化數個粒子，單一發射器無法產生重疊的爆發。【引：bugnet 與 uhiyama-lab】
- 粒子數量：輕擊 3～8 個碎屑像素；已有大量彈幕時近戰粒子減半。【引：gamineai】本專案已經把粒子減半（NE-95），維持「少而精」。

### Nest Egg 可採用做法（第 7 節）

- 擊殺回饋標準組合：hit-stop（67～117 ms）+ 方向性死亡動作 + 1～2 個脫離零件 + 一次小閃光；沒有一般擊殺的慢動作，慢動作僅限 Boss 終結，時間縮放 ≥0.3、≤0.4 秒。
- 屍體：動畫結束 → 停止所有更新 → 烤成單張貼圖（或直接淡出）；同時存活上限 8～12；超過上限最舊先淡出。
- Gibs / 脫離零件 / 粒子全部池化，預建、`restart()` 重用、落地即停、回收；每次擊殺的粒子數上限寫成常數（集中在 `Fx`）。
- 死亡閃光不用 HDR 加亮，用混白 shader（峰值 ≤ 1.0）。

---

## 8. Godot 4 專屬實作提示

1. **AnimationPlayer + Method Call Track**：開關 hitbox、播音效、觸發小震動、發射單顆彈體；函式輕、命名有意義、要有 `RESET` 動畫；容易讓邏輯藏在時間軸上，所以只放「同一個時間點必須發生」的事。【引：uhiyama-lab】
2. **AnimationTree**：`StateMachine`（`travel()` 用 A* 找路徑）+ `OneShot` 疊受擊 + 篩選（filter）決定混哪些軌道 + `Add2` 加性疊加 + root motion 取出位移。【引：Godot 文件】本專案已有自家動畫器，不必遷移；這些是在需要做「完全用 AnimationPlayer 的特殊生物」時的選項。
3. **Skeleton2D + Bone2D**：Bone2D 是骨頭，Sprite / Polygon2D 掛在骨頭或用 Polygon2D 的 `skeleton` + 頂點權重做網格變形（觸手、軟體生物）。零件拼接的角色用「Sprite 掛 Bone2D」最省；需要彎曲的部位才用 Polygon2D 權重。
4. **SkeletonModification2D（實驗性）**：`Jiggle`（次級動態）、`TwoBoneIK`（兩骨腿 / 手臂）、`FABRIK` / `CCDIK`（長鏈）、`PhysicalBones`（ragdoll）。文件都標示可能變更或移除；4.6 之後 IK 又有新的內建支援。【引：Godot 文件、80.lv】建議：核心邏輯寫在自己的類別（目前就是 `HumanoidAnimator`），內建類別只在確認 4.7 穩定時才使用，並且集中在一個轉接層。
5. **PhysicalBone2D 替代方案**：「ragdoll-lite」＝少量零件各自一個簡單的 Verlet / 彈簧積分 + 與地面的簡單碰撞（射線或高度判斷），落地即停；不使用物理引擎的關節，穩定且便宜。
6. **hit-stop**：自己維護 `HitStop` 管理器，只對參與者設定 `process_mode` / 計時器暫停，或給動畫器 `time_scale = 0`；不碰全域 `Engine.time_scale`；用 `Time.get_ticks_usec` 這類不受縮放的時間計時。
7. **閃白 shader**：`shader_type canvas_item;` + `instance uniform float flash_amount : hint_range(0,1);` + `COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount);`；用 `set_instance_shader_parameter()` 控制，共用 material，避免每個敵人複製資源。
8. **物件池**：粒子、碎塊、脫離零件、傷害數字、彈殼各自一個池（預建、`visible=false`、`process_mode=DISABLED`，取用時重設狀態）；一次性 `GPUParticles2D` 取用時呼叫 `restart()`。
9. **效能**：Verlet / IK 更新只對畫面內（`VisibleOnScreenNotifier2D`）的敵人做；同畫面的鏈與腿設上限；`Line2D` 點數盡量少（8～12）；陣列預先配置。
10. **容錯**：資料缺欄位用預設值並記錄「檔案路徑 + 敵人 id + 欄位」；測試鎖定資料引用的骨頭 / 動作 / 狀態都存在（`test_rig_actions.gd` 已有這類檢查）。

### Nest Egg 可採用做法（第 8 節）

- 維持自家動畫器為主；任何內建 `SkeletonModification2D` 先包一層轉接，4.7 不穩定時能換掉。
- Hitbox 開關資料化（`active` 區間），不要散落在 AnimationPlayer 軌道；若某個特殊生物確實用 AnimationPlayer，一律只用 method track 呼叫 `enable_hitbox()` / `disable_hitbox()` 並附 `RESET`。
- 新增共用元件：`HitStop`、`FlashShader`（instance uniform）、`VerletChain`、`DetachedPart` 池、`CorpsePool`；各自單一職責，放在共用資料夾，敵人只提供資料。
- 同畫面上限（Verlet 鏈、IK 腿、屍體、碎塊）寫成集中常數，並加進測試。

---

## 9. 套用到各生物類型的快速對照

| 類型 | 受擊 | 次級動態 | 死亡 |
|---|---|---|---|
| 人形（保全、精英） | 上半身加性後仰、擊退依重量 | 衣襬 / 頭髮彈簧、武器手 IK | 既有倒法 + 1 個脫落零件（武器） |
| 重型（鎮暴、機槍手） | hit-stop 稍長、擊退≈0、腳滑 2～4 px | 裝甲板輕微彈簧 | 慢慢癱坐、零件落地即停 |
| 觸手 | 命中點衝量、整條 Verlet 晃動 | Verlet 鏈 | 斷節、遠端自由落下 |
| 爬行 / 多足 | 身體下沉、腿 IK 目標被彈開 | 腿 IK 世界座標落腳 | 腿抽搐後收攏、身體落地 |
| 飛行 | 大擊退 + 旋轉、短暫失控 | 翅 / 尾彈簧 | 墜落（帶旋轉）+ 落地小爆 |
| 攀牆 | 被打掉牆 → 短暫掉落 | 尾巴 Verlet | 沿牆滑落 |
| 軌道 / 浮游 | 抖動 + 軌道偏移 | 外環彈簧 | 外環先散開、核心熄滅 |

---

## 來源（網址 + 一句重點）

- https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ ：Sakurai 論 hit-stop：依傷害決定長度、攻守雙方都凍結、刻意壓低上限、凍結中微震並衰減。
- https://infovore.org/?p=5275 ：Vlambeer「Art of Screenshake」整理：命中暫停 10～20 ms、第一格全白、擊退 3 px/格、開槍震動 +4、屍體 / 場景物件提供持久性。
- https://gamineai.com/blog/pixel-art-combat-fx-hitstop-smear-frames-impact-timing-2026 ：像素動作遊戲 FX 數字：輕擊 2～4 格、重擊 6～10 格、閃光 1～2 格、近戰震動 4～8 格、粒子數克制。
- https://bugnet.io/blog/how-to-fix-hitstop-or-freeze-frame-feeling-off ：hit-stop 只凍結參與者、使用不受縮放的時間、依力度縮放。
- https://slapcity.wiki.gg/wiki/Hitstop ：hit-stop 長度由傷害與擊退算出；多段攻擊可對兩方給不同值。
- https://game.capcom.com/cfn/sfv/column/131545 ：格鬥遊戲 hit-stop 慣例（輕中重 8/12/16 格、多段縮短）。
- https://www.scitepress.org/Papers/2024/124614/124614.pdf ：研究：hit-stop 最佳約 0.1～0.2 秒，慢動作約 0.2～0.4 秒。
- https://eldenring.wiki.gg/wiki/Poise ：韌性、超級護甲、敵人韌性每秒回復、stance break 的暴露窗口。
- https://hollowknight.wiki/w/Heavy_Blow ：Hollow Knight 擊退依敵人重量，可被護符放大。
- https://gtfo.wiki.gg/wiki/Precision_Multiplier ：弱點倍率常見 2～3，大型敵人較低（約 1.5）。
- https://uhiyama-lab.com/en/notes/godot/modulate-white-flash-damage-effect/ ：Godot `modulate` > 1 會發光（HDR）、要先 kill 舊 tween、`self_modulate` 避免影響子節點。
- https://gamedevacademy.org/godot-sprite-flash-tutorial/ ：Godot 受擊閃色的最簡寫法與 0.1 秒時間。
- https://uhiyama-lab.com/en/notes/godot/animation-player-advanced/ ：AnimationPlayer method track 開關 hitbox、命名有意義、要有 RESET。
- https://forum.godotengine.org/t/why-are-collisions-happening-1-frame-late/67044 ：碰撞可能比動畫晚一個物理影格生效。
- https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html ：AnimationTree 的 OneShot、篩選、StateMachine travel、root motion。
- https://docs.godotengine.org/en/4.2/classes/class_skeletonmodification2djiggle.html ：Jiggle 的 stiffness / mass / damping / gravity 與用途（次級動態）。
- https://docs.godotengine.org/en/4.2/classes/class_skeletonmodification2dphysicalbones.html ：PhysicalBones 把 PhysicalBone2D 的結果傳給 Bone2D，標示為實驗性。
- https://docs.godotengine.org/en/stable/classes/class_skeletonmodification2dtwoboneik.html ：TwoBoneIK 用餘弦定理、只能兩根骨頭、比 FABRIK 輕、實驗性。
- https://forum.godotengine.org/t/how-to-make-physical-bones2d-work/128754 ：PhysicalBone2D 教材很少，社群常用 RigidBody2D + 關節。
- https://docs.godotengine.org/en/3.1/tutorials/physics/ragdoll_system.html ：Ragdoll 每根被模擬的骨頭都有成本，小骨頭與輔助骨不要模擬。
- https://80.lv/articles/ik-driven-procedural-spider-locomotion-in-godot-4-5 ：多足 IK：射線感測落腳點、距離門檻踏步、對角組輪流、身體高度取腳平均。
- https://jonathanwhiting.com/writing/blog/verlet_rope ：Verlet 繩 / 鏈：用位置差代替速度、距離約束、多次迭代增加穩定。
- https://forum.godotengine.org/t/line2d-procedural-animations/66098 ：用 Line2D 點做尾巴 / 觸手程序動畫的社群做法。
- https://bugnet.io/blog/fix-godot-particles2d-one-shot-restart-broken ：一次性粒子要用 `restart()`，並池化多個實例。
- https://80.lv/articles/case-study-dead-cells-character-art-pipeline/ ：Dead Cells 3D 轉 2D 管線與法線貼圖精靈；不涉及受擊細節，作為「引擎程式碼多於 shader」的旁證。
- https://automaton-media.com/en/news/metal-slug-artist-akio-says-his-elaborate-pixel-animations-made-his-programmers-want-to-rip-their-hair-out-but-it-was-so-worth-it/ ：Metal Slug：冗長的敵人動畫沒有玩法功能，但讓世界活起來。
- https://www.moddb.com/features/direction-based-hit-reaction ：方向性受擊（以點積判斷前後 / 左右）；此頁讀取失敗，內容來自搜尋摘要。
- https://www.simonwhatley.co.uk/writing/disney-12-basic-principles-of-animation/ ：預備、跟隨、重疊動作的基本定義。

### 沒有找到的東西（誠實註記）

- Katana Zero、Hollow Knight、Cuphead、Blasphemous、Huntdown、Gunvolt 的第一手受擊毫秒數字沒有公開的 GDC / postmortem 可引用；本文對這些遊戲只用公開行為（擊退依重量、一擊致命的節奏、手繪預兆）做定性參考，不編造數字。
- 第 1.1 節表格、1.3 擊退距離、1.5 擠壓比例、3.3 前搖秒數、第 7 節屍體上限都是【建議】值，需要在實機用截圖 / 錄影逐一調整。
