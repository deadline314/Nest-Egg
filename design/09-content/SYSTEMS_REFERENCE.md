# 成長與貨幣、死亡與復活、小瑕疵檢查：業界做法與可檢查規則

> 來源：2026-10-06 使用者要求第一章補上升級與貨幣系統、修正「第一次死亡後沒有解釋為什麼回到電話亭、診間過場沒播」這類小瑕疵，並做成 skill 檢查。這份整理成參考資料；做事的流程與檢查清單在 skill `continuity-qa`（`.claude/skills/continuity-qa/`）。
> 注意：整理時網路代理擋掉了網頁全文且搜尋額度中途用完，數字來自搜尋摘要，條目已標【出處】【推導】【建議】【沒找到】。引用前請點出處核對；標【建議】的是我們的起始值。


> 研究日期：2026-10-06。方法：WebSearch 摘要為主（WebFetch 被代理擋下，bugnet.io、gamedeveloper.com、giantbomb 等內文都讀不到）。WebSearch 額度在研究中途用完，所以有幾項「沒找到」。
> 標記說明：【出處】= 搜尋結果摘要有出現、附該結果列出的網址；【推導】= 從出處或常識推論，非原文；【建議】= 針對 Nest Egg 的做法；【沒找到】= 搜不到或額度用完沒查，不可當事實引用。
> 注意：搜尋工具的摘要是二手整理，且常把多個結果混在一起，所以每條出處只代表「該網址出現在該次搜尋結果中」，不保證逐字對應。要引用數字進設計文件前，請再開原頁核對。

---

## 0. 先講結論（給趕時間的人）

1. 貨幣：先決定「這個遊戲有幾種錢、各自死了會怎樣」，再談數字。業界常見是 2～3 層：一般錢（死亡會掉）、永久成長貨幣（死亡不掉）、劇情／收集鑰匙（不能買）。
2. 死亡：好的做法是「死亡的解釋住在世界裡」（Vita-Chamber、篝火、冥河、電話亭），第一次用長演出建立規則，之後用短演出維持節奏。
3. 「診間 → 電話亭」的銜接：把診間定位成「初次建檔／註冊復原點」。診間醒來的同時，系統交代「從此以後會在最近的電話亭醒來」。之後每次死亡只做 1.5～3 秒的短演出。細節見 B 章與第 4 章。
4. 小瑕疵多半是「狀態沒對齊」：旗標在錯的時機寫入、特殊流程被一般流程搶先處理。用狀態矩陣加自動檢查最有效。

---

## A. 成長與貨幣系統

### A1. 各遊戲的做法（事實整理）

**Hollow Knight（Geo、護符、骨釘、長椅）**
- Geo 用途：向商人買東西、付 Stag Station 與長椅的過路費、付釘匠升級骨釘。來源：打敵人、砸 Geo 礦、開箱、把遺物賣給 Lemm、救幼蟲給 Grubfather、競技場試煉。【出處】https://hollowknight.wiki/w/Geo
- 總量級距（搜尋摘要中的數字，未逐項核對）：全買約 69,210 Geo；Sly 全買 9,260；Salubra 全買 5,410；骨釘全升級 7,050；Iselda 全部地圖 1,515；Fragile 護符三件 1,286。【出處】https://hollowknight.wiki/w/Geo、https://primagames.com/tips/hollow-knight-geo-farm-guide
- 死亡懲罰（影子 Shade）：死亡時掉光 Geo，原地出現影子，影子帶著那些 Geo；打贏才拿回；靈魂（Soul）容量在取回前被限制在 66；靠近影子會有走音的music box 聲提示；再死一次，舊影子與其中的 Geo 永久消失。【出處】https://hollowknight.wiki/w/Shade
- 農錢手段存在（Crossroads 的 Husk Guard 加長椅循環，摘要稱約每十分鐘 1,000 Geo），代表經濟有「可刷」的出口，避免卡關。【出處】https://primagames.com/tips/hollow-knight-geo-farm-guide
- 設計重點【推導】：貨幣用途分散（地圖、護符、骨釘、交通），每一類都有「買了立刻有感」的東西；長椅同時是存檔點、復活點、付費點，一個物件綁三個功能。

**Dead Cells（細胞、金幣、捲軸）**
- 細胞 Cells：敵人掉落，在關卡之間的安全空間向 The Collector 買永久升級；永久、跨局。【出處】https://deadcells.fandom.com/wiki/Runes_and_upgrades、https://en.wikipedia.org/wiki/Dead_Cells
- 藍圖 Blueprints：要在關卡中找到並「帶出關卡」才算數，才會出現在可解鎖清單。【出處】同上
- 力量捲軸 Power Scrolls：局內升級，分紅（近戰）、紫（遠程與陷阱）、綠（生存），附帶生命上升。【出處】https://en.wikipedia.org/wiki/Dead_Cells（搜尋摘要綜合）
- 金幣：局內貨幣，死亡時會留在 Dead Man's Bag 之類的機制；Gold Reserves 永久升級可以保留 500／1000／1500／2000 金幣不掉。【出處】https://deadcells.fandom.com/wiki/Runes_and_upgrades（摘要出現，來源頁未逐項核對）
- 設計重點【推導】：「局內錢」與「永久錢」分開；永久錢要「在被殺前花掉或存進銀行」才安全，形成每個區域的小決策。
- Destructoid 有一篇標題為「Dead Cells doesn't actually make you spend your cells after every level」的文章，但摘要沒給內容，細節【沒找到】。https://destructoid.com/?p=235925

**Hades（黑暗、鑰匙、寶石、瓊漿、鏡子、恩賜）**
- 黑暗 Darkness：類似經驗值，在 Mirror of Night 買永久能力，死亡不掉；鑰匙 Chthonic Keys：解鎖武器與鏡子新層級；寶石 Gemstones：找 House Contractor 翻修房子；瓊漿 Nectar：送禮增加好感並解鎖信物。【出處】https://primagames.com/gaming/hades-items-guide-nectars-keys-ambrosia-titan-blood-and-more/2、https://twinfinite.net/guides/hades-permanent-upgrades-unlocks/
- 有些貨幣死亡後消失（局內），有些保留（永久）。【出處】https://primagames.com/gaming/hades-items-guide-nectars-keys-ambrosia-titan-blood-and-more/2
- Pact of Punishment（熱度）：沒達到熱度要求打 Boss，只會拿到黑暗水晶，不是稀有掉落；把「難度自選」直接綁到獎勵。【出處】https://www.rpgsite.net/feature/10287-hades-pact-of-punishment-heat-modifiers-and-how-to-maximize-your-rewards
- 設計重點【推導】：每種貨幣對應一個「家裡的物件」（鏡子、承包商、禮物），花錢的地方就是敘事地點，不是冷冰冰的選單。

**Dark Souls（魂、血跡）**
- 死亡掉全部魂與人性，原地出現血跡；回去碰到就取回；若在取回前再死，舊血跡永久消失，只留新的一個。同時間最多一個血跡。【出處】https://darksouls.fandom.com/wiki/Bloodstain
- 還有「空洞化」：每次死亡永久減少部分最大生命，連續死亡最多到 50%。【出處】https://expertbeacon.com/how-does-dark-souls-punish-you-for-dying/（二手整理，與一般認知略有差異，引用前請再核對）

**Blasphemous（淚水 Tears of Atonement、罪 Guilt）**
- 死亡留下 Guilt Fragment；沒取回就累積 Guilt；Guilt 降低最大 Fervour（最多七次、降到 50%）與擊殺得到的淚水。【出處】https://blasphemous.wiki.gg/wiki/Guilt
- 懺悔像（Confessor Statue）可用淚水洗罪，公式 g×(l+1)×100（g = 罪等級，l = Mea Culpa 等級）；打贏任何 Boss 也會清除所有罪碎片。【出處】https://blasphemous.wiki.gg/wiki/Confessor_Statue、https://blasphemous.wiki.gg/wiki/Guilt
- 設計重點【推導】：懲罰同時有「回去取回」與「花錢消除」兩條路，給不同玩家不同選擇，且錢本身就是消耗出口。

**Metroid（升級拾取物）**
- 飛彈等同「鑰匙」，能打開特定障礙；能量箱每個 +100 能量並回滿；擴充包增加彈藥或能量。【出處】https://metroid.fandom.com/wiki/Expansion、https://www.gamedeveloper.com/design/making-sense-of-metroidvania-game-design
- 銀河戰士惡魔城的核心：新能力（二段跳、爬牆）讓玩家回頭重新解讀舊地圖；Super Metroid 從開頭到結尾操作感有明顯差異。【出處】https://allthings.how/metroidvania-explained-design-pillars-history-scope/（摘要綜合）
- 設計重點【推導】：升級不全靠錢，能力解鎖與擴充包由「探索」發放，錢負責「微調」。

**Ori（技能樹）**
- 《Blind Forest》：精神之光經驗累積換能力點，三條樹（青：防禦與功能；橘：攻擊；紫：探索）；技能需依序學。【出處】https://kb.speeddemosarchive.com/Ori/Skills_and_Abilities
- 《Will of the Wisps》：Wellspring Glades 有商人 Twillen 買／升級碎片（shard），Grom 用 Gorlek Ore 做建設以開新區。【出處】https://www.thegamer.com/ori-will-wispsgorlek-ore-guide/
- 設計重點【推導】：商人與建設者就是「據點」的居民，花錢直接改變據點樣貌。

**Katana Zero**
- 沒有商店式經濟。死亡被框成「龍在腦中預演，失敗只是想像」，並用藥物 Chronos 解釋時間倒流。【出處】https://shacknews.com/article/111305/katana-zero-review-the-cutting-edge
- 貨幣與升級【沒找到】，不列入。

**Cyberpunk 2077 與 Deus Ex（義體）**
- Cyberpunk：義體在 Ripperdoc 用 eddies、街頭名聲或屬性等級買；2.0 起所有 Ripperdoc 賣同樣全目錄；摘要列出 Mantis Blades 15,000、Reinforced Tendons 45,000、Second Heart 42,000、Tabula E-Rasa 100,000 eddies。【出處】https://primagames.com/gaming/cyberpunk-2077-cyberware-implants-ripperdoc-guide、https://upcomer.com/the-best-ripperdoc-upgrades-in-cyberpunk-2077
- Deus Ex: Human Revolution：Praxis 點靠找到或購買 Praxis Kit，或累積 5000 XP；新增義體 2 點，升級 1 點；21 種義體、共 69 級，通關很難全拿，所以逼玩家取捨；LIMB clinic 可用錢買 Praxis。【出處】https://pcgamer.com/deus-ex-human-revolution-augmentation-guide
- 設計重點【推導】：「義體店」本身就是世界觀的一部分，花錢＝改造身體，符合賽博龐克；稀缺的升級點逼出取捨與身份認同。

### A2. 貨幣來源與消耗的平衡（通則）

- 來源（faucet）進錢，消耗（sink）出錢；來源長期大於消耗會通膨，反之通縮，玩家沮喪。【出處】https://metavert.io/game-economy-design、https://medium.com/@msahinn21/designing-game-economies-inflation-resource-management-and-balance-fa1e6c894670
- 硬消耗（錢永久消失）是控制通膨的工具；「憧憬型消耗」（玩家自願存錢買大件）最有效，因為不會覺得被懲罰。【出處】同上（摘要，原作者未必單一來源）
- 單機動作遊戲沒有玩家交易，所以只需管「單一玩家的總收入曲線 vs. 總價目表」。【推導】
- 實務檢查法【建議】：每章列兩個數字——「該章可得總金額（含隱藏）」與「該章價目表總和」。目標比例例如：必要升級價格總和 ≈ 主線自然收入的 60～80%，其餘靠探索補足。比例是起手值，必須試玩調整，非業界標準【沒找到】標準值。
- Hollow Knight 的總價目 69,210 對照玩家一般收入，代表「不可能一次全買」是刻意設計（取捨）。【推導】

### A3. 第一章該有哪些（建議，非業界規範）

【沒找到】可靠的「第一次給錢／第一次花錢在第幾分鐘」業界數據，搜尋額度用完前沒搜到；Hollow Knight 早期流程（Crossroads、Sly、Iselda）有提到，但沒有時間數字。以下為【推導／建議】。

| 項目 | 建議 | 理由 |
|---|---|---|
| 第一次拿到錢 | 打第一個敵人或破第一個可破壞物，掉 1～3 枚零錢 | 越早讓玩家學會「打東西會掉東西」越好【推導】 |
| 第一次看到商店 | 在拿到足夠買最便宜品的錢「之前」就先看到店，並看到價格 | 目標先於能力（Hollow Knight 的 Geo 與 Sly 的順序也是先見後買）【推導】 |
| 第一次花錢 | 第一章前半，花一小筆（例如補血道具或一次小改裝），不要一次要玩家存很久 | 讓花錢的循環跑過一遍【建議】 |
| 能力解鎖 | 用劇情／探索發，不用錢買（例如衝刺、鉤爪） | 學 Metroid 的鑰匙式能力【推導】 |
| 武器改裝 | 第一章給一個改裝槽與兩三個選項，價格差明顯 | 「有感」與取捨【建議】 |
| 隱藏收入 | 一兩處不在主路上的小額寶箱 | 鼓勵探索【推導】 |
| 死亡成本 | 第一章只扣少量（見 B 章），不要掉光 | 新手章節別太狠【建議】 |

### A4. 商店融入世界觀：老 K 的當舖

- 先例：Hollow Knight 的商人是角色（Sly、Iselda、Salubra），Ori 的 Twillen、Cyberpunk 的 Ripperdoc、Deus Ex 的 LIMB clinic、Hades 的鏡子與承包商，花錢地點都是「有名字的場所／人」。【出處】見 A1 各條
- 當舖的天然優勢【推導／建議】：
  - 買：賣二手武器、改裝件、補給。「來路不明」可解釋為何便宜與庫存有限。
  - 典當：把物品或記憶換錢。與世界觀的「錨人的記憶被磨損」呼應：典當的物品可以是「紀念品」，之後可贖回（贖回要加利息＝硬消耗）。
  - 贖回機制本身就是消耗出口與劇情鉤子（被典當的東西後來出現在別處）。
  - 老 K 的對話隨章節與玩家死亡次數變化，仿 Hades「死了 NPC 會記得」。【出處】https://mechanicsofmagic.com/2026/05/11/critical-play-hades-2/（Hades 房子角色隨死亡演進對話）
- 若有「復原代價扣信用點」：當舖也應該是「信用點不夠時的救急」，形成「死 → 缺錢 → 典當 → 贖不回」的世界內循環。【建議】

### A5. 死亡懲罰與貨幣

| 作法 | 代表 | 優點 | 風險 |
|---|---|---|---|
| 掉全部，原地取回，再死就消失 | Dark Souls、Hollow Knight | 張力高、有目標 | 新手挫折，需有難度出口 |
| 保留一部分（可升級） | Dead Cells Gold Reserves | 給成長感 | 數值要調 |
| 不掉錢但累積負面狀態 | Blasphemous Guilt、Dark Souls 空洞化 | 有持續壓力 | 玩家看不懂就變成隱性懲罰 |
| 付費復原 | Nest Egg 設定（扣信用點） | 與世界觀一致 | 負債需要底線，避免死循環 |

- 以上各條皆【出處】見 A1。「付費復原」是專案設定。
- 【建議】Nest Egg：扣款設上限（例如不超過身上現金，或最多扣到零不負債），第一次死亡（劇情必死）不扣款或只扣象徵性金額。否則玩家會把「劇情死」誤認成自己的錯。【推導】
- 【建議】取回機制二選一，避免兩套並存：(a) 影子／血跡式取回；(b) 錢直接扣、不取回。若用 (a)，場景切換、第二次死亡覆蓋、存檔讀檔都要寫進狀態矩陣（見 C 章）。

### A6. 升級「有感」設計

- 【沒找到】業界明確數字（例如「至少 +X% 才有感」）。以下為【推導／建議】。
- 立即可見：血條變長、攻擊特效變大、改裝件在武器上看得見、音效不同、角色外觀變化（Deus Ex／Cyberpunk 的義體是外觀＋能力雙重回饋）。【推導】
- 能力解鎖要立刻有一個「示範用的障礙」放在旁邊（Metroid 的飛彈／門）。【出處】https://metroid.fandom.com/wiki/Expansion（飛彈即鑰匙）
- 買了馬上能試：商店旁邊放一個標靶或第一個小敵人。【建議】
- 小升級（+5%）要合併成「一次買一包」或搭配數字提示，否則玩家感覺不到。【建議】
- 升級結果顯示「之前 → 之後」的數值，tooltip 一句話講重點（符合 CLAUDE.md 的引導要求）。【建議】

---

## B. 死亡與復活的敘事與流程

### B1. 各遊戲如何合理化死亡與復活點

| 遊戲 | 世界內解釋 | 備註 |
|---|---|---|
| BioShock | Vita-Chamber：只對特定基因碼有效，玩家（Jack）剛好符合；保留血量與彈藥與敵人傷害，形成消耗戰 | 【出處】https://giantbomb.com/wiki/Objects/Vita_Chamber；BioShock 2 可關掉 Vita-Chamber：https://www.engadget.com/2009-05-25-bioshock-2-lets-you-shut-off-the-vita-chambers-die.html |
| Dark Souls | 不死詛咒；篝火是復活點；Undead Asylum 教學：Oscar 給你鑰匙與灰瓶後死去 | 【出處】https://en.wikipedia.org/wiki/Northern_Undead_Asylum；https://darksouls.fandom.com/wiki/Bloodstain |
| Hades | 冥河：Zagreus 死了就從 Styx 回到 House of Hades，因為他是冥界的王子；房子成為敘事樞紐，角色記得你死在哪 | 【出處】https://mechanicsofmagic.com/2026/05/11/critical-play-hades-2/、https://criticalvideogamestudies.com/hades-death-and-the-players-experience/ |
| Hades（設計思路） | 讓死亡「像結構的自然部分，沒有 Game Over 感」，把玩家體驗與敘事對齊 | 【出處】https://www.screenhub.com.au/news-article/features/digital/jini-maxwell/hades-greg-kasavin-breaks-down-supergiants-unique-approach-to-narrative-262459、https://GamaSutra.com/design/roguelikes-and-narrative-design-with-i-hades-i-creative-director-greg-kasavin |
| Returnal | 時間迴圈；死亡前閃過 Selene 的過去影像，每次死亡的閃回不同 | 【出處】https://en.wikipedia.org/wiki/Returnal、https://www.thesixthaxis.com/2021/02/25/returnal-ps5-gameplay-preview-roguelike-housemarque/ |
| Death Stranding | Sam 是 repatriate，死後會回來；死亡時玩家會造訪死者之地；BB 是橋樑 | 【出處】https://www.powerpyx.com/death-stranding-story-ending-explained/（摘要綜合） |
| Katana Zero | 失敗只發生在「龍的腦中預演」，倒帶＝重新計畫 | 【出處】https://shacknews.com/article/111305/katana-zero-review-the-cutting-edge |
| Dead Cells | 囚犯的身體被細胞／寄生物重新佔用 | 【沒找到】可靠內文，只知道主角稱 The Prisoner：https://en.wikipedia.org/wiki/Dead_Cells |
| Control | Control Point 是補血、換裝、快速移動的據點，進入不重置關卡 | 【出處】https://en.wikipedia.org/wiki/Control_(video_game)；死亡的世界內解釋【沒找到】 |
| Prey、Dishonored | 【沒找到】 | 額度用完未搜到，請勿引用 |

- 學術整理：有論文把這類做法稱為「死亡敘事的敘事學嵌入」，BioShock 被當成讓死亡在虛構邏輯內可信的例子。【出處】https://journals.suub.uni-bremen.de/index.php/gamevironments/article/view/140
- 設計分類：機械式死亡（可量化）與反思式死亡（敘事框架）；死亡可從「失敗信號」轉成「創作工具」。【出處】https://www.gamedeveloper.com/design/narrative-death-vs-game-mechanic-death、https://www.gamedeveloper.com/design/against-the-death-penalty

### B2. 共通模式（【推導】）

1. 先有「世界為什麼允許你復活」，再有「為什麼回到這裡」兩層，缺一層玩家都會問。Nest Egg 目前缺第二層。
2. 復活點是一個「有人或有物」的地方（篝火、房子、艙、據點），不是空地。
3. 復活點同時承載功能（存檔、商店、升級），所以玩家喜歡回去，死亡不是純損失。Hades、Hollow Knight 長椅、Control Point。
4. 死亡回來的場所，NPC 對話會變（Hades）。這是「記得你死過」的低成本演出。

### B3. 第一次死亡的處理

- 業界做法：在教學階段安排「第一次死亡」，用世界內的解釋講規則：Dark Souls 的 Asylum 讓玩家初見就學到死與復活是正常的。【出處】https://en.wikipedia.org/wiki/Northern_Undead_Asylum（教學區，Asylum Demon 設計成逃跑）、https://mysticryst.com/blogs/the-mystic-journal/dark-souls-hero-journey-death-teacher
- 首次與後續區分：Prince of Persia 式「第一次要看、之後可跳過」的過場處理，被視為優雅解法。【出處】https://www.gamedeveloper.com/pc/opinion-the-problem-of-the-cutscene（摘要）
- 通則：過場永遠要能跳過，尤其是重試時；已看過的過場要記錄。【出處】https://bugnet.io/blog/how-to-implement-a-cutscene-system（摘要）

### B4. 只第一次用過場，之後用短演出

- 【沒找到】業界公認的「第二次起演出時長」數字。
- 【建議】三層結構：
  - 第一次特殊死亡（劇情）：完整過場，可跳過，但第一次建議不給跳過鍵或要長按確認（長度視過場）。
  - 一般死亡 early（前 N 次）：短演出約 2～3 秒（暗轉、聲音、一句旁白），N = 3 次左右後縮到 ~1 秒。N 為起手值，需試玩。
  - 一般死亡 late：直接淡出淡入，只留一個小圖示與扣款提示。
- 變化而非重複：每次短演出有幾句不同的句子輪播（Returnal 用不同閃回、Hades 用不同對話）。【出處】Returnal 見 B1；Hades 見 B1。

### B5. 死亡畫面與等待時間上限

- 摘要：低於 3 秒幾乎等同「即時」，3～10 秒玩家不太有感；死亡與重生動畫約 0.5 秒有助平順。【出處】https://gamedev.net/forums/topic/648174-multiplayer-respawn-times/5096291/ 、https://www.gamedeveloper.com/production/the-impact-of-dead-time-in-video-games（兩者都出現在同次搜尋，數字屬於哪個來源未確認，且 gamedev.net 為論壇意見，非研究）
- Super Meat Boy：重生時間極短，「零時間損失」；Celeste 預期玩家會死上百次，所以快速重生。【出處】https://gamesbeat.com/a-minor-inconvenience-made-major/（摘要）
- 失敗應該是「快速重試」，長死亡動畫、慢轉場、長載入讓每次失敗都更煩。【出處】https://bugnet.io/blog/how-to-build-a-respawn-and-death-flow（摘要）
- 【建議】Nest Egg（有敘事性死亡，非極速跳台）：一般死亡從 HP 歸零到可操作 ≤ 3 秒（目標 2 秒內），超過 5 秒要有跳過鍵。首次劇情死亡不受此限。數字為【建議】，非業界標準。

### B6. 復活流程的狀態保存

- 通則：結帳（checkpoint）要在玩家安全穩定時才記，不要在跌落或危險中存；存之前驗證「重生在這裡能活、不被卡死」；重生後給玩家安全位置與短暫無敵。【出處】https://uhiyama-lab.com/en/notes/ue/checkpoint-respawn-system/（摘要）、https://bugnet.io/blog/how-to-fix-checkpoints-saving-in-a-bad-state（標題顯示此問題存在，內文未讀）
- 檢查點可以存：重生位置、物品欄、任務進度、自訂旗標；設計選擇如「重置 HP 但保留金幣」。【出處】https://uhiyama-lab.com/en/notes/ue/checkpoint-respawn-system/
- BioShock 的 Vita-Chamber 保留傷害與彈藥，造成消耗戰；Dark Souls 敵人重生；Hollow Knight 小敵人離開房間就重生，強敵坐長椅才重生。【出處】見 B1；https://mechanicsofmagic.com/2021/04/08/hollow-knight-mechanics-and-dynamics/
- 【建議】Nest Egg 狀態分三類，寫在設計文件並對應程式資料結構：
  - 死亡後保留（劇情旗標、已開寶箱、已開捷徑、已解鎖能力、死亡次數、最近復原點）。
  - 死亡後重置（HP、彈藥是否補滿由設計決定、局部敵人）。
  - 死亡時結算（扣信用點、記憶磨損）。結算要在畫面轉黑「之前」寫入存檔，避免死亡時關遊戲逃避懲罰（讀檔邊界）。【推導】

### B7. 怎麼解釋「為什麼會在這裡醒來」而不打斷節奏

可用手法（皆為【推導】，來自 B1 各遊戲的歸納）：
1. 旁白或內心獨白，一句話（Katana Zero 的「這招行不通」；Returnal 的閃回）。
2. 環境：醒來時身邊有可見的機器、燈光、聲音（Vita-Chamber 的艙、電話亭的復原光柱）。
3. NPC 一句對話（Hades 的房子角色）。
4. 短演出（暗轉 + 音效 + 字幕）。
5. 玩家可選的「更多資訊」：日誌、電話亭的小螢幕、老 K 的閒聊，不擋主流程。

### B8. 專案情境：「診間醒來 → 之後再死都回電話亭」怎麼接

**問題現況**：第一次劇情死亡（水坑）直接去電話亭，沒有解釋、診間過場沒播；之後一般死亡也回電話亭。

**設計原則**【推導】：「例外」要有理由，「規則」要先被教過。第一次死亡是「教規則」的時刻，所以應該是特殊場景，而且規則的最後一句要「把玩家接上一般流程」。

**建議方案（B 案，優先）**：診間＝「初次建檔」
1. 劇情：凜第一次死亡時，她還沒登記任何復原點（電話亭還沒有她的記錄），所以不是傳送，而是收屍人把遺體運到復原館（診間）進行「初次復原」。這一次需要人力與車輛，所以有車、有人、有診間。
2. 診間過場中講清楚三件事（一句一件）：
   - 為什麼你死了也能活：天穹的技術。
   - 為什麼這次在這裡：你是第一次，需要建檔。
   - 之後怎麼辦：已綁定最近的電話亭，下次不用來診間；每次復原會扣信用點，記憶會被磨損。
3. 過場結束的最後一個畫面：凜走出診間，經過電話亭，電話亭亮起「已登記」提示。玩家立刻把「電話亭＝復原點」記進腦子。
4. 診間醒來的鏡頭與位置要定義在資料裡（`spawn_after_clinic`），並確保結束後玩家站在可操作位置，旗標 `clinic_intro_done` 在「過場播完」才寫入，不在「過場開始」寫入（避免中途離開或跳過造成狀態錯誤）。【推導】

**其他方案（備選）**：
- A 案：所有死亡都經診間，之後用「跳過加速」。缺點：每次多一次場景切換，破壞節奏。不建議。
- C 案：診間只是第一次，而電話亭的復原直接在世界裡解釋成「電話亭是復原點，天穹從遠端重建你」。這是最省成本，但要把「為什麼第一次不同」改成「第一次要建檔」，才不會留下漏洞。

**第一次與一般復原的銜接檢查表**【建議】：
- 一般死亡需要知道「目前綁定的復原點」。在診間醒來之前，這個欄位是空的；規則：欄位空時（例如存檔損毀或旗標遺失），退回到最近可用的復原點或診間，並記錄錯誤與位置（符合 CLAUDE.md 容錯要求）。
- 第一次死亡之前若玩家已經經過電話亭：電話亭的「登記」是否已發生？要有一致規則。建議：水坑之前的電話亭只是「看得到、不能用」，診間之後才啟用，並在第一章就用 tooltip 或對話提示一次。
- 診間之後的第二次、第三次死亡：播短演出（見 B4），並且「不再提診間」。
- 讀檔：在診間過場中途存檔／讀檔，應從過場開頭重來，不應跳到電話亭。
- 第一次死亡以外的特殊死亡（例如之後的 Boss 劇情死）：同樣用資料表 `death_scene_id` 指定場景，預設為一般短演出。以資料為主、不改程式。

---

## C. 遊戲「小瑕疵」品質檢查

### C1. 常見的連續性／狀態類錯誤

- 敘事 RPG 的 bug 主要活在狀態裡：任務旗標沒推進、對話忘記選擇、分支導向死路、存檔損毀或讀錯。【出處】https://bugnet.io/blog/bug-tracking-for-narrative-rpgs
- 一個旗標沒寫入就可能卡死任務；結局觸發依賴只有可選任務才會寫的旗標。【出處】https://bugnet.io/blog/how-to-build-qa-checklist-for-game-release（摘要）
- 要測：在戰鬥中、對話中、過場中、自動存檔剛觸發時存檔；過場中退出；Boss 死亡後、旗標寫入前當機。【出處】https://qawerk.com/blog/game-functionality-testing/、https://bugnet.io/blog/qa-testing-for-game-completion-and-credits
- 完成旗標沒寫入，會影響成就、存檔旗標、後續內容與標題畫面，是「安靜卻致命」的 bug。【出處】https://bugnet.io/blog/qa-testing-for-game-completion-and-credits

### C2. 檢查清單（可直接貼進票）【建議，整合自上述出處與常識】

**敘事連貫**
- [ ] 每個「事件」都有前因：玩家在哪、為什麼在那、誰帶他來。
- [ ] 角色身上物品／裝備／外觀在過場前後一致。
- [ ] 對話提到的事實與已發生的事實一致（死亡次數、錢、地點、日期）。
- [ ] 同一件事不被兩個 NPC 以互相矛盾的方式講述。

**旗標與狀態**
- [ ] 每個旗標：誰寫入、誰讀取、初始值、重置時機都有記錄。
- [ ] 旗標寫入時機：「事件完成」而非「事件開始」。
- [ ] 沒有只寫不讀、只讀不寫的旗標。
- [ ] 新遊戲、舊存檔、缺旗標的存檔都能正常進行（缺值走安全預設值並記錄）。

**過場觸發條件**
- [ ] 過場有明確前置條件，且只在條件全滿足時觸發。
- [ ] 過場能被「一般流程」搶先處理嗎（例如死亡處理器在過場之前就把玩家傳走）？
- [ ] 同一過場不會重複觸發（除非設計要求）。
- [ ] 過場可跳過、跳過後狀態與播完相同。
- [ ] 已看過的過場，重玩與讀檔後行為符合設計（短版、跳過或不再播）。

**重玩與讀檔邊界**
- [ ] 過場中、戰鬥中、對話中存檔再讀。
- [ ] 死亡當下存檔再讀。
- [ ] 讀檔後鏡頭、角色位置、面向、物品、HP 一致。
- [ ] 舊版存檔升級後不崩潰。

**死亡與重試後狀態**
- [ ] 死亡後：錢、記憶、道具、敵人、已開機關各自符合 B6 的三類規則。
- [ ] 連續死亡（第 2、3、10 次）演出正確、不累積記憶體或殘留物件。
- [ ] 在復原點被打死、在過場邊界死亡、在場景切換瞬間死亡。

**場景切換後的鏡頭與角色位置**
- [ ] 切換後鏡頭邊界、跟隨目標、縮放、後製效果（HDR、雨）都重設。
- [ ] 角色不卡牆、不浮空、朝向正確（參考 scene-staging skill）。

**文字與音效缺漏**
- [ ] 沒有顯示 key 名稱或空白字串、沒有溢出框。
- [ ] 每個重要動作都有音效；過場的音樂在結束時有收尾。
- [ ] 缺資源時有記錄、有安全預設（CLAUDE.md 要求）。

**提示與教學一致**
- [ ] 提示的按鍵與實際按鍵一致。
- [ ] 提示不在玩家已會之後重複出現。
- [ ] 教學內容與後續實際規則一致（例如「電話亭復原」的說法前後一致）。

**可達性與卡死**
- [ ] 每個區域有出口；每個必要道具可取得；每扇門有鑰匙來源。
- [ ] 玩家在任一狀態下（死亡、讀檔、跳過）都不會進入無法前進的狀態。

**動線**
- [ ] 第一章玩家知道下一步去哪；回頭路有明示。

### C3. 業界 QA 流程

- Smoke test：部署後的基本功能檢查，確認沒有明顯問題、能開始正式測試；在遊戲中是快速淺層通過一個關卡。【出處】https://knowledge.pricefx.com/technical-delivery-roles/quality-assurance-knowledge-base-home/qa-glossary-of-terms/general-qa-terminology（通用定義）；https://bugnet.io/blog/smoke-tests-the-five-minute-check-before-every-build（標題：五分鐘檢查）
- Smoke test 的內容：能啟動、開始遊戲、存檔、讀檔、在乾淨機器上跑。【出處】https://bugnet.io/blog/smoke-tests-the-five-minute-check-before-every-build（摘要）
- Regression test：修完 bug 後確認沒有副作用；維護一份「每個已修重大 bug」清單，發佈前逐一驗證，崩潰與資料遺失一定要重測。【出處】https://pricefx.atlassian.net/wiki/x/RQDuKAE、https://bugnet.io/blog/qa-testing-checklist-for-indie-game-releases（摘要）
- Soak test：長時間遊玩（約 30 分鐘到數小時），找記憶體洩漏、效能漂移、狀態累積、內容耗盡。【出處】https://tessl.io/registry/skills/github/Donchitos/Claude-Code-Game-Studios/soak-test（摘要）。這個來源是 AI 技能登錄頁，非業界權威，僅供參考。
- 新手體驗（FTUE）是最關鍵的測試區，因為影響 100% 玩家。【出處】https://bugnet.io/blog/qa-testing-checklist-for-indie-game-releases（摘要）
- Polish pass：發佈前的最後一輪，在目標硬體上驗證所有功能、檢查視覺與音效小問題。【出處】https://www.wayline.io/blog/game-quality-assurance-checklist-achieving-game-polish-development、https://www.wayline.io/blog/game-polish-checklist-sound-visuals-quality
- 嚴重度與優先級：嚴重度＝技術影響（例如遊戲中斷），優先級＝修復緊迫度，兩者分開記。【出處】https://pricefx.atlassian.net/wiki/x/RQDuKAE（通用 QA 定義）
- 遊戲 bug 的具體分級（Blocker／Critical／Major／Minor／Trivial 之類）【沒找到】明確的業界統一表。以下為【建議】專案用分級：

| 等級 | 定義 | Nest Egg 例子 |
|---|---|---|
| S1 阻斷 | 崩潰、資料損毀、卡死無法前進 | 死亡後讀檔卡在黑畫面 |
| S2 嚴重 | 主線流程錯誤、關鍵過場未播、狀態錯誤 | 診間過場沒播（本案） |
| S3 一般 | 次要功能錯誤、文字錯誤、音效缺漏 | 提示按鍵錯 |
| S4 輕微 | 外觀細節、對齊、非必要重複 | 站位差幾像素 |

### C4. 狀態矩陣測試法

- 原理：旗標、狀態、位置交叉組合數量爆炸（N 個旗標 × M 個值 × K 個情境），無法全測，所以要「有策略地取樣」。【出處】https://oneuptime.com/blog/post/2026-01-30-flag-testing-strategies/markdown、https://tessl.io/registry/testland/feature-flag-test-matrix-reference（兩者為軟體功能旗標的測法，借用到遊戲旗標是【推導】）
- 取樣策略：每個旗標獨立測開與關；會互相影響的旗標用成對組合（pairwise）；一定要測預設狀態；風險導向挑組合。【出處】同上；https://meliorgames.com/game-development/streamlining-mobile-game-testing-with-pairwise-testing/（Pairwise 在遊戲測試的介紹）
- 遊戲測試書有專章講組合測試與測試流程圖。【出處】https://biblio.ebookpoint.pl/szczegoly/e_45oc_ebook/game-testing-mastering-the-art-of-quality-assurance-in-game-development-mercury-learning-and-information-robert-denton-br?jezyk=en

**範例矩陣：第一次死亡與復活**【建議】

欄位：`first_death_done`（否／是）、`clinic_intro_done`（否／播放中／是）、`booth_registered`（否／是）、`death_location`（水坑／一般區／Boss 區／復原點旁）、`save_state`（新局／過場中讀檔／死亡後讀檔）。

| # | first_death_done | clinic_intro_done | booth_registered | 死亡位置 | 讀檔情境 | 預期 |
|---|---|---|---|---|---|---|
| 1 | 否 | 否 | 否 | 水坑 | 無 | 觸發診間完整過場，結束後 booth_registered=是 |
| 2 | 否 | 否 | 否 | 一般區 | 無 | 依設計：視為第一次死亡，同 1（或先擋住不可能發生） |
| 3 | 是 | 是 | 是 | 一般區 | 無 | 短演出，醒在電話亭，扣款 |
| 4 | 是 | 播放中 | 否 | — | 過場中讀檔 | 回到過場開頭，不跳到電話亭 |
| 5 | 是 | 是 | 是 | 水坑（再次） | 無 | 當一般死亡，不再播診間 |
| 6 | 是 | 否 | 否 | — | 旗標遺失的舊檔 | 安全預設＋錯誤記錄，不崩潰 |
| 7 | 否 | 否 | 否 | 水坑 | 死亡當下存檔再讀 | 仍是第一次死亡流程 |

### C5. 可自動化的檢查（Godot 專案，【建議】，皆為專案內自寫腳本，業界做法來源【沒找到】）

搜尋額度用完，沒查到 Ink／Yarn／Articy 等工具的內建靜態分析，也沒查到 Godot 測試框架的資料；以下為依一般靜態檢查思路的【推導】。

1. **旗標引用檢查**：掃描所有資料（對話、過場、關卡、觸發器）中引用的旗標名稱，建立「誰寫、誰讀」表；報告只寫不讀、只讀不寫、拼字相近（編輯距離 1）的旗標。
2. **過場前置條件檢查**：每個過場資料必須宣告 `requires` 與 `sets`；檢查 `requires` 中的旗標至少有一處會 `sets`；檢查 `sets` 發生在「過場結束」事件。
3. **孤兒場景／資源**：從主入口走資料引用圖，找出沒被任何資料引用的場景、過場、對話、音效；列為警告。
4. **不可達內容**：模擬旗標圖（BFS），從新遊戲初始狀態出發，找出永遠不會被滿足的條件（例如需要兩個互斥旗標）。
5. **對話重複觸發**：檢查有 `once` 屬性的對話是否都會寫入已看旗標；沒有寫入的視為會重複。
6. **死亡流程表驅動測試**：從資料枚舉矩陣（C4）的組合，無頭模式下自動走一遍「死亡 → 復活」，檢查結果狀態斷言（位置在復原點、旗標、錢、無腳本錯誤）。
7. **資源遺失容錯**：故意移除一個過場或音效資源，確認遊戲記錄「具體路徑與位置」並退回安全預設，不崩潰（符合 CLAUDE.md）。
8. **文字缺漏**：掃描所有文字 key，缺翻譯或空字串報錯。

---

## 4. 給我們的建議

### 4.1 成長與貨幣

1. 定義三層貨幣：信用點（一般、死亡會扣）、永久成長（不掉，例如改裝零件／義體點）、劇情鑰匙（不可買）。每層都要有「花在哪個有名字的地點」。【建議】
2. 第一章只開：零錢掉落、老 K 當舖（買）、一個武器改裝槽、一個劇情給的能力。典當與贖回可在第二章或第一章後半解鎖。【建議】
3. 價格與收入以資料表驅動（`data/`），用腳本算每章「總收入／總價目」比例，放進測試或報表。【建議】
4. 當舖設計成世界觀的一環：典當記憶物件、贖回加利息、老 K 對話隨死亡次數變化。【建議，靈感來自 Hades 房子與 Cyberpunk Ripperdoc】
5. 死亡扣款設上限，劇情必死不扣款。取回機制二選一。【建議】
6. 每個升級買下後立刻在 HUD 或角色上看得見，tooltip 一句話講重點。【建議】

### 4.2 死亡與復活流程

1. 加一個「死亡場景表」資料：`death_scene_id`、播放條件、是否可跳過、結束後復原點、要寫入的旗標。第一次診間、之後電話亭、日後的特殊死亡都用資料指定。【建議】
2. 診間定位為「初次建檔」，結尾綁定電話亭，並在畫面上給電話亭亮起的視覺回饋。【建議】
3. 旗標在「過場完成」時寫入。過場被中斷時不寫入，重新進入時從頭播。【建議】
4. 一般死亡 2～3 秒短演出，前幾次有不同句子，之後縮短；任何情況不超過 5 秒不可跳過。【建議】
5. 死亡結算（扣款、記憶磨損）在轉黑前寫存檔。【建議】
6. 缺復原點資料時退回診間或最近電話亭，記錄具體位置的錯誤。【建議】

### 4.3 小瑕疵檢查清單與自動檢查規則

1. 每張涉及流程的票附上 C2 清單中相關項目，驗收條件勾選。【建議】
2. 新增自動檢查 C5 的 1、2、3、5（成本低、效益高）；其次 6（死亡矩陣）。【建議】
3. 把本次「診間過場沒播」寫成回歸測試：模擬水坑死亡，斷言診間過場被觸發且旗標在結束後才寫入。【建議】
4. 每次出新章節前跑一次狀態矩陣；任何新旗標都要加進矩陣欄位。【建議】
5. Bug 分級用 C3 的 S1～S4，S1／S2 必須在合併前修掉。【建議】
6. 加一支長時間 soak 腳本（反覆死亡 50 次、換場景），觀察記憶體與殘留物件。【建議，soak 定義見 C3】

---

## 5. 常見錯誤對照表

| 常見錯誤 | 為什麼是問題 | 比較好的做法 |
|---|---|---|
| 死亡後直接傳到復原點，沒有任何解釋 | 玩家疑惑「為什麼在這」，世界觀斷線（Nest Egg 現況） | 第一次完整解釋，之後短演出（B4、B8） |
| 第一次特殊死亡與一般死亡共用同一段程式，特殊場景被搶先 | 該播的過場沒播 | 死亡場景表與優先級；特殊場景先判斷（C2 過場觸發） |
| 旗標在過場「開始」就寫入 | 中途離開、跳過或當機後，旗標已寫但過場沒看完 | 在「完成」時寫入（B8） |
| 每次死亡都播長演出 | 玩家煩躁，節奏被破壞 | 3 秒內為宜，逐步縮短（B5） |
| 每次死亡演出完全相同 | 重複感強 | 句子輪播（Returnal、Hades 的做法） |
| 死亡懲罰太重又無出口 | 新手挫折、死循環 | 設上限、提供取回或消除（A5） |
| 取回機制與扣款機制並存且規則不清 | 玩家看不懂、程式狀態複雜 | 二選一，寫進狀態矩陣（A5） |
| 收入曲線與價目表沒對過 | 通膨或卡錢 | 每章算比例（A2） |
| 升級後看不出差異 | 沒有成就感 | 立即可見的視覺／音效與數值前後對照（A6） |
| 商店只是選單，與世界觀無關 | 失去沉浸 | 當舖角色化、對話隨進度變化（A4） |
| 只在新遊戲測試 | 舊檔、讀檔邊界出錯 | 矩陣含舊檔與過場中讀檔（C4） |
| 缺資源就崩潰 | 違反容錯要求 | 記錄具體路徑並退回預設（C5-7） |
| 提示與實際規則不符 | 玩家被誤導 | 提示文字從資料產生或交叉檢查（C2） |
| 檢查點存在危險位置 | 重生即死或卡死 | 在安全狀態才記錄，並驗證可存活（B6） |

---

## 6. 沒找到、需要日後補查的項目

- 第一章「第一次給錢／第一次花錢」的業界時間數據。
- 升級「有感」的量化門檻。
- Dead Cells 囚犯的世界內復活解釋；Control、Prey、Dishonored 的死亡處理。
- 遊戲 QA 業界統一的 bug 嚴重度分級表。
- 對話與旗標靜態分析工具的內建功能（Ink、Yarn Spinner、Articy）與 Godot 測試框架實務。
- 死亡畫面時長的權威研究（目前只有論壇與部落格意見）。
