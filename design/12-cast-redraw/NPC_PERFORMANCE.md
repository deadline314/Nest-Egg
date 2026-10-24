# NPC 與過場演員的動作表現（NE-250）

NE-206 讓 NPC 有了飄動、呼吸、換腳、轉頭。這份文件記錄第二輪：先列出還不自然的地方、查過的實例，再決定改什麼。
程式在 `game/rig/npc_gesture.gd`（手勢播放）、`npc_life.gd`（何時做什麼）、`npc_animator.gd`（姿勢切換、工作循環），
資料在 `art/rigs/npc_animations.json`（形狀）與 `art/motion/<角色>.json` 的 `npc.life`（個性）。

## 1. 修改前不自然的地方（2026-10-10 量測與畫面）

量測工具：`tools/npc_motion_strip.tscn`（`--metrics` 印數字、不加則截連續畫面）。pop＝骨頭角度每格的二階差分（弧度／格²），repeat＝說話時上臂動作在 0.5～4 秒延遲的自相關（1＝完全重複）。

| # | 角色／動作／時段 | 現象 | 數字或畫面 |
|---|---|---|---|
| 1 | 所有角色說話全程 | 手勢是固定週期的正弦擺動，所有人同一套，只差速度與幅度；Mei 的前臂像鐘擺來回 | repeat：老 K 0.967、Mei 0.958；`pm/Nest-Egg/images/NE-250-talk.png` 上半 |
| 2 | 所有角色坐→站、站→坐 | 姿勢瞬間換，第一格角度跳變；起身約 0.2 秒彈起，中途腳離地往前滑 | 起身 pop 0.127／0.138、坐下第一格腿 0.41（老 K 與 Mei 幾乎相同）；`NE-250-stand-up.png`、`NE-250-sit-down.png` 上半 |
| 3 | 同上 | 每個人起身的速度與方式一模一樣，沒有個性 | 兩人 pop 位置與數值逐位相同 |
| 4 | 擦手（老 K、阿莉）、攪鍋（阿莉）、敲打 | 工作循環是正弦：敲打沒有「慢舉、快敲、停一下」，每一圈完全相同；開始與停止的那一格直接加上骨頭角度 | `NE-250-wipe-hands.png` 上半 |
| 5 | 揮手 | 前臂與手同相位擺動；舉起的上臂袖子蓋過整張臉 | `NE-250-wave.png` 上半 |
| 6 | 聆聽 | 只是固定偏頭，從不點頭附和 | `NE-250-converse.png` 上半 |
| 7 | 站著待機 | 只有飄動、換腳、轉頭，沒有任何角色自己的小動作（揉脖子、看錶…） | 同上 |
| 8 | 轉頭 | 頭、頸、胸同時到位（視線、頭、身體沒有先後） | 程式：三者用同一個彈簧值 |
| 9 | 呼吸 | 吸氣與呼氣一樣長的正弦（人是吸短呼長） | 程式 |
| 10 | 打哈欠疊在靠牆姿勢 | 靠牆姿勢前臂已折 -1.7，打哈欠再加 -2.0，前臂折超過 180° | 資料 |

## 2. 查過的實例與做法

只列實際讀到原文的；讀不到的另外標明。

| 來源 | 實際看到的內容 | 採用／不採用 |
|---|---|---|
| Spine 官方〈Applying Animations〉 https://en.esotericsoftware.com/spine-applying-animations | 「automatically mix (crossfade) between the animations using the mix durations」；可設預設混合時間，也可逐對設定；「Tracks allow animations to be applied in layers」，高軌只覆蓋它有 key 的骨頭，alpha 可與下層混合 | **採用**：姿勢切換有時間、依「舊→新」逐對設定（`transitions`）；待機／說話／手勢分層疊加 |
| Live2D 官方 SDK〈Breath〉 https://docs.live2d.com/en/cubism-sdk-manual/breath | 呼吸以 (offset, peak, cycle, weight) 的正弦驅動參數；範例週期 6.5345、3.5345、5.5345、15.5345、3.2345 秒（刻意互不成整數倍），權重 0.5 | NE-206 已採用（不同步的週期）；**不採用**純正弦呼吸——改成吸短呼長（生理） |
| Live2D 官方 SDK〈Motion〉 https://docs.live2d.com/en/cubism-sdk-manual/motion/ | 動作有淡入、淡出秒數（未指定時預設 1 秒）；同時播放多個動作時「avoid making settings for the same parameter」，否則最後更新的蓋掉、淡出可能不乾淨 | **採用**：工作循環開始、停止緩入緩出；手勢與工作循環不同時搶手臂（手忙時說話只點頭） |
| Live2D 官方〈Eye Blinking〉、〈Auto Generation of Sway Motion〉 https://docs.live2d.com/en/cubism-editor-manual/eye-blink-settings/ 、…/auto-generation-of-sway-motion/ | 眨眼是 0～1 的倍率；小物件與頭髮的擺動自動產生再微調 | 眨眼已由 NE-221 處理；次級擺動用既有彈簧骨，不在本票 |
| Spine 官方〈Physics constraints〉 https://en.esotericsoftware.com/spine-physics-constraints | 頭髮衣物的次級動態用物理約束，以慣性、強度、阻尼、質量調整 | 已有彈簧骨；本票只用「餘勢」原則：收回時延續原本的速度（Hermite），不是突然停住 |
| Hu, Walker, Neff, Fox Tree〈Storytelling Agents with Personality and Adaptivity〉 https://arxiv.org/pdf/1709.01188 | 手勢分 prep／stroke／hold／retract 四段；「insert a hold and connecting prep between two strokes if they are less than 2.5 seconds away from each other. Otherwise, we insert a retraction」；重音比對應的字早 0.2 秒；外向者每句 1–2 個手勢，內向者刪減；個性用 gesture rate、speed、expanse 調整 | **採用**：手勢五段（多一段反向蓄勢）、接得近就不收回直接接、每個角色自己的頻率（every）、速度（speed）、幅度（expanse）與手勢清單 |
| 迪士尼動畫十二原則（維基百科整理） https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation | 預備「prepare the audience for an action」；跟隨與重疊動作；slow in／slow out「more pictures are drawn near the beginning and end」 | **採用**：起身前上身先前傾、手勢反向蓄勢；前臂與手晚一點跟上（drag）；所有切換用緩入緩出 |
| Spine 展示頁 Cult of the Lamb 美術總監引言 https://it.esotericsoftware.com/spine-showcase-all | 只確認該作用 Spine 做角色動畫，沒有描述做法 | 只當作「2D 骨架可以做出有表情的角色」的佐證，不當技術依據 |
| Unity〈Hollow Knight〉案例 https://unity.com/case-study/hollow-knight | 角色是手繪逐格 PNG，不是骨架 | 對照：不適用骨架做法 |

讀不到原文、沒有當作依據：Double Fine《Broken Age》GDC 講座（只看到摘要，影片需會員）、Vanillaware 與 Darkest Dungeon 的動畫做法（沒有找到官方說明）、Spine 論壇關於預設混合時間的討論（只看到搜尋摘要）。

## 3. 改了什麼

1. **說話手勢（NpcGesture＋NpcLife.beat）**：取代固定正弦。每個手勢是資料：準備姿勢、重音、反向蓄勢、各段秒數、骨頭拖曳（舉起時手肘先彎、肩後抬，放下時肩先落、手肘後伸）、停留時的下沉與搓動。說話時依角色的 `vocab` 權重挑手勢，連續兩次盡量不同；手勢之間依 `rest` 機率放下休息或直接接下一個（不收回，從目前位置與速度用 Hermite 接過去）。說完話從目前的位置與速度收回，不跳。
2. **聆聽點頭、待機小動作**：聆聽時依角色頻率點頭；站著沒事時做角色自己的小動作（老 K 揉後頸、阿莉看錶、夜班工人揉眼、Mei 碰耳機、居民搓手…）；手在忙或說話時不做。
3. **姿勢切換（transitions）**：坐、站、靠、蹲之間有秒數、主要動作延後（先做預備）、預備動作（起身前上身前傾、離牆時骨盆先往前推）；角色的 `posture.speed`、`posture.lead` 決定快慢與預備幅度（老 K 慢而大、Mei 快而小）。起身時腳先收回到身體下方再升骨盆；腳的 IK 先移到「站姿交接」位置（膝微彎）再淡出，避開兩骨 IK 在腿打直時的奇異點（見第 5 節）。過場演員從座位起身時，身體落回地面跟著起身的進度。
4. **工作循環（keys＋period＋vary）**：關鍵影格軌道可以有不對稱節奏（敲打：慢舉、停頂、快敲、回彈）；前臂、手用 `offset` 晚一點跟上；每一圈的長度與幅度在 `vary` 範圍內隨機（同角色可重現）；開始與停止各 0.45 秒緩入緩出。擦手改成「低頭擦 2～3 秒、抬頭停一下」的節奏；打哈欠改成仰頭伸展，不再折前臂。
5. 轉頭：頸與胸用較慢的彈簧追頭（視線、頭先動，身體約 0.1 秒後跟上）。呼吸：吸 40%、呼 60%。揮手：前臂與手錯開相位。

## 4. 結果（同一工具、同一腳本、含腿的 12 根骨頭，修前→修後）

| 量測（老 K／Mei） | 修前 | 修後 |
|---|---|---|
| 說話 20 秒，上臂動作的重複度 | 0.967／0.958 | 0.342／0.236 |
| 起身最大跳格（弧度／格²） | 0.127／0.138 | 0.010／0.026 |
| 站→坐→站全程最大跳格 | 0.409／0.406（坐下第一格腿瞬間折起） | 0.016／0.034 |
| 站↔靠牆 | 0.064／0.063 | 0.014／0.014 |
| 揮手 | 0.056 | 0.023 |
| 說話切換到聆聽 | 0.065／0.074 | 0.030／0.028 |

測試門檻（NpcAnimationSuite）：九位角色坐下再起身，腿、手、頭任一骨頭的跳格 < 0.035，且骨盆升起 20% 時上身已比坐著時前傾 0.08 弧度以上。

## 5. 踩過的坑（之後改 NPC 姿勢先看）

- **兩骨 IK 接近打直時，膝角對骨盆高度是平方根關係**：骨盆就算緩停，膝蓋仍以等速伸直到極限再突然停住。起身的終點不能是腿伸直的 IK；交接位置保留一點膝彎（`poses.stand.feet_handoff.reach` 0.99），最後的伸直交給 IK→站姿的緩入緩出。
- `max(姿勢下沉, 搆腳所需下沉)` 的兩條曲線交叉時骨盆會急停：讓姿勢下沉收斂到交接位置自己的搆腳下沉（兩條曲線在速度 0 處相會），再加平滑最大值。
- IK 淡出時把下沉「乘上權重」會讓骨盆升高、腿被拉直；改成在「站姿自己貼地的高度」與「IK 下沉」之間內插，貼地高度在 IK 之前用 FK 腿算（之後算會互相影響）。只移骨盆，不要呼叫 `_apply_body()`（它會把 IK 解好的腿蓋回 FK 角度）。
- 這些都只在 NPC 動畫器裡處理；`HumanoidAnimator._place_feet` 是主角也用的共用流程，沒有改。
- 手勢的總長要包含最晚收回的骨頭延遲，否則最後一格跳回原位。反向蓄勢要「退到底停一瞬」再出發，每段都從速度 0 開始、在速度 0 結束。
- 舉手的姿勢用角度寫時要算手的位置：上臂與前臂的總角度決定手在頭上方還是頸後（揉後頸：上臂 -1.75、前臂 -2.45，手在頸後；舊的 -2.2／-1.5 手在頭頂上方）。各角色手臂長不同，畫面要每人看過。

## 6. 還做不到、交給角色組

- 老 K 舉手灰色肩塊已由 NE-222 Commit-56（2026-10-24）局部修復：[來源控制與左右／揮手圖](../../pm/Nest-Egg/attachments/NE-222-old-k-shoulder/README.md)。灰塊烘在軀幹來源，根部固定試驗無效；修復只採來源遮罩內RGB，保留alpha、綁定與動作。原接點報告仍53,760筆／5,983失敗，完整接縫與自然動作驗收保持未完成。舊「補肩袖或改權重」為歷史候選，並非最終採用方案。
- 手勢目前以角度描述，不同手臂長的角色落點略有差異（例如抓頭時手在頭頂或後腦）；若要精確到「手放在胸口上」，需要以 IK 目標描述手勢（之後的票）。
