# 過場舞台與關卡佈景「合理性」：業界做法與可檢查規則

> 來源：2026-10-06 使用者回報梯子太短、麵攤過場的燈籠與桌椅比例怪異、角色站起來浮空、圖層穿插，要求把「合理的位置、佈景、過場動畫」寫進 skill，並參考更多不同的業界實例。這份是整理後的參考資料；做事的流程與檢查清單在 skill `scene-staging`（`.claude/skills/scene-staging/`）。
> 注意：整理時網路代理擋掉了網頁全文，數字來自搜尋摘要，條目已標【出處】【推導】【建議】【沒找到】。標【建議】或依據欄為 C 的數值是我們的起點，要以遊戲畫面實測調整；引用前請點出處核對。


調查日期：2026-10-06。方法：WebSearch 摘要（WebFetch 被代理擋下，所以沒有讀到任何全文）。
標記說明：
- 【出處】= 搜尋結果摘要裡真的出現，附網址。數字照搜尋摘要抄，未讀全文，引用前請抽查原文。
- 【推導】= 我用出處的數字換算（H = 人高 1.7 m = 170 cm）。
- 【建議】= 沒有出處，是我基於上述原則給我們專案的設計建議，需要你們實測後調整。
- 【沒找到】= 搜了但沒有可靠資料，不編造。

重要誠實聲明：關於 Celeste、Dead Cells、Katana Zero、VA-11 Hall-A、Hades、Dragon's Crown、Cuphead、Valkyria Chronicles 的「具體尺寸規範／過場構圖規則」，搜尋幾乎沒有找到開發者公開的數字。能確認的是少數幾個（Hollow Knight、Metroid、Mario World、Mask of the Rose），其餘標【沒找到】。業界慣例大多是「自己訂一個以角色為單位的 metrics，然後全團遵守」，而不是共通數字。

## 0. 核心結論（先看這段）

1. 一切尺寸以「角色身高 H」為單位，一個場景只允許一個 H（像素值），所有道具以 H 倍數登記。業界做法：先量角色（身高、跳高、跳遠、寬度），再用這些數字定義每個縫隙與走廊。
   【出處】https://www.wayline.io/blog/level-design-mastering-blocking-volumes 、https://www.seeles.ai/resources/blogs/unreal-engine-level-design-and-greyboxing-guide（摘要：「measure the character: max jump height and distance, run speed, reach… Every gap, ledge, and corridor is sized in these units」）
2. 分兩種 metrics：玩家／角色 metrics（引擎量出來的事實）與建築 metrics（你們編碼的建議尺寸）；並且提醒「不要迷信數字，不能靠量測做出好體驗」。
   【出處】https://https-book_leveldesignbook_com.proxy.bugsmash.io/process/blockout/metrics （The Level Design Book，Robert Yang；此為代理鏡像網址，原站應為 book.leveldesignbook.com，未驗證）
3. 地面接觸線、前後遮擋、縮放，三者其實是同一件事：每個物件有一條「接觸線 y」，排序用它、縮放用它、陰影也貼它。
4. 錯誤多半不是美術問題，是「資料沒有宣告尺寸與錨點」。能資料化就能自動檢查（見第 5、9 節）。

## 1. 人體工學與建築標準尺寸（換算成 H）

### 1.1 人體比例（以人高為基準）
- 美國人體測量表（男性中位）：身高 68.7 in、站姿眼高 64.7 in、坐高 34.1 in、坐姿眼高 31.0 in、膝高 21.3 in、膕窩高（坐面高度的依據）17.2 in。
  【出處】https://www.ergocenter.ncsu.edu/wp-content/uploads/sites/18/2017/09/Anthropometric-Summary-Data-Tables.pdf （數字取自搜尋摘要）
- 【推導】換算成 H：眼高 ≈ 0.94H；坐高（坐下時頭頂距坐面）≈ 0.50H；坐姿眼高 ≈ 0.45H（距地，含坐面）；膝高 ≈ 0.31H；膕窩高（合適椅座高）≈ 0.25H。
- 【建議】站姿髖關節高約 0.50–0.55H（本次搜尋沒找到引用，常見人體比例經驗值；請用自家骨架實測 hip 關節距腳底）。

### 1.2 建築與家具標準尺寸表（原始值 → H）
H = 1.7 m。下表「出處」欄為原始數值來源。

| 物件 | 標準值 | 換算 H | 出處／備註 |
|---|---|---|---|
| 門高 | 2040–2100 mm（美制 6'8" = 2032 mm） | 1.20–1.24H | 【出處】https://www.samsfabrications.co.uk/?p=743 ；美制見 Chico 手冊 https://chico.ca.us/documents/Departments/Community-Development/Building-Division/Forms--Handouts/stairs_handrails_and_guards_handout_4-1-09.pdf |
| 樓梯淨空高 | 最小 6'8" = 2032 mm | 1.20H | 【出處】同上 Chico |
| 居室天花板最小 | 7 ft = 2134 mm（IRC） | 1.25H | 【出處】https://www.hunker.com/12591709/what-is-the-minimum-ceiling-height-according-to-the-international-building-code |
| 一般室內天花板 | 2.4–2.7 m | 1.4–1.6H | 【建議】未找到出處；2D 舞台可依構圖再放高，但不應低於 1.25H |
| 椅座高（餐椅） | 18 in = 457 mm | 0.27H | 【出處】https://planner5d.com/blog/dining-table-height/ |
| 凳高（標準凳） | 650 mm | 0.38H | 【出處】samsfabrications 同上（來源較弱） |
| 餐桌面高 | 30 in = 762 mm；另一來源 700–740 mm | 0.41–0.45H | 【出處】planner5d 同上；samsfabrications |
| 椅座到桌面下緣的大腿空間 | 12 in = 305 mm | 0.18H | 【出處】planner5d / dutchcraftfurniture.com/blogs/news/a-complete-guide-to-dining-table-and-chair-heights |
| 吧台／櫃檯高 | 42 in = 1067 mm；另一來源 1020–1090 mm | 0.60–0.64H | 【出處】https://plankandbeam.com/blogs/home-inspiration-information/what-height-bar-stool-do-i-need ；samsfabrications |
| 吧台凳座高 | 30 in = 762 mm（與 42 in 吧台差 12 in） | 0.45H | 【出處】同 plankandbeam |
| 梯階（橫桿）間距 | 10–14 in（25–36 cm），中心到中心 | 0.15–0.21H（常用 12 in = 0.18H） | 【出處】https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.23 |
| 梯子超出上層平台 | 至少 3 ft = 914 mm（可攜式梯） | 0.54H | 【出處】同 OSHA 1910.23 |
| 樓梯級高（最大） | 7¾ in = 197 mm | 0.116H | 【出處】Chico 手冊、https://docs.legis.wisconsin.gov/document/administrativecode/SPS 321.04(2)(c) |
| 樓梯踏面深（最小） | 10 in = 254 mm | 0.149H | 【出處】同上 |
| 樓梯扶手高 | 34–38 in = 864–965 mm | 0.51–0.57H | 【出處】Chico 手冊 |
| 欄杆（住宅） | 36 in = 914 mm | 0.54H | 【出處】https://resources.viewrail.com/code-compliance/getting-started/ibc-vs.-irc-railing-code-requirements |
| 欄杆（商用 IBC） | 42 in = 1067 mm | 0.63H | 【出處】同上 |
| 窗台高 | IBC 最小窗台 36 in = 914 mm；窗台低於 24 in（610 mm）且離地外側高於 72 in 需防墜 | 0.54H（常見下限）；0.36H 為防墜門檻 | 【出處】https://buildingcodetrainer.com/window-fall-protection/ （摘要） |
| 門檻（ADA） | 高度上限 0.5 in | ≈ 0.007H（視覺上等於地面） | 【出處】https://www.enduraproducts.com/wp-content/uploads/2018/01/ADASillsBrochure.pdf（摘要）；2D 中門檻不該畫成台階 |

注意：以上是美國法規／零售尺寸，不是 Neufert 原文。Neufert《建築設計資料集》是公認的人體尺度權威，但本次搜尋只拿到介紹性頁面，沒有取得其具體數字【沒找到具體數字】。

### 1.3 遊戲引擎社群常用比例（以角色為尺）
- Source 引擎：角色 72 單位（約 1.8 m）、牆磚 128 單位、門高 96 單位。換算：牆磚 ≈ 1.78H、門 ≈ 1.33H。
  【出處】https://polycount.com/discussion/comment/1172403 （與同系列 polycount 討論串；摘要）
- Unreal：角色約 180 單位；門高 210–230、門寬 110–140；樓梯級高 15、踏面 30（1.8 m 角色）。換算：門高 1.17–1.28H、門寬 0.61–0.78H、級高 0.083H、踏面 0.167H。
  【出處】https://www.worldofleveldesign.com/categories/ue5/guide-to-scale-dimensions-proportions.php
- Quake：碰撞盒 32×32×56；最小走廊寬 33、最小天花板 57。換算：最小淨高 ≈ 1.02 倍碰撞盒高（這是「剛好能過」的絕對下限，不是美觀值）。
  【出處】https://https-book_leveldesignbook_com.proxy.bugsmash.io/process/blockout/metrics/quake
- 重要警告：很多建築尺寸會為了節奏與鏡頭而調整，務必在遊戲內測試能不能走過去。
  【出處】polycount 討論串摘要，同上。
- 結論【推導】：真實門高約 1.2H；遊戲為了視覺通常放大到 1.2–1.35H。我們的 2D 舞台建議用 1.2–1.3H（見第 8 節）。

## 2. 2D 橫向遊戲的場景比例與可讀性

### 2.1 有找到具體數字的
- Hollow Knight：Knight 精靈 77×128 px；Team Cherry 用 64×64 px 黑色方塊做關卡 blockout（牆與地），HD 美術再手動疊上去。
  【推導】128 px = 2 個方塊 → 角色身高 H = 2 tiles；最小通道 = 3 tiles 高（H 加餘裕約 0.5H）時最舒服（此為推導，未驗證遊戲內實際通道）。
  【出處】https://hollowknight.wiki/w/File:The_Knight_Map.png 與 itch.io 討論 https://itch.io/post/2180877 （摘要，可信度中等：社群來源）
- Metroid／Super Metroid：關卡以 16×16 區塊為單位（底層 8×8 像素精度）；Samus 是「雙倍高」角色，約 2 個區塊高。
  【出處】https://nesdev.nes.science/f2/t17736.xhtml 、https://forum.metroidconstruction.com/index.php/topic,1684.0.html （摘要）
  同源摘要提到「門應與玩家角色等高」的設計想法（可信度低，視為建議）。
- Super Mario World：全部距離標準化為整數方塊；無助跑可跳 4 格高，助跑 1 格可跳 5 格，助跑 11 格可到 6 格。
  【出處】https://www.quaddicted.com/webarchive/thegamedesignforum.com_20160521/features/RD_SMW_3.html
  【推導】→ 「把關卡做成與角色能力對應的格數」的實例：平台高度、縫隙寬度都是跳躍能力的離散倍數，留一格餘裕。
- Super Mario Bros. 1-1：四根高度不同的水管，用來教「按住跳躍鍵越久跳越高」；坑洞大小逐步教奔跑跳。
  【出處】https://en.wikipedia.org/wiki/World_1-1
- Suzy Cube：平台遊戲要避免「跳躍曖昧（jump ambiguity）」——玩家無法判斷能不能跳過；用方塊化物件讓高度和縫隙易於量測。
  【出處】https://www.gamedeveloper.com/design/lessons-from-suzy-cube-measuring-up
- Celeste：內部解析度固定 320×180。
  【出處】https://en.wikipedia.org/wiki/Celeste_(video_game)
  角色 hitbox／tile 尺寸：有摘要說 tile 基準 8 px、角色約 2 個 16×16 高，但同一摘要內容自相矛盾，我沒能驗證【沒找到可靠數字】。

### 2.2 搜了但沒找到公開數字
- Dead Cells：只找到 3D 轉 2D 管線（Thomas Vasseur 用 3DS Max 骨架轉 2D），沒有角色佔畫面比例或門高的數字。
  【出處（管線）】https://80.lv/articles/interview-with-the-developers-of-dead-cells
  【沒找到】角色／門高／平台高度規範。
- Katana Zero、Hades、Cuphead、Dragon's Crown：【沒找到】尺寸規範。Cuphead 只確認「手繪逐格＋水彩背景」的 1930 年代做法（https://www.cbc.ca/lite/story/1.4350427）；Dragon's Crown 只確認西洋繪畫風格與 Flash 式關節動畫（https://en.wikipedia.org/wiki/Vanillaware）。

### 2.3 可操作的通道／平台規則
- 【建議】通道最小淨高 = H + 餘裕。住人空間用 1.2–1.3H（等同真實門高）；戰鬥／跳躍用走廊用 H + 跳躍頭頂餘裕（至少 0.25H，Hollow Knight 實例為 1.5H 的 3 tile 通道，屬推導）。
- 【建議】平台高度 = 跳高的 0.5–0.9 倍（留餘裕，避免「剛好跳不上去」）；落差標示（發光邊緣、顏色）。Suzy Cube 的曖昧問題即此。
- 【建議】過場的舞台不需要可跳躍，但視覺尺度應與遊玩關卡共用同一個 H，否則「過場裡的門」與「關卡裡的門」不一致。
- 【建議】角色在畫面的佔比：對話過場中景（全身）時 H ≈ 畫面高度 30–45%；特寫用立繪。數字無出處，依構圖取捨。

## 3. 視覺小說／冒險／過場的舞台構圖

### 3.1 有出處的規則
- 站位槽位化：Mask of the Rose（Failbetter Games）把場景分成 5 個進場位置（lines）；單人固定在第 4 條線，第二人固定在第 2 條線，依此類推；位置與朝向由規則自動決定。
  【出處】https://www.failbettergames.com/news/character-positioning-in-mask-of-the-rose
- 預設朝向：在左邊的人面向右，在右邊的人面向左，必要時敘事上覆寫。同上。
- 180 度規則：兩人之間有條想像的視線軸，鏡頭不跨過它；對切特寫時一人看畫面右、另一人看畫面左，若同向代表跨線，空間關係會亂。
  【出處】https://artlist.io/blog/180-degree-rule/ 、https://artlist.io/blog/?p=3201
- 三分法：主體放在三分線或交叉點；視覺小說裡角色頭部常落在交叉點。
  【出處】https://journalism.university/electronic-media/mastering-composition-cinematic-visual-rules ；https://www.failbettergames.com/character-positioning-in-mask-of-the-rose
- 視線空間（lead room / looking room）：臉朝的方向要留空間，切太緊會有壓迫感；角色朝畫面左看，通常放在畫面右側，讓左邊有空間（可打破）。頭頂空間（headroom）太少會擠，太多會像下沉。
  【出處】https://neiloseman.com/lead-room-nose-room-or-looking-space/
- 站位與關係：blocking 決定距離、親密或衝突、權力；過肩鏡頭用 Z 軸疊合（前景肩膀＋背景人臉）建立深度。
  【出處】https://nofilmschool.com/blocking-a-conversation 、https://en.wikipedia.org/wiki/Over-the-shoulder_shot
- Disco Elysium：固定視角讓每個畫面被當成「一幅完整的畫」，用古典構圖法管理注意力。
  【出處】https://shazoo.ru/2026/02/04/179176/izometriia-kak-xolst-art-direktor-disco-elysium-obieiasnil-vizualnyi-uspex-igry （俄文，摘要）
- Valkyria Chronicles：過場以「書頁」呈現，故事書背景上有全動畫與配音。
  【出處】搜尋摘要（來源為商品頁，可信度低）；構圖細節【沒找到】。
- VA-11 Hall-A、Hades 對話、Katana Zero 過場：【沒找到】公開的構圖規則。

### 3.2 地平線、透視與比例一致
- 地平線＝眼睛高度（eye level）；背景的 eye level 必須與角色的 eye level 一致。
  【出處】https://tips.clip-studio.com/en-us/articles/4488
- 同一地面上的人物：把新角色等比放大／縮小，使其肩（或眼）與地平線相交；多人身高不同時，以中等身高者定地平線。同上。
- 【推導】（透視幾何）側視平地上，物件螢幕大小與「接觸點在地平線下方的距離」成正比。縮放公式：
  `scale(y) = (y_foot − y_horizon) / (y_ref − y_horizon)`，其中 y_ref 是定義 H 的參考接觸線。
- 另有業界簡化版：縮放隨 y 非線性，參數為地平線 Y、畫面底部最大縮放、Y 指數。
  【出處】https://wiki.gdevelop.io/gdevelop5/extensions/depth-effect/ 、搜尋摘要另提到「物件越靠近地平線，速度也要跟著縮」。
- 【建議】我們的舞台若是「側視、平面背景」：預設 horizon 在畫面外上方很遠（等於不縮放），多人站位只靠前後排序，不縮放；一旦背景畫了明顯透視（地板格線、長走廊）才啟用 scale(y)。兩種模式不可混用。

### 3.3 分層、景深與接觸陰影
- 層結構：前景、中景（可玩／演員所在層）、背景、靜態最遠層；視差速度：前景最快、背景最慢；常用 3–4 層（天、遠、中、近）。
  【出處】https://gamemaker.io/blog/creating-depth-and-immersion-parallax 、https://binus.ac.id/bandung/dkv/2025/11/04/backgrounds-that-breathe-creating-depth-in-flat-worlds/
- 大氣透視：越遠越淡、細節越少、飽和度越低、偏冷藍灰。同 binus 網址。
- 接觸陰影／blob shadow：用一張半透明黑色精靈跟著角色，幫角色「落地」；也有把精靈斜切貼地的變體；軟陰影位於接觸處。
  【出處】https://answers.unrealengine.com/questions/913516/view.html 、https://engine.needle.tools/docs/how-to-guides/components/contact-shadows
- 【建議】每個站在地上的物件（含演員）都有一個接觸陰影，寬度 ≈ 腳寬或底座寬 × 1.1–1.4，高度 ≈ 寬度 × 0.2–0.35（壓扁橢圓），不透明度 30–50%；這是修「飄浮感」最便宜的手法，同時也暴露接觸線對不齊的物件。
- 賽博龐克場景【建議】：霓虹在地面的反光（彩色橢圓）與接觸陰影分開兩層，反光不能取代陰影。

---------------------------------------------------------------------
## 4. 坐、靠、蹲、起身：與家具互動的動畫

### 4.1 業界做法（有出處）
- Naughty Dog（Uncharted 4）：交付前的打磨清單包含「所有 contact points 都要和環境對上」。
  【出處】https://www.gameanim.com/?p=13879 （Interactive Cinematics In Uncharted 4；摘要，細節我沒讀到全文）
  Uncharted 動畫管線整體：https://www.gameanim.com/?p=192 ；GDC 2017 清單：https://www.naughtydog.com/blog/naughty_dog_gdc_2017
  【沒找到】contact point 的具體演算法、數字。
- 程序式坐下：IK 目標套在腳（坐下時腳要貼地）、髖（依家具高度調整髖高）、手；不用為每種椅高做動畫。
  【出處】https://www.animationmentor.com/blog/tutorial-animate-characters-sitting-down/ 、https://thegameswiki.com/paralives/wiki/procedural-animation
- 互動點：在椅子模型地面高度放一個 null transform，定義坐定後的位置與朝向（前向指向椅子正面）；走進椅前的觸發區就啟動坐下腳本。
  【出處】https://www.highfidelity.com/backlog/please-take-a-seat-729f5f3db66c
- 混合法：下半身用靜態動畫、上半身用即時控制加 IK。同 thegameswiki。
- Unity Animation Rigging：Two Bone IK 有目標（手／腳要到哪）與提示（肘／膝朝哪）；可疊多層 rig（腳 IK、瞄準、手 IK）各自加權淡入淡出。
  【出處】https://mocaponline.com/blogs/mocap-news/unity-animation-rigging-guide 、https://docs.unity3d.com/Packages/com.unity.animation.rigging@0.3/manual/ConstraintComponents.html
- Godot 2D 的對應：Marker2D 是編輯器用的位置標記（可當錨點）。【出處】https://docs.godotengine.org/en/4.2/classes/class_marker2d.html ；Godot 沒有內建「坐下」系統，我沒找到官方範例【沒找到】。

### 4.2 給 2D 骨架演員的規則（【推導】＋【建議】）
家具宣告 `seat_anchor`（座面中心上表面的點，單位 px，家具原點在地面接觸線上）：
1. 坐姿：骨盆（hip 關節）放在 `seat_anchor` 上方 ≈ 0.04–0.06H（臀部厚度，【建議】需實測）；腳底接觸線 = 地面 y（或腳凳面）。檢查：`seat_height_h ≈ 0.25–0.30H`，椅子高度偏離此範圍時腳會懸空或膝蓋過高。
2. 重心：骨盆水平位置落在座面 x 範圍的中 60% 內；背靠椅背時，上背接觸椅背 x。
3. 椅腳／椅座底部與地面接觸線一致；人坐著時椅子不能動、不能懸空（椅子是靜態圖層，演員去貼它）。
4. 髖高變化：站→坐，骨盆下降量 ≈ 站姿髖高 − 座面高 − 臀厚 ≈ 0.52 − 0.27 − 0.05 ≈ 0.20H 【推導，依 1.1 節假設，請實測】。
5. 起身過渡：不要瞬間切換。順序：身體前傾（重心前移到腳上）→ 腳收到臀下 → 骨盆上升（先慢後快）→ 站直；若用位移動畫，根（腳）要先鎖在地面接觸線，上升的是骨盆，而不是整個精靈往上漂。浮空 = 骨盆上升時沒有把腳鎖在地面（IK 缺失）。
6. 靠（牆／欄杆）：接觸點是肩或背，距牆 ≈ 身體厚度（0.1–0.15H）；腳底仍在地面線。
7. 蹲：骨盆降到 ≈ 0.30–0.35H，腳底不離地；蹲下時精靈高度變矮，但腳底接觸線不變（錨點在腳底，不在精靈中心）。
8. 所有姿態都以「腳底中點」為精靈原點（Godot 論壇建議：精靈 0,0 位於腳，Y 排序才準）。【出處】https://forum.godotengine.org/t/how-do-i-make-a-y-sort-origin-for-isometric-tiles/42450 、 https://itch.io/t/4929337/how-to-make-y-sorting-in-rpg-games （摘要）
9. 坐在椅上時 y 排序鍵仍用「椅子接觸線」，而不是骨盆位置，否則會穿插。

---------------------------------------------------------------------
## 5. 場景一致性檢查與自動化

### 5.1 有出處的審查原則
- Greybox 階段用無紋理方塊以正確比例建好全場，在改動便宜時驗證動線、視線、可達性；審查者包括關卡設計、專案主管與 QA。
  【出處】https://www.seeles.ai/resources/blogs/unreal-engine-level-design-and-greyboxing-guide 、https://www.wayline.io/blog/level-design-mastering-blocking-volumes
- 細化後保留 blockout（隱藏或放另一層）當比例與間距參考，換成正式美術時不要失準。同 wayline。
- 環境敘事：道具依「使用邏輯」而非格線排列（如拉開的椅子暗示剛有人坐過、地板磨損顯示動線）；每個房間大小的空間一個主要敘事線索＋兩個次要線索。
  【出處】https://pulsegeek.com/articles/environmental-storytelling-techniques-for-games/ ；Don Carson 提出此詞的背景見 https://amara.org/videos/Lv64YfjMFhOC/en/3102784 （摘要）
- 自動驗證：以「不變式」檢查——從起點到所有目標的可達性（走格圖 BFS）、幾何重疊、生成點合法性；BeamNG 的 Level Validator 能找出浮空物件、重複物件、材質錯誤。
  【出處】https://pulsegeek.com/articles/automatic-map-validation-rules-catch-errors-early/ 、https://documentation.beamng.com/world_editor/windows/level_validator

### 5.2 可寫成自動檢查的規則（【建議】，閾值為預設值，可依場景資料覆寫）
假設每個物件資料有：`size_h`（高寬以 H 為單位）、`ground_y`（接觸線，場景座標）、`layer`、`anchors`。

| 編號 | 規則 | 預設閾值 | 抓到的錯誤 |
|---|---|---|---|
| R1 | 物件高度落在其「類別範圍」（第 8 節表）內 | 超出範圍 → 錯誤；超出 ±15% → 警告 | 燈籠比人大、板凳比桌子高 |
| R2 | 同組家具比例關係：椅座高 ∈ [0.22, 0.32]H；桌面高 ∈ [0.40, 0.48]H；桌面高 − 椅座高 ∈ [0.14, 0.24]H；吧台凳座高 = 吧台高 − 0.15～0.20H | 同左 | 板凳與桌子不成比例 |
| R3 | 垂直結構：梯子橫桿數 ≥ 攀爬高度 ÷ 0.21H，≤ 攀爬高度 ÷ 0.15H；梯子上端超出平台 ≥ 0.4H | 同左 | 梯子只有三格、房間十格 |
| R4 | 接觸線一致：站在地面的物件 `ground_y` 必須落在該場景的「地面帶」[floor_top, floor_bottom] 內，且同一深度層的物件 `ground_y` 誤差 ≤ 2 px（或 0.01H） | 2 px | 腳底與地面線沒對齊、地面接觸線不一致 |
| R5 | 演員腳底 y = 其站位 `ground_y`（誤差 ≤ 1 px）；坐姿時骨盆高度落在 `seat_anchor` + [0.03, 0.08]H | 1 px | 浮空、坐在懸空椅子上 |
| R6 | 座位互動點：`seat_anchor` 必須在家具矩形內且離地 ∈ [0.22, 0.32]H；演員 `seat_anchor` 對應的角色 hip 距離 ≤ 0.06H | 同左 | 椅子懸空、陷入 |
| R7 | 不陷入地形：物件底邊不可低於 `floor_bottom` 超過 2 px，也不可浮在 `floor_top` 上方 > 2 px（除非標記為 `floating`／懸掛物） | 2 px | 物件陷入或飄浮 |
| R8 | 通道淨高 ≥ H × 1.2（過場舞台）／ 遊玩區 ≥ H + 0.25H | 同左 | 角色頭撞天花板、門太矮 |
| R9 | 縮放一致：若場景啟用透視，演員縮放 = `scale(y)`（第 3.2 節）誤差 ≤ 3%；不啟用則所有演員縮放 = 1 | 3% | 角色縮放與背景透視不一致 |
| R10 | 層次：演員與家具的排序鍵 = `ground_y`；同一演員所有零件共用同一鍵（見第 6 節） | — | 前後遮擋錯誤 |
| R11 | 互動範圍與視覺一致：互動觸發區（碰撞盒）必須與物件可見範圍重疊 ≥ 80% | 80% | 看得到卻碰不到、碰得到卻看不到 |
| R12 | 構圖：演員 x 位置落在站位槽位上（第 7 節）；兩人間距 ≥ 0.6H（不重疊）且 ≤ 4H（對話不遠）；臉朝向對方（面向 sign 與相對 x 一致） | 同左 | 站位亂、背對對方 |
| R13 | 比例審查圖：偵錯模式畫出 H 的刻度尺（1H、0.5H 格）與地面線，截圖輸出給人審 | — | 人眼才看得出的比例問題 |

### 5.3 資料格式建議（讓內容以資料為主）
- 場景資料：`scene.h_px`、`scene.floor_band = [y_top, y_bottom]`、`scene.horizon_y`（可 null）、`scene.mode = flat|perspective`。
- 物件資料：`prop.kind`（對應第 8 節類別）、`prop.size_h = [w, h]`、`prop.anchors = {seat, lean, grip, ...}`、`prop.layers = {back, front}`、`prop.ground_contact = {x_center, y}`。
- 檢查在匯入／測試時跑，錯誤訊息指出「場景 id／物件 id／規則號／實際值／允許範圍」。

---------------------------------------------------------------------
## 6. 圖層前後遮擋（z 排序）

### 6.1 有出處的做法
- Godot：在父節點啟用 Y Sort；Y 排序是依「節點位置」而不是精靈偏移，所以精靈 0,0 應在腳底；TileMap 的每個磚要把 Y Sort Origin 設在視覺底部（預設是磚中心，對高圖是錯的）；`z_index` 會覆蓋 Y 排序，需注意。
  【出處】https://forum.godotengine.org/t/how-to-make-y-sort-for-tilemaplayer-in-godot-4-3/87689 、https://forum.godotengine.org/t/how-do-i-make-a-y-sort-origin-for-isometric-tiles/42450 （摘要）
- 打架遊戲式做法：把 Y 與 Z 綁定，越靠下越靠前（Double Dragon、Castle Crashers 類）。
  【出處】搜尋摘要來自 https://discussions.unity.com/t/2d-beat-em-up/658033 與 https://wiki.gdevelop.io/gdevelop5/extensions/depth-effect/
- 層結構：前景在可玩層之前、背景在之後，前景視差最快。見 3.3 節出處。

### 6.2 規則（【建議】）
1. 排序鍵 = 物件接觸線 y（腳底／家具底邊），不是精靈中心、也不是圖片頂端。
2. 演員全部零件（身體、手臂、武器、頭髮、陰影）放在同一個節點下，當一個單位排序；內部相對順序用該節點內的 z_index，不要讓零件各自參與場景排序（否則會與家具穿插）。
3. 會「包住」演員的家具拆成兩張圖：`back`（椅背、桌子後緣，永遠在演員後面）與 `front`（桌面前緣、吧台前板、椅子扶手，永遠在演員前面）；坐在椅上時演員夾在兩者之間。
4. 接觸陰影排在家具與演員之下、地面之上（固定在地面層之上一格）。
5. 前景遮擋物（柱子、霓虹管線、欄杆、植物）：只放在畫面邊緣 1/6 以內或不擋臉的下緣；不遮擋對話中角色的臉與眼睛；用半透明或虛化表現層次。【建議】，屬構圖慣例，原則來源見 3.3 節分層做法。
6. 不用 z_index 蓋過 Y 排序，除非是明確的 `always_front` 或 `always_back` 標記物件。

---------------------------------------------------------------------
## 7. 過場站位與構圖模板（【建議】，結合 3.1 節出處）

槽位化（參考 Mask of the Rose 的 5 槽位）：以畫面寬 W 為準，槽位 x = 0.12W、0.30W、0.50W、0.70W、0.88W。
- 單人：中央偏一側（0.30W 或 0.70W）；或置中（0.50W）做獨白。
- 兩人對話：0.30W 與 0.70W（距離 0.4W），朝向對方；說話者可略往前（y 往下 0.02–0.04H）而不是放大。
- 三人：0.15W、0.50W、0.85W；中間者 y 往上（較遠）或往下（較近）錯開，避免三人一排像合照。
- 多人（4–5 人）：兩排，後排 y 往上 0.05–0.10H，前後排 x 錯開，後排頭頂不被前排遮住臉。
- 朝向：左邊的人面向右，右邊的人面向左；跨線時（180 度規則）在整段對話內保持同一側，換邊只在明確切鏡時。
- 視線空間：朝左看的人放在偏右，反之亦然；頭頂留 0.15–0.35H（無出處的經驗值，依鏡頭調整）。
- 角色眼睛放在畫面上 1/3 線附近；地平線（若有）切在眼高 ≈ 0.94H 附近或肩高（見 3.2）。
- 留白：對話區上方留給光源／霓虹招牌，下方留給字幕框；字幕框不遮臉與接觸線。
- 構圖用「主角色臉」在 1/3 線，次要物件放在角色視線延伸處，避免與臉競爭。

---------------------------------------------------------------------
## 8. 給我們的尺寸比例表（以 H 為單位）

H = 角色站立身高（含頭髮，不含帽子、角）。一個場景只有一個 H。
「依據」欄：A = 第 1 節標準尺寸直接換算；B = 遊戲引擎社群慣例；C = 無出處的建議。

| 類別 | 物件 | 高度（H） | 寬／深（H） | 依據／備註 |
|---|---|---|---|---|
| 結構 | 門（洞口高） | 1.20–1.30 | 寬 0.50–0.65 | A/B；門框要比角色頭高 ≥ 0.2H |
| 結構 | 室內天花板高 | 1.40–1.80 | — | A（下限 1.25）＋C |
| 結構 | 門檻／地面高低差 | ≤ 0.02 | — | A（ADA） |
| 結構 | 窗台高 | 0.50–0.60 | 窗寬 0.4–1.2 | A（0.54） |
| 結構 | 欄杆／扶手 | 0.51–0.63 | — | A |
| 結構 | 樓梯級高／踏面 | 0.09–0.12／0.15–0.17 | — | A/B；整層高 1.4H 約 12–15 級 |
| 結構 | 平台層高（二樓地面） | 1.50–1.90 | — | C（≥ 天花板淨高） |
| 垂直 | 梯子橫桿間距 | 0.15–0.21（常用 0.18） | 梯寬 0.30–0.40（C） | A（OSHA 10–14 in） |
| 垂直 | 梯子超出上層平台 | ≥ 0.4–0.55 | — | A（OSHA 3 ft = 0.54H） |
| 垂直 | 梯子橫桿數（爬升 1.0H／1.5H／2.0H） | 約 5–7／8–10／11–13 | — | 【推導】= 高度 ÷ 0.18H；十格高的房間就要約 10 橫桿以上 |
| 坐具 | 椅座高 | 0.25–0.30 | 座寬 0.25–0.30、深 0.24–0.28 | A（0.27）；寬深為 C（450 mm 座寬 ≈ 0.26H 見 samsfabrications） |
| 坐具 | 椅背總高 | 0.50–0.60 | — | C |
| 坐具 | 板凳／圓凳 | 0.30–0.40 | 0.18–0.30 | A（650 mm = 0.38H）；必須低於同場桌面高 −0.14H |
| 坐具 | 吧台凳 | 0.43–0.48 | 0.20–0.25 | A（30 in = 0.45H） |
| 坐具 | 沙發座高／總高 | 0.22–0.28／0.45–0.55 | 寬 0.9–1.4 | C |
| 桌面 | 餐桌／書桌面高 | 0.41–0.45 | 寬 0.8–1.6、深 0.4–0.6 | A；桌下留 ≥ 0.2H 高放腿 |
| 桌面 | 吧台／櫃檯面 | 0.60–0.64 | — | A |
| 桌面 | 床面（含床墊） | 0.25–0.32 | 長 1.15、寬 0.6–0.9 | C |
| 收納 | 書櫃／貨架 | 1.0–1.3 | 深 0.15–0.25 | C |
| 收納 | 木箱／板條箱 | 0.2–0.5 | 0.2–0.5 | C |
| 收納 | 酒桶 | 0.4–0.6 | 0.3–0.45 | C |
| 賽博龐克 | 自動販賣機 | 1.0–1.15 | 寬 0.45–0.6 | C |
| 賽博龐克 | 霓虹招牌（店面橫招） | 0.2–0.6 | 寬 0.8–3 | C；高於門頂、不低於 1.4H 離地 |
| 賽博龐克 | 路燈 | 2.0–3.0 | 桿徑 0.04 | C |
| 手持小物 | 提燈（手提） | 0.12–0.25 | 0.08–0.15 | C；超過 0.3H 就像在拿燈籠柱 |
| 手持小物 | 掛燈籠（垂吊，一般） | 0.15–0.35 | 0.12–0.25 | C；掛的位置 ≥ 1.25H（高過頭） |
| 手持小物 | 酒瓶／杯 | 瓶 0.12–0.18／杯 0.04–0.08 | — | C |
| 手持小物 | 武器（長槍／刀） | 刀 0.4–0.6／長槍 1.0–1.3 | — | C |
| 互動空間 | 椅座到桌下緣的大腿空間 | 0.14–0.20 | — | A（12 in = 0.18H） |
| 互動空間 | 兩人站距（對話） | — | 中心距 0.6–1.5；握手距離 ≈ 0.5 | C |
| 互動空間 | 通道淨高（過場） | ≥ 1.2；遊玩區 ≥ 1.25 | 寬 ≥ 0.45 | A/C；Quake 最小淨高僅 1.02 倍碰撞盒（極限值，不推薦） |
| 人體 | 眼高／坐高／膝高／膕窩 | 0.94／0.50／0.31／0.25 | — | A 推導（NCSU） |

表使用規則：
- 若美術設計意圖超出範圍（巨大招牌、小人國），必須在資料中標記 `scale_exempt: true` 並寫原因。
- 角色不是 1.7 m（如兒童、機器人）時，仍以「該角色的 H」套同一張表，但家具改以「人類 H = 1.0」當基準，不隨角色縮放（家具是世界尺度，不是角色尺度）。這點【建議】需專案決策。

---------------------------------------------------------------------
## 9. 過場舞台檢查清單

### A. 開工前（定義）
- [ ] 本場景 `H` 已定義（px），所有道具以 H 倍數登記；與遊玩關卡的 H 一致。
- [ ] 地面帶 `floor_band` 與 `horizon_y`（或 `flat`）已定義，並畫在偵錯圖上。
- [ ] 每個站立物件有 `ground_contact`（接觸線），每個互動家具有 `seat_anchor`／`lean_anchor`。
- [ ] 圖層劃分：背景／中景（演員）／前景遮擋；每個遮擋家具拆成 back／front。

### B. 比例（對應 R1–R3、R8）
- [ ] 門高 1.2–1.3H；天花板 ≥ 1.25H；不出現「比人還矮的門」。
- [ ] 椅座 0.25–0.30H；桌面 0.41–0.48H；桌椅差 0.14–0.24H；吧台凳比吧台矮 0.15–0.20H。
- [ ] 梯子橫桿數 ≈ 高度 ÷ 0.18H；梯子上端超出平台。
- [ ] 手持物（燈籠、瓶、武器）不大於 0.3H（長兵器除外）；掛燈籠不比頭大 1.5 倍以上。
- [ ] 沒有「不同比例的同類物件」（兩張椅子大小不同要有理由）。

### C. 地面與接觸（對應 R4–R7）
- [ ] 所有站地物件底邊落在地面帶內；同深度物件接觸線差 ≤ 2 px。
- [ ] 演員腳底 = 站位接觸線；坐著時骨盆落在座面上；站起來時腳未離地。
- [ ] 每個站地物件有接觸陰影；陰影與底邊貼合不留縫。
- [ ] 沒有陷入地面或浮空的物件（懸吊物件已標 `floating`）。

### D. 遮擋與排序（對應 R10）
- [ ] 排序鍵 = 接觸線 y；演員零件同一節點。
- [ ] 桌椅 back／front 分層正確：演員夾在中間時，腿在桌下、手在桌上。
- [ ] 前景遮擋物不擋臉、不擋字幕。

### E. 透視與景深（對應 R9）
- [ ] 若背景有透視：演員縮放 = scale(y)；若平面背景：所有演員縮放 = 1。
- [ ] 背景遠層較淡、較冷、較少細節；視差速度前快後慢。
- [ ] 地平線／eye level 與角色一致（以演員肩或眼為準）。

### F. 構圖（對應 R12，第 7 節）
- [ ] 站位用槽位；左邊面向右、右邊面向左；對話期間不跨 180 度線。
- [ ] 臉朝向有視線空間；頭頂留白合理；眼睛接近上 1/3 線。
- [ ] 說話者以前後位置強調，而非放大。
- [ ] 前景、中景、背景各有明確功能，沒有無意義的雜物搶焦點。

### G. 驗收
- [ ] 偵錯模式截圖（H 刻度尺＋地面線＋接觸點）存檔；至少一張「不開偵錯」成品圖。
- [ ] 自動檢查腳本 0 錯誤、0 警告（或警告已逐條說明）。
- [ ] 換不同解析度（16:9、21:9）構圖仍成立。

---------------------------------------------------------------------
## 10. 常見錯誤對照表

| 症狀 | 常見原因 | 對應規則／修法 |
|---|---|---|
| 燈籠比人還大 | 素材來源比例不同，直接擺上；沒登記 `size_h` | R1：以 H 倍數登記並用類別範圍檢查；手持 ≤ 0.25H、掛燈籠 ≤ 0.35H |
| 板凳與桌子不成比例 | 兩張圖獨立生成／繪製，沒有共用 H | R2：桌面 0.41–0.48H、凳 0.30–0.40H 且桌凳差 ≥ 0.14H |
| 梯子三格高、房間十格高 | 梯圖被拉伸或裁切，橫桿數不隨高度走 | R3：橫桿數 = 高度 ÷ 0.18H；超出上平台 0.4–0.55H；梯圖用可重複橫桿（tile）而非整張縮放 |
| 角色腳底與地面線沒對齊 | 精靈原點在圖片中心或底部留白；站位用精靈中心定位 | R4/R5：原點設在腳底中點；站位直接給接觸線 y；匯入時偵測腳底像素 |
| 坐在椅子上但椅子懸空 | 椅圖留白在底部，或座面高與骨盆高沒對 | R6：宣告 `seat_anchor`，骨盆貼座面；椅腳底邊 = 地面接觸線 |
| 站起來時浮空 | 起身只動精靈，不鎖腳；過渡沒有 IK | 4.2 第 5 點：先鎖腳，再升骨盆；根錨點在腳底 |
| 演員與家具遮擋錯誤 | 排序鍵用精靈中心；零件各自排序；家具沒拆 back/front | 6.2：鍵 = 接觸線 y；演員零件同節點；家具分層 |
| 角色縮放與背景透視不一致 | 背景畫了透視，角色都用同一縮放（或反過來） | R9／3.2：單一模式；`scale(y) = (y−y_h)/(y_ref−y_h)` |
| 多人站位像合照／無視線方向 | 沒有槽位與朝向規則 | 第 7 節：槽位化＋朝向預設＋視線空間 |
| 同場景各物件地面接觸線不一致 | 各物件各自以視覺感覺擺放 | R4：地面帶＋接觸線誤差 ≤ 2 px；偵錯畫線 |
| 角色浮在地上沒有落地感 | 沒有接觸陰影 | 3.3：每個站地物件加壓扁橢圓接觸陰影 |
| 門比人矮 | 背景圖中的門直接縮小；H 沒定 | R8：門 ≥ 1.2H；以 H 為基準先畫輔助線再畫背景 |
| 同一道具在不同場景大小不同 | 每個場景各自縮放素材 | 以 `size_h` 資料為準，素材只決定外觀，不決定尺寸 |
| 角色被前景擋住臉 | 前景遮擋物放在畫面中央 | 6.2 第 5 點：只放邊緣，並與對話安全區做相交檢查 |

---------------------------------------------------------------------
## 11. 未解決與後續建議

- 沒有找到：Neufert 具體表格、Dead Cells／Katana Zero／Hades／Dragon's Crown／Cuphead 的尺寸規範、VA-11 Hall-A 與 Hades 對話的構圖規則、Naughty Dog contact point 的具體演算法。若要補，建議的下一步：GDC Vault 相關演講全文（https://gdcvault.com/play/1012300/Animation-and-Player-Control-in 為較早的 Naughty Dog 動畫演講，標題相近，我沒驗證內容是否相關）、Neufert 原書。
- 本文件所有 H 比例以 1.7 m 為準；若角色美術設定不是寫實比例（大頭、短腿的手繪立繪），椅座高與髖高比例要以「骨架實測」為準，不要照第 1.1 節。這是最常見的落差來源，建議先量自家角色的 hip／knee／eye 高度各佔 H 幾％，再回填第 4.2 與第 8 節。
- 建議第一個落地項目：把「場景 H、地面帶、物件 `size_h`、接觸線、`seat_anchor`」做成資料欄位並寫 R1、R4、R5、R6、R10 的檢查腳本，這五條覆蓋了你們列出的 6 類錯誤中的大部分。
