# 劇情對關卡的限制：哪些區域的動線可以改

地圖線、玩法線、敵人線改關卡之前，先查這張表。表上「不能改」的是劇情需要：對話一定要在某個位置發生、某一段不能有敵人、人物或物件的站位被過場或互動動作引用、限時路線的長度決定趕不趕得上。「可以改」的部分照各線自己的判斷做。

故事線新增觸發格、人物站位或劇情綁定的物件時，同步更新這份文件。

## 怎麼看

- 第一到三章的地圖短對話綁在地圖上的觸發格（`&`，由左到右對應關卡的 `story_triggers`）。移動觸發格會讓對話在錯的位置出現。
- 第四到六章的劇情綁在地圖物件（legend 字元）上。限制在於物件的格位，以及 `data/cutscene/world_prop_actions.json` 裡凜相對物件的站位偏移（`station`）。
- 標「推定」的是從劇本方向推出來的，不是劇本明文；要改之前先問故事線。標「待定」的是還沒有可以核對的資料。

## 第五、六章

| 區域 | 可以改 | 不能改 | 依據 |
|---|---|---|---|
| ch5_pawnshop 當舖（貨架盤點） | 店後段（廚房、餐桌那側）可加小段落差與裝飾 | 不放敵人。四件舊貨、盤點板、索引留在貨架與櫃台；收據、總帳在櫃台兩端的工作面（桌高是固定換算）；葉與文件在暖燈工作檯旁 | `CH05_FEE_LEDGER.md` 櫃台工作面、`CH05_PAWNSHOP_OFFER.md`、`SCRIPT_CH05.md` 36～48 行 |
| ch5_harbor_street 港區街道 | 高差、第二條路（例如上層屋簷到後巷的捷徑）、零星可避的危險物 | 往電話亭的出口要 `ch5_ye_offer_declined` 才開；地面永遠有一條主線可走；從街上看得見樓梯口的黃燈。**推定**：不放敵人（第五章設計為無戰鬥，但這一區沒有明文） | `ch5_harbor_street.tres`、`SCRIPT_CH05.md` 27 行、`CH05_SCRIPT_REVIEW.md` |
| ch5_revival_lounge 復原館 | 裝飾性的小落差 | 吧台談話的位置：阿梨在吧台（約 x38），裁坐在吧台外端。**推定**：不放敵人（同上） | `SCRIPT_CH05.md` 60～70 行 |
| ch5_back_alley 當舖後巷 | 已有地面與維修架兩層，可再加高差，或從上層掩體回底層排水溝的路 | 聲音鎖（x41）與籠燈在通往樓梯口的出口前；樓梯口要 `ch5_basement_voice_unlocked` 才開；不加戰鬥 | `CH5_BACK_ALLEY_VOICE_LOCK.md`、`SCRIPT_CH05.md` 28 行 |
| ch5_basement_stair 地下室樓梯口 | 只能調三段維修架的高度與外觀，改了要重新驗躲避的手感 | 灰衣人躲避戰的定位（home 20、retry 8、start 13）；上下兩層都能回到梯口；灰外套在 x29 的退場位置；被抓時短距離帶回有地面的巷口側；不能換成一般敵人 | `CH05_STAIR_ENCOUNTER.md`、`data/encounters/ch5_stair_avoidance.tres` |
| ch5_basement_archive 地下室檔案間 | 只加天花板或背景細節 | 由西往東的順序固定：老 K（西側樓梯旁）→ 回單 → 錨椅 → 附頁（東側檯燈小桌）→ 記憶片；物件留原位；不放敵人 | `CH05_ANCHOR_AGREEMENT.md`、`CH05_ANCHOR_CHAIR.md` |
| 洪水回放（`game/cutscene/local_replay/flood_memory_stage.gd`，不在地圖上） | 不能從地圖改 | 踏面、扶欄、當舖燈、座椅座標寫在程式裡；低街與乾梯兩條路和十分鐘倒數綁在一起 | `CH5_FLOOD_MEMORY.md` |
| ch5_gray_path 灰道換班廊 | 檢修廊中段可加高差；不建議放戰鬥 | 回口閂（x46）留在遠端、從內側打開；小桌與暖燈是安全歇腳點；按閂的站位跟著道具 | `CH5_GRAY_PATH.md`、`world_prop_actions.json` 的 `ch5_gray_latch_press` |
| ch5_phone_alley 電話亭巷 | 西段可加小落差 | 電話亭（x29）留原位；街道回口、灰道回口、東側鐵網階梯三者分開；入口與電話亭周圍 18 格內不放敵人 | `CH5_LEDGER_CALL.md`、`SCRIPT_CH05.md` 206 行、`CH01_LEVEL.md` 電話亭規則 |
| ch6_harbor_plaza 港區廣場 | 高差、屋頂支線；要加遭遇戰只能是可選、可退的 | 喇叭（x30）與貨梯（要 `ch6_su_approach_confirmed`）不動；復原排隊的人龍保留 | `SCRIPT_CH06.md` 44、50 行 |
| ch6_broadcast_overpass 廣播站高架維修道 | 可加可選遭遇戰（不鎖場） | 上下兩路都要保留連續踏面、落腳燈與可撤回的出口；從下層一定走得到前庭 | `CH06_BROADCAST_APPROACH.md` |
| ch6_broadcast_outside 廣播站前庭 | 外廊、高維修道的視覺細節 | 乾台不放敵人、不限時；水位尺 x24、手輪 x29、退水盒 x35、備援箱 x45、錄音室門 x50 依序排；地面與上層兩種回路，可以折回補做；蘇在雨棚下 | `CH06_RELAY_WATER.md`、`world_prop_actions.json` 的三個裝置動作 |
| ch6_recording_booth 廣播站錄音室 | 不能改 | 安全區；試音監看、蘇、控制終端的順序固定 | `CH06_LAMP_CONTROL.md`、`CH06_STUDIO_TRIAL.md` |
| ch6_rain_chase_alley 市集外街與屋簷 | 只改不限時那條外街的裝飾 | 限時路線起點 (20,17)、普通 23 秒／引導 58 秒、終點三樓便門；乾台與扶手踏板的長度、高度決定趕不趕得上；不放敵人 | `CH06_RAIN_ROUTE.md`、`data/levels/features/ch6_rain_time_trial.tres` |
| ch6_ali_homefront 阿梨家門廊 | 不能改 | 不放敵人；門廊字條與兩個要旗標的出口不動 | `SCRIPT_CH06.md` 124 行 |
| ch6 屋頂（棘的鎖場） | **待定** | **待定**：劇本要求屋頂門和安全重試點在同側、母親坐的錨椅看得見，但還沒有關卡檔可以核對 | `SCRIPT_CH06.md` 130～150 行 |

## 第一到四章（只列有劇情限制的區域）

| 區域 | 可以改 | 不能改 | 依據 |
|---|---|---|---|
| ch1_booth_alley、ch1_rooftop | 安全區以外 | 安全區不放敵人；入口與電話亭周圍 18 格內不放敵人 | `CH01_LEVEL.md` |
| ch1_street 港區街道 | 市集口安全段（x1～48）以外 | 安全段不放敵人；教學段前 9 格不放敵人；觸發格不移：出門獨白 x9、街坊聊天 x27（ST-59）、燈的通訊 x40；發傳單的人站在 x29、夜班工人在 x32（ST-59） | `CH01_LEVEL.md`、`ch1_street.tres` 的 `story_triggers` |
| ch1_stall 宵夜麵攤 | 鐵皮棚以外 | 出口頂上鐵皮棚（第 37～44 欄、第 13 列）的野貓碗在第 41 欄（ST-62） | `ch1_stall.tres` |
| ch1_prologue、ch1_warehouse | 倉庫非鎖場的段落 | 序章是試貨教學，有開場場景；看門狗是不鎖場的迷你頭目，要留逃回街道的路；上層梯是單向的 | `CH01_LEVEL.md` |
| ch2_harbor_street 港區街道（白天） | 觸發格與三個站位以外 | 觸發格 x12（凜與夜班工人的早晨氣泡，工人要在畫面內）；夜班工人 x17（魚攤旁）、早報架 x37（報架擺設）、發傳單的人 x55（排隊告示旁）（ST-60） | `ch2_harbor_street.tres` |
| ch2_loading、ch2_market_gate | 觸發格以外 | 觸發格不移（`ch2_s09_wire`、`ch2_s09_hawker`、`ch2_b_booth_b3`） | 各區 `.tres` 的 `story_triggers` |
| ch3_plaza 廣場貨梯 | 站位以外 | 早班護理員 x21（長椅旁）、廣場公告欄 x26（公告欄擺設）（ST-61） | `tools/level/build_ch3.py` |
| ch3_pump 集水槽與泵室 | 觸發格以外 | 觸發格不移；上層路線一定要留，因為觸發的台詞講的就是它（`ch3_b_c02_upper_route`）；值班櫃 x72（ST-61） | `ch3_pump.tres`、`tools/level/build_ch3.py` |
| ch3_clinic 夾層診所 | 備品間以外 | 裂縫牆後的備品間（x97～102）裡的舊備品櫃 x99（ST-61）；備品間要繼續藏在牆後 | `tools/level/build_ch3.py` |
| ch3_office_hall 天穹辦公接待廊 | 維修廊以外 | 空調維修廊上的維修口 x24、第 13 列（ST-61），工作單講的就是辦公內門上方的出風口 | `tools/level/build_ch3.py` |
| ch4_factory_safety 清理線安全臺 | — | 不放敵人；電話亭保留，它是重生點，清掃工作廊死亡也回這裡 | `CH04_FACTORY_SERVICE_WALK.md` |
| ch4_factory_roof 廠房屋頂 | 可加高差 | 刻意不安排戰鬥；維修平台上的冷氣主機保養卡在第 44 欄（ST-63 收藏文件） | `CH4_LANTERN_ROOF.md` |
| ch4_factory_loading、ch4_factory_work、ch4_factory_relay | 接線廊可調戰鬥與換層 | 裝卸帶與工作帶的固定地面、等待用的支撐、白線清掃範圍外的入口／中段電話／終點；接線廊最下層要一路相連、不封門 | `CH04_SWEEP_REHEARSAL.md`、`CH04_WORK_LANE.md` |
| ch4_nursing_ward 安養病房 | 擺設與動線可以調 | 鷺的現地回放在執行時用名字找床頭櫃（`ch4_cabinet` 與 `nursing_ward__bedside_locker` 擺設）、內廊門與門栓，並沿同一條走道或高架走；這幾件要留在病房、站在可走的地面上，格位可以移、回放會跟著走（ST-63 核對）。備品頂架盡頭的交班便條在第 52 欄、第 11 列（ST-63 收藏文件） | `CH04_LAST_SUNDAY.md`、`game/cutscene/local_replay/last_sunday.gd` |
| ch4_ward_lamp_bay 病房側窗床位 | 擺設與動線可以調 | 床邊收音座要等屋頂通訊請凜架好話筒之後才出現（`MIC_REQUESTED` 旗標）；沒有回放引用格位（ST-63 核對） | `ch4_roof_layout.py` |
| ch4_pawnshop 當舖（赴約） | 地圖動線可以調 | 返店的演出用的是過場舞台（`data/cutscene/stages/`），不讀關卡地圖；櫃台收銀機上的便條在第 52 欄（ST-63） | `CH4_PAWNSHOP_RETURN.md`、`tools/story/ch4_pawnshop_return.py` |
| ch4_ward_reception 病房外櫃檯 | 站位以外 | 早班護理員在第 27 欄（ST-63） | `tools/level/build_ch4.py` |
| ch4_revival_lounge 復原館的換班口 | 站位以外 | 衣帽架旁的失物招領箱在第 50 欄（ST-63） | `tools/level/build_ch4.py` |

另外，第一到三章的過場舞台（`data/cutscene/stages/*.json`）是獨立檔，不讀關卡地圖；但有些舞台沿用關卡裡同一件道具的尺寸，改道具大小時要注意。

## 每區的時間與天氣

畫面線對齊光影用。只列劇本與關卡資料有根據的；沒有寫明的標「未定」，不自己補。同一個地點在不同章節或時段出現，分開列。「現在的光影」是關卡目前引用的 `data/lighting/*.tres`；下雨除了標「關」的區域，都是預設開。

依據縮寫：S1～S6＝`design/13-story-v2/SCRIPT_CH0N.md`、L1＝`CH01_LEVEL.md`、CL＝`CH01_CLOSURE_SCRIPT.md`、PS＝`PROLOGUE_SCRIPT.md`、OL＝`OUTLINE.md`、MAP＝`MAP.md`（以上在 `design/13-story-v2/`）；J2／J3／J5＝`data/story/ch2_heron.json`／`ch3_clearwater.json`／`ch5_paymaster.json`。

| 區域 | 劇情時段 | 室內／外 | 下雨 | 劇情指定的光 | 依據 | 現在的光影 |
|---|---|---|---|---|---|---|
| ch1_prologue 巢蛋當舖（試貨） | 夜（第一晚，晚飯前） | 室內＋店後遮雨棚 | 是 | 店裡暖窗、廚房光保留，不能整店黑掉；工作檯燈由玩家關 | PS:11,25,29,218 | rooftop＋pawnshop_warm |
| ch1_pawnshop 當舖 | 夜 | 室內＋後空地露天 | 是 | 暖黃桌燈、窗外冷藍霓虹、爐火橘光 | S1:451,527；L1:126,135；OL:189 | pawnshop_warm＋rooftop |
| ch1_pawnshop_dawn 當舖（天亮） | 清晨 | 室內 | 是（雨聲） | 灰藍的清晨光＋廚房暖黃 | S1:1067-1068；L1:138,271 | mezzanine_gray |
| ch1_rooftop 屋頂 | 夜 | 室外 | 是 | 遠處塔頂一圈金光 | S1:567；L1:156 | rooftop |
| ch1_street 港區街道 | 夜 | 室外 | 是 | 霓虹招牌、積水反光 | S1:691,709；MAP:416 | street_market 等三段 |
| ch1_booth_alley 電話亭巷 | 夜 | 室外 | 是 | 青色亭燈、冷藍的雨 | S1:636,663；L1:96,206 | alley_calm |
| ch1_warehouse 碼頭倉庫 | 夜 | 室外碼頭＋倉內閘門廳 | 是 | 冷藍、探照燈、水面反光 | S1:742-743,892；CL:9 | warehouse_quay＋warehouse_interior |
| ch1_vault 倉庫深處 | 夜 | 室內 | 未定 | 倉庫停電的暗場 | L1:441；CL:9 | warehouse_interior |
| ch1_handoff 復原館外交接櫃 | 夜 | 室外（館外後巷） | 是 | 青燈櫃，青光不能把臉打到過曝 | S2:100；CL:9,106 | market |
| ch1_lounge 復原館 | 夜 | 室內 | 外面下了一整夜 | 低燈、紫粉與暖黃、雨的反光 | S1:956-958；CL:137 | lounge_safe |
| ch1_stall 宵夜麵攤 | 清晨（凌晨、天亮） | 室外（麵攤頂棚） | 是（雨小了一點） | 凌晨灰藍、蒸氣暖白；L1 指定用 mezzanine_gray 再調暗 | S1:1009-1013；L1:266 | alley_calm |
| ch2_pawnshop 當舖（早上） | 早上（次晨結算） | 室內 | 是 | 未定 | S2:112-114,137 | rooftop＋pawnshop_warm |
| ch2_rooftop 屋頂茶座 | S03 早上；S22 夜 | 室外 | 是 | 未定 | S2:148,153,426；S3:7 | rooftop |
| ch2_harbor_street 港區街道（白天） | 白天 | 室外 | 是 | 未定 | J2「白天還是在下雨」「早」（ST-60） | alley_calm |
| ch2_market_gate 市集入口 | 白天（間接） | 室外 | 是 | 未定 | S2:179；S2:137 | market_gate |
| ch2_market 公眾攤道 | 白天（間接：公告屏預報「今晚」降雨偏多） | 室外 | 是 | 未定 | S2:229 | market |
| ch2_ali_home 阿梨的小廚房 | 白天（間接：阿梨夜班下班之後） | 室內 | 未定 | 屋內淺暖黃 | S2:196,204 | residential |
| ch2_loading 雨棚背面與裝卸間 | 未定 | 半室外（雨棚） | 是 | 未定 | S2:137,159 | market＋hangar |
| ch2_ledger_front 北棟二樓前室 | 未定 | 室內 | 未定 | 未定 | — | warehouse_interior |
| ch2_ledger_office 二樓帳房 | 未定 | 室內 | 是（雨打通風窗） | 未定 | S2:292 | ledger_office_interior |
| ch2_lounge_front 復原館外 | 未定（接著是阿梨準備夜班） | 室外 | 未定 | 未定 | S2:326,340,358 | lounge_front |
| ch3_pawnshop 當舖（週日） | 早上（C00）＋傍晚（C22） | 室內 | 未定 | 未定 | S3:105,415 | rooftop＋pawnshop_warm |
| ch3_plaza 廣場貨梯 | 白天 | 室外 | 是（雨小） | 未定 | OL:191；S3:118 | plaza |
| ch3_pump 集水槽與泵室 | 白天 | 室內 | 未定 | 未定（劇情有斷支路電） | OL:191；S3:131 | pump_room＋pump_drained |
| ch3_mezzanine 夾層通道 | 白天 | 室內 | 外面下（雨外、冷白內） | 冷白管線；上層玻璃只反光，還沒進到日光區 | S3:149,563 | transfer |
| ch3_clinic 夾層診所 | 白天 | 室內 | 未定 | 未定 | OL:191 | clinic_ward |
| ch3_gate_hall 門禁大廳 | 白天 | 室內 | 未定 | 未定 | OL:191 | facility |
| ch3_glass_edge 玻璃邊緣 | 白天 | 室內（玻璃內） | 否（下雨關） | 第一次看到陽光：腳底有光，人物曝光漸變 | S3:297,302,566 | sunlit_edge |
| ch3_showroom 晴岸樣品房 | 白天 | 室內 | 否（下雨關） | A 晨窗上午 8～10 點最亮、C 晚窗下午 2～4 點最亮、B 靜窗少有直射 | S3:320,335,337；J3 | showroom_day＋showroom_quiet |
| ch3_office_hall 天穹辦公接待廊 | 白天 | 室內 | 否（下雨關） | 未定 | OL:191；S3:358 | reception_white |
| ch4_pawnshop 當舖（赴約） | 早上（星期日）；回程未定 | 室內 | 是（屋漏、從屋外帶雨回店） | 暖光 | S4:51,245；CH4_PAWNSHOP_RETURN.md:13 | rooftop＋pawnshop_warm |
| ch4_ward_reception 病房外櫃檯 | 未定（週日） | 室內 | 未定 | 黃色病房牌當路標 | S4:38,63 | reception_white |
| ch4_nursing_ward 安養病房 | 未定（週日） | 室內 | 未定 | 暖色床頭燈標出可訪床位 | S4:39 | clinic_ward |
| ch4_ward_lamp_bay 病房側窗床位 | 未定（週日） | 室內 | 是（雨窗） | 暖色床頭燈 | S4:39；CH4_ARCHIVE_RECORDING.md:5 | clinic_ward |
| ch4_revival_lounge 復原館的換班口 | 未定 | 室內 | 未定 | 背光的舊排班牌 | S4:40 | lounge_safe |
| ch4_factory_approach 舊廠外廊 | 未定 | 半室外 | 未定 | 廠外保留暗色 | CH04_FACTORY_APPROACH.md:14 | factory_rust |
| ch4_factory_loading 舊廠裝卸帶 | 未定 | 室內 | 未定 | 固定亮度的暖色工作燈 | CH04_FACTORY_APPROACH.md:14 | ch4_loading_bay |
| ch4_factory_cleaning／relay／safety／work | 未定 | 室內 | 未定 | 未定 | — | ch4_loading_bay |
| ch4_factory_office 原帳辦公室 | 未定 | 室內 | 未定 | 未定 | — | clinic_ward |
| ch4_factory_roof 廠房回程梯與屋頂 | 未定（OL 只說第四章「陰」） | 室外 | 是（小雨） | 未定 | S4:229；OL:192 | rooftop |
| ch5_pawnshop 當舖（貨架盤點） | 未定 | 室內 | 未定 | 櫃台黃燈；葉在暖燈的工作檯旁 | S5:26；CH05_PAWNSHOP_OFFER.md:3 | rooftop＋pawnshop_warm |
| ch5_back_alley 當舖後巷 | 未定 | 室外 | 是 | 未定 | S5:13；J5 | 無區段 |
| ch5_basement_stair 地下室樓梯口 | 未定 | 室外到室內 | 是 | 樓梯口一盞帶雨滴的黃燈，從街上要看得見 | S5:27,94；CH05_STAIR_ENCOUNTER.md:3 | 無區段 |
| ch5_basement_archive 地下室檔案間 | 未定 | 室內 | 未定 | 暖燈下的錨椅 | CH05_ANCHOR_CHAIR.md:3 | basement_amber |
| ch5_gray_path 灰道換班廊 | 未定 | 室內 | 未定 | 小桌留一盞暖燈 | CH5_GRAY_PATH.md:5,7 | 無區段 |
| ch5_harbor_street 港區街道 | 未定 | 室外 | 未定 | 從街上看得見樓梯口的黃燈 | S5:27 | 無區段 |
| ch5_phone_alley 電話亭巷 | 未定（第六章開頭說接的是「那場雨延續下來的晚上」） | 室外 | 是 | 電話亭亮起暖燈 | S5:198；S6:5 | 無區段 |
| ch5_revival_lounge 復原館 | 未定 | 室內 | 未定 | 未定 | S5:60 | lounge_safe |
| ch6_harbor_plaza 港區廣場（廣播前） | 夜 | 室外 | 是（暴雨） | 塔的雙白燈、廣場鐘；復原隊伍沿燈號排隊 | S6:5,34,156 | 無區段 |
| ch6_broadcast_overpass 廣播站高架維修道 | 夜 | 室外 | 是 | 貨梯燈從琥珀轉成冷白 | S6:5；CH06_BROADCAST_APPROACH.md:13 | 無區段 |
| ch6_broadcast_outside 廣播站前庭 | 夜 | 室外（有雨棚） | 是（斜雨） | 接點燈、告示燈 | S6:62,80,246 | ch6_studio_light |
| ch6_recording_booth 廣播站錄音室 | 夜 | 室內 | 未定 | 未定 | S6:5 | ch6_studio_light |
| ch6_rain_chase_alley 市集外街與屋簷 | 夜 | 室外 | 是 | 走路燈亮著的外街 | S6:114 | 無區段 |
| ch6_ali_homefront 阿梨家門廊 | 夜 | 室外 | 是 | 未定 | S6:5；CH06_RAIN_ROUTE.md:1 | 無區段 |

### 劇情時段和現在的光影明顯不合

1. **ch2_harbor_street**：劇情是白天下雨，現在用第一章夜裡電話亭巷的 `alley_calm`；色彩腳本也配成鈉燈琥珀的夜色。
2. **第二章白天的室外**（市集入口、公眾攤道、裝卸間）：色彩腳本把第二章當夜景（COLOR_SCRIPT 21、74 行）。`OUTLINE.md:190`（第二章「夜到凌晨」）與 `MAP.md:426`（屋頂「凌晨」）是較舊的寫法，和劇本 S2「次晨」、遊戲裡的「白天」不合，以劇本為準；這兩份舊文件待故事線更正。
3. **ch2／ch3／ch4 的當舖（早上、週日早上與傍晚）**：都沿用第一章夜晚的 `rooftop＋pawnshop_warm`，後空地是夜雨屋頂。第一章天亮版已換成 `mezzanine_gray`，這三章沒有白天版。店內暖燈可以保留，窗外與後空地的光不對。
4. **ch1_stall**：劇本是凌晨灰藍，L1 也指定 `mezzanine_gray` 調暗，實際用夜巷的 `alley_calm`。另外 `CH01_CLOSURE_SCRIPT.md:164` 稱這場「今晚」，和劇本「天亮」不一致，以劇本為準，待故事線更正收尾稿的用詞。
5. **ch3_plaza**：劇情是白天、雨小；色彩腳本給的是洋紅霓虹的夜配色，和它自己寫的「第三章室外暖杏、太陽暖光」不一致。
6. **ch2_rooftop**：同一區要演早上（S03）和夜裡（S22），現在只有夜雨的 `rooftop`。
7. **下雨開關**：只有第三章三個玻璃區關掉雨，其他室內區都是預設開（例如 ch1_vault、ch3_clinic、ch6_recording_booth）；室內會不會畫出雨要看引擎，這份文件沒有確認。

### 未定較多的地方

- 第五章八區都沒有寫時段，只能從第六章開頭推出結尾的電話亭巷是晚上。
- 第四章除了當舖的星期日早上，其他區只知道是週日；工廠各區的雨和光都未定。
- 第二章中段（裝卸間、北棟前室、帳房、復原館外）沒有寫時段；第二章的「白天」多半是間接證據。要定下來屬於劇本決定，故事線會把問題列進 `design/06-roadmap/open-questions.md`，不自己補。

## 更新紀錄

- 2026-11-28：ST-59 建立（故事線依地圖線需求整理）。
- 2026-11-28：ST-60 加入第二章港區街道（白天）的觸發格與站位。
- 2026-11-28：ST-63 核對第四章回放引用的位置，並加入第四章的新站位與兩份收藏文件。
- 2026-11-28：ST-62 加入第一章麵攤鐵皮棚的野貓碗。
- 2026-11-28：加入「每區的時間與天氣」（依劇本與關卡資料整理，給畫面線對齊光影）。
- 2026-11-28：ST-61 加入第三章廣場、泵室與兩處秘密空間的站位（第三章由產生器輸出，改站位要改 `build_ch3.py`）。
