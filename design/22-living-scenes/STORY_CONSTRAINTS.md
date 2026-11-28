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
| ch1_prologue、ch1_warehouse | 倉庫非鎖場的段落 | 序章是試貨教學，有開場場景；看門狗是不鎖場的迷你頭目，要留逃回街道的路；上層梯是單向的 | `CH01_LEVEL.md` |
| ch2_harbor_street 港區街道（白天） | 觸發格與三個站位以外 | 觸發格 x12（凜與夜班工人的早晨氣泡，工人要在畫面內）；夜班工人 x17（魚攤旁）、早報架 x37（報架擺設）、發傳單的人 x55（排隊告示旁）（ST-60） | `ch2_harbor_street.tres` |
| ch2_loading、ch2_market_gate | 觸發格以外 | 觸發格不移（`ch2_s09_wire`、`ch2_s09_hawker`、`ch2_b_booth_b3`） | 各區 `.tres` 的 `story_triggers` |
| ch3_pump 集水槽與泵室 | 觸發格以外 | 觸發格不移；上層路線一定要留，因為觸發的台詞講的就是它（`ch3_b_c02_upper_route`） | `ch3_pump.tres` |
| ch4_factory_safety 清理線安全臺 | — | 不放敵人；電話亭保留，它是重生點，清掃工作廊死亡也回這裡 | `CH04_FACTORY_SERVICE_WALK.md` |
| ch4_factory_roof 廠房屋頂 | 可加高差 | 刻意不安排戰鬥 | `CH4_LANTERN_ROOF.md` |
| ch4_factory_loading、ch4_factory_work、ch4_factory_relay | 接線廊可調戰鬥與換層 | 裝卸帶與工作帶的固定地面、等待用的支撐、白線清掃範圍外的入口／中段電話／終點；接線廊最下層要一路相連、不封門 | `CH04_SWEEP_REHEARSAL.md`、`CH04_WORK_LANE.md` |
| ch4_nursing_ward、ch4_ward_lamp_bay、ch4_pawnshop | **待定** | **待定**：病房櫃子、廊門的位置可能被回放引用，做第四章環境敘事那張票時逐一核對後補上 | `CH04_LAST_SUNDAY.md`、`CH4_PAWNSHOP_RETURN.md` |

另外，第一到三章的過場舞台（`data/cutscene/stages/*.json`）是獨立檔，不讀關卡地圖；但有些舞台沿用關卡裡同一件道具的尺寸，改道具大小時要注意。

## 更新紀錄

- 2026-11-28：ST-59 建立（故事線依地圖線需求整理）。
- 2026-11-28：ST-60 加入第二章港區街道（白天）的觸發格與站位。
