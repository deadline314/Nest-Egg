# ST-15 改寫前全文違規清單

> 基準：`967bf8bd`（生產資料與 `6f4805be` 相同）；以最終版 PlayerTextAudit 唯讀掃描既有 checkout。只列来源可讀性違規，不重複計 Story 服務。

共 **2,585 條來源、147 個違規位置、232 次規則命中（107 錯誤、125 警告）**。包含現有日英文、章節副標題及描述／提示陣列。腳本掃描保守納入部分內部訊息，數量不是玩家獨立句數。

最初盤點曾為 2,572／148／233；最後統一欄位與格式字串分類後，移除改裝通知純占位符子句的一次誤判。該通知仍依語義改成完整說明，沒有因此保留斷句。新增欄位不代表新增故事內容。

| 位置 | 改寫前文字 | 規則 |
|---|---|---|
| `res://data/codex/defeat_cards.json/cards/68/text` | 督察不趕時間：帳要收，人也要收。 | 子句平均 |
| `res://data/levels/ch1_pawnshop.tres:29/locked_text` | 漏水，別開。 | 短子句數 |
| `res://data/levels/ch1_pawnshop_dawn.tres:28/locked_text` | 漏水，別開。 | 短子句數 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 看門狗睡在大廳深處：牠的傷會留著，死了不白死 | 子句平均 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 隔牆：打倒看門狗才會升起 | 子句平均 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 電話亭 B2：先備份，再往裡走 | 子句平均 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 開關：按 {interact} 切換，閘門跟著開關 | 子句平均 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 牆上的水位刻度很高：這個坑會漲水 | 子句平均 |
| `res://data/levels/ch1_warehouse.tres:75/hints` | 前面是倉庫深處：保險箱有人守著 | 子句平均 |
| `res://data/props/ch1_crate.tres:10/hint` | 貨箱：打破它，裡面有零錢 | 短子句數、子句平均 |
| `res://data/props/crate.tres:12/hint` | 貨箱：打破它，裡面可能有補給 | 短子句數、子句平均 |
| `res://data/props/lift.tres:10/hint` | 升降梯：站上去，會自動上下往返 | 短子句數、子句平均 |
| `res://data/props/lift_tall.tres:10/hint` | 高升降梯：站上去往上，到維修走道 | 子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c01_open/steps/10/text` | 水位又上來了。鷺等一下來，有差事。 | 子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c01_open/steps/13/text` | 照抽。保費嘛，你自己簽的。去後面試試手感。 | 短片段、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_b_dinner/lines/2/text` | 四十。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_1/lines/2/text` | 九。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_1/lines/3/text` | 九啊。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_1/lines/5/text` | 喔。吃飯。 | 短片段、短片段、短句並列、短子句數 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_2/lines/2/text` | 嗯。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_2/lines/3/text` | 路上小心。水大。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_d1/lines/2/text` | 一次。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_d4/lines/2/text` | 別數。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_oldk_d4/lines/3/text` | 我數。我替你數。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_b_roof/lines/1/text` | 小鬼。遲到三分鐘。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_1/lines/1/text` | 地點，碼頭倉庫。目標，保險箱裡一片資料盤。 | 連續短子句、短子句數、子句平均、名詞斷句 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_1/lines/2/text` | 有隻看門狗守著。兩條腿，一條尾巴，脾氣不好。 | 連續短子句、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_1/lines/4/text` | 上面。我不問，你也別問。 | 短片段、連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_1/lines/5/text` | 你呢。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_1/lines/7/text` | 你一個人去。不要一個人死，浪費。開玩笑啦。 | 子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_2/lines/1/text` | 欸，晴岸？你要買房？ | 連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_2/lines/2/text` | 還早。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_2/lines/3/text` | 給誰？ | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_2/lines/6/text` | 別說。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_egret_2/lines/7/text` | 好好好。嘴巴縫起來。你要帶他去喔。 | 子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g06_lamp/lines/1/text` | 喂喂，一、二、三。聽得到嗎？市集被收帳人封了，走碼頭那邊。 | 連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g06_clear/lines/1/text` | 好。倉庫在碼頭盡頭，我在你耳邊。 | 短片段、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g07_dog/lines/2/text` | 多大。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g10_pit/lines/1/text` | 站上去，水淹過頭，我就死了。 | 連續短子句、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g10_pit/lines/2/text` | 對。我要你死一次。差別很大。 | 短片段、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_g10_cross/lines/2/text` | …對。很方便。 | 短片段、短句並列、短子句數 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c09_wake/steps/5/text` | …幹。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c09_wake/steps/9/text` | 穿灰外套的人，開貨車。不說話，也不收錢，放下就走。 | 連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c09_wake/steps/19/text` | 復原費，從信用點裡扣一點。還有，每次醒來，記憶的邊角會磨掉一點點。 | 短子句數 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c09_wake/steps/25/text` | 走了。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_b_lounge/lines/1/text` | 坐吧，湯還熱。 | 短子句數 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/2/text` | 一。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/3/text` | 一？那你運氣好。吃什麼？復原餐，還是酒？ | 短片段、短句並列、連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/4/text` | 都要。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/6/text` | 凜。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/7/text` | 阿梨。梨子的梨。別分梨吃，會分開。 | 短片段、連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_1/lines/8/text` | 好。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_2/lines/4/text` | 多少。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_b_stall/lines/1/text` | 吃。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_4/lines/2/text` | 好。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_3/lines/1/text` | 多少。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_t_ali_3/lines/8/text` | 市集後面，三樓。敲三下，再敲兩下，是我。 | 連續短子句、短子句數、子句平均 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/5/text` | 老 K。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/7/text` | 啊。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/10/text` | 是。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/11/text` | 老了。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/21/text` | 剛剛。 | 短片段 |
| `res://data/story/ch1_kasa.json/scenes/ch1_c14_home/steps/22/text` | 喔。水燒好了。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/prologue/lines/6/text` | 順便。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/radio_start/lines/1/text` | 喂喂，一、二、三。聽得到嗎，你耳機又有雜音，我說過那顆喇叭該換了。 | 連續短子句、短子句數 |
| `res://data/story/chapter_01.json/scenes/radio_market_mei/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/radio_market_mei/variants/1/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/radio_shield/variants/1/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/radio_mech/lines/1/text` | 壁壘的鑰匙在左邊輪胎上面。外套拉鍊拉起來，你喔，會著涼。 | 短子句數 |
| `res://data/story/chapter_01.json/scenes/radio_facility/lines/2/text` | 別點。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/radio_facility/variants/1/lines/2/text` | 沒有。別點。 | 短片段、短片段、短句並列、短子句數 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/1/text` | 又瘦了喔。坐啦，雨這麼大，站著幹嘛。 | 連續短子句、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/3/text` | 趕什麼，湯滾了啦。這碗我多放一顆蛋，不用錢。 | 短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/4/text` | 多少。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/5/text` | 說不用錢就不用錢。你弟呢？還咳嗎？ | 短句並列、短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/6/text` | 咳。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/7/text` | 喔。上次他在我這桌畫了一張，我老花，看不懂畫什麼，你拿去。 | 短片段、短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_1/lines/8/text` | 嗯。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_2/lines/2/text` | 不用。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_ahpo_2/lines/7/text` | 是喔？老了，記錯啦。對了，電視說半夜要停雨。 | 短片段、連續短子句、短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_worker_1/lines/1/text` | 欸，這個時間不該有人。你誰。 | 短片段、短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/npc_worker_1/lines/2/text` | 領貨。NEST-07。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_worker_2/lines/2/text` | 不用。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/npc_worker_2/lines/5/text` | 好。 | 短片段 |
| `res://data/story/chapter_01.json/scenes/boss_intro/lines/3/text` | 是，抱歉。系統裡只登記了編號。名單我每晚都念一遍，到十六號為止。 | 短子句數 |
| `res://data/story/chapter_01.json/scenes/boss_intro/lines/5/text` | 請不要在意。請隨我來，路上辛苦了。 | 子句平均 |
| `res://data/story/chapter_01.json/scenes/epilogue/lines/2/text` | 碎片打開了。受試者，航。進度百分之六十二。 | 短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/epilogue/lines/4/text` | 出來吧，凜。晶片滿了就回來，粥還熱著喔。 | 短子句數、子句平均 |
| `res://data/story/chapter_01.json/scenes/epilogue/lines/6/text` | ……停了。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_prologue/lines/2/text` | 航呢。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_prologue/lines/3/text` | 半夜來接的。手沒事吧？粥熱著，先喝一口喔。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_radio_cloak/lines/1/text` | 欸，前面有人。我這邊看不到，可是熱源在動。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_radio_corridor/lines/2/text` | 嗯。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_radio_corridor/variants/1/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_radio_power/lines/1/text` | 總閘在前面。拉下去，保全全瞎，我們也看不到路。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_radio_medic/variants/1/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_radio_k2/lines/1/text` | 凜，上面不管有什麼，別回頭看我喔。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_radio_last/variants/1/lines/2/text` | 沒有。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_curtain/lines/2/text` | 後面有燈在動。快跑，我不開玩笑。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_1/lines/1/text` | 囝仔，別走那邊。梯子鬆了。 | 連續短子句、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_1/lines/3/text` | 沒事。我值三班了。十七層……不對，十八。 | 短片段、短子句數、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_1/lines/4/text` | 老伯。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_1/lines/5/text` | 那晚啦。十年前，最後一班。推車上來，蓋著布，我以為是貨。 | 連續短子句、短子句數、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_1/lines/8/text` | 戴手套的。穿白的。這個你拿去，電池還有電，我用不到了。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_chen_2/lines/1/text` | 囝仔，還在啊。往上是十九層，別數錯。 | 短子句數、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_resident_1/lines/5/text` | 老二。上個月去的，說兩天就回來。 | 短片段、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_resident_1/lines/8/text` | 還沒。你快走，九點了。 | 短片段、連續短子句、短子句數、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_npc_nurse_1/lines/1/text` | 七號？床位在最裡面。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_npc_nurse_1/lines/6/text` | 上次。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_obj_marks/lines/2/text` | 01。03。05。數到十六。 | 短片段、短片段、短片段、短句並列、連續短子句、短子句數、子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_boss_intro/lines/4/text` | 上面。已經在上面了。你現在趕上去，只會追到空的。 | 短片段 |
| `res://data/story/chapter_02.json/scenes/c2_boss_intro/lines/5/text` | 他在拖時間。凜，地板在響。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_epilogue/lines/1/text` | 回收失敗。又要寫報告。他的進度，九成了。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_epilogue/lines/4/text` | 日誌寫，送去塔頂。電梯就在你後面。 | 子句平均 |
| `res://data/story/chapter_02.json/scenes/c2_epilogue/lines/5/text` | 凜。你右手裡那條線……是我接的。我沒跟你說過，對吧。 | 短片段、短子句數 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c1_shop/steps/19/text` | 站好。線又鬆了。 | 短片段 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c1_shop/steps/22/text` | 嗯。 | 短片段 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c1_shop/steps/28/text` | 順便。 | 短片段 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c1_shop/steps/32/text` | 喂。聽得到嗎。我在你耳朵裡面，不用揮手。 | 短片段、子句平均 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c1_shop/steps/33/text` | 嗯。 | 短片段 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c2_hangar/steps/14/text` | 是，抱歉。系統裡只登記了編號。名單我每晚都念一遍，到十六號為止。 | 短子句數 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c2_hangar/steps/18/text` | 請不要在意。請隨我來，路上辛苦了。 | 子句平均 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c3_terminal/steps/9/text` | 碎片打開了。受試者，航。進度百分之六十二。 | 短子句數、子句平均 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c3_terminal/steps/18/text` | 出來吧，凜。晶片滿了就回來，粥還熱著喔。 | 短子句數、子句平均 |
| `res://data/story/cutscenes_ch1.json/scenes/cut_c3_terminal/steps/24/text` | ……停了。 | 短片段 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c4_dawn/steps/9/text` | 航呢。 | 短片段 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c4_dawn/steps/12/text` | 半夜來接的。手沒事吧？粥熱著，先喝一口喔。 | 子句平均 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c6_corridor/steps/14/text` | 上面。已經在上面了。你現在趕上去，只會追到空的。 | 短片段 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c6_corridor/steps/17/text` | 他在拖時間。凜，地板在響。 | 子句平均 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c7_elevator/steps/4/text` | 回收失敗。又要寫報告。他的進度，九成了。 | 子句平均 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c7_elevator/steps/12/text` | 日誌寫，送去塔頂。電梯就在你後面。 | 子句平均 |
| `res://data/story/cutscenes_ch2.json/scenes/cut_c7_elevator/steps/20/text` | 凜。你右手裡那條線……是我接的。我沒跟你說過，對吧。 | 短片段、短子句數 |
| `res://data/story_items/doc_cargo_manifest.tres:13/body` | 編號 NEST-07，低溫貨櫃一只。收件單位：軌道醫院第三研究所。備註：嚴禁開啟，內容物是「生物相容資料」。簽收人欄只寫了一個字：K。 | 短子句數 |
| `res://data/story_items/doc_crayon_drawing.tres:13/body` | 兩個人撐一把紅傘，一個高，一個矮。窗戶後面還有一個很小的人，用最淡的黃色蠟筆畫的，差點看不出來。右下角歪歪的字：姐姐跟我。 | 短子句數 |
| `res://data/story_items/doc_echo_flyer.tres:13/body` | 復原出來的東西叫回音，人早就不在了。你聽見的每一句話，都是別人說剩下的。週日傍晚，港口廣場，不收費。背面用鉛筆補了一行：我爸說的不一樣。 | 連續短子句 |
| `res://data/story_items/doc_nest_log.tres:13/body` | 七號的義體相容率最高，列為基準。十號以後一律標註消耗品。技師：K。 | 短子句數 |
| `res://data/story_items/doc_pawn_stub.tres:13/body` | 當品：懷錶一只。當金八百。贖回期限：無。備註：客人說先放著，晚點回來拿，已經六年。老 K 每個月都會把它擦一遍。 | 連續短子句、短子句數、子句平均 |
| `res://data/story_items/doc_rain_news.tres:13/body` | 本月降雨量創新高，氣象台表示屬正常波動。社論：水位與利率，今年都沒有降下來。第二版：復原館週年慶，今晚第一次復原半價。 | 短子句數 |
| `res://data/story_items/doc_shift_note.tres:13/body` | 交班。巡三圈，鐵門鎖好，吊車斷電。NEST-07 的貨櫃又有人來領，這個月第三個。前兩個沒出來。主管說不要問。電鍋裡留了一碗飯，誰餓誰吃。 | 短片段、連續短子句、短子句數 |
| `res://data/story_items/doc_transfer_sheet.tres:13/body` | 床位 12。受試者：航。21:00 轉送上層。家屬欄：七號，未到。床位保留。手環維持 37 度，每小時遠端確認一次。備註：七號回來的話，別讓她等太久。 | 連續短子句、短子句數、子句平均 |
| `res://data/story_items/nest07_shard.tres:9/description` | 裡面是一個孩子的神經掃描。受試者：航。轉移進度 62%。 | 短子句數 |
| `res://data/story_items/nest_roster.tres:9/description` | 終端機截下的名單。七號簽名欄的字歪歪的，像小孩寫的。05 那行被圈起來，寫著：執行中。底下小字：回收獎勵 91,000，補完上傳。 | 連續短子句、短子句數 |
| `res://data/story_items/rec_old_k_voicemail.tres:13/body` | 小鬼，你聽到這段的時候，我大概又在擔心了。拿了東西就回來，別逞強。粥我煮好放桌上了。航昨晚咳得兇，你回來先看他。瓦斯又漲了，你喔。 | 短子句數 |
| `res://data/weapons/melee/melee_blade.tres:15/description` | 長刀：速度與威力均衡，三段連斬，第三刀能打出硬直；不耗電 | 短子句數、子句平均 |
| `res://data/weapons/melee/melee_dagger.tres:15/description` | 短刃：揮得最快、要貼身，連刺三下收尾較重；不耗電 | 短子句數 |
| `res://data/weapons/melee/melee_glaive.tres:15/description` | 長柄：刺得遠、可朝準星，但貼臉有死角；不耗電 | 短子句數、子句平均 |
| `res://data/weapons/pistol.tres:19/description` | 主武器：單發精準，備彈無限 | 連續短子句、子句平均 |
| `res://data/weapons/railgun.tres:19/description` | 能量武器：單發重創，貫穿一整排 | 子句平均 |
| `res://ui/settings_screen.gd:180@30` | 開啟：生命與護盾閒置時淡出，受傷或格擋時才出現；關閉：一律顯示 | 短子句數 |
| `res://ui/settings_screen.gd:200@28` | 開啟：介面文字用平滑的黑體；關閉：改回像素字。立即生效 | 短子句數、子句平均 |
| `res://game/enemies/chain_hook.gd:142@30` | 被鉤住了：衝刺掙脫，或打斷鎖鏈 | 子句平均 |
| `res://game/props/flood_pit.gd:17@21` | 踏板：站上去，閘門會一直開著 | 短子句數、子句平均 |
