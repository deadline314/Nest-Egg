# 場景背景與場景專屬物件登記表

> 來源：2026-10-04 依 `design/13-story-v2/OUTLINE.md` 第 5 節為每個場景畫背景並設計專屬物件。這份表是進度依據：中斷後從「待畫」的項目接續，不要重做「完成」的。
> 做法與工具見 `.claude/skills/free-asset-pipeline/SKILL.md` §8。清單：`assets_src/pipeline/scene_bgs.json`（背景，1536×864，輸出 `art/environment/scenes/<場景id>.webp`，亮點抽成 `_glow.webp`）、`assets_src/pipeline/scene_props.json`（物件，圖在 `art/environment/scene_props/<場景id>/`，資料在 `data/environment/scene_props/<場景id>/`，之後場景的環境主題用 `prop_dir` 指向）。
> 同一地點在不同章節換狀態（OUTLINE 5.3）只建一個場景，「狀態變體」欄註明各章的換法；變體背景不在這次範圍。

## 進度

- 場景 43 個；背景完成 12 / 43；物件完成 36（已規劃 430，目標每場景 10 個，共 430）
- 場景包素材量：10.2 MB / 160 MB（`python tools/assets/check_assets.py`）；物件預設貼圖倍率 6（`texture_scale`），伏筆與小物件提高到 10～16
- 備註：階段 1 進行中（每場景 1 背景 + 3 物件）；階段 2 之後每輪每場景加 1 個。

狀態說明：完成＝圖與資料都已產出；完成（備註）＝接受最佳版本並註明缺點；待畫＝尚未生成。物件 id 同時是 `.tres` 檔名，場景的環境主題用 `prop_dir` 指向 `res://data/environment/scene_props/<場景id>/`。

## 場景總表

| 章 | 場景 id | 名稱 | 類型 | 背景 | 物件 |
|---|---|---|---|---|---|
| 1（變體 2～9） | `pawnshop_front` | 巢蛋當舖（店面） | 據點 | 完成 | 3 / 10 |
| 1（變體 3） | `pawnshop_kitchen` | 當舖廚房 | 據點 | 完成 | 3 / 10 |
| 1、5（變體） | `basement_door` | 地下室的門 | 據點（第一章不可進） | 完成 | 3 / 10 |
| 1 | `harbor_street` | 港區街道（雨夜） | 探索 | 完成 | 3 / 10 |
| 1、2、4、8 | `rooftop` | 屋頂（當舖屋頂） | 探索／演出 | 完成 | 3 / 10 |
| 1 | `dock_warehouse` | 碼頭倉庫 | 探索＋頭目 | 完成 | 3 / 10 |
| 1（每次復原） | `revival_room` | 復原室 | 演出 | 完成 | 3 / 10 |
| 1 起（每章） | `anchor_phone_booth` | 錨點電話亭（街角） | 探索（存檔點） | 完成 | 3 / 10 |
| 1（變體 4 酒客） | `revival_lounge` | 復原館（夜） | 演出 | 完成 | 3 / 10 |
| 1 | `dawn_noodle_stall` | 天亮的麵攤 | 演出 | 完成 | 3 / 10 |
| 2（變體 6、A） | `neon_market` | 霓虹市集 | 探索 | 完成 | 3 / 10 |
| 2 | `yong_hideout` | 阿勇的據點 | 探索＋頭目 | 完成 | 3 / 10 |
| 2 | `radio_workbench` | 收音機修理（當舖工作檯） | 據點 | 待畫 | 0 / 10 |
| 間章一（第二章之後） | `guest_book_room` | 客人簿（復原館包廂） | 間章 | 待畫 | 0 / 10 |
| 3 | `mezzanine` | 夾層 | 探索 | 待畫 | 0 / 10 |
| 3（邊緣）、7 | `sunlit_district` | 日照區街道 | 探索 | 待畫 | 0 / 10 |
| 3、B 結局 | `clearwater` | 晴岸（接待與樣品房） | 探索／演出 | 待畫 | 0 / 10 |
| 3 | `clinic` | 診所（錨庫分站） | 探索＋頭目 | 待畫 | 0 / 10 |
| 3 | `tianqiong_corridor` | 天穹辦公室外 | 演出 | 待畫 | 0 / 10 |
| 4、間章二 | `nursing_ward` | 安養病房（用盡者的病房） | 探索／演出 | 待畫 | 0 / 10 |
| 4、間章二 | `abandoned_factory` | 廢棄廠房 | 探索＋頭目 | 待畫 | 0 / 10 |
| 4 | `factory_office` | 廠房的辦公室 | 演出 | 待畫 | 0 / 10 |
| 5 | `basement` | 當舖地下室 | 探索／演出 | 待畫 | 0 / 10 |
| 5（間章三）、8 | `flood_street` | 洪水的港區 | 探索（非戰鬥）／間章 | 待畫 | 0 / 10 |
| 6 | `broadcast_outside` | 廣播站（外） | 探索 | 待畫 | 0 / 10 |
| 6 | `recording_booth` | 廣播站（錄音室） | 演出 | 待畫 | 0 / 10 |
| 間章四（第六章） | `control_room` | 控制室（燈） | 間章 | 待畫 | 0 / 10 |
| 6 | `broadcast_roof` | 廣播站屋頂 | 頭目 | 待畫 | 0 / 10 |
| 6 | `rain_chase_alley` | 雨中追逐（小巷） | 探索（限時） | 待畫 | 0 / 10 |
| 6（變體 結局 A） | `harbor_plaza` | 港區廣場（廣播後） | 演出 | 待畫 | 0 / 10 |
| 6 | `pawnshop_bathroom` | 當舖浴室 | 據點 | 待畫 | 0 / 10 |
| 7 | `sunlit_noodle_stall` | 麵攤（日照區） | 演出 | 待畫 | 0 / 10 |
| 7 | `public_garden` | 公共花園（日照區） | 探索（無戰鬥） | 待畫 | 0 / 10 |
| 7 | `nightmare_arena` | 夢魘（日曆頁的花園） | 頭目 | 待畫 | 0 / 10 |
| 7 | `tower_garden` | 天穹塔頂花園 | 探索／演出 | 待畫 | 0 / 10 |
| 7 | `accounting_lobby` | 櫃台（帳房大廳） | 演出 | 待畫 | 0 / 10 |
| 8 | `sluice_hall` | 水閘廳 | 頭目 | 待畫 | 0 / 10 |
| 8 | `suo_boat` | 蘇的船 | 演出 | 待畫 | 0 / 10 |
| 8 | `night_harbor` | 港口（夜） | 演出 | 待畫 | 0 / 10 |
| 9 | `tower_floors` | 天穹塔（各層） | 探索 | 待畫 | 0 / 10 |
| 9 | `ledger_hall` | 帳房 | 頭目 | 待畫 | 0 / 10 |
| 9（結局 A） | `ending_a_stall` | 「欠著」麵攤 | 演出 | 待畫 | 0 / 10 |
| 9（真結局片尾） | `school_terminal` | 學校的終端前 | 演出 | 待畫 | 0 / 10 |

## 巢蛋當舖（店面）（`pawnshop_front`）

- 章：1（變體 2～9）　類型：據點
- 畫面：貨架到天花板，每件東西都貼著手寫標籤；櫃台、工作檯、招牌「什麼都收，不收命」；屋頂漏水滴進一個桶；暖黃燈。
- 色調與光：暖橙（當舖）對冷藍（窗外的街）；夜、中雨；黃燈與窗外霓虹對比最強。
- 背景：完成（`art/environment/scenes/pawnshop_front.webp`）
- 狀態變體：1 完整（貨架滿、標籤整齊、漏水桶）→ 2 標籤開始有空白 → 3 老 K 留的飯 → 4 安靜、收音機放著歌 → 5 調查現場（抽屜全開、標籤被翻）→ 6 暖色浴室另立場景 → 7 空 → 8 水到膝蓋、標籤漂在水上 → A 結局標籤泡掉一半。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `pawnshop_front__tag_shelf` | 貼滿標籤的高貨架 | 貼著手寫來歷標籤的雜物高貨架，伏筆「標籤」的主場。 | 2.4 m | 完成 |
| `pawnshop_front__leak_bucket` | 漏水桶 | 屋頂漏水滴進的鐵桶，老 K 說那是他的鬧鐘；水面有漣漪。 | 1.4 m | 完成 |
| `pawnshop_front__pawn_sign` | 「什麼都收，不收命」招牌 | 當舖招牌的霓虹字，會閃；全作的規矩。 | 0.9 m | 完成 |
| `pawnshop_front__counter_register` | 櫃台與黃銅收銀機 | 長木櫃台、老式黃銅收銀機、算盤與一盞小檯燈；老 K 的位置。 | 1.2 m | 待畫 |
| `pawnshop_front__fare_jar` | 「船錢」罐 | 貨架上裝著舊硬幣的玻璃罐，標籤寫著「船錢」；老 K：「留給回不來的人。」 | 0.5 m | 待畫 |
| `pawnshop_front__crate_pile` | 寄物箱堆 | 疊起來的木箱與紙箱，每個貼著寄物標籤；地上的雜物。 | 1.1 m | 待畫 |
| `pawnshop_front__hanging_bulb` | 吊著的燈泡 | 從天花板垂下的裸燈泡，暖橙色，輕輕搖晃。 | 0.9 m | 待畫 |
| `pawnshop_front__wall_instruments` | 牆上的舊樂器 | 牆上的吉他、小提琴與薩克斯風；每一件都貼著標籤。 | 1.6 m | 待畫 |
| `pawnshop_front__arms_workbench` | 武器改裝工作檯 | 當舖後面的改裝工作檯：台鉗、零件盤、槍械零件與一盞檯燈；教學場景。 | 1.05 m | 待畫 |
| `pawnshop_front__locked_ledger_box` | 鎖著的帳本匣 | 老 K 那本鎖著的帳：黑色的皮匣與黃銅鎖；一成手續費都記在這裡。 | 0.45 m | 待畫 |

## 當舖廚房（`pawnshop_kitchen`）

- 章：1（變體 3）　類型：據點
- 畫面：小廚房：爐上燒水的壺、兩副碗筷、窄窄的桌子、窗外的雨；晚飯。
- 色調與光：暖黃的小燈，窗外冷藍；整個畫面最溫暖、最小的一間。
- 背景：完成（`art/environment/scenes/pawnshop_kitchen.webp`）
- 狀態變體：1 晚飯、水燒乾了 → 3 老 K 留的飯，標籤寫著「今天的」，字跡抖。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `pawnshop_kitchen__kettle_stove` | 燒水的鐵爐與壺 | 爐上的水壺冒蒸汽，章末水燒乾了；爐口透出暖光。 | 0.95 m | 完成 |
| `pawnshop_kitchen__dining_table` | 兩副碗筷的小餐桌 | 窄桌、兩把椅子、兩副碗筷；一人份的飯菜與一張紙標籤。 | 0.85 m | 完成 |
| `pawnshop_kitchen__old_fridge` | 貼滿紙條的老冰箱 | 舊冰箱門上用磁鐵貼著紙條與購物單，每張都是老 K 的字跡。 | 1.6 m | 完成 |
| `pawnshop_kitchen__hanging_pans` | 掛鍋架 | 牆上的鍋鏟與平底鍋；老 K 用了二十年。 | 1.0 m | 待畫 |
| `pawnshop_kitchen__carrot_board` | 砧板與紅蘿蔔 | 小砧板上切成細絲的紅蘿蔔；「她不吃紅蘿蔔，我每次都切得很細。」 | 0.55 m | 待畫 |
| `pawnshop_kitchen__dish_cabinet` | 碗櫃 | 木製碗櫃，玻璃門後兩副碗盤整齊疊著；水燒乾的那晚它也在。 | 1.7 m | 待畫 |
| `pawnshop_kitchen__paper_shade_lamp` | 紙罩吊燈 | 廚房中間垂下的圓形紙罩燈，柔和的暖黃光。 | 0.8 m | 待畫 |
| `pawnshop_kitchen__lunch_left_for_today` | 「今天的」飯菜與標籤 | 蓋著盤子的飯菜，旁邊一張紙標籤寫著「今天的」，字跡抖；第三章。 | 0.45 m | 待畫 |
| `pawnshop_kitchen__water_urn` | 水缸與瓢 | 角落的陶水缸，木蓋上放著一把長柄瓢。 | 0.9 m | 待畫 |
| `pawnshop_kitchen__tear_off_calendar` | 日曆 | 牆上的撕頁日曆，有幾天用紅筆圈起來。 | 0.6 m | 待畫 |

## 地下室的門（`basement_door`）

- 章：1、5（變體）　類型：據點（第一章不可進）
- 畫面：後屋的短走廊盡頭，一扇鎖著的鐵門，門縫下有光，門上貼著「漏水，別開」。
- 色調與光：昏暗的灰綠水泥牆，只有門縫下的一線暖黃光；水管滴水。
- 背景：完成（`art/environment/scenes/basement_door.webp`）
- 狀態變體：1 鎖著，貼「漏水，別開」→ 5 打開、樓梯與入口（老鬼守著，外套鋪在樓梯上）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `basement_door__locked_iron_door` | 鎖著的地下室鐵門 | 鐵門上貼著「漏水，別開」，門縫下透出一線暖光；全作第一個伏筆。 | 2.1 m | 完成 |
| `basement_door__voice_lock` | 聲音鎖面板 | 牆上的小對講面板，紅色指示燈；第五章的聲音鎖，問「帶傘了嗎」。 | 0.7 m | 完成 |
| `basement_door__wet_floor_sign` | 「小心地滑」警示牌與積水 | 黃色折疊警示牌與一灘水，漏水的線索。 | 0.75 m | 完成 |
| `basement_door__leaking_pipe` | 漏水的管接頭 | 牆上鏽蝕的管接頭，一滴一滴落到地上；門上寫的「漏水」不是騙人的。 | 1.3 m | 待畫 |
| `basement_door__concrete_steps` | 水泥小階梯 | 通往下面的三級水泥階，邊角剝落；第五章的樓梯入口。 | 0.7 m | 待畫 |
| `basement_door__caged_bulb` | 鐵網罩燈 | 天花板上的鐵網罩燈泡，昏黃，偶爾閃一下。 | 0.55 m | 待畫 |
| `basement_door__fuse_box` | 老電表與保險絲箱 | 牆上的鐵殼電表箱，一排老式保險絲；拉下它地下室的光就滅了。 | 0.8 m | 待畫 |
| `basement_door__grey_coat_on_steps` | 鋪在樓梯上的灰外套 | 老鬼留下的灰色舊外套，內側繡著兩個字：必安；第五章。 | 0.55 m | 待畫 |
| `basement_door__storage_rack` | 鐵架雜物 | 牆邊的鐵架：油漆罐、紙箱、舊毯子；沒人動過的一層灰。 | 1.5 m | 待畫 |
| `basement_door__junk_pile` | 舊雨靴與水桶 | 地上的雜物：兩隻舊雨靴、水桶與拖把。 | 0.8 m | 待畫 |

## 港區街道（雨夜）（`harbor_street`）

- 章：1　類型：探索
- 畫面：霓虹招牌、積水的路面、傘、排隊的空欄杆；遠處塔的光。出門的第一個畫面，建立比例。
- 色調與光：夜、中雨；冷藍的街與洋紅、青色霓虹，積水倒映；遠處雲上的塔是唯一的冷白光。
- 背景：完成（`art/environment/scenes/harbor_street.webp`）　重畫 1 次（避免像真實大樓的高塔，改成虛構的針狀塔）
- 狀態變體：1 初見；2、6 的市集在另一處；A 結局洪水退後（雨沒停）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `harbor_street__rebirth_billboard` | 「再來一次」看板 | 全作的標語看板，沈望的聲音；每章都在，後面會變。 | 3.0 m | 完成（重生 1 次（老婦人臉）） |
| `harbor_street__umbrella_stand` | 門口的傘架 | 插滿雨傘的舊傘架，每把傘不一樣；「帶傘了嗎」的象徵。 | 1.0 m | 完成 |
| `harbor_street__tide_gauge` | 水位標尺 | 牆邊的潮位標尺，刻度與數字；「水位」動詞的教學，也是第八章的牆上數字。 | 2.2 m | 完成（偶數刻度較暗、重生 1 次） |
| `harbor_street__restore_queue_sign` | 復原申請排隊牌 | 路邊的排隊指示牌，寫著「復原申請：請依序排隊」；隊伍的欄杆沒有人。 | 1.8 m | 待畫 |
| `harbor_street__umbrella_vending` | 雨傘販賣機 | 街角的雨傘自動販賣機，一排透明傘與發光價牌；「帶傘了嗎」的路邊版本。 | 1.9 m | 待畫 |
| `harbor_street__stacked_neon_signs` | 疊起來的直式霓虹招牌 | 大樓外牆上疊著的直式霓虹：麵、藥、酒、旅社，顏色各不相同。 | 3.2 m | 待畫 |
| `harbor_street__steam_manhole` | 冒蒸汽的排水孔 | 街邊的排水孔，一根舊通氣管冒著白煙。 | 0.9 m | 待畫 |
| `harbor_street__pole_wire_knot` | 電線桿與纏結的電線 | 老電線桿與一大把纏在一起的電線，其中一條垂下來。 | 4.5 m | 待畫 |
| `harbor_street__fish_cart` | 魚販推車 | 港口的魚販推車：冰塊、藍色塑膠箱、一盞小吊燈。 | 1.5 m | 待畫 |
| `harbor_street__parked_scooter` | 停著的小速克達 | 靠牆停著的舊小綿羊機車，座墊上蓋著塑膠袋，濕答答的。 | 1.2 m | 待畫 |

## 屋頂（當舖屋頂）（`rooftop`）

- 章：1、2、4、8　類型：探索／演出
- 畫面：水塔、天線、晾衣繩、遠處的塔；雨。鷺介紹差事、教凜看雨、燈坦白、灰衣人接人都在這裡。
- 色調與光：夜、雨；冷藍的天，遠處塔的冷白光，近處當舖樓梯間的暖黃門燈。
- 背景：完成（`art/environment/scenes/rooftop.webp`）
- 狀態變體：1 鷺介紹差事 → 2 看雨（破傘、兩杯茶）、對面屋頂有灰色人影（只用遠景）→ 4 燈坦白（夜）→ 8 灰衣人丟下繩子接人。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `rooftop__torn_umbrella_tea` | 破傘與兩杯茶 | 撐著一把破傘的小茶座，兩個小凳、兩杯茶；第二章的情感核心。 | 1.5 m | 完成 |
| `rooftop__stairwell_hut` | 屋頂樓梯間 | 屋頂上的樓梯間小屋，門口一盞暖黃燈，雨從簷下滴落。 | 2.4 m | 完成 |
| `rooftop__cut_cable_box` | 被剪斷的電線盒 | 牆上的接線盒，電線被利落地剪斷垂下；灰衣人先清過路的伏筆。 | 1.5 m | 完成 |
| `rooftop__rusty_water_tank` | 生鏽的水塔 | 屋頂上的圓形鐵水塔，底部滲水，下面支著鐵腳；每一章都在背景裡。 | 3.4 m | 待畫 |
| `rooftop__antenna_forest` | 電視天線叢 | 屋頂上一叢老式天線，頂端有紅色信標，雨中閃著。 | 3.6 m | 待畫 |
| `rooftop__dish_pair` | 兩面碟型天線 | 並排的兩面舊碟型天線與一個灰色設備箱。 | 1.6 m | 待畫 |
| `rooftop__rope_coil_hook` | 繩圈與鐵鉤 | 牆角的粗麻繩圈與一個鐵鉤；第八章灰衣人丟下的繩子從這裡來。 | 0.6 m | 待畫 |
| `rooftop__rain_collecting_barrel` | 集雨桶 | 接屋簷落水的圓形桶，水面有雨滴漣漪。 | 1.0 m | 待畫 |
| `rooftop__folding_chairs_boxes` | 折疊椅與紙箱 | 靠在牆邊的折疊椅與幾個濕掉的紙箱；屋頂上的雜物。 | 1.1 m | 待畫 |
| `rooftop__skylight_hatch` | 屋頂小天窗 | 透出暖黃光的屋頂天窗，雨珠沿著玻璃滑落。 | 0.7 m | 待畫 |

## 碼頭倉庫（`dock_warehouse`）

- 章：1　類型：探索＋頭目
- 畫面：貨櫃、吊車、水位閘門、積水；保全機甲看門狗的巡邏燈。水位謎＋頭目戰；死亡後世界保持。
- 色調與光：夜；工業的鏽橙與冷灰，探照燈的冷白，警示信標的紅，地上一層積水。
- 背景：完成（`art/environment/scenes/dock_warehouse.webp`）
- 狀態變體：第一章水位閘門謎（以死解謎）、看門狗戰；之後不再使用。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `dock_warehouse__sluice_gate` | 水位閘門與手輪 | 第一章水位謎的閘門：鐵閘、手輪、刻度牌與警示燈。 | 2.6 m | 完成 |
| `dock_warehouse__float_drum_crate` | 浮筒與木箱 | 水位升起就會漂浮的藍色浮筒與貨箱；水位謎的道具。 | 1.0 m | 完成 |
| `dock_warehouse__searchlight_post` | 巡邏探照燈 | 保全機甲的巡邏燈：冷白強光、會明滅。 | 2.4 m | 完成 |
| `dock_warehouse__open_container` | 開著門的貨櫃 | 一只貨櫃，大門開著，裡面堆著木箱；水位謎的終點。 | 2.7 m | 待畫 |
| `dock_warehouse__hoist_chain` | 吊鏈與吊鉤 | 從天車垂下的粗鏈，末端的大鉤輕輕擺動。 | 3.2 m | 待畫 |
| `dock_warehouse__wrapped_pallets` | 纏膜棧板 | 疊在一起的棧板，貨物裹著半透明膠膜，膠膜被雨水泡皺。 | 1.4 m | 待畫 |
| `dock_warehouse__watchdog_dock` | 看門狗的充電座 | 保全機甲看門狗的停機座：粗纜線、紅燈；它現在不在座上。 | 2.0 m | 待畫 |
| `dock_warehouse__rotating_beacon` | 旋轉警示燈 | 桿上的橙紅旋轉警示燈，警戒時閃著。 | 1.1 m | 待畫 |
| `dock_warehouse__floor_switch_plate` | 水底的踏板開關 | 地上的壓力踏板與一條粗電纜；站上去第三道閘門才會開。 | 0.55 m | 待畫 |
| `dock_warehouse__water_pump` | 抽水機與軟管 | 水泥基座上的柴油抽水機，粗黃軟管盤繞；水位動詞的道具。 | 1.2 m | 待畫 |

## 復原室（`revival_room`）

- 章：1（每次復原）　類型：演出
- 畫面：白色小房間，一張台子，赤裸醒來的第一個畫面；金屬味；牆上有「再來一次，沒關係」。
- 色調與光：冷白、近乎過曝的日光燈，只有一條冷青色的亮邊；乾淨得令人不安。
- 背景：完成（`art/environment/scenes/revival_room.webp`）　背景幾乎全白，不抽發光層（整間會被誤抽成發光）
- 狀態變體：1 第一次要特別長 → 之後每次復原都用；賣掉復原權之後（第七章起）不再使用。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `revival_room__revival_slab` | 復原台 | 金屬台，邊緣有束帶與排水槽；醒來的第一個畫面。 | 0.95 m | 完成 |
| `revival_room__slogan_panel` | 標語燈箱 | 牆上的燈箱：「再來一次，沒關係」；每次醒來都看到。 | 0.75 m | 完成 |
| `revival_room__printing_tank` | 殼列印槽 | 列印身體的圓筒槽，淡青色的液體與氣泡；帶金屬味的來源。 | 2.3 m | 完成 |
| `revival_room__steel_locker` | 金屬置物櫃 | 牆邊的灰色鋼櫃，櫃門貼著編號，一格開著。 | 1.9 m | 待畫 |
| `revival_room__gown_cart` | 推車與折好的衣物 | 醫療推車：折好的灰色衣物、毛巾與一杯水；醒來之後的第一件東西。 | 0.95 m | 待畫 |
| `revival_room__surgical_lamp` | 無影燈 | 天花板垂下的懸臂無影燈，刺眼的冷白光。 | 2.1 m | 待畫 |
| `revival_room__vitals_monitor` | 生命徵象監視器 | 台旁的小監視器，綠色心跳線與數字：「0」。 | 1.3 m | 待畫 |
| `revival_room__steel_sink` | 不鏽鋼洗手台 | 角落的洗手台，水龍頭還滴著水。 | 1.1 m | 待畫 |
| `revival_room__countdown_display` | 復原倒數顯示器 | 牆上的紅色數字：10:00，倒數十分鐘；錨人必須在這十分鐘內坐上椅子。 | 0.55 m | 待畫 |
| `revival_room__restore_control_panel` | 列印槽控制台 | 列印槽旁的控制台：一排開關、旋鈕與進度條，標示「列印中」。 | 1.2 m | 待畫 |

## 錨點電話亭（街角）（`anchor_phone_booth`）

- 章：1 起（每章）　類型：探索（存檔點）
- 畫面：發光的老式電話亭，玻璃有雨痕，青色的光；死後在這裡醒來。
- 色調與光：夜、雨；一小塊青色冷光（電話亭）在深藍灰的巷口，積水反光。
- 背景：完成（`art/environment/scenes/anchor_phone_booth.webp`）
- 狀態變體：1 起每章的存檔點；6 沈望的電話（暴雨中）；9 最後一座亭子，話筒的聲音換了。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `anchor_phone_booth__phone_booth` | 錨點電話亭 | 老式公共電話亭，玻璃有雨痕，青色光；存檔點與復原醒來的地方。 | 2.5 m | 完成 |
| `anchor_phone_booth__restore_arrow_sign` | 「復原室→」指示牌 | 電線桿上的發光箭頭指示牌，指向最近的復原室。 | 1.6 m | 完成 |
| `anchor_phone_booth__backup_kiosk` | 備份狀態燈箱 | 路邊的小燈箱，一排 LED 顯示最近備份；每次存檔會亮。 | 1.4 m | 完成 |
| `anchor_phone_booth__poster_wall` | 破舊的海報牆 | 一整面貼滿又撕掉的海報：復原廣告「再來一次」被塗鴉劃掉。 | 2.2 m | 待畫 |
| `anchor_phone_booth__flicker_lamp_post` | 忽明忽暗的路燈 | 老路燈，燈罩破了一角，光閃得不穩。 | 3.4 m | 待畫 |
| `anchor_phone_booth__trash_bags` | 垃圾袋堆 | 牆角的黑色垃圾袋、紙箱與一隻破傘。 | 0.9 m | 待畫 |
| `anchor_phone_booth__gutter_downpipe` | 落水管與水柱 | 牆上的落水管，破口處流下一道水柱，地上濺起水花。 | 2.8 m | 待畫 |
| `anchor_phone_booth__leaning_bicycle` | 靠牆的舊腳踏車 | 靠在牆邊的鐵腳踏車，車籃裡有一把收起的傘。 | 1.1 m | 待畫 |
| `anchor_phone_booth__shutter_graffiti` | 鐵捲門與塗鴉 | 拉下的鐵捲門，噴著「還沒有人付」的塗鴉與一個畫掉的雲。 | 2.2 m | 待畫 |
| `anchor_phone_booth__news_rack` | 報攤架 | 電話亭旁的報攤架：頭版是氣象預報與降雨量。 | 1.5 m | 待畫 |

## 復原館（夜）（`revival_lounge`）

- 章：1（變體 4 酒客）　類型：演出
- 畫面：復原室旁的夜間店：酒、復原餐、低燈；吧台後面是阿梨的位置。陌生人。
- 色調與光：夜；低燈的琥珀色與洋紅、青色霓虹，煙與酒的紫；暖而曖昧。
- 背景：完成（`art/environment/scenes/revival_lounge.webp`）
- 狀態變體：1 復原夜與阿梨；間章一 客人簿在同一棟的包廂（另立場景 guest_book_room）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `revival_lounge__bar_counter` | 吧台與高腳凳 | 長吧台、酒架、一排高腳凳；阿梨站的位置。 | 1.9 m | 完成 |
| `revival_lounge__menu_board` | 「復原餐」菜單看板 | 發光菜單板，寫著復原餐與酒；復原夜的人來這裡找東西吃。 | 1.2 m | 完成 |
| `revival_lounge__booth_sofa` | 卡座沙發與小桌燈 | 紅色皮沙發卡座與桌上的小檯燈；低聲說話的地方。 | 1.2 m | 完成 |
| `revival_lounge__neon_glass_sign` | 霓虹酒杯招牌 | 掛在牆上的霓虹雞尾酒杯，粉紅與青色閃爍。 | 0.9 m | 待畫 |
| `revival_lounge__jukebox` | 點唱機 | 復古點唱機，彩色燈管與唱片窗；播放著慢歌。 | 1.6 m | 待畫 |
| `revival_lounge__corner_plant_string_lights` | 盆栽與小燈串 | 角落的大葉盆栽纏著小黃燈串。 | 1.7 m | 待畫 |
| `revival_lounge__bottle_wall_shelf` | 發光酒瓶牆架 | 牆上的玻璃酒架，一瓶瓶彩色酒液被燈光照得發亮。 | 1.5 m | 待畫 |
| `revival_lounge__round_table_stools` | 圓桌與高腳凳 | 兩張小圓桌配高腳凳，桌上一支小蠟燭。 | 1.0 m | 待畫 |
| `revival_lounge__hat_coat_rack` | 衣帽架 | 入口的木衣帽架，掛著幾件濕外套與一頂帽子；沒有人。 | 1.8 m | 待畫 |
| `revival_lounge__meal_cart` | 復原餐餐車 | 推車上的粥鍋、湯鍋與一疊碗，冒著熱氣。 | 1.2 m | 待畫 |

## 天亮的麵攤（`dawn_noodle_stall`）

- 章：1　類型：演出
- 畫面：凌晨灰藍的光，一碗宵夜，蒸氣；「不收錢。」「那我欠你。」「那就欠著。」
- 色調與光：凌晨、雨將停；灰藍的天與濕地面，麵攤一點暖黃的燈與白色蒸氣。
- 背景：完成（`art/environment/scenes/dawn_noodle_stall.webp`）
- 狀態變體：1 天亮的宵夜；7 的日照區麵攤另立場景（sunlit_noodle_stall）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `dawn_noodle_stall__ali_noodle_cart` | 阿梨的小麵攤車 | 推車式小麵攤：鍋裡冒蒸氣、暖黃燈泡、一面小招牌空白著；名字還沒想好。 | 2.2 m | 完成 |
| `dawn_noodle_stall__noodle_bowls_table` | 矮桌與兩碗麵 | 路邊的矮桌、兩張小板凳、兩碗熱麵；「欠著」的那一碗。 | 0.85 m | 完成 |
| `dawn_noodle_stall__hanging_lantern` | 掛著的小燈籠 | 屋簷下的紙燈籠，在晨風裡輕輕擺動。 | 1.1 m | 完成 |
| `dawn_noodle_stall__stool_stack` | 疊起來的塑膠椅 | 收起來的紅色塑膠椅，一疊疊在牆邊。 | 1.2 m | 待畫 |
| `dawn_noodle_stall__shop_shutter_dawn` | 拉下的小店鐵門 | 還沒開門的小店，鐵捲門上有一張褪色的招牌。 | 2.3 m | 待畫 |
| `dawn_noodle_stall__cat_box_bed` | 紙箱貓窩 | 紙箱改成的小貓窩，一隻虎斑貓縮成一團睡著。 | 0.5 m | 待畫 |
| `dawn_noodle_stall__broth_stove` | 高湯爐與大鍋 | 地上的瓦斯爐與一口大湯鍋，咕嘟咕嘟冒著蒸氣；高湯要熬一整晚。 | 0.9 m | 待畫 |
| `dawn_noodle_stall__noodle_making_table` | 製麵桌 | 撒著麵粉的木桌：一團麵、擀麵棍與切麵刀；阿梨在練習。 | 0.9 m | 待畫 |
| `dawn_noodle_stall__dawn_string_lights` | 小燈串 | 屋簷下的一串黃色小燈泡，隨風輕輕擺動。 | 1.2 m | 待畫 |
| `dawn_noodle_stall__blank_sign_board` | 還沒寫名字的招牌 | 斜靠在牆邊的一塊空白木招牌，只有一個畫了一半的碗；名字還沒想好。 | 1.0 m | 待畫 |

## 霓虹市集（`neon_market`）

- 章：2（變體 6、A）　類型：探索
- 畫面：密集的攤位、廣告螢幕、麵攤、雨棚；螢幕上沈望的週年演說；氣象預報跑馬燈。沿路有被清過的路。
- 色調與光：夜到凌晨、雨稍大；市集的紅、粉、青，雜亂飽和，廣告光在濕地上反光。
- 背景：完成（`art/environment/scenes/neon_market.webp`）
- 狀態變體：2 熱鬧（週年演說、跑馬燈）→ 6 廣播之後，人們繼續排隊復原 → A 結局洪水退後，攤位歪斜、雨沒停。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `neon_market__speech_screen` | 週年演說大螢幕 | 市集的大螢幕：天穹週年演說，沈望的臉（白髮的老婦）；每章鋪陳的最終反派。 | 2.6 m | 完成 |
| `neon_market__weather_ticker` | 氣象跑馬燈看板 | LED 跑馬燈：「今夜降雨量偏多，復原申請量高峰」；雨與復原量的伏筆。 | 0.8 m | 完成 |
| `neon_market__debt_desk` | 收帳人的桌子與債務簿 | 鋪著債務簿、收據與算盤的折疊桌；對帳謎：金額差一筆。 | 1.1 m | 完成 |
| `neon_market__produce_stall` | 蔬果攤 | 條紋雨棚下的蔬果攤：一箱箱濕漉漉的菜、掛秤與一盞吊燈。 | 2.2 m | 待畫 |
| `neon_market__ad_pillar` | 旋轉廣告燈柱 | 圓柱形的廣告燈柱：循環播放藥、保險與復原廣告，亮得刺眼。 | 3.0 m | 待畫 |
| `neon_market__tv_stack_stall` | 舊電視攤 | 疊成一面牆的舊電視，其中一台在放雜訊畫面。 | 1.8 m | 待畫 |
| `neon_market__cut_lock_gate` | 鎖被剪斷的鐵門 | 鐵柵門的鏈條被乾淨地剪斷，鎖掉在地上；有人先走過這條路。 | 1.9 m | 待畫 |
| `neon_market__dripping_tarp` | 滴水的帆布雨棚 | 塑膠帆布雨棚積著水，邊緣不斷滴落水串。 | 1.6 m | 待畫 |
| `neon_market__tea_urn` | 熱水大茶桶 | 攤位旁的大鋁茶桶與塑膠凳，白煙裊裊。 | 0.9 m | 待畫 |
| `neon_market__permit_board` | 攤位許可公告板 | 公告欄上貼著蓋章的攤位許可申請單；阿梨要的是一個攤位與一張許可。 | 1.4 m | 待畫 |

## 阿勇的據點（`yong_hideout`）

- 章：2　類型：探索＋頭目
- 畫面：舊倉庫改成的帳房：債務簿、算盤、小薇的房間（一張小床、玩偶）；阿勇的平台後面是小薇。
- 色調與光：夜；倉庫的暗紅與鏽橙，吊燈的暖黃；後方高台小房間透出柔和的暖光。
- 背景：完成（`art/environment/scenes/yong_hideout.webp`）
- 狀態變體：2 頭目戰場地；阿勇的平台後面是小薇。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `yong_hideout__ledger_wall` | 債務簿牆 | 整面牆的債務簿與帳櫃，每本的書脊寫著人名與日期。 | 2.3 m | 完成 |
| `yong_hideout__banker_desk` | 阿勇的帳房大桌 | 橡木大桌、綠罩檯燈、大算盤與錢箱；收帳人頭目的位置。 | 1.2 m | 完成 |
| `yong_hideout__xiaowei_bed` | 小薇的小床與兔子玩偶 | 高台小房間裡的單人小床、玩偶與夜燈；阿勇的錨人，十二歲。 | 0.85 m | 完成 |
| `yong_hideout__vault_safe` | 大保險櫃 | 整面牆那麼大的老保險櫃：黃銅轉盤、鉚釘鐵門；收來的錢都放在這裡。 | 2.2 m | 待畫 |
| `yong_hideout__teller_cage` | 鐵欄收款窗口 | 帶鐵欄杆的收款窗口與一個小旋轉托盤；債務人在這裡低著頭。 | 2.0 m | 待畫 |
| `yong_hideout__pendant_bulbs` | 三盞吊燈 | 從橫樑垂下來的三盞工業吊燈，暖黃色。 | 1.0 m | 待畫 |
| `yong_hideout__toy_corner` | 玩偶與積木 | 小薇房間地上的積木、小火車與一隻布偶。 | 0.5 m | 待畫 |
| `yong_hideout__platform_stairs` | 通往高台的木階 | 通往小薇房間高台的木階梯，欄杆上掛著一件小外套。 | 1.6 m | 待畫 |
| `yong_hideout__debt_blackboard` | 債務黑板 | 牆上的黑板：名字、金額與利息，粉筆字被擦掉又寫上。 | 1.4 m | 待畫 |
| `yong_hideout__money_sacks` | 錢袋與錢箱 | 地上堆著的帆布袋與鐵皮錢箱。 | 0.8 m | 待畫 |

## 收音機修理（當舖工作檯）（`radio_workbench`）

- 章：2　類型：據點
- 畫面：工作檯上拆開的收音機；調頻時出現雜訊與一個平淡念名字的聲音（蘇）；小謎，伏筆 T8。
- 色調與光：夜；檯燈的暖黃圈在深褐色的工作角落，收音機刻度盤的小光與示波器的綠光。
- 背景：待畫（`art/environment/scenes/radio_workbench.webp`）
- 狀態變體：2 收音機修理小謎 → 4 收音機放著鷺愛聽的歌（悼念）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `radio_workbench__radio_open_bench` | 拆開的老收音機 | 工作檯上拆開殼的收音機：真空管、線圈、刻度盤亮著；調頻時出現念名字的聲音。 | 1.0 m | 待畫 |
| `radio_workbench__pegboard_tools` | 掛滿工具的洞洞板 | 洞洞板牆：鉗子、螺絲起子、焊槍、一圈圈電線；每件工具有白線描出的位置。 | 1.5 m | 待畫 |
| `radio_workbench__oscilloscope` | 示波器 | 綠色波形的老示波器；調頻時波形跳動，念名單的聲音出現時會抖。 | 0.7 m | 待畫 |
| `radio_workbench__worn_stool` | 木凳與靠墊 | 磨得發亮的木圓凳，椅面上一塊舊靠墊。 | 0.7 m | 待畫 |
| `radio_workbench__parts_drawers` | 零件小抽屜櫃 | 牆上一格一格的小抽屜，每個貼著電阻、電容的標籤。 | 1.2 m | 待畫 |
| `radio_workbench__magnifier_lamp` | 放大鏡檯燈 | 彈簧臂上的放大鏡燈，一圈白色環形燈照著工作區。 | 1.1 m | 待畫 |
| `radio_workbench__radio_shelf` | 待修收音機架 | 架上一排待修的收音機，每一台掛著寫著症狀的標籤。 | 1.4 m | 待畫 |
| `radio_workbench__cassette_deck` | 卡式錄音機 | 桌上的舊卡式錄音機，帶子轉著；念名單的聲音被錄了下來。 | 0.4 m | 待畫 |
| `radio_workbench__soldering_station` | 焊接台 | 烙鐵架、焊錫與一縷細煙；剛焊完一個接點。 | 0.5 m | 待畫 |
| `radio_workbench__wire_spool_rack` | 電線卷架 | 牆上的木架，一卷卷彩色電線與一束天線線。 | 1.1 m | 待畫 |

## 客人簿（復原館包廂）（`guest_book_room`）

- 章：間章一（第二章之後）　類型：間章
- 畫面：復原館的包廂：三位客人、三種氣氛（死去的女兒、妻子、朋友）；阿梨的客人簿攤在桌上。阿梨視角，非戰鬥。
- 色調與光：夜；窗簾與紙燈的暖橙粉色，朦朧、親密、帶一點哀傷。
- 背景：待畫（`art/environment/scenes/guest_book_room.webp`）
- 狀態變體：間章一（阿梨視角）專用；第一章復原館的同一棟建築。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `guest_book_room__guest_book_table` | 客人簿與矮桌 | 矮桌上攤開的客人簿、茶具與一支筆；問、聽、記的操作點。 | 0.75 m | 待畫 |
| `guest_book_room__paper_floor_lamp` | 落地紙燈 | 包廂角落的紙罩落地燈，暖橙色的柔光。 | 1.5 m | 待畫 |
| `guest_book_room__memorial_shelf` | 遺照與蠟燭小櫃 | 小櫃上的相框與蠟燭：客人帶來的、死去的人的樣子。 | 1.3 m | 待畫 |
| `guest_book_room__loveseat` | 小沙發與靠墊 | 包廂裡的深紅色小沙發，椅背搭著一條披肩。 | 0.9 m | 待畫 |
| `guest_book_room__burgundy_curtain` | 厚絨窗簾 | 垂到地上的酒紅色厚窗簾，邊緣微微飄動。 | 2.3 m | 待畫 |
| `guest_book_room__keepsakes_tray` | 客人帶來的紀念物 | 漆盤上的三件東西：小孩的鞋、女人的圍巾、一支口琴。 | 0.45 m | 待畫 |
| `guest_book_room__incense_burner` | 香爐與煙 | 銅香爐裡插著三炷香，細煙一縷一縷往上飄。 | 0.5 m | 待畫 |
| `guest_book_room__folding_screen` | 屏風 | 四扇木屏風，畫著一片淡淡的雨與一座橋。 | 1.8 m | 待畫 |
| `guest_book_room__tea_cart` | 茶具推車 | 小推車上的鐵壺、茶杯與一碟點心。 | 0.9 m | 待畫 |
| `guest_book_room__wall_scroll` | 掛軸 | 牆上的掛軸，兩個大字：「相逢」。 | 1.2 m | 待畫 |

## 夾層（`mezzanine`）

- 章：3　類型：探索
- 畫面：港區與日照區之間的結構層：管線、廢棄通道、昏暗的緊急燈；往上走漸亮。垂直探索的前半。
- 色調與光：白天但幾乎照不到光；灰綠、鏽橙的管線，緊急燈的琥珀色，右上方漸漸有一絲冷白的天光。
- 背景：待畫（`art/environment/scenes/mezzanine.webp`）
- 狀態變體：3 凜垂直探索的前半；往上漸亮，連到日照區邊緣。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `mezzanine__pipe_manifold` | 管線閥門組 | 兩層樓高的粗管線與閥門組，滴著冷凝水；夾層的主要結構。 | 3.0 m | 待畫 |
| `mezzanine__amber_lamp_cluster` | 琥珀色緊急燈組 | 牆上並排的三盞緊急燈：琥珀色，其中一盞閃爍。 | 0.9 m | 待畫 |
| `mezzanine__hatch_ladder` | 維修爬梯與頂艙 | 通往上層的細長鐵爬梯，頂端一個半開的圓艙口，透下一點天光。 | 3.0 m | 待畫 |
| `mezzanine__grating_stairs` | 鐵網階梯 | 斜著往上的鐵網樓梯與扶手，每一階都在滴冷凝水。 | 2.8 m | 待畫 |
| `mezzanine__hanging_cables` | 垂掛的線纜束 | 從天花板橋架垂下來的粗纜線，末端的接頭晃著小綠燈。 | 2.2 m | 待畫 |
| `mezzanine__exhaust_fan` | 大型換氣扇 | 牆上的巨大換氣扇，扇葉停了一半，縫隙透出微光。 | 2.4 m | 待畫 |
| `mezzanine__abandoned_cart` | 廢棄的推車與工具箱 | 停在通道邊的平板推車，上面一只工具箱與捲好的水管。 | 1.0 m | 待畫 |
| `mezzanine__service_door` | 維修通道鐵門 | 貼著警告標誌的灰色鐵門：「夾層維修　非工作人員禁止進入」。 | 2.2 m | 待畫 |
| `mezzanine__drip_basin` | 冷凝水盆 | 管線下接水的金屬盆，水面一圈圈漣漪。 | 0.6 m | 待畫 |
| `mezzanine__daylight_shaft` | 天光井口 | 天花板上一個垂直通風井，一道淡白的天光灑下，灰塵在光裡飄。 | 3.0 m | 待畫 |

## 日照區街道（`sunlit_district`）

- 章：3（邊緣）、7　類型：探索
- 畫面：乾淨的街道、整齊的樹、玻璃外的陽光（凜第一次站在光裡）；第七章走進去：白天、唯一的晴天，畫面最亮。
- 色調與光：白天；白、淡金、淡藍天，強烈柔和的陽光與乾淨的陰影；全作最亮。
- 背景：待畫（`art/environment/scenes/sunlit_district.webp`）
- 狀態變體：3 隔著玻璃（邊緣，凜第一次站在光裡）→ 7 走進去（最亮，老 K 瞇著眼說「太亮了」）→ B 結局住進去。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `sunlit_district__glass_window_wall` | 落地玻璃牆 | 夾層出口的大片玻璃，外面是陽光與淡藍的天；凜第一次看到真正的陽光。 | 2.6 m | 待畫 |
| `sunlit_district__street_tree_planter` | 整齊的行道樹與花槽 | 修剪成圓球的行道樹種在白色花槽裡；乾淨得不像港區。 | 3.2 m | 待畫 |
| `sunlit_district__white_bench` | 白色長椅 | 乾淨的白色公園長椅，日光下的第一個座位。 | 0.85 m | 待畫 |
| `sunlit_district__glass_balcony` | 白色玻璃陽台 | 乾淨的玻璃陽台，欄杆上掛著白色的花盆與一條晾乾的毛巾。 | 2.6 m | 待畫 |
| `sunlit_district__street_clock` | 街頭立鐘 | 街邊的立柱鐘，指針與樹影一樣整齊。 | 3.0 m | 待畫 |
| `sunlit_district__flower_planters` | 花槽與白花 | 一排白色花槽，開滿白色與淡黃的花。 | 0.8 m | 待畫 |
| `sunlit_district__sorting_bins` | 分類垃圾桶 | 三個顏色分明的垃圾桶：白、淡藍、淡綠，乾淨得沒有一點污漬。 | 1.0 m | 待畫 |
| `sunlit_district__info_kiosk` | 導覽亭 | 街角的導覽螢幕亭：地圖、天氣與一個微笑的圖示。 | 1.9 m | 待畫 |
| `sunlit_district__cafe_awning_set` | 咖啡座與遮陽篷 | 白黃條紋遮陽篷下兩張小桌椅與一杯咖啡。 | 2.3 m | 待畫 |
| `sunlit_district__water_fountain_post` | 飲水臺 | 石柱上的飲水臺，水弧線落進小水槽，陽光裡閃閃發亮。 | 1.0 m | 待畫 |

## 晴岸（接待與樣品房）（`clearwater`）

- 章：3、B 結局　類型：探索／演出
- 畫面：白牆、大窗、安靜；林小姐的辦公桌；樣品房：床、窗、一把椅子。凜在這裡替老 K 算窗戶的方向。B 結局的房間。
- 色調與光：白天；全白與淡木色，大窗外的陽光與淡藍的天；非常亮、非常安靜，安靜得有人睡不著。
- 背景：待畫（`art/environment/scenes/clearwater.webp`）
- 狀態變體：3 樣品房與接待（凜站在窗邊算窗戶的方向）→ B 結局：老 K 的房間（窗邊雨聲機、窗台上一枚舊硬幣）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `clearwater__model_bed` | 樣品房的床 | 鋪得一絲不苟的白色單人床，沒有人睡過。 | 0.7 m | 待畫 |
| `clearwater__reception_desk` | 林小姐的接待桌 | 白色接待桌：名牌、小盆花、平板與一疊宣傳冊；「這裡很安靜，安靜得有人睡不著。」 | 1.15 m | 待畫 |
| `clearwater__window_chair` | 窗邊的一把椅子 | 樣品房窗邊的原木椅與小圓几：凜站在這裡想像老 K 坐著。 | 1.0 m | 待畫 |
| `clearwater__white_curtains` | 白紗窗簾 | 落地窗邊的白色薄紗窗簾，被一點空調風吹得微微飄動。 | 2.4 m | 待畫 |
| `clearwater__rain_sound_machine` | 雨聲機與床頭几 | B 結局：床邊的小几上一台雨聲機，指示燈亮著；因為這裡太安靜了。 | 0.75 m | 待畫 |
| `clearwater__sill_with_coin` | 窗台與舊硬幣 | B 結局：窗台上有一枚舊硬幣，他不知道是誰放的（船錢）。 | 0.5 m | 待畫 |
| `clearwater__brochure_rack` | 宣傳冊架與價目表 | 接待處的小架：晴岸的介紹冊與價目表，480,000 的頭期款印得很小。 | 1.3 m | 待畫 |
| `clearwater__plain_wall_clock` | 沒有聲音的掛鐘 | 牆上一只極簡的白色掛鐘，秒針無聲地走。 | 0.6 m | 待畫 |
| `clearwater__tall_floor_plant` | 落地大植物 | 角落的一棵大琴葉榕，葉子乾淨得發亮。 | 1.9 m | 待畫 |
| `clearwater__sun_chart_notes` | 凜算窗戶方向的紙 | 桌上凜的手寫紙：窗戶方位、日照時數與老 K 的名字，被塗了又寫。 | 0.45 m | 待畫 |

## 診所（錨庫分站）（`clinic`）

- 章：3　類型：探索＋頭目
- 畫面：候診室、報表櫃、牆上沈望的一句話：「讓每個人都有第二次。」；守門人的櫃台。對帳謎；頭目守門人。
- 色調與光：白天；冷白日光燈與淡綠的牆、冷灰地板；清潔、官方、有點冷。
- 背景：待畫（`art/environment/scenes/clinic.webp`）
- 狀態變體：3 診所：對帳謎（耗損報表被竄改）、頭目守門人。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `clinic__report_cabinet` | 報表櫃 | 一排貼著月份標籤的檔案櫃；對帳謎的報表在這裡。 | 1.9 m | 待畫 |
| `clinic__waiting_chairs` | 候診椅排 | 固定在牆邊的一排灰色塑膠椅，椅背貼著號碼。 | 0.85 m | 待畫 |
| `clinic__quote_plaque` | 「讓每個人都有第二次」牆牌 | 大廳牆上的大牌：沈望的一句話，旁邊她的簽名；每章鋪陳。 | 1.1 m | 待畫 |
| `clinic__reception_window` | 掛號窗口 | 玻璃窗口與小托盤，後面是空著的座位與一台電腦。 | 1.8 m | 待畫 |
| `clinic__queue_number_display` | 叫號顯示螢幕 | 天花板下的紅色叫號器：「0 號」，沒有人。 | 0.5 m | 待畫 |
| `clinic__gatekeeper_desk` | 守門人的櫃台 | 擦得一塵不染的接待櫃台：訪客簿、一個小鈴與一張「請預約」的牌子。 | 1.2 m | 待畫 |
| `clinic__water_dispenser` | 飲水機 | 牆邊的飲水機，水桶裡的氣泡緩緩上升。 | 1.3 m | 待畫 |
| `clinic__anchor_room_door` | 錨椅間的門牌 | 走廊上的門：「錨椅間 3　使用中」，紅燈亮著。 | 2.2 m | 待畫 |
| `clinic__fern_pot` | 候診室的蕨類 | 角落的大蕨類，葉子有點發黃。 | 1.1 m | 待畫 |
| `clinic__public_rate_poster` | 「耗損輕微」宣導海報 | 牆上的官方海報：「錨人耗損輕微　僅 3%」；真實的數字是 11%。 | 1.3 m | 待畫 |

## 天穹辦公室外（`tianqiong_corridor`）

- 章：3　類型：演出
- 畫面：走廊，玻璃牆，老 K 與葉在室內說話，凜在外面聽不見聲音，只能讀唇或透過門縫。「她不能再死了。」
- 色調與光：白天；冷白的日光、玻璃的反光、淡藍灰；高級、安靜、疏離。
- 背景：待畫（`art/environment/scenes/tianqiong_corridor.webp`）
- 狀態變體：3 凜在外面透過玻璃與門縫看老 K 與葉；5 葉在當舖來訪是另一場景（用當舖）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `tianqiong_corridor__frosted_partition` | 霧面玻璃隔間 | 半透明的霧面玻璃隔間，裡面有模糊的人影輪廓（不畫人）；聽不見聲音。 | 2.6 m | 待畫 |
| `tianqiong_corridor__office_door_ajar` | 門縫透光的辦公室門 | 一扇沒關緊的辦公室門，門縫透出一線光；凜從這裡聽見「她不能再死了」。 | 2.3 m | 待畫 |
| `tianqiong_corridor__modern_planter` | 走廊的白色盆栽 | 白色圓柱花盆裡的細葉植物；連一片枯葉都沒有。 | 1.5 m | 待畫 |
| `tianqiong_corridor__sleek_bench` | 走廊長凳 | 磨光的白色長凳，只有一個靠墊；沒有人坐過的樣子。 | 0.55 m | 待畫 |
| `tianqiong_corridor__wall_light_strip` | 牆面燈條 | 牆上的冷白色長條燈，一小段閃了一下。 | 0.35 m | 待畫 |
| `tianqiong_corridor__glass_door_swing` | 玻璃對開門 | 辦公區的玻璃對開門，把手是一條細長的不鏽鋼棒。 | 2.4 m | 待畫 |
| `tianqiong_corridor__water_cooler` | 辦公室飲水機 | 走廊角落的飲水機，一疊紙杯整齊地疊著。 | 1.2 m | 待畫 |
| `tianqiong_corridor__cloud_sculpture` | 雲的雕塑 | 走廊盡頭的白色抽象雕塑，一朵凝固的雲，下面的銘牌寫著天穹的名字。 | 1.5 m | 待畫 |
| `tianqiong_corridor__exec_elevator` | 高層電梯門 | 走廊底的電梯：雙開不鏽鋼門，上方的樓層顯示燈亮著。 | 2.4 m | 待畫 |
| `tianqiong_corridor__portrait_frame` | 巨幅畫像 | 牆上的巨幅畫像：一位白髮老婦人，神情平靜，下面寫著「沈望」。 | 2.0 m | 待畫 |

## 安養病房（用盡者的病房）（`nursing_ward`）

- 章：4、間章二　類型：探索／演出
- 畫面：長走廊般的病房，一排病床，窗外是雨；棠的床邊有櫃子；鷺每週日來；一首哼的歌。回放謎。
- 色調與光：陰、大雨；病房的灰綠、冷白日光燈，窗外灰藍的雨光；安靜到能聽見雨。
- 背景：待畫（`art/environment/scenes/nursing_ward.webp`）
- 狀態變體：4 凜的路線（回放櫃子的謎）↔ 間章二：鷺的路線，同一條走廊。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `nursing_ward__bedside_locker` | 棠的床邊櫃 | 回放謎的櫃子：櫃面有指甲敲過的三道痕；鷺的信就在裡面。 | 1.1 m | 待畫 |
| `nursing_ward__heart_monitor_stand` | 點滴架與生命監視器 | 點滴架旁的心電監視器，綠色波形緩緩跳動；病房裡唯一會動的光。 | 1.9 m | 待畫 |
| `nursing_ward__folded_wheelchair` | 折起的輪椅 | 靠牆折起的輪椅，扶手上掛著一條小毯子；等人來推的樣子。 | 1.0 m | 待畫 |
| `nursing_ward__ward_bed` | 病房的空床 | 白床單鋪得平整的病床，床欄升起；棠的床，她不記得誰每週日來。 | 0.95 m | 待畫 |
| `nursing_ward__rain_window_wide` | 雨窗 | 高大的窗戶，玻璃上雨痕一道一道，外面是灰藍的天。 | 2.2 m | 待畫 |
| `nursing_ward__visitor_chair` | 探訪椅與探訪袋 | 床邊的小圓凳，椅面上放著一只紙袋與一把收好的傘；鷺每週日坐的位置。 | 0.7 m | 待畫 |
| `nursing_ward__bed_curtain` | 床簾 | 沿著軌道拉到一半的淡綠色床簾，輕輕晃動。 | 1.9 m | 待畫 |
| `nursing_ward__bedside_radio` | 床頭的小收音機 | 床頭櫃上的小塑膠收音機，旋鈕旁有一個小紅燈，正播著一首沒有歌詞的曲子。 | 0.4 m | 待畫 |
| `nursing_ward__sunday_calendar` | 週日圈起來的日曆 | 牆上的月曆，每個週日都用紅筆圈起來，圈得整整齊齊。 | 0.7 m | 待畫 |
| `nursing_ward__nurse_cart` | 護理推車 | 走廊上的護理推車：藥盒、體溫計、一疊病歷夾與一個小鈴。 | 1.0 m | 待畫 |

## 廢棄廠房（`abandoned_factory`）

- 章：4、間章二　類型：探索＋頭目
- 畫面：鏽蝕的機台、吊鉤、斷掉的輸送帶、打翻的油；天穹清理隊的白色裝甲；場地逐步被擦掉。
- 色調與光：陰、雨大；鏽橙與冷灰，閃爍的冷白日光燈，打翻的油的暗反光。
- 背景：待畫（`art/environment/scenes/abandoned_factory.webp`）
- 狀態變體：4 頭目戰場地（清理隊隊長，場地逐步被擦掉）↔ 間章二：鷺的路線（她替凜清出的捷徑）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `abandoned_factory__broken_conveyor` | 斷掉的輸送帶 | 輸送帶從滾輪上垂下一截，斷口翹起；廠房被放棄的樣子。 | 1.4 m | 待畫 |
| `abandoned_factory__hook_chain` | 吊鉤與鏈條 | 從天車軌垂下的粗鏈條與大鉤，輕輕擺動；頭目戰裡可以抓取的東西。 | 3.0 m | 待畫 |
| `abandoned_factory__oil_drum_spill` | 打翻的油桶 | 歪倒的藍色油桶，黑色的油拖出一道；清理隊來過的痕跡。 | 0.9 m | 待畫 |
| `abandoned_factory__press_machine` | 鏽蝕的沖壓機 | 大型沖壓機，上模高高懸著，臺面積滿鐵屑與油污。 | 3.4 m | 待畫 |
| `abandoned_factory__broken_skylight` | 破碎的天窗 | 屋頂的玻璃天窗破了一半，雨與灰色的天光漏進來。 | 1.8 m | 待畫 |
| `abandoned_factory__tube_lamps` | 閃爍的日光燈 | 兩根吊著的日光燈管，一根不停閃，一根暗了一半。 | 0.8 m | 待畫 |
| `abandoned_factory__scrap_pile` | 廢料堆 | 堆在牆邊的鐵皮、齒輪與斷掉的軸，滿是鏽。 | 1.1 m | 待畫 |
| `abandoned_factory__cleaner_gear_case` | 清理隊的白色裝備箱 | 打開的白色硬殼裝備箱，裡面是整齊收好的白色護甲片；乾淨得和廠房格格不入。 | 1.1 m | 待畫 |
| `abandoned_factory__power_panel` | 配電盤 | 牆上的灰色配電盤，門開著，裡面冒著小火花，紅燈閃爍。 | 1.7 m | 待畫 |
| `abandoned_factory__rust_tank` | 鏽蝕的儲槽 | 一只立式圓儲槽，槽身滲著鐵鏽水，下方一圈黑色的油漬。 | 2.6 m | 待畫 |

## 廠房的辦公室（`factory_office`）

- 章：4　類型：演出
- 畫面：保險櫃、帳本；鷺倒下的地方。「你自己看。」
- 色調與光：陰、雨；辦公桌檯燈的暖黃圈與窗外灰藍的雨光，舊紙與灰塵的褐黃。
- 背景：待畫（`art/environment/scenes/factory_office.webp`）
- 狀態變體：4 帳本、鷺倒下的地方（劇情演出）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `factory_office__wall_safe` | 半開的保險櫃 | 灰色鋼製保險櫃，門半開，裡面空了一半；帳本就放在這裡。 | 1.5 m | 待畫 |
| `factory_office__desk_with_ledger` | 辦公桌與檯燈 | 老木辦公桌：檯燈、攤開的帳本、一枚小晶片；整張桌子積著灰。 | 1.2 m | 待畫 |
| `factory_office__bulletin_board` | 公布欄 | 軟木公布欄，釘著泛黃的班表與通知；字跡還讀得出來。 | 1.1 m | 待畫 |
| `factory_office__toppled_chair` | 倒下的辦公椅 | 翻倒的轉椅，輪子還在微微地轉。 | 0.9 m | 待畫 |
| `factory_office__blinds_rain_window` | 百葉窗與雨 | 半拉起的百葉窗，窗外是灰色的雨；窗台積著灰。 | 1.7 m | 待畫 |
| `factory_office__filing_cabinet` | 檔案櫃 | 綠色的四層鐵檔案櫃，抽屜被拉開了兩層，紙散在裡面。 | 1.4 m | 待畫 |
| `factory_office__scattered_papers` | 散落一地的紙 | 地上散亂的文件、一本被踩髒的帳冊與一張被撕開的信封。 | 0.35 m | 待畫 |
| `factory_office__stopped_clock` | 停住的掛鐘 | 牆上的圓形掛鐘，玻璃裂了，指針停在半夜。 | 0.55 m | 待畫 |
| `factory_office__hotplate_kettle` | 電爐與水壺 | 桌角的小電爐與舊水壺，水壺蓋掀開，裡面是乾的。 | 0.5 m | 待畫 |
| `factory_office__team_photo_frame` | 工廠合照 | 桌上的相框：一排穿工作服的人與一面橫幅，臉都小得看不清。 | 0.45 m | 待畫 |

## 當舖地下室（`basement`）

- 章：5　類型：探索／演出
- 畫面：全作最重要的房間：一張錨椅、一個頭盔、一本帳、一疊給她的錢、收屍人名單、老 K 的筆記本；扶手上一枚硬幣；一個小暖爐。
- 色調與光：室內；地下室的暗、黃與紙的顏色；手電筒與頭盔指示燈的點光，小暖爐的橙光，水泥牆的灰。
- 背景：待畫（`art/environment/scenes/basement.webp`）
- 狀態變體：5 打開之後的地下室（只有第五章與間章三結尾）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `basement__anchor_chair` | 錨椅 | 老 K 私設的錨椅：舊診椅改裝，纏著線纜，扶手上一枚硬幣（船錢）；全作最重要的家具。 | 1.3 m | 待畫 |
| `basement__anchor_helmet` | 讀取頭盔與支架 | 懸在錨椅旁的讀取頭盔，電線垂下，指示燈一閃一閃。 | 1.0 m | 待畫 |
| `basement__kerosene_heater` | 小暖爐 | 地下室的小煤油暖爐，橙色的火光映在牆上；老 K 一個人待在這裡的證據。 | 0.75 m | 待畫 |
| `basement__notebook_desk` | 老 K 的筆記本與小書桌 | 小木桌上攤開的筆記本：「她不吃紅蘿蔔」「她第一天來把鞋脫在門外」；全作最重的一本書。 | 0.85 m | 待畫 |
| `basement__cash_envelopes` | 一疊給她的錢 | 用橡皮筋捆好的鈔票與一個信封，信封上寫著「給凜」。 | 0.4 m | 待畫 |
| `basement__fee_ledger` | 手續費帳本 | 攤開的帳本：一欄一欄的小數字，每月一筆，合計 52,000，旁邊標著「給凜」。 | 0.4 m | 待畫 |
| `basement__name_list_board` | 收屍人名單 | 牆上的軟木板，釘著六個名字與日期；每月同一天付現。 | 1.3 m | 待畫 |
| `basement__chip_reader` | 記憶晶片讀取器 | 桌上的小讀取器：插著一枚晶片，螢幕上一個模糊的、笑著的輪廓。 | 0.45 m | 待畫 |
| `basement__army_cot` | 行軍床與毯子 | 牆角的摺疊行軍床，一條灰毯子與一個枕頭；老 K 守夜的地方。 | 0.6 m | 待畫 |
| `basement__old_crt_screen` | 舊錄影螢幕 | 角落的舊映像管螢幕，只剩一片雪花雜訊的光。 | 0.75 m | 待畫 |

## 洪水的港區（`flood_street`）

- 章：5（間章三）、8　類型：探索（非戰鬥）／間章
- 畫面：淹水的街：水位逐漸上升（膝、腰、胸）；牆上的水位數字；漂浮的門板、箱子；人們互相拉手、撐傘、開船；船燈。第五章間章三是七年前、不同街區。
- 色調與光：夜、暴風雨；水的深藍黑，閃電的冷白，船燈與手電筒的暖黃點光；水面反光。
- 背景：待畫（`art/environment/scenes/flood_street.webp`）
- 狀態變體：間章三：七年前，老 K 揹著凜（不同街區，只有剪影）→ 8 第三次洪水夜，水位膝、腰、胸，蘇的船第一艘。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `flood_street__floating_door` | 漂浮的門板與木箱 | 水面上漂著的門板、木箱與塑膠桶；義體磁吸可以拉動的踏腳物。 | 0.8 m | 待畫 |
| `flood_street__water_scale_wall` | 牆上的水位刻度 | 刷在牆柱上的水位數字，標出每分鐘漲多少；第八章的教學。 | 3.0 m | 待畫 |
| `flood_street__submerged_street_lamp` | 淹到一半的路燈 | 半截泡在水裡的路燈，燈泡閃爍，電線在水面冒著小光。 | 3.2 m | 待畫 |
| `flood_street__drowned_van` | 半沉的貨車 | 只剩車頂與車窗露出水面的小貨車，車燈還亮著一盞。 | 1.5 m | 待畫 |
| `flood_street__half_sunk_sign` | 半泡水的招牌 | 一面掛在牆上的招牌，下半截泡在水裡，霓虹忽明忽暗。 | 1.6 m | 待畫 |
| `flood_street__floating_umbrellas` | 漂著的雨傘 | 水面上漂著的幾把撐開的傘，顏色各異，隨浪搖擺。 | 0.7 m | 待畫 |
| `flood_street__rescue_rope_line` | 救援繩線 | 牆與牆之間拉起的一條粗繩，掛著浮球與一排手抓環，水面上被拉得很緊。 | 1.2 m | 待畫 |
| `flood_street__balcony_lantern` | 陽台上的提燈 | 二樓陽台欄杆上垂下的一盞防風提燈，為路過的船指路。 | 1.0 m | 待畫 |
| `flood_street__plank_bridge` | 木板橋 | 兩棟樓之間搭起的一條窄木板橋，用繩子綁在窗框上。 | 0.6 m | 待畫 |
| `flood_street__sandbag_wall` | 沙袋牆 | 門口疊起來的一排沙袋，泡濕了，滲著水。 | 0.9 m | 待畫 |

## 廣播站（外）（`broadcast_outside`）

- 章：6　類型：探索
- 畫面：暴雨、天線塔、閃電；中繼器、冷卻閥與水位；蘇與斷錨派。謎：依雲蓋冷卻閥與水位恢復電力。
- 色調與光：夜、暴雨、雲蓋最厚；廣播站的藍與紅警示，天線上的閃電冷白光。
- 背景：待畫（`art/environment/scenes/broadcast_outside.webp`）
- 狀態變體：6 凜與蘇的掩護、廣播站電力謎；間章四的控制室在同一棟（另立場景）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `broadcast_outside__cooling_valve` | 雲蓋冷卻閥 | 調節雲蓋用的大冷卻閥：粗管、紅手輪、壓力表與蒸汽；水位謎的第一個機關。 | 1.8 m | 待畫 |
| `broadcast_outside__relay_battery` | 中繼器與浮著的電池 | 中繼器機櫃與一顆浮在水上的大電池；義體磁吸把電池拉到對的位置。 | 1.3 m | 待畫 |
| `broadcast_outside__antenna_tower` | 天線塔 | 高聳的鋼格天線塔，頂端與腰間紅色信標明滅；閃電會打在上面。 | 7.0 m | 待畫 |
| `broadcast_outside__big_dish` | 大型碟型天線 | 場地中央的巨大碟型天線，碟面積滿雨水，底座有電纜。 | 3.4 m | 待畫 |
| `broadcast_outside__pond_gauge_pole` | 冷卻池水位標桿 | 插在冷卻池裡的水位標桿，浮標與紅白刻度，水正漸漸上升。 | 2.4 m | 待畫 |
| `broadcast_outside__cable_reel` | 粗電纜捲盤 | 木製大線盤，粗黑電纜纏了一半，一端拖到地上接進機櫃。 | 1.0 m | 待畫 |
| `broadcast_outside__sandbag_barrier` | 沙袋與擋水板 | 站外圍起的沙袋牆，加一塊木擋水板，水已經滲進一些。 | 0.9 m | 待畫 |
| `broadcast_outside__lamp_mast` | 探照燈柱 | 高桿上兩盞探照燈，被雷聲震得微微晃動。 | 4.0 m | 待畫 |
| `broadcast_outside__studio_door` | 錄音室入口 | 低矮的混凝土建築門，門上一盞紅色的燈，門縫透出一線光。 | 2.2 m | 待畫 |
| `broadcast_outside__pump_hut` | 抽水小屋 | 水邊的小鐵皮屋，管線從牆上伸出去，窗裡一盞小黃燈。 | 2.4 m | 待畫 |

## 廣播站（錄音室）（`recording_booth`）

- 章：6　類型：演出
- 畫面：小房間、麥克風、蘇平淡地念名單；人名一個一個出現在牆上。
- 色調與光：夜；錄音室的深藍與一盞紅色「廣播中」燈，檯燈的暖黃，吸音棉的深灰。
- 背景：待畫（`art/environment/scenes/recording_booth.webp`）
- 狀態變體：6 蘇念名單；人名一個一個出現在牆上（程式疊字）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `recording_booth__boom_microphone` | 麥克風與防噴罩 | 桌上的吊臂麥克風、防噴罩與耳機；蘇平淡地念名單的位置。 | 1.5 m | 待畫 |
| `recording_booth__on_air_lamp` | 「廣播中」紅燈 | 門上的紅色警示燈箱：亮著代表正在廣播。 | 0.5 m | 待畫 |
| `recording_booth__name_wall` | 名單牆 | 牆上的名單：一個一個手寫的名字，有的被劃掉；斷錨派要讓人記得。 | 1.9 m | 待畫 |
| `recording_booth__mixing_console` | 調音台 | 一排推桿、旋鈕與音量表；每個通道貼著手寫的名字紙條。 | 1.0 m | 待畫 |
| `recording_booth__foam_panels` | 吸音棉牆片 | 牆上的灰色波浪吸音棉，邊角被撕破了一塊。 | 1.8 m | 待畫 |
| `recording_booth__recording_desk_lamp` | 桌燈 | 桌上的老式金屬桌燈，暖黃的光圈照著一疊稿子。 | 0.75 m | 待畫 |
| `recording_booth__booth_stool` | 播音高腳凳 | 一張高腳凳，椅面凹下去一個坐出來的圓；蘇坐的位置。 | 0.8 m | 待畫 |
| `recording_booth__reel_recorder` | 盤帶錄音機 | 兩個大帶盤與紅色錄音燈，帶子一圈一圈地走。 | 0.6 m | 待畫 |
| `recording_booth__glass_window` | 錄音室觀察窗 | 牆上的厚玻璃窗，後面是暗著的控制室，玻璃上映著紅燈。 | 1.2 m | 待畫 |
| `recording_booth__script_sheets` | 稿子與水杯 | 桌上一疊念名單用的稿紙，一支紅筆，一杯水。 | 0.4 m | 待畫 |

## 控制室（燈）（`control_room`）

- 章：間章四（第六章）　類型：間章
- 畫面：燈的畫面：螢幕牆、中繼器圖、通訊面板；阿梨的求救彈出。UI 為主，非戰鬥。
- 色調與光：夜；暗室，螢幕的藍、青、洋紅與警示紅；乾淨、冷、孤單。
- 背景：待畫（`art/environment/scenes/control_room.webp`）
- 狀態變體：間章四（燈）：重導中繼器、壓制干擾、阿梨的求救彈出。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `control_room__monitor_wall` | 螢幕牆 | 九宫格螢幕：波形、網路圖、通訊狀態；其中一格閃著求救的紅色。 | 2.3 m | 待畫 |
| `control_room__comm_console` | 通訊面板與耳機 | 燈的通訊台：推桿、旋鈕、一副耳機與一杯涼掉的飲料。 | 1.15 m | 待畫 |
| `control_room__relay_map_display` | 中繼器圖 | 牆上的城市中繼器網路圖：節點與連線，被干擾的節點閃紅。 | 1.8 m | 待畫 |
| `control_room__control_chair` | 控制室的辦公椅 | 舊辦公椅，椅背掛著一件外套，椅面有被坐出的凹陷。 | 1.1 m | 待畫 |
| `control_room__server_rack_small` | 小型機櫃 | 一座窄機櫃，一排排網路孔與閃爍的燈。 | 1.8 m | 待畫 |
| `control_room__console_clutter` | 桌上的雜物與母親的照片 | 桌上的空飲料罐、零食袋與一張貼在螢幕框的小照片：病床上的女人。 | 0.4 m | 待畫 |
| `control_room__cable_bundle_floor` | 地上的電線束 | 從牆洞拖到機台的一大把電線，用膠帶隨便纏著。 | 0.3 m | 待畫 |
| `control_room__whiteboard_notes` | 白板與便利貼 | 白板上畫著中繼器的草圖，邊緣貼滿黃色便利貼。 | 1.3 m | 待畫 |
| `control_room__cold_light_strip` | 冷白燈條 | 天花板上的冷白色長條燈，一端的燈管閃著。 | 0.35 m | 待畫 |
| `control_room__sos_panel` | 求救通話紅燈 | 控制台角落的小面板：一盞紅燈在閃，一個「求救」按鈕亮著。 | 0.5 m | 待畫 |

## 廣播站屋頂（`broadcast_roof`）

- 章：6　類型：頭目
- 畫面：暴雨、天線、母親坐在角落的錨椅上，罩著玻璃；棘（落雷與磁吸）。
- 色調與光：夜、暴雨；閃電的冷白與雲的深藍黑，錨椅玻璃罩的青色光。
- 背景：待畫（`art/environment/scenes/broadcast_roof.webp`）
- 狀態變體：6 頭目戰（棘）：母親的錨椅在右角。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `broadcast_roof__glass_dome_chair` | 玻璃罩下的錨椅 | 角落裡罩著玻璃的錨椅：棘的母親坐在這裡（這件只畫空椅與玻璃罩）。 | 1.7 m | 待畫 |
| `broadcast_roof__lightning_mast` | 避雷針桿 | 高高的避雷針桿，尖端時不時迸出藍白色火花；棘的落雷會打在這裡。 | 4.5 m | 待畫 |
| `broadcast_roof__generator_unit` | 發電機組 | 屋頂的柴油發電機組：外殼、排氣管、指示燈，轟轟作響。 | 1.5 m | 待畫 |
| `broadcast_roof__roof_dish` | 屋頂的大碟 | 屋頂邊緣的鐵鏽碟型天線，碟面有一道被雷擊出的黑斑。 | 3.0 m | 待畫 |
| `broadcast_roof__guy_mast` | 拉線桅桿 | 插在屋頂的桅桿，四面拉著鋼線，頂端一盞紅燈。 | 4.2 m | 待畫 |
| `broadcast_roof__exhaust_vent` | 屋頂排氣管 | 彎成鵝頸形的排氣管，冒出白色的熱氣，被風吹得斜斜的。 | 1.5 m | 待畫 |
| `broadcast_roof__sparking_box` | 冒火花的接線箱 | 屋頂牆上的接線箱，門被風吹得開開關關，裡面迸出藍白火花。 | 1.2 m | 待畫 |
| `broadcast_roof__roof_railing` | 屋頂護欄 | 屋頂邊緣的鏽鐵護欄，鏈條垂著，雨從上面成串滴下。 | 1.1 m | 待畫 |
| `broadcast_roof__magnet_coil` | 磁吸線圈塔 | 頭目戰的機關：粗大的銅線圈柱，頂端會放出藍白色電弧。 | 2.8 m | 待畫 |
| `broadcast_roof__storm_shelter` | 避雨的帆布棚 | 屋頂角落用鋼管撐起的帆布棚，裡面一張折疊桌與一盞提燈。 | 2.2 m | 待畫 |

## 雨中追逐（小巷）（`rain_chase_alley`）

- 章：6　類型：探索（限時）
- 畫面：從廣播站到阿梨家的街道；有 knows_ali_address 才有那條近路。事件本身不出現畫面，只有結果。
- 色調與光：夜、暴雨；窄巷的深藍與霓虹碎光，積水，遠處一盞暖黃的窗燈（阿梨家）。
- 背景：待畫（`art/environment/scenes/rain_chase_alley.webp`）
- 狀態變體：6 限時追逐；近路與繞遠路兩條路線共用這個外觀。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `rain_chase_alley__shortcut_gate` | 近路的鐵柵門 | 半掩的小鐵柵門，只有知道地址的人才知道可以穿過；近路的入口。 | 1.9 m | 待畫 |
| `rain_chase_alley__wet_laundry` | 淋雨的晾衣 | 橫過巷子的晾衣繩，衣服被雨打濕，隨風擺動。 | 1.7 m | 待畫 |
| `rain_chase_alley__alley_neon_noodle` | 「麵」小霓虹招牌 | 巷子裡突出的小霓虹招牌，一個大大的麵字；阿梨的店在附近。 | 1.2 m | 待畫 |
| `rain_chase_alley__ac_stack` | 冷氣室外機堆 | 牆上疊了三層的冷氣室外機，每一台底下都在滴水。 | 2.4 m | 待畫 |
| `rain_chase_alley__hanging_fire_ladder` | 放下一半的逃生梯 | 牆上垂下的鐵逃生梯，最後一段拉到一半，在風裡微微晃。 | 3.0 m | 待畫 |
| `rain_chase_alley__alley_dumpster` | 巷子的垃圾箱 | 綠色的大鐵垃圾箱，蓋子半掀，旁邊散落著袋子。 | 1.3 m | 待畫 |
| `rain_chase_alley__ali_window` | 阿梨家的黃窗 | 巷子盡頭二樓的小窗，窗簾後透出暖黃的燈光；追逐的目標。 | 1.2 m | 待畫 |
| `rain_chase_alley__wall_pipe_run` | 牆上的管線 | 沿牆爬上去的粗管線與電線，轉角處在滴水。 | 3.0 m | 待畫 |
| `rain_chase_alley__pallet_pile` | 濕木棧板堆 | 靠牆斜倚著的木棧板與幾個空箱，泡得發黑。 | 1.2 m | 待畫 |
| `rain_chase_alley__chalk_arrow_wall` | 牆上的粉筆箭頭 | 牆上用粉筆畫的箭頭、一個碗的圖案與「近路」二字，雨把它洗得有點糊。 | 1.0 m | 待畫 |

## 港區廣場（廣播後）（`harbor_plaza`）

- 章：6（變體 結局 A）　類型：演出
- 畫面：人們聽完廣播，繼續排隊復原；一個女人：「我知道。我還是要。」
- 色調與光：夜、雨變小；廣場的冷藍，大螢幕與擴音桿，排隊欄杆，遠處復原室的青色光。
- 背景：待畫（`art/environment/scenes/harbor_plaza.webp`）
- 狀態變體：6 廣播之後 → A 結局洪水退後（可選）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `harbor_plaza__queue_barriers` | 復原排隊欄杆 | 一排伸縮帶欄杆，長長的蛇形排隊線，沒有人。 | 1.0 m | 待畫 |
| `harbor_plaza__loudspeaker_pole` | 擴音喇叭桿 | 廣場中央的擴音喇叭桿：四個喇叭朝向四方；廣播從這裡傳出。 | 3.6 m | 待畫 |
| `harbor_plaza__plaza_screen` | 廣場大螢幕 | 廣場上的大螢幕：廣播結束後只剩一串滾動的名字，然後是廣告。 | 2.8 m | 待畫 |
| `harbor_plaza__apply_kiosk` | 復原申請亭 | 廣場邊的自助申請亭：觸控螢幕、號碼單與一個小雨棚。 | 2.2 m | 待畫 |
| `harbor_plaza__plaza_lamps` | 廣場的路燈列 | 兩盞並排的老式路燈，其中一盞的光是歪的。 | 3.4 m | 待畫 |
| `harbor_plaza__plaza_bins` | 廣場垃圾桶 | 並排的兩個灰色圓桶垃圾桶，桶口被雨打得發亮。 | 0.9 m | 待畫 |
| `harbor_plaza__plaza_benches` | 廣場長椅 | 濕透的木長椅，椅面上積了一排小水珠。 | 0.8 m | 待畫 |
| `harbor_plaza__fallen_umbrellas` | 掉在地上的傘 | 地上幾把被丟下、被踩過的傘；人們聽完廣播就走了。 | 0.4 m | 待畫 |
| `harbor_plaza__notice_board_plaza` | 公告欄 | 廣場上的公告欄，貼著一張寫滿名字的紙，雨把一角泡爛了。 | 1.4 m | 待畫 |
| `harbor_plaza__hot_drink_kiosk` | 收攤的熱飲亭 | 小熱飲亭，櫃台拉下一半的鐵捲門，裡面還亮著小燈。 | 2.3 m | 待畫 |

## 當舖浴室（`pawnshop_bathroom`）

- 章：6　類型：據點
- 畫面：暖色，水氣，老 K 的背；凜替他洗澡。老去的身體不被遮掩。全作最近的畫面。
- 色調與光：夜；暖色的小燈與水氣，白瓷磚與木色；整個遊戲最溫暖、最近的一幕。
- 背景：待畫（`art/environment/scenes/pawnshop_bathroom.webp`）
- 狀態變體：6 凜替老 K 洗澡（只畫場所）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `pawnshop_bathroom__clawfoot_tub` | 鑄鐵浴缸 | 老式白瓷浴缸，熱氣緩緩升起；水面反光。 | 0.85 m | 待畫 |
| `pawnshop_bathroom__bath_stool_basin` | 小板凳與臉盆 | 矮木凳與黃銅臉盆；一條毛巾掛在邊上。 | 0.6 m | 待畫 |
| `pawnshop_bathroom__heat_lamp_rack` | 毛巾架與暖燈 | 掛著乾毛巾的鐵架與一盞橙色的紅外線暖燈。 | 1.7 m | 待畫 |
| `pawnshop_bathroom__sink_mirror` | 洗手台與圓鏡 | 老式洗手台，上面一面被水氣弄花的圓鏡，台上放著刮鬍刀與牙刷。 | 1.7 m | 待畫 |
| `pawnshop_bathroom__laundry_basket` | 洗衣籃 | 編織的洗衣籃，裡面是一件舊毛衣與一條格子睡褲。 | 0.65 m | 待畫 |
| `pawnshop_bathroom__frosted_bath_window` | 毛玻璃小窗 | 浴室的毛玻璃窗，外面的路燈把一圈光暈透進來。 | 0.9 m | 待畫 |
| `pawnshop_bathroom__shaving_shelf` | 老 K 的小置物架 | 牆上的小木架：肥皂、梳子、一瓶舊髮油與一副假牙盒。 | 0.7 m | 待畫 |
| `pawnshop_bathroom__slippers_mat` | 拖鞋與踏墊 | 門口一張舊踏墊，兩雙拖鞋一大一小並排放著。 | 0.3 m | 待畫 |
| `pawnshop_bathroom__gas_heater` | 瓦斯熱水器 | 牆上的老式瓦斯熱水器，點火的小藍焰與熱水管上的蒸氣。 | 1.0 m | 待畫 |
| `pawnshop_bathroom__step_stool` | 小踏凳 | 浴缸邊的木製小踏凳，扶著它才能跨進去。 | 0.4 m | 待畫 |

## 麵攤（日照區）（`sunlit_noodle_stall`）

- 章：7　類型：演出
- 畫面：戶外座位，陽光，兩碗麵；他們坐在長椅上。「明天再說，今天太亮了。」
- 色調與光：白天、唯一的晴天；白、淡金與天藍，麵的蒸氣在陽光裡特別白。
- 背景：待畫（`art/environment/scenes/sunlit_noodle_stall.webp`）
- 狀態變體：7 老 K 與凜在陽光下吃麵；與第一章天亮的麵攤（港區）是不同的地方。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `sunlit_noodle_stall__sunny_stall` | 日照區麵攤 | 乾淨的小麵攤：白黃條紋雨棚、冒煙的湯鍋、碗疊與一盞小燈；陽光下的蒸氣。 | 2.3 m | 待畫 |
| `sunlit_noodle_stall__bench_two_bowls` | 長椅與兩碗麵 | 木長椅與旁邊的小桌，桌上兩碗熱麵，一碗吃了一半；他們並肩的地方。 | 0.9 m | 待畫 |
| `sunlit_noodle_stall__parasol_table` | 遮陽傘與桌椅 | 白色遮陽傘下的小圓桌與兩把椅子；日照區的戶外座位。 | 2.3 m | 待畫 |
| `sunlit_noodle_stall__chalk_menu` | 黑板菜單 | 立在攤位旁的小黑板：「麵　一碗」與一個笑臉。 | 1.2 m | 待畫 |
| `sunlit_noodle_stall__flower_pots` | 窗台花盆 | 攤位旁階梯上的一排小花盆，開著紅色和白色的花。 | 0.8 m | 待畫 |
| `sunlit_noodle_stall__bunting_flags` | 彩色小旗 | 屋簷下拉著的一串彩色三角旗，被風吹得輕輕晃動。 | 0.9 m | 待畫 |
| `sunlit_noodle_stall__wind_chime` | 風鈴 | 屋簷下的玻璃風鈴，紙籤上寫著「平安」，陽光裡閃閃發亮。 | 0.8 m | 待畫 |
| `sunlit_noodle_stall__sunbathing_cat` | 曬太陽的貓 | 石階上攤開肚皮曬太陽的橘貓，尾巴偶爾輕輕甩一下。 | 0.35 m | 待畫 |
| `sunlit_noodle_stall__dish_rack_cart` | 洗碗推車 | 推車上的洗碗盆、一疊洗好的碗與一條毛巾，碗在陽光下閃著水光。 | 0.95 m | 待畫 |
| `sunlit_noodle_stall__tea_dispenser` | 麥茶桶 | 桌上的大保溫茶桶與一疊紙杯，旁邊一把摺扇。 | 0.6 m | 待畫 |

## 公共花園（日照區）（`public_garden`）

- 章：7　類型：探索（無戰鬥）
- 畫面：草地、噴泉、長椅、樹影；他們睡著的地方。
- 色調與光：白天；淡綠與白金，樹影，噴泉的水珠在陽光裡閃；輕、暖、沒有威脅。
- 背景：待畫（`art/environment/scenes/public_garden.webp`）
- 狀態變體：7 兩人在長椅上睡著、頭目夢魘（場地另立 nightmare_arena）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `public_garden__stone_fountain` | 圓形噴泉 | 石砌的圓形噴泉，水柱灑落，水珠在陽光裡閃亮。 | 1.8 m | 待畫 |
| `public_garden__big_shade_tree` | 大樹 | 枝葉茂密的大樹，樹影斑駁；他們睡著的長椅就在樹下。 | 6.0 m | 待畫 |
| `public_garden__park_bench_wood` | 公園長椅 | 樹下的舊木長椅，扶手上有一小片落葉；兩個人睡著的地方。 | 0.9 m | 待畫 |
| `public_garden__flower_bed` | 花圃 | 圓形花圃，白色與黃色的小花開得滿滿，一隻蝴蝶停在上面。 | 0.7 m | 待畫 |
| `public_garden__trimmed_hedge` | 修剪整齊的樹籬 | 一段方方正正的綠色樹籬，上面一圈小白花。 | 1.1 m | 待畫 |
| `public_garden__garden_lamp` | 花園路燈 | 白天的老式花園路燈，玻璃罩上停著一隻麻雀。 | 2.6 m | 待畫 |
| `public_garden__bird_bath` | 鳥浴盆 | 石製的小水盆，三隻麻雀在邊緣喝水，水面反光。 | 0.9 m | 待畫 |
| `public_garden__picnic_set` | 野餐墊與籃子 | 草地上的格子野餐墊、一個藤籃與一壺茶；沒有人。 | 0.5 m | 待畫 |
| `public_garden__path_signpost` | 步道指示牌 | 木製的路標，兩塊箭頭板分別寫著「噴泉」與「出口」。 | 1.6 m | 待畫 |
| `public_garden__rose_bush` | 玫瑰叢 | 一叢盛開的白玫瑰與粉玫瑰，花瓣上有露珠。 | 1.0 m | 待畫 |

## 夢魘（日曆頁的花園）（`nightmare_arena`）

- 章：7　類型：頭目
- 畫面：日曆頁組成的巨人，場地是長椅與花園被拉長、扭曲；減速圈。「明天」。
- 色調與光：夢；過亮的白金，粉黃的天，被拉長的影子，紙色；亮得有點不對。
- 背景：待畫（`art/environment/scenes/nightmare_arena.webp`）
- 狀態變體：7 頭目「明天」（EPIMETHEUS）：減速圈；場地由第七章公共花園扭曲而來。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `nightmare_arena__calendar_pillar` | 日曆頁柱 | 一疊撕不完的巨大日曆頁形成的柱子，每一頁寫著「明天」。 | 3.2 m | 待畫 |
| `nightmare_arena__long_warped_bench` | 被拉長的長椅 | 長到不合理的長椅，椅腳一組一組往遠處排去；夢裡的比例。 | 1.0 m | 待畫 |
| `nightmare_arena__falling_calendar_sheet` | 飄落的日曆頁 | 一張慢慢飄落的日曆頁，輕輕擺動；減速圈裡一切都變慢。 | 1.4 m | 待畫 |
| `nightmare_arena__giant_clock_face` | 巨大的鐘面 | 夢裡的巨大鐘面：數字拉長、指針垂下來，像融化的奶油；永遠停在「明天」。 | 3.2 m | 待畫 |
| `nightmare_arena__crooked_tree` | 歪曲的樹 | 被拉彎的樹，葉子是一張張小小的日曆紙。 | 4.0 m | 待畫 |
| `nightmare_arena__stopped_hourglass` | 停住的沙漏 | 巨大的沙漏，沙子停在半空，一粒一粒懸浮著。 | 3.0 m | 待畫 |
| `nightmare_arena__page_swirl` | 盤旋的日曆頁 | 一串日曆頁排成螺旋，一張接一張地飄過去，頭目的攻擊軌跡。 | 2.2 m | 待畫 |
| `nightmare_arena__slow_ring` | 減速圈 | 地上一圈淡金色的光環與細小的符號，進去的一切都會變慢（頭目機制的標記）。 | 0.5 m | 待畫 |
| `nightmare_arena__giant_umbrella` | 插在草地上的巨傘 | 一把比房子還大的米白色傘插在地上，傘面印著日期；夢裡的「帶傘了嗎」。 | 3.6 m | 待畫 |
| `nightmare_arena__melting_fountain` | 融化的噴泉 | 噴泉的水柱向上凝成一朵花的形狀，花瓣是水；夢裡的花園。 | 2.0 m | 待畫 |

## 天穹塔頂花園（`tower_garden`）

- 章：7　類型：探索／演出
- 畫面：全城唯一真正的花園，茉莉；沈望坐在長椅，汐的墓或空椅子；城市在腳下；沈望的筆記本謎。
- 色調與光：白天；雲海之上的亮藍天，白金的陽光，茉莉的白與綠；寧靜、不真實的美。
- 背景：待畫（`art/environment/scenes/tower_garden.webp`）
- 狀態變體：7 沈望的花園、汐的空椅子；9 的塔內部另立場景。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `tower_garden__jasmine_trellis` | 茉莉花架 | 爬滿白色茉莉的花架；沈望筆記本的指示對應的機關之一。 | 2.4 m | 待畫 |
| `tower_garden__empty_garden_chair` | 汐的空椅子 | 花園裡的一把木椅，椅背搭著一條披肩，椅邊一小瓶茉莉；沈望每天來陪的位置。 | 1.0 m | 待畫 |
| `tower_garden__greenhouse_window` | 溫室的窗與搖桿 | 溫室的小窗與手搖開窗的搖桿；「早上先開窗」，沈望筆記本第一條指示的機關。 | 1.8 m | 待畫 |
| `tower_garden__glass_railing` | 玻璃護欄 | 花園邊緣一段透明玻璃護欄，雲海在後面緩緩流動。 | 1.2 m | 待畫 |
| `tower_garden__notebook_lectern` | 沈望的筆記本與講台 | 花園入口的小木架：翻開的筆記本，寫著「她喜歡茉莉。不要問她昨天的事。早上先開窗。」 | 1.15 m | 待畫 |
| `tower_garden__path_lamps` | 花園小路燈 | 路邊一排矮矮的小路燈，白天熄著，燈罩是淺色的玻璃花。 | 0.6 m | 待畫 |
| `tower_garden__pergola_bench` | 藤架長椅 | 白色藤架下的木長椅，椅背上纏著茉莉的藤。 | 2.4 m | 待畫 |
| `tower_garden__mist_sprinkler` | 噴霧灑水機關 | 地上的銅噴頭，細細的水霧在陽光裡出現小小的彩虹；沈望筆記本的第二條指示的機關。 | 1.0 m | 待畫 |
| `tower_garden__jasmine_pots` | 茉莉盆栽 | 三只白瓷盆種著開滿花的茉莉，一盆放在小凳上。 | 1.2 m | 待畫 |
| `tower_garden__sundial` | 日晷 | 石製日晷，指針的影子停在一個刻度上；沈望的第三條指示。 | 1.0 m | 待畫 |

## 櫃台（帳房大廳）（`accounting_lobby`）

- 章：7　類型：演出
- 畫面：白色大廳，一個櫃台，一個按鈕「把命當了」；玩家親手按。受錨者同意：已簽署；錨人同意：未簽署。
- 色調與光：白天；全白、淡灰與一點金屬；冷、乾淨、巨大的空；唯一的色彩是按鈕的紅。
- 背景：待畫（`art/environment/scenes/accounting_lobby.webp`）
- 狀態變體：7 賣掉復原權（把命當了）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `accounting_lobby__pawn_button_pedestal` | 「把命當了」按鈕台 | 白色圓台上一個大紅按鈕與玻璃罩；全作最重的一個按鈕。 | 1.15 m | 待畫 |
| `accounting_lobby__lobby_counter` | 櫃台與同意書螢幕 | 白色長櫃台與一塊螢幕：受錨者同意已簽署，錨人同意未簽署。 | 1.2 m | 待畫 |
| `accounting_lobby__ticket_machine` | 取號機 | 大廳角落的取號機，螢幕顯示「0」；沒有人排隊。 | 1.5 m | 待畫 |
| `accounting_lobby__lobby_sofa` | 候位沙發 | 白色的長沙發，沒有人坐過的平整椅面。 | 0.75 m | 待畫 |
| `accounting_lobby__light_column` | 天光柱 | 天花板的圓形天窗灑下的一道光柱，光裡有灰塵緩緩飄。 | 3.5 m | 待畫 |
| `accounting_lobby__contract_stand` | 合約與簽名台 | 小立架上攤開的合約：兩個簽名欄，一個簽了名，一個空白。 | 1.15 m | 待畫 |
| `accounting_lobby__dome_camera` | 半球型攝影機 | 天花板的白色半球攝影機，一個小紅點亮著。 | 0.4 m | 待畫 |
| `accounting_lobby__lobby_tree` | 大廳的室內樹 | 大廳角落一棵修剪得很圓的室內樹，種在白色圓筒裡。 | 2.6 m | 待畫 |
| `accounting_lobby__directory_sign` | 樓層指示牌 | 大廳的立式指示牌：樓層一覽，最上面一行寫著「帳房」。 | 1.6 m | 待畫 |
| `accounting_lobby__paper_shredder` | 碎紙機 | 櫃台旁的白色碎紙機，吐出一條一條細碎的紙；簽了名的合約會被送進去。 | 0.8 m | 待畫 |

## 水閘廳（`sluice_hall`）

- 章：8　類型：頭目
- 畫面：巨型水閘機關，三個部位，放水區塊；水位。協定（THEMIS）。
- 色調與光：夜、暴風雨；水的深藍黑，閘門與管線的鋼灰，冷白與警示橙的點光，水霧。
- 背景：待畫（`art/environment/scenes/sluice_hall.webp`）
- 狀態變體：8 頭目戰（協定）：三個部位、放水區塊。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `sluice_hall__gate_gear` | 巨型閘門齒輪 | 閘門機關的大齒輪與鏈條，緩緩轉動；頭目的部位之一。 | 3.6 m | 待畫 |
| `sluice_hall__water_level_gauge_tower` | 水位計塔 | 立在水道旁的高水位計：玻璃管裡的水位、數字與警示色帶。 | 3.4 m | 待畫 |
| `sluice_hall__release_console` | 放水區塊控制盤 | 控制盤：一排放水區塊的推桿與紅綠燈；頭目戰中玩家要打開的機關。 | 1.4 m | 待畫 |
| `sluice_hall__hydraulic_piston` | 液壓推桿 | 推動閘門的巨大液壓缸，油亮的活塞桿緩緩伸縮。 | 3.4 m | 待畫 |
| `sluice_hall__catwalk_section` | 檢修走道 | 一段鐵網走道與欄杆，下面就是滾滾的水。 | 1.6 m | 待畫 |
| `sluice_hall__orange_flood_lamp` | 橘色警示泛光燈 | 牆上的大型橘色警示燈，一圈圈地閃。 | 1.2 m | 待畫 |
| `sluice_hall__giant_chain` | 巨鏈 | 從閘門垂下來的巨大鏈條，每一環都比人頭還大，滴著水。 | 4.0 m | 待畫 |
| `sluice_hall__leaking_pipe_spray` | 噴水的管線 | 牆上的粗管爆開一道縫，水像一把白色的扇子噴出來。 | 2.0 m | 待畫 |
| `sluice_hall__siren_horn` | 警報喇叭 | 水閘廳樑上的紅色警報喇叭，喇叭口一圈紅燈。 | 0.8 m | 待畫 |
| `sluice_hall__pillar_stencil` | 鋼柱與水位數字 | 刷了大大白色數字的鋼柱，水痕已經淹過「3」。 | 3.4 m | 待畫 |

## 蘇的船（`suo_boat`）

- 章：8　類型：演出
- 畫面：小船、船燈；避免：阿梨站在船上伸手；未避免：空位。船載走老 K。
- 色調與光：夜、暴風雨、洪水；水的深藍黑，船燈的暖黃是唯一的暖，閃電的冷白。
- 背景：待畫（`art/environment/scenes/suo_boat.webp`）
- 狀態變體：8 蘇的船載走老 K（阿梨在船上或空位）。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `suo_boat__rescue_boat` | 蘇的小船 | 漆著白字的小木船與船燈、一圈繩索；第一艘開進洪水的船。 | 1.5 m | 待畫 |
| `suo_boat__lantern_pole` | 船燈桿 | 插在水裡的一根竹桿，掛著防風提燈，隨浪搖晃；為人指路的燈。 | 2.0 m | 待畫 |
| `suo_boat__hanging_rope` | 垂下的繩子 | 從屋頂垂下來的一條粗繩，末端打著結；灰衣人丟給凜的那一條。 | 2.6 m | 待畫 |
| `suo_boat__life_ring` | 救生圈與繩 | 紅白相間的救生圈掛著一圈白繩，在水面邊緣晃。 | 0.7 m | 待畫 |
| `suo_boat__boat_oars` | 木槳 | 斜靠著的兩支長木槳，槳葉漆著白色。 | 1.5 m | 待畫 |
| `suo_boat__boat_umbrella` | 船上撐開的傘 | 插在船舷上的一把大黑傘，傘下留著一個位置。 | 1.5 m | 待畫 |
| `suo_boat__tilted_signpost` | 傾斜的路牌 | 只剩上半截露出水面的路牌，歪向一邊，「港區 3 街」。 | 2.0 m | 待畫 |
| `suo_boat__floating_crates` | 漂浮的木箱 | 水面上漂著的兩個木箱與一捆竹竿。 | 0.7 m | 待畫 |
| `suo_boat__flashlight_plank` | 木板上的手電筒 | 漂在水上的小木板，一支手電筒亮著，光圈打在水面。 | 0.5 m | 待畫 |
| `suo_boat__blanket_bundle` | 毛毯包與空位 | 船上一件疊好的灰毛毯與一把空著的小凳；為某個人準備的位置。 | 0.7 m | 待畫 |

## 港口（夜）（`night_harbor`）

- 章：8　類型：演出
- 畫面：船離開，凜看著塔。
- 色調與光：夜、暴風雨將停；深藍黑的海與天，遠處雲上的塔的冷白光，船燈漸遠的暖黃點。
- 背景：待畫（`art/environment/scenes/night_harbor.webp`）
- 狀態變體：8 章末：船離開，凜看著塔。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `night_harbor__mooring_bollards` | 繫船柱與纜繩 | 碼頭邊的鑄鐵繫船柱，纜繩垂向水裡；船離開之後留下的。 | 0.9 m | 待畫 |
| `night_harbor__buoy_lamp` | 浮標燈 | 漂在水面的紅色浮標燈，明滅的紅光；一直亮著。 | 1.3 m | 待畫 |
| `night_harbor__floodlight_mast` | 碼頭泛光燈桿 | 高桿上的四盞泛光燈，一盞已經壞了；照著空空的碼頭。 | 4.0 m | 待畫 |
| `night_harbor__dock_crane_far` | 遠處的龍門吊 | 碼頭盡頭一座靜止的龍門吊，吊臂頂端的紅燈一閃一閃。 | 4.5 m | 待畫 |
| `night_harbor__mini_lighthouse` | 小燈塔 | 碼頭尖端的小燈塔，一束暖黃光掃過海面。 | 3.6 m | 待畫 |
| `night_harbor__pier_boards` | 碼頭木板 | 碼頭邊的一段濕木板，板縫透著水光，一盞小提燈放在邊上。 | 0.5 m | 待畫 |
| `night_harbor__anchor_chain_pile` | 錨與鏈條堆 | 一個鏽鐵錨與一堆粗鏈條，堆在碼頭一角。 | 0.9 m | 待畫 |
| `night_harbor__fishing_nets_pile` | 漁網堆 | 一堆濕漉漉的綠色漁網與浮球。 | 0.9 m | 待畫 |
| `night_harbor__harbor_bench_wet` | 碼頭的濕長椅 | 面向海的舊木長椅，椅面積著一層水。 | 0.9 m | 待畫 |
| `night_harbor__moored_boat` | 停靠的漁船 | 繫在碼頭邊的小漁船，船頭一盞小燈亮著，隨著浪輕輕搖。 | 1.8 m | 待畫 |

## 天穹塔（各層）（`tower_floors`）

- 章：9　類型：探索
- 畫面：垂直探索，每層一個動詞：水位層、錨點層、回放層、對帳層、問層；最後一層全部組合。塔越往上越白、越安靜。
- 色調與光：塔內沒有天氣；帳房的白與金屬，冷白光，條款的字是唯一的顏色。
- 背景：待畫（`art/environment/scenes/tower_floors.webp`）
- 狀態變體：9 五層各一個動詞（水位、錨點、回放、對帳、問），最後一層全部組合；同一塔 3 外面、7 頂樓花園另立場景。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `tower_floors__water_riser_valves` | 水位層的閥門塔 | 水位層：透明水管裡的水位與一排可轉的閥門。 | 3.2 m | 待畫 |
| `tower_floors__anchor_terminal_chair` | 錨點層的終端與椅 | 錨點層：白色的錨椅與前面的終端，沒有線纜的乾淨版本。 | 1.5 m | 待畫 |
| `tower_floors__memory_column` | 回放層的記憶柱 | 回放層：玻璃柱裡流動著模糊的影像光，一格一格；看不清臉。 | 3.0 m | 待畫 |
| `tower_floors__ledger_wall_white` | 對帳層的帳本牆 | 對帳層：整面白牆的帳本格，每一冊側邊有一條彩色細線，三個一組。 | 3.0 m | 待畫 |
| `tower_floors__ask_pedestal` | 問層的對話台 | 問層：白色圓台上兩把相對的小椅，中間一個發光的問號；只有問，才會開門。 | 1.5 m | 待畫 |
| `tower_floors__glass_floor_grid` | 玻璃地板 | 透明玻璃地板下透出一格格的燈，往下看不到底。 | 0.3 m | 待畫 |
| `tower_floors__lift_capsule` | 電梯艙 | 透明的圓形電梯艙，掛在一根銀色的軌道上，內壁亮著柔和的白光。 | 2.6 m | 待畫 |
| `tower_floors__fibre_trunk` | 光纜幹線 | 沿著牆爬上去的一束光纜，每條纜線裡有光點緩緩上升。 | 3.4 m | 待畫 |
| `tower_floors__light_pillar` | 光柱 | 一根細長的白色光柱立在中央，像一根被點亮的柱子。 | 3.6 m | 待畫 |
| `tower_floors__tower_checkpoint` | 塔內的檢查點 | 一顆懸浮在小台座上的光球，輕輕自轉；塔內的存檔點。 | 1.4 m | 待畫 |

## 帳房（`ledger_hall`）

- 章：9　類型：頭目
- 畫面：塔的中心，一座巨大的白色圓形檔案庫；牆上是被磨掉的記憶：一格一格的光；沈望坐在核心，筆記本；三條條款在空中，被撕裂時有暖光。
- 色調與光：塔內；帳房的白與金屬，冷白光，被撕裂時才有暖光；條款的字是唯一的顏色。
- 背景：待畫（`art/environment/scenes/ledger_hall.webp`）
- 狀態變體：9 最終頭目沈望；真結局：凜坐在沈望的位置。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `ledger_hall__core_seat` | 核心的座位 | 高台上的白色座椅，連著細纜；沈望坐的位置，真結局時凜坐在這裡。 | 2.0 m | 待畫 |
| `ledger_hall__clause_tablet` | 條款石板 | 懸在空中的透明條款板：「四、雙方同意。錨人：未簽署。」是畫面唯一的顏色。 | 2.0 m | 待畫 |
| `ledger_hall__cell_wall` | 記憶格牆 | 一整面格子的光：每一格是被磨掉的一段記憶，有的亮、有的暗。 | 3.0 m | 待畫 |
| `ledger_hall__shen_notebook` | 沈望的筆記本 | 懸浮在空中的筆記本，攤開的最後一頁：「四、雙方同意。錨人：未簽署。」 | 1.2 m | 待畫 |
| `ledger_hall__torn_clause_pieces` | 被撕裂的條款碎片 | 一片片被撕開的條款紙，邊緣透著暖金色的光，緩緩飄開。 | 1.6 m | 待畫 |
| `ledger_hall__light_ring_dais` | 光環圓台 | 地面中央的白色圓台，台邊一圈細細的金色光環。 | 0.6 m | 待畫 |
| `ledger_hall__floating_glass_panels` | 懸空的條款板群 | 三片大小不同的透明玻璃板，懸在半空，各刻著一條條款。 | 3.0 m | 待畫 |
| `ledger_hall__archive_rail_ladder` | 檔案軌道與梯子 | 沿著圓牆弧形軌道滑動的白色梯子，梯腳的小輪停在軌上。 | 3.2 m | 待畫 |
| `ledger_hall__memory_orb_cluster` | 記憶光球 | 一簇小小的發光球，一顆一顆是被磨掉的記憶，暖色冷色都有。 | 1.2 m | 待畫 |
| `ledger_hall__contract_seal` | 契約印章 | 金屬底座上的圓形印章，印面刻著一朵雲與「不得中止」。 | 0.5 m | 待畫 |

## 「欠著」麵攤（`ending_a_stall`）

- 章：9（結局 A）　類型：演出
- 畫面：洪水退後的港區，麵攤，招牌「欠著」；碗上的熱氣；雨沒停。
- 色調與光：清晨或黃昏、雨還在下；洪水退後的灰、泥色與水痕，麵攤的暖黃光與熱氣是唯一的暖。
- 背景：待畫（`art/environment/scenes/ending_a_stall.webp`）
- 狀態變體：結局 A：走過地圖後，最後走進這間麵攤。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `ending_a_stall__owe_sign_stall` | 「欠著」麵攤 | 招牌寫著「欠著」的小麵攤：暖黃燈、冒煙的鍋；阿梨的夢想。 | 2.3 m | 待畫 |
| `ending_a_stall__bowl_steam` | 一碗冒煙的麵 | 碗上的熱氣；全作最後的畫面。 | 0.7 m | 待畫 |
| `ending_a_stall__flood_debris_pile` | 退水後的雜物堆 | 牆邊被水推來的雜物：傘、木板、泥巴；牆上標籤只剩一半。 | 1.1 m | 待畫 |
| `ending_a_stall__half_washed_tags` | 泡掉一半的標籤串 | 一串被水泡掉一半的紙標籤，墨跡暈開，還讀得出幾個字。 | 0.9 m | 待畫 |
| `ending_a_stall__stall_stools` | 麵攤的小凳 | 三張矮矮的塑膠小板凳，凳面還有一圈水痕。 | 0.45 m | 待畫 |
| `ending_a_stall__tilted_lamp` | 歪斜的路燈 | 被水撞歪的路燈，燈罩裂了，燈還亮著一點點黃光。 | 3.2 m | 待畫 |
| `ending_a_stall__waterline_wall` | 牆上的水痕 | 牆面上一道清楚的泥水線，線以下是深褐色，上面還貼著一張泡爛的海報。 | 2.2 m | 待畫 |
| `ending_a_stall__wet_umbrella_hung` | 掛著晾乾的傘 | 掛在門框上晾著的紅傘，傘尖還一滴一滴地滴水。 | 1.0 m | 待畫 |
| `ending_a_stall__drying_rack` | 曬衣架 | 木製曬衣架，掛著幾條洗過的毛巾與一件圍裙；洪水過後的第一個晴天（雖然雨沒停）。 | 1.5 m | 待畫 |
| `ending_a_stall__mud_boots` | 門邊的泥靴 | 一雙沾滿泥巴的膠鞋整齊地放在門邊，旁邊一支鏟子。 | 0.55 m | 待畫 |

## 學校的終端前（`school_terminal`）

- 章：9（真結局片尾）　類型：演出
- 畫面：學校的終端前，十歲的女孩（只剪影，不露臉），螢幕：「預設：同意」。
- 色調與光：白天；學校走廊的乾淨白光與淡藍，窗外陽光；溫和得令人不安。
- 背景：待畫（`art/environment/scenes/school_terminal.webp`）
- 狀態變體：9 真結局片尾（伏筆）：十歲女孩站在終端前。

| id | 中文名 | 一句話 | 尺寸 | 狀態 |
|---|---|---|---|---|
| `school_terminal__school_terminal_unit` | 學校終端機 | 走廊的安心登錄終端：螢幕寫著「預設：同意」；右下簽署：凜。 | 1.7 m | 待畫 |
| `school_terminal__locker_row` | 置物櫃 | 一排淡藍色置物櫃，貼著孩子的名字貼紙。 | 1.8 m | 待畫 |
| `school_terminal__notice_board_school` | 學校公布欄 | 貼著彩色圖畫與「安心登錄」宣導海報的公布欄。 | 1.2 m | 待畫 |
| `school_terminal__child_umbrella_pegs` | 孩子們的傘架 | 牆上一排掛鉤，每一把小傘上貼著名字，有一個鉤子是空的。 | 1.1 m | 待畫 |
| `school_terminal__shoe_cubbies` | 鞋櫃 | 格子鞋櫃，每格裡放著一雙小鞋與一雙拖鞋。 | 1.0 m | 待畫 |
| `school_terminal__school_water_fountain` | 學校飲水臺 | 走廊的矮飲水臺，水弧形地噴出來。 | 0.7 m | 待畫 |
| `school_terminal__backpack_bench` | 放著書包的長椅 | 走廊長椅與幾個小書包；放學後沒有被帶走的樣子。 | 0.9 m | 待畫 |
| `school_terminal__school_clock` | 學校的掛鐘 | 走廊牆上的白色圓鐘，指針指著三點。 | 0.55 m | 待畫 |
| `school_terminal__sill_plants` | 窗台上的盆栽 | 窗台上一排小盆栽，豆子才剛發芽，旁邊貼著孩子的名字。 | 0.45 m | 待畫 |
| `school_terminal__mural_wall` | 孩子們的牆畫 | 走廊牆上一幅彩色蠟筆牆畫：一把大傘下站著很多小人，旁邊畫著太陽。 | 1.6 m | 待畫 |

