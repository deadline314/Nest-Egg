# 畫面活化與融入：研究依據

2026-11-27，使用者指出地圖、介面與玩法看起來簡陋死板，圖片像被直接貼上；要求參考業界做法，加入合適動畫、把圖片拆成部件處理、讓物件融入場景，背景要有動態與互動，同時調整光照、渲染與效能。本文整理查到的做法與取捨，專案決策寫在 [DESIGN.md](DESIGN.md)。

## 現況觀察（原生 Forward+ 截圖，main f0fbd7d60）

| 畫面 | 看到的問題 |
|---|---|
| 第一章街道、屋頂 | 建築立面是整片重複貼圖，窗戶排列一模一樣；除了雨之外沒有東西在動 |
| 街道、市集的擺設 | 物件帶淺色外框、腳下沒有接地陰影，明暗與背牆不一致，像貼紙 |
| 平台下方與坑洞 | 畫面下三分之一是整片死黑，邊緣是一條硬線 |
| 告示提示 | 黑底大字方塊蓋在場景上，和世界沒有關係 |
| 設定與難度選單 | 版面靜止，切頁與選取沒有回饋，大片空白 |
| 過場舞台 | 城市天際線只有一層，雨是等長直線 |

## 業界做法

### 分層與景深

- 《Hollow Knight》的場景分前景、中景、背景三層，玩家在中景活動，各層以不同速度捲動；遠層降低對比並略為模糊，模仿大氣透視。[The Art of Hollow Knight](https://medium.com/3d-environmental-art/the-art-of-hollow-knight-f4c05dda3882)、[80.lv：Silksong 的世界其實不是 2D](https://80.lv/articles/hollow-knight-silksong-s-game-world-isn-t-actually-2d)、[Godot 論壇的實作討論](https://forum.godotengine.org/t/currently-prototyping-hollow-knights-visual-style-feedback-needed/54925)
- 鏡頭不動時也讓某些層自己動（雲、遠方交通），背景才不會像一張照片。[Tuts+：視差捲動](https://code.tutsplus.com/parallax-scrolling-a-simple-effective-way-to-add-depth-to-a-2d-game--cms-21510t)
- 《Dead Cells》場景美術 Gwenaël Massé：背景與可走地形的對比要拉到最大，背景色彼此融合、不出現斷線；裝飾永遠低於地形、敵人與危險的視覺優先序。[Art Design Deep Dive](https://www.gamedeveloper.com/production/art-design-deep-dive-giving-back-colors-to-cryptic-worlds-in-i-dead-cells-i-)

### 讓靜態圖動起來

- 植被與布料用頂點著色器加上以貼圖或雜訊驅動的風，每株相位不同，避免整片同步擺動。[Trees in the Breeze](https://www.gamedeveloper.com/programming/trees-in-the-breeze)
- 一張圖拆成部件後各自綁骨頭或網格變形（cutout 動畫）；只有需要動的部件拆開，固定支架留在原圖。Godot 的 Polygon2D 可對自訂形狀做 UV 與頂點變形。[Godot cutout animation](https://docs.godotengine.org/en/stable/tutorials/animation/cutout_animation.html)
- 靜態插畫先分割主體，再嵌入三角網格，以少數控制點帶動周圍像素，可做呼吸、搖晃等小幅循環。[After Effects Puppet 工具](https://helpx.adobe.com/after-effects/using/animating-puppet-tools.html)、[Animating Still Images](https://www.arxiv.org/pdf/2209.10497)

### 融入場景，不像貼上

- 賽璐璐合成把陰影分成兩種：把角色「釘」在地上的接觸陰影，和投到佈景上的投影；兩者分開處理。[Petrovic et al., 2000](https://gfx.cs.princeton.edu/proj/cel_shadows/petrovic2000.pdf)
- 物件底部一圈柔和的環境遮蔽，加上與場景陰影同色、同濃度的影子，是合成時最有效的接地手段；陰影以相乘疊在背景上。[Autodesk 合成教學](https://help.autodesk.com/cloudhelp/2017/ENU/3DSMax/files/GUID-3F934E37-CC74-4EC7-A0E2-A96A0880CF84.htm)、[Soft Shadow Network](https://par.nsf.gov/servlets/purl/10286980)
- Godot 的 2D 光只在有法線貼圖且光源高度不為零時才有立體受光；沒有 CanvasModulate 壓暗環境時，光只會把原圖再加亮。[Godot 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)

### 介面動效

- 按下與聚焦的回饋 100–200 毫秒，開關頁面 200–300 毫秒，介面動效不超過 300–500 毫秒；進場用 ease-out。[NN/g：動畫時間](https://www.nngroup.com/articles/animation-duration/)、[web.dev：選擇緩動](https://web.dev/articles/choosing-the-right-easing)
- 高頻操作（清單移動、滑鼠滑過）動效要小或沒有；動畫不能讓玩家等，輸入在動畫期間照常生效。[Emil Kowalski：7 個動效建議](https://emilkowal.ski/ui/7-practical-animation-tips)
- 減少動態時縮短時間、拿掉大位移與縮放，但保留按下與錯誤等必要回饋。

### 把提示做進世界，面板要有形狀語言

- 《Dead Space》幾乎所有資訊都做成世界裡的東西：生命與能量在裝甲上，其餘是角色身邊的全像投影。[Markers：Dead Space 的介面](https://www.giantbomb.com/profile/gamer_152/blog/markers-i-a-deep-dive-into-dead-spaces-ui/249377/)
- 《Splinter Cell: Conviction》把目標文字投在場景表面上，是給玩家看、但放在空間裡的「空間介面」；文字太大時會稍微出戲。[User interface design in video games](https://www.gamedeveloper.com/design/user-interface-design-in-video-games)
- 全部做成世界內的東西會限制能傳達的資訊，也比較難做；關鍵資訊仍要優先讀得到。[Diegetic interfaces](https://www.wayline.io/blog/diegetic-interfaces-game-design)
- 全像效果的基本組成：掃描線、色版錯位、切片位移的故障感、隨時間的閃爍。[Godot Shaders：Hologram Effect](https://godotshaders.com/shader/hologram-effect/)
- 《Beastieball》整套介面用平行四邊形當形狀語言，作者說這只是「把字放進矩形」這種最無聊排法的一點小變化，卻讓整個介面有了個性。[Deep Dive：Beastieball 的介面視覺語言](https://www.gamedeveloper.com/art/deep-dive-developing-a-clear-and-consistent-visual-language-in-the-ui-of-beastieball)
- 風格定了就全部照做，不留特例；狀態不能只靠顏色區分，要有形狀或圖示輔助。[Game UI Design: A Practical Guide](https://madegooddesigns.com/game-ui-design/)

### 效能

- 2D 遊戲通常先卡在 CPU；每次改動都重新量測，不靠猜。[Godot 一般最佳化](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- 自訂著色器盡量共用同一份材質，才不會打斷批次。[Godot GPU 最佳化](https://docs.godotengine.org/en/4.2/tutorials/performance/gpu_optimization.html)

### 玩法多樣性

- 新機制第一次出現時只有它是新的，放在安全的地方讓玩家試；之後逐段加壓，最後和舊機制組合。《Celeste》與《Rayman Legends》都是這個結構。[How to Design Breathtaking 2D Platformer Levels](https://medium.com/swlh/how-to-design-breathtaking-2d-platformer-levels-e8a261cdac93)、[Lessons from Suzy Cube：關卡多樣性](https://www.gamedeveloper.com/design/lessons-from-suzy-cube-level-variety)
- 機制夠深時不必每關都加新的；同一機制換情境、換組合就能撐很多段。[Cornell CS3152 關卡設計講義](https://www.cs.cornell.edu/courses/cs3152/2024sp/lectures/lecture21/slides-21.pdf)
