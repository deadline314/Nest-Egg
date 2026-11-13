# 第一章：港區立體回環（NE298）

2026-11-13，CPU已實作候選。依本次使用者委託作一般設計決策；不是本人逐項親審，也不是已通關/已驗畫面。基底9470bc43。幾何與保存接口供NE297對接，真輸入/畫面仍待驗。

## 房間與進度

四張主要地圖改高56格，寬保持原值；所有原物件預設向下32格，例外逐筆給映射。其餘安全區保24格與原位置；天亮當舖仍共享當舖版面並自動結章。沒有新增主線條件/物品權限，所有旗標與保存沿原owner。

| 區域 | 真正主線高度（腳所在格） | 回環/支線與實體限制 |
|---|---|---|
| street，208×56 | 入口/電話亭51 → 47/43/39/35階梯 → 市集31 → 36/42下降段 → 排水51 → 47/44/40階梯 → 路障高路36 → 倉庫門51 | 市集下方x64–119以實心地基填滿，路障高路x152–182同理；不能沿舊底層平廊一路走過。維修道15、獎勵平台23形成第三層。 |
| warehouse，166×56 | 街口48 → 看門狗/電話亭/開關與水坑保持原相對結構 → 水位閘門後貨道48→44→40→36→32→28→24→20→16 | 垂直貨道只在flood_c閘門後的x135–164；清掉此段舊頂板，左右交替踏板，出口wh_vault移到162,16。先前的看門狗/水位段不能經新高路繞過。 |
| vault，124×56 | 入口48 → 44/40/36/32階梯 → 資料盤/督察平台28 → 24/20/16階梯 → 上層走道12 | 資料盤40,28；盤與出口都在上層，完成主線必須爬升。單向踏板下保留安全返回地面，不能從底層直接取得盤或使用出口。上層走道既通原交接出口120,12，也通新維修回環116,12。 |
| rooftop，72×56 | 當舖入口/鷺49；保安全談話功能 | 蛇形階梯49→44→39→34→31到維修門66,31，接street高路；不強加戰鬥。兩端都驗取得資料盤。 |

這些是設計落點，不是從速度簡式宣稱的極限。普通必走階梯以約4格升高為起點；空間/頭部淨空與真Player輸入需分別驗證。street兩塊實心地基會迫使第一次去倉庫的主路上下變化，不是原走廊下移後只在上方加可選平台。

新增兩對真正互返門，兩端**全部requires_flag=ledger_disk_obtained**：

- vault `vault_street` (116,12) ↔ street `street_vault` (122,15)。先通過看門狗/水位、拿資料盤，才可走此環返回街道；沒有先進vault的反向入口。
- street `street_roof` (46,15) ↔ rooftop `roof_maintenance` (66,31)。原當舖↔屋頂與當舖↔街道都保留，形成後期第二個環。

原credits_large (139,9)移到street (100,23)平台，從市集31能看見，落差8格。無再躍先不可達；獲盤解鎖再躍後回訪。上層維修道15也經此高度層或新回環抵達。8格只是候選，必須以NE296真Player在相同幾何/起點的未取得負控及取得正控證實，不能只給RouteState較大的jump_tiles就算完成。能力/HUD沿NE296，章內安全練習由NE298提供；主線拿盤前全用普通跳躍與原衝刺。

盤後的章內練習由本圖提供：vault x27–50的隔層內腳20→12為8格高台，失手落回實心floor21，可立即重試，提示使用真`{jump}`綁定。側面入口與主線仍是普通階差；練習室無敵人、坑、雷射或尖刺，以floor21隔開盤平台守衛，右側兩道錯位實牆隔開上層火線。原drone (52,9)最終改至(60,44)，不併入原walkway波次；初次練習路線在其detect_range外。這些是幾何/靜態範圍檢查，活敵追逐與實際操作的安全性仍需真場景驗證，不能報已完成教學。

## 不能改的故事與遭遇責任

晚飯→屋頂鷺委託、首次溺毙/診間、水位持久、盤的真持有歷史→交接櫃/收據、復原館/宵夜/回家全部維持原結果及Main write-before-notify。原門ID、NPC資源/entry/talk、內容ID與資料盤flag不改。普通遭遇仍不鎖場。

street的plaza/blockade、vault的disk/walkway之原成員保持；區域中心只移到對應高度，盡量不改成員x，避免誤變encounter membership。兩個貨道sweeper另列x/y例外。死亡仍5%/cap250，持久敵人及已消耗物不重發。

## 明確遷移資料

四張改動map JSON：

```json
{"layout_revision":2,"legacy_layout":{"revision":1,"cell_offset":[0,32],"cells":{"162,16":[162,16]}}}
```

上例是warehouse真出口的例外；完整值由作者輸出。cells只列偏離offset的例外。一個舊格只映到一個新格，不能依kind靜默覆蓋。其餘七個LevelData維持原map修訂1/identity；pawnshop_dawn仍用pawnshop map。

`work/ne298-layout-proposal-v1/mapping-proposal-v1.json` 保存原52例外/246筆記錄提案；`mapping-actual-v5.json` 列CPU輸出11 LevelData的實際offset、原格映射與四個新portal。相對v3，唯一原resource更動是上述drone (52,9)→(60,44)；metadata另有6個非resource標記/燈/提示位置修正。每個原resource cell無合併，原多部件同格共用同一映射；任何修改需重出表並告知NE297，不能聲稱已做runtime migration。

安全回復候選：street P(4,51)，原路障已完成可用倉庫口(204,51)；warehouse門(3,48)，watchdog_defeated後可用電話亭(77,48)；vault入口(4,48)，ledger_disk_obtained後可用盤平台(43,28)；roof P(5,49)。NE297決定最窄、受進度及真幾何檢查的應用，不以全圖界內位置冒充安全。

## 必須一起對接的作者資料

- ch1_closure.Binding候選座標與ch1_runtime_backend.QUEST_LOCATIONS中的brief、street_clear、watchdog、flood、disk_pickup要改成同一新真格；只改座標，不改條件/結果/敘事。
- 原視覺props也要固定正確樓層。PropPlacement.ground_surface取第一個可站表面，新上層可能把舊下層物件抬走；以輸出map的明確y/ground=false及現有scenery_contacts接觸偏移保支撐，不能靠移鏡頭或忽略SceneSanity。
- 倉庫hoist_chain的原頂板4隨房間移至36；vault三件上層道具明示支撐列29/29/17。原寬貨櫃從x8移至x65的下層地面，避免穿入新階梯；這是非持久視覺prop，沒有重用它作保存cell映射。
- Grid.write只需增加extra的scalar/object JSON輸出，list沿原byte格式。NE297所有保存core仍由Root所有，本票不動。

## 驗證分層

先CPU生成/所有舊→新表/無合併/實心隔斷/門雙端條件/普通跳躍多層路線與未取得負控；再原受影響套件。代表真輸入涵蓋street上行下行、倉庫保留機關與貨道、vault拿盤/交接及回環；再躍獎勵同起點前後對照。舊檔/死亡/冷讀與拒寫另接NE297。Forward+/HDR LOW/HIGH看得到落點、前景遮擋/光影與鄰區落點最後驗；原186圖不是新圖驗收。沒有可用引擎窗口時，只能報CPU範圍。

SceneAudit僅對street三個真目標100,23／122,15／46,15讀取`capability_targets`。每筆只允許`ability: air_jump`與實際PlayerTuning的`flag: ledger_disk_obtained`；門自身也須同旗標。普通未標目標仍沿原5格模型，原8格不可達負控保留。late模型從同區P出發，不以互返門作自證seed；用一次追加跳躍與實際apex重力算有限上界（目前調校12格），仍檢查完整角色淨空及牆。此上界只篩除不可能幾何，不能證明8格操作可達；真Player前後輸入對照仍是交付前提。

## 首輪真窄測的修正（v5）

92521基底首輪原SceneSanity/Chapter1Map實跑2408/11紅保留，不回填。新圖移除runtime已退役的arena_gate glyph：MechanismData判GATE且arena_gate且非lock_combat_area；Gate._ready本來就不建shape/art且隱藏。原resource檔/舊cell migration資料仍保留，live ENCOUNTER區/成員/增援不刪，真正封路門不套此移除。既有SceneAudit仍檢所有剩餘機關，沒有加略過。

原18格出生安全距離改用同一世界腳底的2D歐氏距離，數值不變，另保同層/斜向真近敵拒絕與垂直遠距正控。兩個真近新門仍實際移位：street114,15→122,15；vault104,12→116,12。倉庫146,40到162,16原本2D距28.84格，原敵人不為只看x的舊假設而搬動；無實牆/火線安全不從距離推定已驗。

vault111..113的上層平台留3格真落下口，接下層floor29與裂牆後118,28獎勵。這是可走的普通下降路，不把舊不可達道具補貼能力標籤。

### v6任務標記對接

v5原同兩套件2399/1：舊street_clear仍指被移除的retired門182,36。實際完成來源是live ENCOUNTER `ch1_enc_street_blockade`中心167,36，channel `arena_street_blockade`經LevelData.channel_cleared_flags產生`ch1_street_route_open`。Binding、QUEST_LOCATIONS與正式quest location一起指此真來源；不恢復舊門、不放寬validator。原139場景/10任務的效果/交易皆同，只相對92521有7個location座標scalar變動。幾何與v5原cell mapping完全不變。

### v7 late body界線

v6原雙suite2399/0原件保留。實際Player.BODY_SIZE=12×44，原SceneAudit普通模型仍保歷史2格；只有新增late strict_arc改由真Player高度/tile推3格，從起點/升降/落地整段都沿此淨空。追加2格舊診斷假綠而真3格頭碰頂必拒反例。這仍只是geometry upper-bound，不代替真Input。

### v8室內封頂與原生工具

v7 Native首輪89/1原11圖/float/trace保留：四雙跳（vault安全房HP6→6、street真受擊HP6→5仍抵達獎勵）與三普通階差通，roof私有起點錯格拒收，未當作20格green。實看發現vault/cargo變戶外：LevelBuilder用row0的#判covered_columns，原兩室內圖全covered，新圖曾只135/166、4/124。作者geometry補兩區全寬row0..3頂板，不改runtime lighting。唯一額外原敵人目的格drone舊90,6由新90,3改新90,6避開頂板；其餘原格不動，mapping-actual-v8.json逐筆保246記錄。

私有roof Input起點依真平台修57,44→62,39；另在真Level/Hud ready後作flag false→true，以實際Label文字/visible/alpha/path/hold clock及原生PNG驗解鎖提示，不拿發出事件當可見。此時仍待新原生重拍，不以原雨中圖收尾。
