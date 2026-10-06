# 2D 角色骨架動畫：業界實例與工具（補充資料）

> 來源：2026-10-06 使用者要求骨架與動畫的規則「參考多一點不同的業界最佳實例」並寫成 skill。這份補充 `LOCOMOTION_REFERENCE.md`（走跑生物力學）：涵蓋 Spine、Live2D、DragonBones、Godot、Unity 的工具慣例，Vanillaware、UbiArt、Hollow Knight、Dead Cells、Cuphead、Skullgirls、Xrd、Ori 等案例，關節處理、動作原則、待機、程序動畫與驗收方式。做事的流程與檢查清單在 skill `rig-animation`。
> 注意：整理時網路代理擋掉了網頁全文，數字來自搜尋摘要，條目已標【出處】【推導】【建議】【沒找到】。標【建議】的數值是我們的起點，要用截圖與逐格檢查調整；引用前請點出處核對。


研究日期：2026-10-06。方法：只用 WebSearch 摘要（WebFetch 被代理擋下，esotericsoftware.com、80.lv 皆 EGRESS_BLOCKED）。
標記規則：【出處】= 搜尋結果中真實出現的網址（內容為搜尋摘要，未讀全文）；【推導】= 由出處數字算出；【建議】= 我們專案的做法建議，非業界數字；【沒找到】= 搜尋沒有可靠資料，不補數字。
注意：搜尋摘要有時沒說明內容來自結果清單中的哪個網址，這種情況會寫「候選出處」並列出可能的網址，請勿當成逐句引文。
已有的走路／跑步生物力學資料不重複。

---

## 0. 結論速覽（給趕時間的人）

1. 業界做法分三派：(a) 逐格手繪（Cuphead、Skullgirls、Dust、Hollow Knight、Owlboy、Blasphemous）；(b) 3D 烘 2D 或 3D 偽 2D（Dead Cells、Hades、Guilty Gear Xrd）；(c) 2D 骨架／網格（Spine、Live2D、UbiArt、Vanillaware 部分角色）。我們是 (c)，所以最該學的是 (c) 的工具慣例與 (a)(b) 的「節奏／停頓／姿勢」。
2. 數字能查到的很少。能引用的硬數字：Cuphead 24 fps 動畫、60 fps 遊戲；Guilty Gear Xrd 約 15 fps 無補間、招式動畫不超過 20 格；Ori 1 代 30 fps；人類眨眼 100–150 ms、靜止呼吸 12–20 次/分；Overgrowth 全角色只用 13 個關鍵姿勢；腳滑偵測門檻常見 2.5 cm 位移 / 5 cm 離地高度。
3. 找不到可靠數字的項目（Hollow Knight、Hades、Katana Zero、Hyper Light Drifter 的 fps／關鍵姿勢數；Disco Elysium、Stardew、TLOU 的 idle 週期；Naughty Dog conversation idle）已明確標【沒找到】，第 4 節以人體生理數字＋【建議】補。
4. 對 Godot 4.7 的具體提醒：SkeletonModification2D 系列在 4.3 文件被標示為實驗性／過時文件，4.7 現況【沒找到】，採用前先在引擎內確認；彈簧骨建議自己寫（臨界阻尼彈簧），不依賴它。

---

## 1. 2D 骨架動畫工具與最佳實務

### 1.1 Spine（Esoteric Software）
- 【出處】網格頂點應同時權重到多根骨頭，包含較上層的骨（如 hip），讓網格邊緣在旋轉時不走位。候選出處：https://uk.esotericsoftware.com/spine-roadmap 、https://skills.cat/skills/logos-liber/atlas-agent-teams/rigging （後者是通用 3D 綁定資料，非 Spine 官方）。
- 【出處】關節處理方式（摘要整理自多個來源，非單一官方頁）：關節附近加密頂點、用平滑權重工具拓寬過渡到幾個頂點、在關節加輔助骨並把塌縮的頂點權重給它再縮放、把膝窩多邊形切開避免重疊。候選出處：https://ja.esotericsoftware.com/forum/d/7673-best-practices-for-rigging-mesh-joints 、https://polycount.com/discussion/comment/939128 、https://bugnet.io/blog/fix-unity-2d-animation-rig-bone-deformation-twist
- 【出處】IK 約束：用目標骨控制整串骨頭，常用於腿、手臂、脊椎、手指，可限制 IK 範圍。https://spineplugin.readthedocs.io/en/latest/_sources/api_reference/skeleton/ikConstraint/index.rst.txt
- 【出處】雙手持槍（官方部落格）：武器骨不能是身體骨的後代，建議掛在 root；建兩根 hand-on-weapon-l / hand-on-weapon-r 當兩條手臂 IK 的目標；設定模式下把 IK Mix 從 100 改成 0，方便不持武器時擺姿勢。https://eu.esotericsoftware.com/blog/Holding-a-two-handed-weapon
- 【出處】Transform constraint 可把骨頭黏在一起，mix 可 key（讓骨頭逐漸過渡到目標），可設只保留 rotate mix=100、其他 0。https://it.esotericsoftware.com/forum/d/7269-combining-path-constraint-with-transform-constraints 、https://pt.esotericsoftware.com/forum/d/10284-transform-constraints-horizontal-and-vertical-mix
- 【出處】Slot：顏色 tint 可 key、控制透明度；tint black 可分別著色暗部與亮部。繪製順序屬於 slot，且「換 skin 不能自動換繪製順序」，做法是事先為不同繪製順序準備不同 slot（例：手臂圖有「頭上方」「頭下方」兩個 slot，依 skin 決定放哪個）。https://eu.esotericsoftware.com/spine-slots 、https://ko.esotericsoftware.com/forum/d/17221-spine-pro-draw-order-question
- 【出處】Spine 4.2 物理約束：模擬骨頭的次要運動（頭髮、衣物）；能同時反應動畫與角色在世界中的移動。https://esotericsoftware.com/spine-physics-constraints 、https://us.esotericsoftware.com/blog/Spine-4.2-The-physics-revolution
- 【出處】動畫教學系列：時間與間距（#3）、擠壓與拉伸（#5）、跟隨與重疊（#8）。https://eu.esotericsoftware.com/blog/Timing-and-Spacing-Animating-with-Spine-3 、https://eu.esotericsoftware.com/blog/Squash-and-Stretch-Animating-with-Spine-5 、https://ar.esotericsoftware.com/blog/Follow-through-and-overlapping-action-Animating-with-Spine-8
- 【出處】轉身：常見做法是執行期把 skeleton scaleX 設 -1；進階做法是每個零件準備替代角度圖，做一段轉身動畫。https://ar.esotericsoftware.com/forum/d/24825-turnaround-images-and-bones
- 【沒找到】Spine 官方「骨架命名規則」「骨長比例」「每網格最大頂點數」的明文數字。只找到通用 3D 的命名前綴建議（JNT_／CTRL_ 一致即可）：https://www.tripo3d.ai/blog/explore/clean-skeleton-hierarchy-standards-for-marketplaces （非 2D、非 Spine，僅供命名一致性參考）。

### 1.2 Live2D Cubism
- 【出處】PSD 的圖層變成 ArtMesh；材料要先切成眼睫毛、眼球、輪廓線等部件；可用群組（資料夾）保留層級，睫毛這類數量多的物件與多款式的手臂可整組匯入。https://docs.live2d.com/en/cubism-editor-tutorials/psd/ 、https://docs.live2d.com/en/cubism-editor-manual/divide-the-material
- 【出處】預設 ArtMesh 比圖層大小內縮 1 像素的邊界，可在匯入前於 PSD 匯入設定調整。https://docs.live2d.com/4.2/en/cubism-editor-manual/psd-import/
- 【出處】官方建議為「會被遮住、動起來才露出」的部位多畫一塊（例：頭髮蓋住的脖子、臉）。https://docs.live2d.com/en/cubism-editor-manual/divide-the-material （此條摘要出自搜尋整理，原句措辭未核對）
- 【出處】設計基準：整張臉一個頭部變形器；眼、眉、口各自分組；再往下才是睫毛、瞳孔等小變形器。呼吸參數可掛在網格或父變形器；若不想某部位跟著呼吸同步，疊多層父變形器，讓它們在呼吸參數不同位置有不同反應。https://news.viverse.com/post/rig-2d-vtuber-model-live2d-cubism
- 【出處】標準參數：ParamBreath（呼吸）、ParamEyeLOpen（左眼開合；預設值=全開，往最大值為睜大，最小到預設為正常閉眼）。https://www.animaze.us/manual/gettingstarted2d/paramlist 、https://docs.live2d.com/en/cubism-sdk-manual/breath
- 【出處】物理：支援單擺到多段擺；有「計算 FPS」設定（15/30/60/120 或自訂）以對齊場景 FPS；輸出 *.physics.json。https://docs.live2d.com/en/cubism-editor-manual/physics-operation/
- 【沒找到】Live2D 官方的呼吸週期秒數、眨眼間隔秒數。
- 【建議】借用概念：「一個參數驅動多個部位、各部位在參數不同區段有不同響應」＝我們的呼吸可做成單一相位 0..1，由各骨頭用自己的曲線取樣（胸比肩早半拍），不是各骨獨立正弦。

### 1.3 DragonBones
- 【出處】開源免費；骨骼綁圖、網格＋FFD（可擠壓拉伸彎曲）、IK 約束、蒙皮（頂點綁多根骨）、時間軸、運行時支援 Egret/Pixi/Starling/Cocos2d-x/Unity。https://www.abratabia.com/game-animation/animation-tools.php 、https://abratabia.com/game-animation/skeletal-animation.php （第三方整理，可信度中低）
- 【沒找到】DragonBones 官方最佳實務文件。

### 1.4 Godot 4（Skeleton2D / Polygon2D / SkeletonModification2D）
- 【出處】官方 2D skeletons 教學：先讀 Cutout animation；Skeleton2D 為參考骨架，Bone2D 建階層；設定 rest pose 用工具列 Skeleton2D > Overwrite Rest Pose；Polygon2D 的 Skeleton 屬性指向 skeleton 才會被變形。https://docs.godotengine.org/en/4.6/tutorials/animation/2d_skeletons.html 、https://godotengine.org/article/godot-gets-2d-skeletal-deform
- 【出處】Polygon2D 內部有 Bone2D 清單與每根骨的權重陣列（get/set_bone_weights、add_bone、erase_bone…）。https://docs.godotengine.org/en/4.2/classes/class_polygon2d.html
- 【出處】SkeletonModification2DTwoBoneIK：用餘弦定理求兩骨旋轉，適合手臂／腿，比 FABRIK 輕量。https://docs.godotengine.org/en/4.2/classes/class_skeletonmodification2dtwoboneik.html
- 【出處】SkeletonModificationStack2D 標示為實驗性，可能改動或移除；4.3 文件頁已標「過時」。https://docs.godotengine.org/en/4.3/classes/class_skeletonmodificationstack2d.html 。Jiggle 類別：https://docs.godotengine.org/en/4.2/classes/class_skeletonmodification2djiggle.html
- 【沒找到】4.7 對 SkeletonModification2D 的現況；【建議】開工前在 4.7 實測，或自寫 TwoBoneIK（餘弦定理約 20 行）以免被引擎移除影響。
- 【出處】AnimationTree：BlendSpace1D/2D 做混合；逐格 2D 動畫建議切到 Discrete 模式。https://docs.godotengine.org/en/4.2/tutorials/animation/animation_tree.html
- 【出處】Godot 論壇：scale.x=-1 翻轉綁骨角色會有 IK 鏡像錯誤、頭翻轉等問題。https://forum.godotengine.org/t/how-do-i-properly-flip-a-2d-rigged-character-with-ik-and-lookat-in-godot-4/136805 、https://forum.godotengine.org/t/scaling-and-flipping-polygon2d-skeleton-animation/114097
- 【建議】翻轉的穩妥做法：骨架永遠朝右建模，翻面時只翻「根節點」並在翻面瞬間重設 IK 目標與彈簧狀態（見第 5 節）；用測試驗證翻面前後左右手腳的繪製順序不變。

### 1.5 Unity 2D Animation / PSD Importer
- 【出處】存成 .psb；每個零件獨立圖層，擺成預設姿勢；匯入設定：Sprite(2D and UI)、Sprite Mode = Multiple、勾 Mosaic、Character Rig、Use Layer Grouping；匯入器自動排成 Sprite Sheet 與保留圖層原位置的 Prefab。https://docs.unity3d.com/Packages/com.unity.2d.animation@3.2/manual/PreparingArtwork.html 、https://docs.unity3d.com/Packages/com.unity.2d.psdimporter@9.1/manual/PSD-importer-properties.html
- 【出處】2D IK 三種解算器：CCD、FABRIK、Limb（限三節鏈、CCD 修改版，適合人形）。https://docs.unity3d.com/Packages/com.unity.2d.animation@6.0/manual/2DIK.html
- 【沒找到】Unity 官方對「零件重疊量」的明確像素建議。
- 【出處】flip 注意：負縮放翻轉會讓子節點變換反轉並破壞附件；替代方案是 Y 軸轉 180 度或 sprite skin 的翻轉支援。https://bugnet.io/blog/how-to-fix-unity-2d-skeletal-flip-breaking-bone-attachments

---

## 2. 實際遊戲案例

| 遊戲 | 技術路線 | 可引用的事實 |
|---|---|---|
| Dragon's Crown / Odin Sphere（Vanillaware） | 逐格＋骨架＋精靈變形混用 | 見 2.1 |
| Rayman Legends / Child of Light（UbiArt） | 高解析手繪＋骨架＋網格 | 見 2.2 |
| Hollow Knight | 逐格手繪 | 見 2.3 |
| Dead Cells | 3D 烘 2D | 見 2.4 |
| Cuphead | 逐格手繪 24 fps | 見 2.5 |
| Skullgirls | 逐格手繪 | 見 2.5 |
| Guilty Gear Xrd | 3D 模型模仿 2D 低格數 | 見 2.6 |
| Ori | 1 代 2D 精靈 30 fps、2 代 3D 60 fps | 見 2.7 |

### 2.1 Vanillaware
- 【出處】Vanillaware 作品至少混用三種：精靈（sprite）、骨架（skeletal）、對精靈做變形（deformation）。維基也描述為「角色有關節式手動腳本動作，類似 Flash 動畫」。https://en.wikipedia.org/wiki/Vanillaware 、https://discussions.unity.com/t/skeletal-vs-sprite-animation/682988 （前者較確定；後者摘要未明確標示這句出處）
- 【出處】Muramasa 被論壇討論者視為「2D 骨架結合傳統精靈結構」的好例子；Dragon's Crown 的流程被稱為「技術謎團」（資料少）。https://ru.esotericsoftware.com/forum/d/8587-your-favorite-game-animation-amp-animators-inspirations
- 【出處】Dragon's Crown 動畫由插畫家 Shigatake 負責；規劃文件早於遊戲發行約 13 年。https://www.siliconera.com/a-conversation-with-dragons-crown-director-george-kamitani/
- 【沒找到】Dragon's Crown / Odin Sphere 的 fps、關鍵姿勢數、雙手持武器處理、轉身處理、部件切割數。不補數字。
- 【推導】從「骨架 + 精靈 + 變形混用」可知：骨架負責大位移，關鍵時刻（出招、受擊）用手繪精靈或變形補足；我們可對應成「骨架為主、少數姿勢用零件替換變體」。

### 2.2 UbiArt Framework（Rayman Legends、Child of Light）
- 【出處】骨架與骨頭套用在獨立素材上；任何可數位化的圖都能切成零件；動畫師設計姿勢，工具負責圖像變形。https://en.wikipedia.org/wiki/UbiArt_Framework
- 【出處】GDC 2013 由動畫師講工具，目標是「把藝術家放在開發中心」。https://gdconf.com/news/gdc_2013_adds_visual_art_talks 、https://gdcvault.com/play/1020398/contactUs
- 【出處】網格變形流程：加骨頭、在骨頭外畫方框當作網格上的晶格，藝術家直接操作幾何；框架目標是「限制重複工作」。https://gamedeveloper.com/design/video-the-tools-used-to-design-i-rayman-legends-
- 【沒找到】UbiArt 的 fps、關鍵姿勢數、零件數。

### 2.3 Hollow Knight
- 【出處】Ari Gibson 負責角色設計、環境美術與每個實體的逐格動畫；手繪 2D。https://mcvuk.com/when-we-made-hollow-knight/ 、https://shapes.inc/fandom/hollow-knight/author
- 【出處】摘要稱過場為 30 fps 檔案，遊戲內感知格率因手繪格數少而更低。https://steamcommunity.com/app/367520/discussions/0/2442587820572671029 （玩家討論，可信度低）
- 【沒找到】主角 idle／run 的格數、轉身處理、打擊停頓的幀數（hit stop 時間 Team Cherry 未公開，搜尋沒有）。
- 【建議】Hollow Knight 的啟示是「少格數＋姿勢強」，對我們意思是：骨架動畫也可以把動作做在 2s 或 3s（每 2–3 個 60fps 影格更新一次姿勢）再配合強關鍵姿勢，而不是全部平滑補間。此為設計建議，非 Team Cherry 的已知做法。

### 2.4 Dead Cells
- 【出處】主角與怪物用 3D 模型，以自製工具烘成 2D 精靈；模型與動畫都在 3ds Max，由一個人完成；好處是為了手感調整（例如讓武器更有重量）可以快速改動畫，不必重畫。https://80.lv/articles/interview-with-the-developers-of-dead-cells （網站被擋，內容來自搜尋摘要）
- 【出處】Motion Twin 的 Sébastien Bénard 在 Pocket Gamer Connects Helsinki 2018 說約一半開發時間花在讓「跳躍與殺敵」核心手感好玩。https://www.pocketgamer.biz/video-a-dead-cells-post-mortem-from-motion-twins-sebastian-bernard
- 【沒找到】Dead Cells 烘焙 fps、每個動作格數。

### 2.5 Cuphead 與 Skullgirls（手繪極端）
- 【出處】Cuphead：動畫 24 fps、遊戲 60 fps；「animating on the ones」（每格都畫）；全手繪，鉛筆紙上畫再在 Photoshop 上色。https://gamesradar.com/the-making-of-cuphead
- 【出處】Cuphead 幀數：金氏紀錄頁面稱主遊戲約 45,000 張、DLC 27,000 張（合計約 72,000，【推導】）；另有來源稱 12 萬以上（兩者矛盾，未判定）；平均 25 分鐘畫一格。https://www.guinnessworldrecords.com/world-records/508061-most-hand-drawn-frames-of-animation-in-a-videogame
- 【出處】Skullgirls：8 名角色共 11,515 格，平均每人 1,439 格（金氏紀錄）；另一來源稱平均約 1,300 格；開發早期每角約 70–90 格、目標約 1,000 格。https://www.guinnessworldrecords.com/world-records/105505-most-frames-of-animation-per-character-in-a-videogame 、https://www.siliconera.com/dreaming-of-making-a-game-spotlight-on-skullgirls/
- 【推導】24 fps 動畫在 60 fps 遊戲裡顯示，每格約停 2.5 個遊戲影格，所以實際是不均勻的 2/3 影格交替。【建議】我們用程式驅動時不必限定 24 fps，但可參考「動畫節奏與輸入回應分離」：動畫格率低、輸入／判定仍 60 Hz。

### 2.6 Guilty Gear Xrd（3D 偽 2D）
- 【出處】GDC 2015 Junya Motomura：核心原則「Kill everything 3D」。https://gdcvault.com/play/1022031/ 、https://www.ggxrd.com/Motomura_Junya_GuiltyGearXrd.pdf
- 【出處】角色以約 15 fps 擺姿勢，關鍵格不做補間（模仿動畫低格率），遊戲本身 60 fps；招式動畫不超過 20 格，並把重要關鍵格拉長停留，使玩家看懂是哪一招。https://www.pressreader.com/australia/edge/20150115/281513634528873 、https://amara.org/videos/bDmpkclvfB5I/info/the-animation-of-guilty-gear-xrd-dragon-ball-fighterz
- 【推導】15 fps ÷ 60 Hz ＝ 每 4 個影格換一個姿勢；招式 ≤20 格 ＝ 以 15 fps 計 ≤1.33 秒。
- 【建議】我們的攻擊動作可採「關鍵姿勢 3–6 個、中間不補或少補、命中姿勢多停幾格」。數字待試。

### 2.7 Ori、Hades、Celeste、Metal Slug、Owlboy、Blasphemous、Dust、Katana Zero、Hyper Light Drifter
- Ori【出處】：1 代 Ori 是 2D 精靈、30 fps，與 60 fps 場景不協調，也無法優雅處理旋轉平台、抓取、斜坡；2 代改 3D，動畫師多來自 Disney／Pixar／DreamWorks（習慣 24 fps），團隊仍採 60 fps，3D 後可在狀態間混合。https://www.orithegame.com/rockpapershotgun-how-animation-powers-ori-and-the-will-of-the-wisps/ 。【推導】骨架動畫的價值就是能適應地形與旋轉（斜坡站姿由 IK 補），這是我們選骨架的理由之一。
- Hades【出處】：部分角色（如 Red）先 3D 建模再烘成數千格；3D 建模與動畫由 Camilo Vanegas。https://www.tripo3d.ai/blog/collect/from--d-art-to--d-masterpiece--the-process-of-bringing-characters-to-life-in-hades-cyj6d1ifsqa 、https://www.stashmedia.tv/?p=72528 。【沒找到】fps、hit stop。
- Celeste【出處】：跑步 4 格循環（部落格，可信度低）https://www.sprite-ai.art/blog/pixel-art-animation ；離地後 6 影格寬限（土狼時間，來自 TAS 社群摘要，具體貼文未確認）https://tasvideos.org/Forum/Topics/22956 。【沒找到】官方 squash/stretch 數字。
- Metal Slug【出處】：Akio Oyabu 的長且精細的像素動畫讓程式組想叫他停手；https://automaton-media.com/en/news/metal-slug-artist-akio-says-his-elaborate-pixel-animations-made-his-programmers-want-to-rip-their-hair-out-but-it-was-so-worth-it/ 。「上下半身拆開」只在玩家自製素材包出現，不是官方資料：https://poohcom1.itch.io/soldier-girl-sprite-pack 。【沒找到】原作的拆分做法。
- Owlboy【出處】：全部逐像素、無漸層、無描圖、無 3D 擷取；披風與武器火光動畫被稱讚。https://alternativemagazineonline.co.uk/2017/12/05/interview-in-conversation-with-d-pad-studio-creators-of-owlboy/ 、https://www.killscreen.com/owlboy/ 。【沒找到】格數、雙手持槍處理。
- Blasphemous【出處】：動畫師 Raul Vivar 的時間軸流程：以現有格為基礎快速修改出新格以加速迭代。https://www.gameanim.com/?p=67403 、https://gonintendo.com/contents/28532-blasphemous-ii-dev-diary-7-bringing-the-pixel-to-life
- Dust: An Elysian Tail【出處】：Dean Dodrill 想完全手繪主角、不用分節或多邊形動畫，塞數百張高清格進 RAM 是技術難題。https://gameinformer.com/b/features/archive/2012/09/26/afterwords-dust-an-elysian-tail 、https://gamedev.net/forums/topic/644080-2d-workflow-for-side-scroller/
- Katana Zero、Hyper Light Drifter：【沒找到】動畫格數、fps、hit stop 數字（搜尋只得到泛論與玩法描述）。

### 2.8 打擊停頓（hit stop）
- 【出處】Sakurai（Famitsu 專欄，Source Gaming 翻譯）列八項增強：被打者多抖、不移動判定框、地面水平抖／空中垂直抖、抖動逐漸減弱、控制停頓量、插補到受擊姿勢、攻擊者繼續微動、依鏡頭距離調整抖動量。https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- 【出處】SF2 的「2in1 取消」與 hitstop 有關：每個普通技前 5 格可取消，停頓約 10 格延長取消窗口（摘要整理，未核對原文）。https://slapcity.wiki.gg/wiki/Hitstop 、https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/
- 【出處】Vlambeer（Nuclear Throne）：開火鏡頭後座 6 像素、加 4 的畫面震動、槍枝後座設為 2、震動快速衰減。https://infovore.org/?p=5275
- 【出處】泛論「重擊凍結 50–100 ms」「hit stop 2–5 幀」（部落格／技能庫整理，可信度低）。https://www.wayline.io/learn/game-feel/1 、https://playbooks.com/skills/dylantarre/animation-principles/game-development
- 【沒找到】Street Fighter 3rd Strike 逐招 hitstop 表；Hollow Knight、Hades 的實測數字。
- 【建議】hit stop 以輕/中/重分三級（例 2/4/6 影格，60 Hz），只凍結雙方動畫與骨頭，不凍結輸入緩衝與鏡頭抖動；停頓期間給受擊方 1–2 像素水平抖動。數字為起點、待試玩調。

### 2.9 預備與跟隨、輸入回應
- 【出處】預備（anticipation）：小動作 2–4 格、大動作 12–24 格；輸入回應應 <100 ms；折衷做法是玩家動作在 1–2 格內回應，把角色格數花在跟隨而不是預備。（技能庫整理，可信度低）https://playbooks.com/skills/dylantarre/animation-principles/anticipation-mastery
- 【出處】12 原則遊戲化解說：https://www.gamedeveloper.com/production/the-12-principles-of-animation-in-video-games 、https://gameinformer.com/b/news/archive/2014/05/11/an-inside-look-at-the-principles-of-animation.aspx
- 【建議】攻擊：預備 ≤3 影格（50 ms）且預備姿勢的「反向拉伸」可在命中判定同時發生（判定不等動畫）；跟隨（手臂、武器、頭髮）用彈簧骨自然做出，不吃輸入延遲。

---

## 3. 剛體零件切割與關節問題

- 【出處】最通用的數位剪紙關節是「兩個重疊圓」，旋轉軸在圓心，關節不會破；缺點是圓弧明顯；變體是圓只佔肢體一部分，更自然但彎曲範圍小、需要多個狀態。https://community.adobe.com/questions-540/types-of-joints-used-in-digital-cutout-animation-106544
- 【出處】Toon Boom 的做法：關節多為圓形、重疊處不能放到後面否則露餡；可在 Overlay 圖層加線條營造肘彎折痕。https://docs.toonboom.com/help/harmony-12-2/premium/rigging/fix-articulations.html
- 【出處】Live2D：隱藏部分要多畫（頭髮蓋住的脖子、臉）。（見 1.2）
- 【出處】Spine/網格關節：加密頂點、平滑權重、輔助骨、切膝窩。（見 1.1）
- 【出處】Spine 繪製順序要預先為不同朝向／skin 準備不同 slot。（見 1.1）
- 【出處】Unity PSD Importer：預設姿勢切分、圖層群組保留。（見 1.5）
- 【沒找到】「零件重疊量佔肢體寬度的百分比」的業界標準數字；「遠側手腳要比近側暗多少 %」的標準數字；「彎曲姿勢變體要做幾個角度」的標準數字。以下為推導與建議，非業界規範。
- 【推導】兩圓關節在旋轉範圍 θ 內不露縫的條件：關節圓半徑 r ≥ 肢體半寬 w/2，且重疊區的圓心與旋轉軸一致；θ 越大，外側邊緣差 ≈ 2·r·sin(θ/2)，所以 r 取肢體半寬即可保證邊緣連續，只剩輪廓線的圓弧感。
- 【建議】重疊量：每個相鄰零件在關節兩側各多畫 ≥ 肢體寬度的 25%（相當於彎 90° 時仍遮得住）；上限由「不得露出到對側輪廓之外」決定。驗收用測試：把每個關節轉到其角度範圍極值，渲染後檢查關節處無背景像素漏出（可用 alpha 取樣）。
- 【建議】彎曲變體：肘、膝各準備「伸直／微彎／深彎」3 張，在 0–30°、30–100°、100°+ 切換，切換點加 1–2 影格的 crossfade 或在姿勢變化瞬間切（人眼對快速動作中的切換不敏感，此為經驗推測）。
- 【建議】遠近側：遠側手腳整體降亮度約 10–25%、略偏冷、繪製順序放身體之後；數字當起點，用截圖對照調整。
- 【建議】頭髮／衣物彈簧骨：優先用臨界阻尼或略欠阻尼彈簧（半衰期 0.05–0.15 s 起試）；錨點隨身體移動時要給彈簧「速度繼承」；翻面、傳送、復活時重設狀態以免甩飛。
- 【出處】彈簧骨概念：每個次要元素為一串以彈簧連接的點，根點附在角色上，其餘點被拉向相對父骨的休息位置，加阻尼與重力。https://diglib.eg.org/handle/10.1111/cgf70209 。半衰期定義：值走到目標一半所需時間（Epic 文件頁，詳述不一定同 Holden 文章）。https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Core/SpringMath/CriticalDecay

---

## 4. 動作設計原則實例與 NPC 待機

### 4.1 十二原則在遊戲角色上的套用
- 【出處】十二項清單（Disney 1981，Thomas & Johnston）：擠壓與拉伸、舞台呈現、預備、直接/關鍵姿勢、跟隨與重疊、緩入緩出、弧線、次要動作、吸引力、時間、誇張、紮實繪畫。https://www.gamedeveloper.com/game-platforms/12-principles-for-game-animation
- 【出處】重疊動作：出拳時頭與軀幹領先，彎曲的手臂拖在後面，命中前一刻才甩出；跟隨：投球放開後手繼續動。https://education.siggraph.org/static/HyperGraph/animation/character_animation/principles/follow_through.htm
- 【出處】擠壓與拉伸：落地時變形、跳前蹲（跳躍預備）。https://www.gamedeveloper.com/production/the-12-principles-of-animation-in-video-games
- 【出處】審查時差距：靜態縮圖與 onion skin 不能取代播放；onion skin 能直接看出間距不均、抖動、弧線不順。https://garagefarm.net/blog/mastering-onion-skinning-in-animation
- 【沒找到】遊戲裡擠壓量的標準百分比。
- 【建議】擠壓／拉伸用「體積守恆」：scaleX × scaleY ≈ 1；落地擠壓 ≤ 10–15%（寫實）到 25–30%（卡通），持續 2–4 影格後彈簧回復。起手數字待試。
- 【建議】弧線：手、武器尖端的軌跡取樣畫線，檢查是否為平滑弧（見第 6 節軌跡測試）。
- 【建議】緩入緩出：關鍵姿勢之間用 ease-in-out，但攻擊的命中瞬間用 ease-in（加速到命中再停頓），避免命中前減速。

### 4.2 待機「像人」：可引用的生理與設計數字
- 【出處】靜止成人呼吸 12–20 次/分（部分醫學來源 12–18）。https://socratic.com/answers/459544 、https://acibademinternational.com/?p=355744 。【推導】週期 = 60/次數 = 3–5 秒（12–20 次）或 3.3–5 秒（12–18 次）。
- 【出處】眨眼：健康成人 15–20 次/分；實驗室平均約 10 次/分；閱讀專注時降到 3–4 次/分；單次時長平均 100–150 ms（UCL）或 100–400 ms（Harvard 資料庫）；>1000 ms 視為微睡眠。https://en.wikipedia.org/wiki/Blinking 。【推導】間隔 = 60/次數 = 3–4 秒（15–20 次）、約 6 秒（10 次）、15–20 秒（3–4 次）；60 Hz 下 100–150 ms ≈ 6–9 影格。
- 【出處】眼球掃視（saccade）：持續約 30–120 ms；注視（fixation）通常 200–600 ms；掃視後約 200 ms 的不應期；注視時有 <1° 的微漂移與微掃視。https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11404824/ 、https://smartbody.ict.usc.edu/HTML/documentation/SB/Eye-Saccade_8552851.html
- 【出處】遊戲 idle：循環不要太長，動畫學校建議最多 45 格；起止同一姿勢；呼吸從髖開始（髖先上，再胸上並後仰，接著頭、肩、手臂）。https://blog.animschool.edu/2024/06/14/breathing-life-into-idle-animations 。（動畫學校部落格，非特定遊戲）
- 【出處】idle 設計指南：基礎循環 2–4 秒、起止同姿勢且各關節速度一致；較複雜的重心轉移可用 8–12 秒；另有由計時器觸發的變體 idle（看錶、整理衣服、東張西望）打破重複；重心轉移是骨盆輕微側向移動，沒有它角色像被凍結。https://mocaponline.com/blogs/mocap-news/idle-animation-design-guide 、https://mocaponline.com/blogs/mocap-news/idle-animation-loop
- 【出處】Naughty Dog TLOU2：系統性臉部動畫約 15,000 個姿勢，與 idle 動畫結合；Uncharted 4 臉部 300–500 根骨。https://www.gameanim.com/?p=59355 、https://blog.playstation.com/?p=334953 、https://www.gamepro.de/artikel/uncharted_4,3085867.html
- 【出處】Uncharted 4：對話中加入手勢；玩家離開或開戰時角色暫停對話、平靜後接續。https://www.actugaming.net/?p=10616 、https://invenglobal.com/articles/1226/how-naughty-dog-creates-realistic-performances-in-games
- 【出處】Valve Source：Half-Life 2 的臉部以 FACS 為基礎，由 flex controller（滑桿）控制，Face Poser 做靜態 Expression 與動畫 Flex 事件，並能編排身體手勢。https://developer.valvesoftware.com/wiki/Flex_animation 、https://developer.valvesoftware.com/wiki/Facial_Expressions_Primer 、https://developer.valvesoftware.com/wiki/Choreography_creation
- 【出處】Stardew Valley：NPC 精靈表為 16 格＝四方向各 4 格；農夫走路序列 R1F1,R1F2,R1F1,R1F3（等於 2→1→3 的 4 拍輪替）；社群 mod 把每列第 1 格保留為 idle 專用姿勢。https://stardewvalleywiki.com/Modding:Farmer_sprite 、https://www.curseforge.com/stardewvalley/mods/idle-plus-walk/install
- 【沒找到】Disco Elysium（立繪式角色，搜尋只得到油畫風與藝術指導資訊）、The Last of Us 的 idle 週期與幅度、Naughty Dog conversation idle 的週期／隨機化數字。不補數字。
- 【建議】我們的待機參數（皆為起點，需試玩調）：
  - 呼吸：週期 3.6–4.4 s（每次循環隨機 ±10%），胸 scaleY 振幅 1–2%、肩上下 0.5–1 px（以 100 px 身高為基準）；髖領先、胸隔 ~0.1 s、頭再隔 ~0.1 s（相位延遲）。
  - 重心轉移：每 6–12 s 隨機一次，持續 0.8–1.5 s（ease-in-out），骨盆橫移 1–2 px、肩線反向傾 1–2°；轉移時重心腳換邊。
  - 眨眼：間隔 3–6 s 隨機（偶發雙眨 10%），閉眼 6–9 影格（60 Hz，約 100–150 ms）；視線大幅移動前先眨。
  - 視線：注視 0.3–2 s 隨機，轉換用 saccade 90 ms 內完成（頭晚眼 ~0.1 s 跟上）；不看目標時微漂移 <1°。
  - 手勢（說話中）：每 1.5–3 s 一次小手勢，強調字詞時才大幅度；結束後回到 idle 的混合 0.2–0.3 s。
  - 隨機化：用「間隔＝基準×(0.7~1.3) 的均勻亂數」並禁止兩個事件同影格觸發（眨眼與重心轉移錯開至少 0.3 s）；以角色 ID 當種子，使同場景的 NPC 不同步。

---

## 5. 程式驅動／混合

- 【出處】Overgrowth（Wolfire，David Rosen，GDC 2014 Animation Bootcamp）：用簡單程序技巧，靠極少關鍵姿勢達成互動流暢的動畫，所有角色動作只用 13 個關鍵姿勢；骨骼姿勢以傳統蒙皮插值，用數學自動化而非逐格調整。https://www.gdcvault.com/play/1020583/Advanced-Animation-with 、https://gamedeveloper.com/design/video-an-indie-approach-to-procedural-animation
- 【出處】Rain World：生物由「以特定距離連接的點」組成框架，其上疊紙娃娃式零件；slugcat 是兩個固定距離的球加上純裝飾的四肢與尾巴，隨輸入程序化動作；Joar 起初混用傳統與程序動畫，後來更偏向程序。https://unity.com/blog/exploring-procedural-design-rain-world
- 【出處】Spore（Chris Hecker）：針對使用者自創、事先未知形態的生物，用強健的 IK 解算器擷取姿勢並重定向動作。https://chrishecker.com/How_To_Animate_a_Character_You%27ve_Never_Seen_Before 、https://www.chrishecker.com/Real-time_Motion_Retargeting_to_Highly_Varied_User-Created_Morphologies
- 【出處】Rubber Hose（Battle Axe，After Effects）：預先綁好的可彎曲可拉伸向量肢體，兩個控制器＋一個 Hose 圖層，每影格用表達式即時計算；可把腳、手掛在肢體上。IK Studio 為較新的類似工具。https://lesterbanks.com/2015/08/rubberhose-for-after-effects-surfaces-for-preorders/ 、https://www.cgchannel.com/2025/02/richard-rosenman-releases-ik-studio-for-after-effects
- 【出處】Motion Matching（Ubisoft For Honor，GDC 2016，Kristjan Zadziuk、Michael Buttner）：依位置速度、過去與當前軌跡、關節（腳、手）位置速度與標籤，在無結構的姿勢庫找匹配片段；關鍵技巧是只需匹配少數骨頭，主要是腳的位置與速度。https://www.gameanim.com/?p=14043 、https://www.dualshockers.com/ubisoft-introduces-motion-matching-the-first-step-to-next-gen-animation/
- 【出處】腳滑成因與解法：腳滑＝移動速度與動畫速度不匹配；IK 只管垂直接地，水平滑動要靠播放速率對齊（或距離匹配）；stride warping 縮放腿伸展；foot lock 偵測著地相位，在離地前把腳的世界座標鎖住，把 IK 當「拋光層」而非補救。https://bugnet.io/blog/how-to-fix-animation-foot-sliding 、https://bugnet.io/blog/how-to-fix-unreal-control-rig-foot-ik-sliding-during-locomotion
- 【出處】Unity blend tree 相位對齊：混合的剪輯必須讓關鍵動作（如落腳）發生在相同正規化時間（例：左腳 0.0、右腳 0.5）；1D blend tree 共用正規化時間；不同長度可用 Cycle Offset 重對齊。https://docs.unity3d.com/410/Documentation/Components/class-BlendTree.html 、https://bugnet.io/blog/how-to-fix-unity-mecanim-sync-group-locomotion-feet-sliding-out-of-phase
- 【出處】Unity Animation Rigging 的 foot IK：射線要在主執行緒做、再餵給約束；沒有物理整合時 foot IK 會慢一影格；需要骨盆下移避免腿被拉直。https://discussions.unity.com/t/animation-rigging-foot-ik/801830 、https://forum.unity.com/threads/foot-placement-ik.883708/
- 【建議】Nest Egg 側面橫向版的簡化 Motion Matching／距離相位：相位 φ（0..1）每影格加 `距離增量 / 步幅長度`，而不是加時間；腿用 TwoBoneIK，支撐腳在 φ 的支撐區間鎖世界 X；高速時啟動 stride warp（縮短擺動腿而不是拉伸動畫速度）；走→跑混合時兩者的左腳著地 φ 都校到 0.0。
- 【建議】2D 地形：腳 IK 用單一向下射線取地面高度，骨盆（hip）下移量 = min(左腳高差, 右腳高差) 的負值再平滑（臨界阻尼，半衰期 ~0.08 s），避免抖動。
- 【建議】混合規則：狀態切換用 0.08–0.15 s 的 crossfade（攻擊類 ≤0.05 s）；相位依賴的循環（走、跑）切換時保持 φ，不重置為 0。
- 【建議】Godot 面：AnimationTree 的 BlendSpace1D 以速度當軸；注意第 1.4 節提到 flip 與 IK 的衝突。

---

## 6. 驗收方式

- 【出處】遊戲動畫 QA：重點是過渡有回應、狀態邏輯正確、沒有嚴重缺陷；遊戲中動作會重複且玩家注意力在操作上，過場可接受的瑕疵在戰鬥中常看不出來。https://mocaponline.com/blogs/mocap-news/game-animation-qa-testing-guide
- 【出處】審查工具：onion skin（前後幀疊影）看間距不均、抖動與弧線；播放要先正常速度再放慢，不可只看縮圖；rotoscope（描摹實拍）校準比例。https://garagefarm.net/blog/mastering-onion-skinning-in-animation 、https://www.ramotion.com/blog/qa-for-complex-animations 、https://education.nsw.gov.au/content/dam/main-education/documents/teaching-and-learning/curriculum/creative-arts/visual-arts-7-10-mip-animation.pdf （最後一項為教育部教材，僅作 rotoscope 定義）
- 【出處】腳滑量測：以 cm/幀 度量。門檻範例：關節離地 <0.05 m（5 cm）視為近地，近地幀水平漂移 >0.025 m（2.5 cm）算滑；HuMoR 設定腳趾 4 cm／腳踝 8 cm 高度門檻；真實資料平均 0.512 cm/幀。https://research.nvidia.com/labs/sil/projects/kimodo/docs/benchmark/metrics.html 、https://arxiv.org/pdf/2206.03287
- 【沒找到】業界「角色動畫審查清單」的標準表單、2D 角色骨長容許誤差、關節角度範圍的標準數字、跳動（jitter）偵測的標準門檻。
- 【建議】自動化測試（Godot 無頭，直接補進 `tests/`）：
  1. 骨長保持：每根骨每影格 |長度 − 靜止長度| ≤ 0.5 px（IK/擠壓骨除外，單獨列白名單）。
  2. 關節角度範圍：肘、膝、頸等逐影格 ∈ 資料表的 [min,max]；超出記錄骨名與影格。
  3. 腳滑：支撐相內腳的世界 X 位移 ≤ 1 px/影格（2D 版，以像素換算）、整個支撐相累積 ≤ 3 px（起始值，待調）。
  4. 跳動：任一骨位置的二階差分（加速度）超過該動作 P99 的 3 倍視為尖峰；或相鄰影格旋轉差 >45° 且非預期（如翻面、攻擊命中）。
  5. 循環閉合：循環動畫第 0 影格與末影格的各骨姿勢差 ≤ 1 px / 1°，且速度連續。
  6. 繪製順序：翻面前後每個 slot 的 Z 順序不變（或符合翻面表）；遠側肢體亮度 < 近側。
  7. 關節遮蓋：把每個關節轉到範圍極值，渲染離屏圖，檢查關節矩形內 alpha ≥ 0.99。
  8. 表情／呼吸：呼吸 1000 影格模擬後各骨的位移包絡不超出振幅上限（防累積漂移）。
  9. 彈簧穩定：施加衝擊後 2 秒內速度衰減到 <1% 且不發散；翻面／傳送後狀態重設。
- 【建議】人工：用 frame step 逐格看每個動作的 3 個關鍵影格（接觸、最低點、通過）；在螢幕截圖中用 `tools/screenshot.tscn` 疊 onion skin（前後各 2 影格）與軌跡線；找一段真人／參考影片 rotoscope 對照步幅與頭部上下起伏（只比節奏與弧線，不照搬）；輸出 GIF 逐格比對（前後版本疊差異圖）。

---

## 7. 骨架設計檢查清單（切割、關節、命名、骨長、圖層）

標記同上；【建議】類條目的數字皆為起點。

### 切割
- [ ] 零件切分至「會獨立旋轉的最小單位」：頭、頸、軀幹（上/下）、髖、上臂/前臂/手（左右）、大腿/小腿/腳（左右）、頭髮（前/後/側）、衣物下擺、武器。【建議】12–20 塊，與 Unity PSD Importer 的「每圖層一零件、預設姿勢擺放」一致。https://docs.unity3d.com/Packages/com.unity.2d.animation@3.2/manual/PreparingArtwork.html
- [ ] 被遮住的部位多畫（脖子、軀幹被手臂擋的部分、大腿根）。【出處】Live2D 同樣建議。https://docs.live2d.com/en/cubism-editor-manual/divide-the-material
- [ ] 以預設姿勢（T 或自然站姿）擺放並存成單一來源檔（PSB/PSD）。【出處】Unity。
- [ ] 零件邊緣向外留 ≥2 px 透明邊以防縮放/補間滲色；Live2D 預設內縮 1 px 為對照。【建議】

### 關節
- [ ] 每個旋轉關節兩側零件重疊 ≥ 肢體寬度 25%，旋轉軸對準圓心。【建議】/【出處】圓形關節 https://community.adobe.com/questions-540/types-of-joints-used-in-digital-cutout-animation-106544
- [ ] 肘、膝、頸、腰有彎曲變體或輔助骨（至少 3 段角度）。【建議】
- [ ] 角度範圍寫進資料表（肘 0–150°、膝 0–140° 等），並有測試。【建議】（人體關節範圍為解剖常識，非本次搜尋）
- [ ] 網格零件：關節附近頂點加密、權重平滑過渡；頂點同時權重給父骨。【出處】Spine 見 1.1。

### 命名
- [ ] 一致的前綴與左右後綴（如 `arm_up_L`、`arm_dn_L`、`hand_L`），不混用大小寫風格。【出處】通用建議 https://www.tripo3d.ai/blog/explore/clean-skeleton-hierarchy-standards-for-marketplaces （3D 資料）
- [ ] 控制骨（IK 目標、武器握點）與變形骨用不同前綴；匯出時不留未使用的鏈與重複輔助骨。【出處】同上
- [ ] 武器骨掛在 root 而不是身體骨下，握點骨另建（hand-on-weapon-L/R）。【出處】https://eu.esotericsoftware.com/blog/Holding-a-two-handed-weapon

### 骨長與階層
- [ ] root →（hip）→ spine → neck → head；肩、髖為各自分支；階層深度只在必要處加深。【出處】通用 https://mocaponline.com/blogs/mocap-news/character-rigging-basics-guide
- [ ] 骨長＝零件旋轉軸距離，單位固定；運行時長度保持誤差 ≤0.5 px（測試）。【建議】
- [ ] IK 兩骨鏈的總長 ≥ 目標最遠距離，否則啟用伸展或夾限。【推導】（餘弦定理在目標超出長度和時無解）
- [ ] 同一個 rig 可同時被 IK 與動畫驅動時，用 mix 權重切換，不直接關閉約束。【出處】Spine mix https://eu.esotericsoftware.com/blog/Holding-a-two-handed-weapon

### 圖層／繪製順序
- [ ] 預先決定朝右時的 Z 順序，並列出「翻面表」。【建議】
- [ ] 遠側手臂、遠側腿在身體後；近側在前；武器按持法分層。【建議】
- [ ] 需要在動畫中改順序的零件（手在身前／身後）用雙 slot 預置，而非即時重排。【出處】Spine 做法 https://eu.esotericsoftware.com/spine-slots
- [ ] 遠側肢體亮度 −10~25%。【建議】

---

## 8. 動作設計檢查清單

每項標【建議】者為起點數值（60 Hz 下），其餘有出處者另標。

- **待機**：週期 3.6–4.4 s（循環 ≤ 45 格設計的出處為動畫學校）；呼吸髖領先；每 6–12 s 重心轉移；眨眼 3–6 s 一次、6–9 影格；循環首尾姿勢差 ≤1 px。出處見 4.2。
- **走**：相位以距離推進；支撐腳鎖世界座標；頭上下起伏跟隨步伐。細節見你們既有生物力學資料（此處不重複）。
- **跑**：預備傾斜前進；兩腳同離地的飄浮相存在；擺動腿縮短（stride warp）。【建議】
- **跳**：蹲（預備）2–4 影格 → 起跳拉伸 → 空中姿勢 → 落地擠壓。預備不可吃輸入延遲：起跳判定在按鍵當影格，蹲姿用視覺補償。【出處】輸入 <100 ms 與預備數字見 2.9（低可信度）。
- **落地**：擠壓 ≤10–15%，2–4 影格回彈；落地腳 IK 吸附地面；高處落地多一次重心下沉＋手臂跟隨。【建議】
- **蹲**：骨盆下降，膝彎；重心保持在支撐面上方；進出蹲各 4–8 影格過渡。【建議】
- **坐**：先重心轉移到椅面，髖下降，最後上身放鬆；idle 呼吸幅度降低 30–50%。【建議】
- **說話**：頭微點、嘴型與重音同步；手勢每 1.5–3 s 一次；視線在聽者與別處間切換。【建議】；對話中角色被打斷可暫停再繼續（Uncharted 4 做法，見 4.2）。
- **受擊**：hit stop 2–6 影格（輕/中/重）、受擊姿勢立刻到位、被打方抖動衰減；之後 3–6 影格擺回。【出處】Sakurai 八項；數字【建議】。https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- **死亡**：速度與方向取自致命一擊（承接 hit stop）；先主要部位後次要部位依序倒（重疊與跟隨）；落地後有 1–2 次彈起；結束於靜止姿勢並停止彈簧運算以省效能。【建議】
- **轉身**：不要瞬間翻面，至少一個轉身姿勢（身體窄化＋頭領先）2–4 影格；翻面時重設 IK 與彈簧狀態；Z 順序換成翻面表。【出處】Spine 轉身討論 https://ar.esotericsoftware.com/forum/d/24825-turnaround-images-and-bones ；Godot 翻轉問題 https://forum.godotengine.org/t/how-do-i-properly-flip-a-2d-rigged-character-with-ik-and-lookat-in-godot-4/136805

---

## 9. 常見錯誤對照表

| 現象 | 常見原因 | 解法 | 判準（驗收） | 出處／標記 |
|---|---|---|---|---|
| 關節處露縫或穿幫 | 零件沒重疊、旋轉軸不在圓心 | 加大重疊、圓形關節、補畫隱藏區 | 角度極值渲染時關節 alpha ≥0.99 | 【出處】Adobe 社群、Live2D；數字【建議】 |
| 彎曲處網格塌縮／捏扁 | 頂點不足、權重過硬 | 加密頂點、平滑權重、輔助骨 | 彎到極值時網格無自交、肉眼無尖角 | 【出處】Spine 論壇 7673 摘要 |
| 腳滑 | 動畫速度≠移動速度；IK 只管垂直 | 距離相位、stride warp、foot lock | 支撐相腳位移 ≤2.5 cm（3D 研究門檻）；2D 版 ≤1 px/影格 | 【出處】bugnet、NVIDIA 指標；2D 數字【建議】 |
| 走跑混合時腳打架 | 兩剪輯落腳相位不同 | 對齊落腳到相同正規化時間（左 0.0／右 0.5） | 混合中途兩腳不交叉倒置 | 【出處】Unity blend tree |
| 轉身後左右手腳順序亂、IK 翻錯 | scale.x=-1 帶來負縮放 | 翻根節點＋重設 IK；準備翻面順序表 | 翻面前後 Z 順序一致的測試通過 | 【出處】Godot 論壇、Unity bugnet |
| 換 skin／朝向後手臂在頭的錯誤一側 | 繪製順序綁在 slot | 預置雙 slot | 各朝向截圖比對 | 【出處】Spine slots |
| 頭髮／衣物甩飛或抖動 | 彈簧不穩、狀態未重設 | 臨界阻尼、限制速度、翻面／傳送時重設 | 衝擊後 2 s 衰減至 <1% | 【建議】 |
| 動作「飄」沒重量 | 沒預備／沒跟隨、命中無停頓 | 預備 2–4 影格、hit stop 2–6 影格、落地擠壓 | 慢放可見預備與跟隨 | 【出處】泛論低可信；【建議】 |
| 動作遲鈍 | 預備太長 | 判定與輸入不等動畫；預備 ≤3 影格 | 按鍵到畫面回應 ≤100 ms | 【出處】泛論（低可信） |
| NPC 像凍結的假人 | 只有單一呼吸循環 | 呼吸＋重心轉移＋眨眼＋視線，各自隨機、錯開 | 30 秒內至少 4 種事件出現且不同步 | 【出處】生理數字、idle 指南；組合【建議】 |
| 每個 NPC 同步呼吸 | 共用相位 | 以角色 ID 為隨機種子偏移相位 | 同畫面兩 NPC 相位差 >0.1 週期 | 【建議】 |
| 眨眼太頻繁／太規律 | 固定間隔 | 3–6 s 隨機＋偶發雙眨 | 間隔標準差 >0.5 s | 【推導】自 15–20 次/分 |
| 循環動畫跳一下 | 首尾姿勢不同、速度不連續 | 閉合循環、檢查速度 | 首尾差 ≤1 px/1° | 【建議】 |
| 弧線不順、手尖軌跡有折 | 線性補間、關鍵姿勢過少 | 加中間關鍵姿勢、改 ease | 軌跡曲率無尖峰 | 【出處】onion skin 檢視；測試【建議】 |
| 擠壓後角色變胖 | 未做體積守恆 | scaleX×scaleY≈1 | 乘積在 0.95–1.05 | 【建議】 |
| 雙手持槍手飄離槍 | 武器骨掛在身體下、IK 目標沒跟 | 武器骨掛 root、握點骨當 IK 目標 | 握點與手距離 ≤1 px | 【出處】Spine 部落格；數字【建議】 |
| 動作順暢卻「不像手繪」 | 全部補間 | 低格率（15 fps 級）＋關鍵姿勢停留，如 Xrd | 招式關鍵姿勢有 hold | 【出處】Xrd 摘要 |
| 引擎升級後 SkeletonModification2D 壞掉 | 實驗性 API | 自寫 TwoBoneIK／彈簧 | 4.7 無頭測試過 | 【出處】Godot 文件標示實驗性 |

---

## 10. 尚未解決／建議後續

- 想補足【沒找到】項目，需讀全文：GDC Vault（Motomura 2015、Rosen 2014、Hecker 2008、Zadziuk 2016 的投影片）、Spine 使用者指南全文（被代理擋下）、Dead Cells 的 GDC 或 Pocket Gamer 演講影片、Naughty Dog 的 GDC 動畫演講。本次搜尋未取得其全文。
- 所有【建議】數字應在遊戲內以截圖＋逐格 GIF 驗證後，寫進資料表（`design/` 或角色資料檔），避免寫死在程式。
- 低可信度來源（技能庫網站、個人部落格、論壇）已在條目標示，採用前請二次確認。
