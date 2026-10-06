# 章節節奏、關卡與戰鬥設計、敘事融入玩法：業界做法與可檢查規則

> 來源：2026-10-06 使用者回報第一章「走一段路、看一段過場、再走一段路」太碎、戰鬥太少、地圖無聊、過場不知道在幹嘛，要求重新設計並以業界最佳實例為主。這份整理成參考資料；做事的流程與檢查清單在 skill `chapter-design`（`.claude/skills/chapter-design/`）。
> 注意：整理時網路代理擋掉了網頁全文且搜尋額度中途用完，數字來自搜尋摘要，條目已標【出處】【推導】【建議】【沒找到】。「戰鬥／探索比例」「兩次過場的最短間隔」業界沒有找到可引用的數字，文件中的值都是【建議】的起始值，要靠遊測校正。


研究日期：2026-10-06。給 Nest Egg 第一章（雨夜港區、8 個區域、30–45 分鐘、凜、手槍＋匕首＋衝刺格擋）重構用。

## 0. 先講研究限制（請務必讀）

- WebFetch 全被代理擋（deepnight.net、gamedeveloper.com、amara.org、book.leveldesignbook.com 皆 EGRESS_BLOCKED），只能靠 WebSearch 摘要。
- WebSearch 額度在研究中途用完（上限 200 次/回合，與其他 agent 共用），所以「barks 定義」「字幕每行字數」「遊測量測業界值」「Jim Brown」沒有查到，都標【沒找到】。
- 搜尋摘要多為二手整理，GMTK、GDC 原文沒能直接讀。凡是數字，只有標【出處】才代表摘要裡真的有；其餘是【推導】（由出處合理推算）或【建議】（我們自己的起始值，需遊測校正）。
- 標籤：【出處：網址】＝摘要中真實出現；【推導】；【建議】；【沒找到】。可信度另以（高／中／低）標註。
- 重要：「戰鬥／探索／敍事／休息」的業界比例、「兩次過場之間至少玩多久」的業界經驗值，兩者都【沒找到】可引用的數字。下面所有比例與間隔都是【建議】，不是業界標準。

---

## 1. 節奏

### 1.1 張力曲線與「谷與峰一樣重要」

- 節奏＝活動與事件的順序與韻律；單人關卡需要強節奏；玩家搞不清楚在發生什麼、能做什麼，通常是節奏問題。【出處：Level Design Book（Robert Yang）pacing 頁，搜尋結果出現的是代理鏡像，原站同路徑 book.leveldesignbook.com/process/preproduction/pacing：https://https-book_leveldesignbook_com.proxy.bugsmash.io/process/preproduction/pacing】（中）
- 強度畫成折線圖，峰（高強度）與谷（平靜）一樣重要；重複＝無聊，對比才有滿足感。【出處：World of Level Design, Pete Ellis, gameplay beats：https://www.worldofleveldesign.com/categories/wold-members-tutorials/peteellis/level-design-pacing-gameplay-beats-part2.php】（中）
- 遭遇節奏：戰鬥與較安靜的探索／解謎交替，避免變成純戰鬥苦工。【出處：https://bugnet.io/blog/how-to-design-encounter-pacing-in-a-level】（低，部落格）
- 「鋸齒」強度範例：休息／教學 0.1、一般戰鬥 0.5、較難戰鬥 0.8、高潮 1.0。【出處：https://claudeskills.info/skills/gamedev-skills/awesome-gamedev-agent-skills/level-design/ ，該頁是 AI skill 檔，可信度低，只當一個可用的標尺語言】
- 【推導】把一區想成「小弧線」：低（進場、環境敍事）→ 中（遭遇 1–2）→ 高（區域高潮：迷你頭目或鎖場）→ 低（獎勵、存檔、捷徑解鎖）。整章再疊一條大弧線，後段峰值逐區抬高，第 7 區略降、留給最終頭目。

### 1.2 比例（戰鬥／探索／敍事／休息）

- 【沒找到】沒有可引用的業界比例。
- 【建議】起始值（以遊玩時間計）：戰鬥 40–45%、移動與探索（含平台跳躍、機關謎題）35–40%、地圖上敍事（氣泡、廣播、環境）約 8–10%（與其他活動重疊，不額外佔時間）、休息（存檔點、商店、安全房間）約 8–10%、過場 ≤5%。目前第一章「走路＋過場」比例要反過來：過場降到 ≤5%。
- 【建議】遊測後以「每分鐘遭遇數」「過場佔比」兩個量測校正（見第 5 節）。

### 1.3 各作品的章節／區域結構（搜尋能確認的部分）

| 作品 | 能確認的事實 | 出處／可信度 |
|---|---|---|
| Hollow Knight | 主線約 25–35 小時；約 47 個頭目（含變體），主線必打約 10 個，其餘選擇性／夢境／DLC；區域順序大致 Crossroads → Greenpath → Fungal Wastes → City of Tears → Waterways → Basin。City of Tears 是從較線性轉向自由探索的轉折點 | 時長：https://www.svg.com/398724/how-long-does-it-take-to-beat-hollow-knight、https://twinfinite.net/guides/how-long-hollow-knight-answered/；頭目數：https://hollowknight.wiki/w/Bosses_(Hollow_Knight) 搜尋摘要（中）；GMTK 世界設計逐字稿：https://amara.org/subtitles/1YBjcP2T6VPf/en/1/download/The%20World%20Design%20of%20Hollow%20Knight%20%20Boss%20Keys.en.srt（中，僅看到摘要） |
| Dead Cells | 單輪約 30–60 分鐘；每次是手工設計「區塊」拼成，兼顧手作感與每次不同；全程序生成會變得不合邏輯、缺乏一致性與沉浸感，所以採混合 | 長度：https://www.thegamer.com/dead-cells-how-long-beat/；混合法：https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/（中）。各生態域的計時門時間（如 Promenade 2 分、Ossuary 8 分…）只在二手摘要出現（https://deadcells.wiki.gg/wiki/Biome ），單位與定義不清，低可信，不採用 |
| Celeste | 主線 8 章、約 6–8.5 小時；「碎形結構」：分成區域，每個區域有多個關卡，每個關卡自成故事並連到主線 | 結構：https://en.wikipedia.org/wiki/Celeste_(video_game)；時長：https://orbispatches.com/gaming-faq/how-many-hours-does-it-take-to-beat-celeste（低）。每章幾個房間：【沒找到】。速通時間不是一般玩家時間，不採用 |
| Katana Zero | 主線約 4.5 小時；關卡短，一次死亡損失約 20 秒內、單一段落至多約 30 秒；關卡之間用對話樹講故事；作者目標是「困難、以劇情為主但不強迫玩家等對話與過場」 | 時長／短段：https://www.dekudeals.com/items/katana-zero 與 Steam 討論搜尋摘要（低）；作者意圖：https://en.wikipedia.org/wiki/Katana_Zero、https://www.gamerevolution.com/features/520685-katana-zero-interview（中） |
| Hades | 每輪是房間序列；對話散在輪與輪之間與房間內，超過 22,000 句；採「乘法式內容」，劇情依玩家進度改變 | https://gdcvault.com/play/1026975/Breathing-Life-into-Greek-Myth（句數，中）；https://GamaSutra.com/design/roguelikes-and-narrative-design-with-i-hades-i-creative-director-greg-kasavin（高） |
| Metroid Dread | 製作人 Sakamoto 說最根本的事是節奏：高強度、快節奏的動作，加流暢操作；在多處暫時把玩家鎖進地圖的一小段，降低迷路 | https://nintendowire.com/news/2022/01/24/metroid-dread-producer-discusses-the-games-difficulty-and-why-the-e-m-m-i-encounters-were-so-unforgiving/（中）；鎖定區段：GMTK 逐字稿 https://amara.org/subtitles/Aci4iDbgsAtY/en/1/download/Why%20You%20Didnt%20Get%20Lost%20in%20Metroid%20Dread.en.txt 、https://tildes.net/~games/z02/why_you_didnt_get_lost_in_metroid_dread（中） |
| Ori and the Blind Forest | 逃脫段（環境追著 Ori）拿掉探索，專測移動技巧；Ginso Tree 是把所有核心移動技能連續串起的垂直逃脫；有玩家要 30+ 次嘗試、死亡要整段重來，被評為破壞節奏的難度尖峰 | https://godisageek.com/?p=159726 、https://steamcommunity.com/app/261570/discussions/0/492378265890019133（低–中） |
| Blasphemous | 祭壇（Prie Dieu）是存檔點，補血補藥但敵人重生；捷徑被評為聰明且有成就感；敍事機制多為選擇性，只給想看的人 | https://metroidvaniareview.com/blasphemous/ 、https://www.gamereactor.eu/the-game-kitchen-on-blasphemous-ambiguous-story/ （中） |
| Cuphead | 以連續頭目戰為核心，穿插分散在世界地圖上的跑跳射擊關；各類型精確數量搜尋摘要互相矛盾 | https://www.gamedeveloper.com/business/road-to-the-igf-studio-mdhr-s-i-cuphead-i- ；數量【沒找到】 |
| Super Metroid | 開場 Crateria 只有一條路，帶玩家很快拿到 Morph Ball 與飛彈，兩者分別開小縫與粉紅門，從此開出多條路；每拿一個道具就教一課，且不讓人覺得被牽著走 | https://www.gamedeveloper.com/design/the-invisible-hand-of-super-metroid 、https://amara.org/v/C3BE7（GMTK Boss Keys，Super Metroid 世界設計）（中） |
| Dark Souls／Hollow Knight／Half-Life／Bastion | 見第 4 節 | 見第 4 節 |

- 各區「多長、幾場戰鬥、有沒有迷你頭目」：以上作品皆【沒找到】可引用的逐區數字。不要假裝有。
- 【推導】可用的粗略對照：Katana Zero 單段 ≤30 秒、Dead Cells 單輪 30–60 分，說明業界動作遊戲常把「一個失敗單位」壓在 30 秒到數分鐘之間。我們第一章每區約 4–5 分鐘（38 分 ÷ 8），單一遭遇 30–60 秒，在此範圍內。

### 1.4 過場長度與間隔

- 一般論壇意見：純說話解說不應超過 5 分鐘；10 分鐘算長、20 分鐘是濫用玩家注意力；最早的過場要短、只講必要資訊；不要把長過場放在最前面；可用小互動或選擇讓過場變可玩。【出處：https://intfiction.org/t/how-long-is-too-long-for-a-cutscene/57215/13 、https://rpgmaker.net/forums/topics/8601】（低，論壇意見，且針對敍事向遊戲，不適用動作平台）
- 另一個摘要說「過場長度要跟敍事目的相稱，過長相對於敍事價值是主要失敗模式」。【出處：morphic.com 詞彙頁 https://morphic.com/ai-glossary/cutscene】（低）
- 兩次過場之間「至少玩多久」的業界經驗值：【沒找到】。
- 【建議】過場長度：開場 ≤20 秒、章中大事 ≤45 秒、章末 ≤60 秒；全章過場總長 ≤2 分鐘（≈5%）。一律可跳過（按住 0.5 秒）。
- 【建議】兩次過場之間至少 8 分鐘純遊玩（≈ 兩個區域）。理由【推導】：Katana Zero 一段 ≤30 秒就有一次劇情窗口，但它的窗口是玩家可互動的對話，不是被動過場；被動過場應該更稀有。
- 【建議】判準「改變世界狀態才用過場」：（1）地圖永久改變（區域毀滅、通道出現／消失）（2）角色關係不可逆（死亡、背叛、加入）（3）新區域或新能力的首次揭露（4）章末。其餘一律走地圖上敍事。

---

## 2. 戰鬥遭遇設計

### 2.1 遭遇戰的結構

- 遭遇＝「一連串支援多種玩家戰術的系統性挑戰」，不是「一堆敵人站在房間裡」。【出處：Level Design Book，combat/encounter 頁，鏡像 https://https-book_leveldesignbook_com.proxy.bugsmash.io/process/combat/encounter】（中）
- 【推導／建議】把遭遇拆成 5 拍：①預告（看得到敵人或聽得到聲音，可選擇偷襲或繞路）②接觸（第一個敵人入場，教一個行為）③加壓（增援或第二種敵人，用到地形）④高點（打破玩家節奏的一個轉折，如飛行敵從背後、地形落下）⑤收尾（清空後有短暫安靜與掉落／獎勵）。小遭遇只需 ①②⑤，每區至少一場完整 5 拍。
- 時長：【沒找到】業界數字。【建議】小遭遇 15–30 秒、標準 30–60 秒、區域高潮 60–90 秒；超過 90 秒的非頭目戰通常是疲勞點。

### 2.2 同屏數量與增援

- 同時攻擊的上限用「攻擊令牌」控制：id Software 在 GDC 談 DOOM（2016）時，每種攻擊類型有限量令牌，敵人要攻擊先申請，結束釋放；Naughty Dog 在 The Last of Us Part II 對近戰也描述類似做法；常見預設池：近戰 1、遠程 2、重擊 1。【出處：https://www.strayspark.studio/blog/attack-token-system-ue5-group-combat-that-feels-fair】（中，二手，且「預設池」是該部落格的範例數字，不是 id 的數字）
- 觀點：玩家大約只追得到「一個近戰攻擊＋幾發遠程」。【同上出處】
- 【建議】凜（近戰匕首＋手槍＋衝刺格擋）：同屏存活 ≤6、同時主動攻擊近戰 ≤2、遠程 ≤2、重擊／特殊 ≤1；其餘敵人走位、喊話、等待。區域 1–2 上限再降一級（≤3 存活）。
- 【建議】波次：每場鎖場 2–3 波，每波 2–4 隻；第一波 3 秒內可開打，下一波在上一波只剩 1 隻時入場（避免空窗），增援要有入場演出（從門、管線、空投進來）並預告 1 秒。
- 【建議】敵人要有「角色分工」：近戰突進者、遠程壓制者、扛盾（要用格擋破防）、飛行／高處騷擾者。每場遭遇至少 2 種分工，才逼出戰術切換。

### 2.3 教學曲線（引入 → 安全練習 → 組合 → 考驗）

- 【出處】Super Metroid：開場先給單一路徑，拿到 Morph Ball／飛彈後才開出多條路，每個道具是一課。（https://www.gamedeveloper.com/design/the-invisible-hand-of-super-metroid ）
- 【出處】Metroid Dread：暫時鎖定小段地圖，降低玩家要記的範圍。（GMTK 逐字稿，見 1.3）
- 【推導】經典四步（引入→發展→轉折→收束）源自 Nintendo 關卡設計談論，GMTK 常引用；本次搜尋沒有直接取得，視為【沒找到】直接證據。
- 【建議】每個新機制在我們第一章的流程：
  1. 引入：安全環境、單一敵人／單一危險、失敗代價低（例：第一次格擋，敵人慢出拳、玩家前方沒有坑）。
  2. 練習：同機制 2–3 次變化（敵人速度、角度、地形不同），仍無額外壓力。
  3. 組合：與已學機制混用（格擋＋手槍、衝刺穿過攻擊＋平台）。
  4. 考驗：在區域高潮或迷你頭目用，且之後還會回來（捷徑路上放一個回顧遭遇）。
- 【建議】一章只引入 3–4 個新東西（建議：衝刺穿越、格擋破防、盾兵、遠程無人機或電擊地板）；八區平均每 2 區一個，避免每區都在教。

### 2.4 競技場鎖場 vs 開放遭遇

- 【出處】Dead Cells：房間式遭遇，以手工區塊拼接，兼顧手作與變化。（https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/ ）
- 【出處】Hollow Knight 是區域遊走式：敵人分布在連續地圖裡，玩家邊走邊遇；（概念層級，來自 GMTK 世界設計與一般評論，數字【沒找到】）
- 【推導】取捨：鎖場能保證遭遇品質（敵人組合可控、玩家可預期）但打斷探索；開放遭遇保探索連續但難控強度。Metroid Dread 的「鎖進小區段」是折衷。
- 【建議】比例 3:7：每區 1 場鎖場（區域高潮，且有入口預告與可見的鎖與解鎖條件）＋ 3–5 場開放遭遇（敵人沿路徑放置，可繞過、可偷襲、可帶到地形上）。鎖場時間 ≤90 秒，鎖場不可放在剛死亡重試的第一個房間之後立刻出現。

### 2.5 迷你頭目節奏與地形配合

- 【出處】Ori 的逃脫段像「頭目」，檢驗玩家是否學會移動技。（https://godisageek.com/?p=159726 ）；Cuphead 以頭目為核心。（見 1.3）
- 【建議】本章迷你頭目 2 個（區域 4、區域 6），最終頭目 1 個（區域 8）。迷你頭目打 60–120 秒、2 個階段、使用玩家剛學的機制；最終頭目 3–4 分鐘、3 階段。頭目前一個房間放存檔點，頭目後放捷徑與劇情氣泡。
- 【建議】地形配合：掩體可被破壞（讓玩家只能暫時躲）、垂直空間（上下兩層，敵人從高處射擊、玩家可用衝刺跳上）、危險地形（電擊地板、起重機、水）用在「加壓」那一拍，不要一開場就用。
- 【建議】敵人佈置：沿路徑設置「看得到下一個敵人」的視線；高處與低處各放一個遠程；入口附近放弱敵、深處放強敵；同類敵人不連續超過 2 場。

---

## 3. 地圖設計

### 3.1 Metroidvania 核心原則

- 世界隨能力開啟，邀請回頭；檢驗：是否至少有一項新能力讓玩家回到「曾經看過但到不了」的地方。【出處：https://allthings.how/metroidvania-explained-design-pillars-history-scope/ 】（中）
- 地圖是緊密連通的網，區域互相迴圈，不是各自獨立的區塊。【同上】
- 捷徑與易讀、可教學的版面，才讓回頭走不枯燥；解鎖後的捷徑避免長路折返。【同上】
- 鎖與鑰匙：鎖＝暫時過不去（太寬的縫、要炸的牆、高台、酸池），鑰匙＝能力；通常一把鑰匙對多把鎖，只有一個是主線，其餘通往選擇性獎勵、秘密頭目或另一道鎖。【同上】
- 可見但不可達的獎勵：玩家先看到，之後帶新能力回來。【同上，及 https://bugnet.io/blog/how-to-design-a-metroidvania-map 】（低–中）
- 【出處】Super Metroid 開場：單一路徑 → Morph Ball／飛彈 → 小縫與粉紅門 → 多路徑。（見 1.3）
- 【出處】Metroid Dread：用敵人與物件擺放把玩家悄悄導向目標；先限制路線，之後再隨能力開放地圖。（GMTK 逐字稿，見 1.3）
- 【出處】Hollow Knight：City of Tears 是從線性轉向自由的轉折。（GMTK 世界設計逐字稿，見 1.3）

### 3.2 其他你列名的來源狀況

- Mark Brown／Game Maker's Toolkit：Boss Keys 系列（Super Metroid、Hollow Knight、Metroid Dread 皆有影片）。只拿到摘要與部分逐字稿；細節不要當原話引用。
- Jim Brown：【沒找到】（人物指涉不明，未查到對應的關卡設計文章）。
- Level Design Book：有 pacing、encounter、flow（circulation、verticality）、prospect-refuge 等章，原文被擋，只讀到章名與一兩句定義（見 1.1、2.1）。
- Game Developer／Gamasutra：Super Metroid（The Invisible Hand）、Dead Cells（deepnight 教學）、Hades 訪談已列入。
- Celeste 房間設計（一個機制「引入—發展—轉折—收束」）：搜尋摘要只確認「碎形結構」，細節【沒找到】。

### 3.3 其他設計原則（【推導／建議】，無直接出處）

- 地標：每區有 1 個遠處可見的視覺地標（霓虹招牌、起重機、燈塔），讓玩家知道「往那裡走」。
- 光與視線：用亮度、霓虹色、雨幕中的光束引導方向；出口與下一個目標略亮、危險略暗紅。（賽博龐克雨夜天然合適）
- 垂直與水平混合：每區至少一段「爬升」與一段「下潛」；跨區用垂直連接（升降梯、管線）形成立體地圖。
- 迴圈：每區至少一條迴圈，例如單向捷徑（只能從後面打開的捲門）把後段接回前段。
- 獎勵可見：第 1–2 區就放 2 個「看得到拿不到」的獎勵（需衝刺距離、需高處格擋才能破的牆），第 5–7 區回來拿。
- 秘密：每區 1 個秘密房（可破壞牆、隱藏通風管），提示一句話或一個視覺線索（牆縫透光、地上血跡），秘密獎勵為升級碎片，不鎖主線。
- 三段式結構：入口段（引入）→ 中段（發展、迴圈、捷徑）→ 高潮段（轉折，鎖場／迷你頭目）→ 出口段（獎勵、存檔、下一區預告）。
- 章節地標：整章有 1 座「中央地標」（例如港區中央的巨大廣告塔），在多個區域從不同角度看到，最後頭目戰在它頂端。

---

## 4. 敍事融入玩法（少過場）

### 4.1 各作品做法

- Half-Life：玩家幾乎不間斷地控制角色，故事主要靠腳本事件而非過場，連獨白時也盡量不奪走操控。【出處：https://en.wikipedia.org/wiki/Half-Life_(video_game) 、https://wwrdeepdives.substack.com/p/half-life-how-to-tell-a-story-without】（中）
- Hollow Knight：靠環境線索、簡短神祕的 NPC 對話、隱藏日誌，不停下來解釋歷史；用「物種」建立區域文化（Mantis Village＝力量與榮譽、Hive＝對女王忠誠、Deepnest＝掠食與迷宮）。【出處：https://proseandquans.substack.com/p/hollow-knight-and-breadcrumbing-backstory 、https://mechanicsofmagic.com/?p=61009】（中）
- Dark Souls：故事主要靠物品說明文字與環境設計，活著的角色很少且說得不多；用廢棄營地、破損武器、褪色壁畫講故事。【出處：https://media.gdcvault.com/gdc2017/GameNarrativeReview/Calvin_Walantus_UCSC_GDC_Narrative.pdf 、https://amrsalehduat.substack.com/p/how-fromsoftware-tells-stories-without】（中）
- Bastion：動態旁白，依玩家行為說話（例：常翻滾就會被說「somersaulting like crazy」）；台詞除非玩家重複同樣內容否則不重複；不是流水帳式實況，而是加深互動；設計動機是「容易上手、不打斷遊玩、仍有情感重量」。【出處：https://en.wikipedia.org/wiki/Bastion_(video_game) 、https://www.supergiantgames.com/blog/in-depth-writing-bastion/ 、https://gamebanshee.com/86p4】（中–高）
- Hades：對話量極大（22,000+ 句），分散成短句，劇情依玩家進度與選擇變化，放在輪與輪之間與房間內。【出處：https://gdcvault.com/play/1026975/Breathing-Life-into-Greek-Myth 、GamaSutra 訪談見 1.3】（中）
- Katana Zero：關卡間用對話樹，對話可打斷（打斷也算選擇），作者刻意不讓玩家等待對話與過場，且讓高速殺戮與安靜劇情對比。【出處：Wikipedia 與 GameRevolution 訪談，見 1.3】（中）
- Blasphemous：敍事機制多為選擇性，只給想看的人；仍有手繪過場動畫。【出處：https://www.gamereactor.eu/the-game-kitchen-on-blasphemous-ambiguous-story/ 、https://metroidvaniareview.com/blasphemous/】（中）
- Celeste、Transistor、Metal Gear／Dishonored 的「可走動廣播」：本次搜尋未取得具體摘要，【沒找到】。（Celeste 的對話氣泡、Metal Gear 無線電為眾所周知的手法，但本文不引用細節。）
- 「barks／戰鬥中短句」的業界準則、長度：【沒找到】（搜尋額度用完）。

### 4.2 在地圖上說話的手法（【推導】自上述，【建議】為我們的規格）

| 手法 | 適合傳達 | 對流暢度影響 | 備註 |
|---|---|---|---|
| 環境敍事（塗鴉、屍體、海報、場景道具） | 世界背景、前因、警告 | 零 | 一個畫面一個故事，勿塞滿 |
| 對話氣泡（NPC 或凜的內心） | 當下情緒、提示、關係 | 低，不停下 | 玩家可邊走邊讀，不鎖操作 |
| 廣播／無線電（可移動時播放） | 任務、委託人指示、情勢更新 | 低，需可跳過重播 | 全程允許操作；重要詞彙配字幕 |
| 戰鬥 barks（短句） | 敵人反應、凜的吐槽、情境提示 | 極低 | 每場遭遇最多 2 句，不重複 |
| 旁白／日誌／物品描述 | 深度背景 | 零（自願閱讀） | 選擇性，做成收集 |
| 過場 | 改變世界狀態的大事 | 高 | 全章 ≤3 次 |

### 4.3 對話規格建議（【建議】，業界字數規範【沒找到】）

- 氣泡每句 ≤18 個中文字（超過就拆成兩句，各自獨立顯示）；一個氣泡最多 2 行。
- 同屏最多 2 個氣泡同時存在；新的出現時，舊的淡出。
- 顯示時間 ≈ 1.2 秒 + 0.1 秒 × 字數（上限 4 秒），可選擇「點一下跳到下一句」；無需輸入也會自動消失。
- 戰鬥中不顯示長對話：戰鬥中只出 barks（≤10 字），完整對話在戰前或戰後。
- 一段連續地圖對話 ≤4 句；兩次地圖對話之間至少 20 秒純遊玩。
- 全章主要的「劇情窗口」約 10–14 個（每區 1–2 個），每個 ≤15 秒；全部可略過。
- 重要資訊（任務目標、機關提示）必須被重複：氣泡＋HUD 一行提示，避免玩家戰鬥時漏看。
- 避免打斷流暢度的三原則：不鎖操作、不改鏡頭（除非鎖場演出）、玩家死亡重來時不重播同樣的長對話。

---

## 5. 驗收與檢查清單

### 5.1 章節設計文件應包含

- 章節目標：玩家學到什麼、感受什麼、世界狀態改變了什麼（一句話）。
- 一頁式地圖圖解：區域連線、迴圈、捷徑、鎖與鑰匙、秘密、存檔點、地標。
- 張力曲線圖：逐區的預期強度與時長；標出迷你頭目與頭目。
- 區域表：每區功能、時長、遭遇數、敵人種類與數量上限、新機制、獎勵、劇情窗口。
- 教學表：新機制出現的區域與「引入／練習／組合／考驗」落點。
- 敍事表：每個劇情窗口的手法（環境／氣泡／廣播／過場）、字數、位置；過場清單與判準說明。
- 風險表：預期死亡熱點、疲勞點、迷路點，以及應對。
- 通過標準（見下）。

### 5.2 遊玩測試量測（業界門檻【沒找到】；以下為【建議】起始值，需用我們自己的遊測校正）

| 量測 | 目標 | 警訊 |
|---|---|---|
| 全章通關時間（首次） | 30–45 分鐘 | <25 或 >55 |
| 每分鐘遭遇數 | 0.5–0.8 | <0.3（太空）或 >1.0（太擠） |
| 每區停留時間 | 3–6 分鐘 | 任一區 >8 分鐘 |
| 兩次過場間隔 | ≥8 分鐘 | <5 分鐘 |
| 過場佔總時長 | ≤5% | >8% |
| 地圖對話被跳過率 | <30% | >50%（太長或太無聊） |
| 單一遭遇死亡占全章死亡 | <15% | ≥20%（死亡熱點） |
| 任一區連續無遭遇時間 | ≤60 秒 | >90 秒（走路模擬器） |
| 迷路（>60 秒沒前進） | 少於 1 次／區 | ≥2 次／區 |
| 秘密發現率 | 25–50% | <10%（太隱晦）或 >80%（太明顯） |

- 記錄方式：事件日誌（遭遇開始／結束、死亡位置、對話顯示與跳過、區域進出時間），遊測後輸出死亡熱點圖與時間軸。
- 【推導】只有看數據，不看感覺：同一份地圖至少 5 位沒看過的玩家遊測，抓「同一處卡住 ≥3 人」。

---

## 6. 給我們第一章的結構建議（【建議】）

總長目標 38 分鐘（範圍 30–45）；戰鬥 40–45%、探索 35–40%、休息 8–10%、過場 ≤5%。

### 6.1 八區表

| # | 區域（暫名） | 功能 | 時長 | 遭遇 | 迷你頭目／頭目 | 探索、捷徑、秘密 | 過場 |
|---|---|---|---|---|---|---|---|
| 1 | 碼頭貨櫃場 | 教學：移動、手槍、匕首、第一次衝刺；廣播介紹委託 | 3–4 分 | 3 場小（1–2 隻） | 無 | 看得到拿不到的高處獎勵 1 個；可跳平台＋貨櫃堆垂直感；無捷徑 | 開場 ≤20 秒（或改為鏡頭推進＋廣播，不算過場） |
| 2 | 冷凍倉儲 | 教學：格擋破防、盾兵；第一次鎖場 | 4–5 分 | 4 場（含 1 場 2 波鎖場） | 無 | 第一條單向捷徑（捲門）接回區 1；秘密房 1 | 無 |
| 3 | 霓虹夜市 | 休息＋氣泡密度最高；NPC 短對話、商店、存檔；輕戰鬥 | 4–5 分 | 2 場輕 | 無 | 屋頂層垂直路線、機關謎題（招牌電路）；秘密 1；第二個可見但不可達獎勵 | 無 |
| 4 | 排水道 | 加入遠程與地形危險（水、電）；機關謎題（閥門） | 5 分 | 4 場＋區域高潮 | 迷你頭目 A（區末，60–120 秒） | 迴圈接夜市；秘密 1 | 無 |
| 5 | 港務塔 | 垂直攀登＋剛學技能的考驗；揭露劇情轉折 | 5 分 | 3 場（含 1 場高處遭遇） | 無 | 垂直迴圈＋升降梯捷徑；拿到能力→回收區 1–3 的可見獎勵 | 中段大事 ≤45 秒（世界狀態改變：例如港區停電、通道出現） |
| 6 | 停電下層碼頭 | 世界已改變，舊區域變新；組合考驗；黑暗中看光線引導 | 5 分 | 4 場＋鎖場 | 迷你頭目 B（區末，與地形配合） | 回收獎勵；兩個捷徑連回區 2、5 | 無 |
| 7 | 控制中樞走廊 | 回落：整理狀態、存檔、補給、廣播鋪陳最終戰；少量精英敵人 | 3–4 分 | 2 場精英 | 無 | 秘密 1；通往區 8 的最終捷徑（頭目死亡後可回返） | 無 |
| 8 | 屋頂／廣告塔頂 | 高潮：最終頭目，使用全章所學 | 4–5 分 | 頭目前 1 場短遭遇 | 最終頭目（3–4 分鐘、3 階段） | 無 | 章末 ≤60 秒 |

合計：約 33–38 分（含迷路與重試後約 40–45 分）；遭遇 22–26 場；過場 2–3 次、總長 ≤2 分 05 秒；兩次過場間隔：開場→區 5 約 20 分；區 5→章末約 18 分，皆 ≥8 分鐘。

### 6.2 劇情窗口分配（地圖上）

- 區 1–4：以廣播＋環境為主，每區 1–2 個氣泡窗口；建立委託人、凜的個性、港區勢力。
- 區 5：唯一「世界狀態改變」過場，其餘為對話氣泡。
- 區 6–7：以戰鬥 barks、廣播、日誌回收伏筆。
- 區 8：頭目戰中以短 barks 推動，不插入暫停對話；章末過場收束。

### 6.3 現狀改造順序（【建議】）

1. 先把「走一段路、看過場、再走」改成區域式地圖（見 6.1 表），過場降為 ≤3 次。
2. 補遭遇：先做標準遭遇模板（5 拍）與敵人令牌系統（資料化）。
3. 補地圖：每區迴圈、捷徑、秘密、可見但不可達獎勵，逐區加。
4. 把原過場內容拆成氣泡、廣播、環境物件。
5. 遊測、量測、校正（第 5 節表）。

---

## 7. 常見錯誤對照表

| 常見錯誤 | 症狀 | 對應做法 |
|---|---|---|
| 走路—過場—走路，節奏碎 | 玩家只在走路時被打斷，沒有累積感 | 過場全章 ≤3 次、每次 ≤1 分；其餘用氣泡、廣播（見 1.4、4.2） |
| 過場瑣碎、不知道在幹嘛 | 玩家跳過、記不得內容 | 判準：只有改變世界狀態才用過場；其他改成地圖上短句 |
| 戰鬥太少或太空 | 每分鐘遭遇數 <0.3 | 目標 0.5–0.8；每區至少 3 場；加一場鎖場高潮 |
| 戰鬥擠成一團 | 同屏敵人多卻只是打轉，玩家不知道被誰打 | 令牌限制同時攻擊者（見 2.2）；每場有角色分工 |
| 全程鎖場 | 探索被打斷、走一步就鎖 | 鎖場 1 場／區；其餘開放遭遇 |
| 一次教太多新機制 | 玩家搞不清楚該用什麼 | 引入→練習→組合→考驗；一章 3–4 個新機制 |
| 地圖是一條直線 | 沒有選擇、沒有回頭的理由 | 迴圈、捷徑、可見但不可達獎勵、秘密 |
| 地圖看起來都一樣 | 迷路、無記憶點 | 每區地標與主色；中央地標在多處可見 |
| 長路折返 | 回頭走枯燥 | 解鎖單向捷徑；回頭路加新遭遇或新獎勵 |
| 氣泡太長、同時太多 | 讀不完、戰鬥中漏看 | ≤18 字／句、同屏 ≤2 個、戰鬥中只放 ≤10 字 barks |
| 氣泡打斷操作 | 玩家被卡住等待 | 不鎖操作、可自動消失 |
| 重要資訊只講一次 | 玩家漏看就卡關 | 氣泡＋HUD 一行提示雙重呈現 |
| 難度尖峰藏在非頭目段落 | 單點死亡占比高（Ori 的逃脫段被批評） | 死亡熱點 ≥20% 就調整；加檢查點、縮短整段重來距離 |
| 頭目前沒有存檔、死後走很遠 | 挫折 | 頭目前放存檔點；死後可立即重試 |
| 把業界數字當聖旨 | 套了別人的比例卻不合自己遊戲 | 以本文第 5 節量測校正；沒找到的數字不要當標準 |

---

## 8. 來源清單（本文引用，皆為搜尋結果中真實出現的網址）

- Level Design Book（鏡像）：https://https-book_leveldesignbook_com.proxy.bugsmash.io/process/preproduction/pacing 、…/process/combat/encounter
- World of Level Design（Pete Ellis）：https://www.worldofleveldesign.com/categories/wold-members-tutorials/peteellis/level-design-pacing-gameplay-beats-part2.php
- https://allthings.how/metroidvania-explained-design-pillars-history-scope/
- https://bugnet.io/blog/how-to-design-a-metroidvania-map 、https://bugnet.io/blog/how-to-design-encounter-pacing-in-a-level
- https://claudeskills.info/skills/gamedev-skills/awesome-gamedev-agent-skills/level-design/（低可信）
- GMTK：Metroid Dread 逐字稿 https://amara.org/subtitles/Aci4iDbgsAtY/en/1/download/Why%20You%20Didnt%20Get%20Lost%20in%20Metroid%20Dread.en.txt ；https://tildes.net/~games/z02/why_you_didnt_get_lost_in_metroid_dread ；Super Metroid https://amara.org/v/C3BE7 ；Hollow Knight https://amara.org/subtitles/1YBjcP2T6VPf/en/1/download/The%20World%20Design%20of%20Hollow%20Knight%20%20Boss%20Keys.en.srt
- https://www.gamedeveloper.com/design/the-invisible-hand-of-super-metroid
- https://deepnight.net/tutorial/the-level-design-of-dead-cells-a-hybrid-approach/ 、https://www.thegamer.com/dead-cells-how-long-beat/
- https://gdcvault.com/play/1026975/Breathing-Life-into-Greek-Myth 、https://GamaSutra.com/design/roguelikes-and-narrative-design-with-i-hades-i-creative-director-greg-kasavin
- https://en.wikipedia.org/wiki/Katana_Zero 、https://www.gamerevolution.com/features/520685-katana-zero-interview 、https://www.dekudeals.com/items/katana-zero
- https://en.wikipedia.org/wiki/Half-Life_(video_game) 、https://wwrdeepdives.substack.com/p/half-life-how-to-tell-a-story-without
- https://en.wikipedia.org/wiki/Bastion_(video_game) 、https://www.supergiantgames.com/blog/in-depth-writing-bastion/ 、https://gamebanshee.com/86p4
- https://media.gdcvault.com/gdc2017/GameNarrativeReview/Calvin_Walantus_UCSC_GDC_Narrative.pdf 、https://amrsalehduat.substack.com/p/how-fromsoftware-tells-stories-without
- https://proseandquans.substack.com/p/hollow-knight-and-breadcrumbing-backstory 、https://mechanicsofmagic.com/?p=61009 、https://www.svg.com/398724/how-long-does-it-take-to-beat-hollow-knight 、https://twinfinite.net/guides/how-long-hollow-knight-answered/ 、https://hollowknight.wiki/w/Bosses_(Hollow_Knight)
- https://en.wikipedia.org/wiki/Celeste_(video_game) 、https://orbispatches.com/gaming-faq/how-many-hours-does-it-take-to-beat-celeste
- https://nintendowire.com/news/2022/01/24/metroid-dread-producer-discusses-the-games-difficulty-and-why-the-e-m-m-i-encounters-were-so-unforgiving/
- https://godisageek.com/?p=159726 、https://steamcommunity.com/app/261570/discussions/0/492378265890019133
- https://metroidvaniareview.com/blasphemous/ 、https://www.gamereactor.eu/the-game-kitchen-on-blasphemous-ambiguous-story/
- https://www.gamedeveloper.com/business/road-to-the-igf-studio-mdhr-s-i-cuphead-i-
- https://www.strayspark.studio/blog/attack-token-system-ue5-group-combat-that-feels-fair
- https://intfiction.org/t/how-long-is-too-long-for-a-cutscene/57215/13 、https://rpgmaker.net/forums/topics/8601 、https://morphic.com/ai-glossary/cutscene

## 9. 未解決與建議後續

- 【沒找到】：業界戰鬥／探索／敍事比例；兩次過場最短間隔；Celeste 每章房間數；Cuphead 精確關卡數；各作品逐區遭遇數；barks 規範；對話氣泡字數規範；遊測量測的業界門檻；Jim Brown 的文章。
- 若能繼續查：①GDC Vault 或 YouTube 上 Dead Cells／Hades／Katana Zero 的演講逐字稿 ②Game Accessibility Guidelines 字幕建議 ③Naughty Dog／id 的 AI 令牌演講，以替換第 2、4、5 節的【建議】數字。
- 本文所有【建議】數字應被視為「第一輪遊測用的起始值」，不是業界標準。
