# NE261 狹義來源審查（2026-11-12）

只讀immutable原提交 `bbe79e04e38edf0e8848cfb336840862442b51c6` 與已發布 `a4f2db7a81cd8c58bf8dea1afcdf499375dcba58`，沒有讀primary C的未交NE27726作發布版，也沒有引擎、音訊解碼、下載或新試聽。Root對兩份原OGG的decode／原音量規則已另在 `work/ne261-independent-review-20261112` 完成，本工作不重做。

入口：[source-index.json](source-index.json)固定原95／發布97份Git原byte；[index.json](index.json)逐檔／逐欄比較；[reader.py](reader.py)完全離線讀取來源副本；[commit2.diff](commit2.diff)與[commit2-evidence-scope.json](commit2-evidence-scope.json)保留歷史測試聲稱範圍。`python -X utf8 reader.py` 重算30檔與授權鏈；`python -X utf8 -m unittest test_reader -v` 六個故意壞資料控制均拒絕。沒有新播放／功能／人耳或回歸通過宣稱。

## 檔案與登記

五把每把 swing_a、swing_b、swing_heavy、hit、hit_heavy、idle，共30個OGG全部逐byte相同；每個bank entry、pipeline配方、source layers、逐檔LICENSES登記、cache fingerprint/SHA1與Godot import也相同。30輸出追到35次配方component、12個來源pack；每個component的原始filename與output都在LICENSES列出，manifest／LICENSES記CC0-1.0且頁面一致，bank.pack也等於配方pack集合，pipeline與bank volume一致，5個idle的loop配方／bank flag齊全。這是**既存檔案的來源登記一致性**，不是本輪重新打開頁面作授權判定。部分author仍是原記錄的`?`，不補造作者或授權證書。

整份pipeline／LICENSES／manifest／cache／sound_bank／materials／slots／stage_scenes在這兩提交間其實也相同，並非只推定selected相同；`sound_events.json`整份已不同，但戟／錘／鞭的三個first-swing事件selected內容相同。`license_check.json`只有2026-10-06、982頁／0problems摘要，沒有逐頁清單，不能由該總數新證這12pack都被哪頁檢過。

五份招式JSON**整份不同**；原16個attack ID的sounds、各combo和idle ID仍相同。已發布版每把多1個hold attack：dash_cut／frenzy／guard_stance／quake／orbit，合計5個，原版沒有hold。原24段錄音（4個ref＋5把各idle/miss/hit/holster）不覆蓋這5個按住模式，不借用未交NE277證據冒充本輪發布版已錄過。

## 播放路由（來源分析，非新執行）

- `MeleeHum`整份相同：PlayerVisual每process呼叫follow，`shows_melee_weapon()`且可見／Sfx.enabled時選MeleeSet.idle_sound；單一AudioStreamPlayer掛SFX bus，BASE_DB=-12、出招gain目標.45、fade-out5/秒，gain≤.02時stop。切聲前先淡出，stream複製後設loop=true。因此 `.ogg.import`的loop=false不等於待機不迴圈。5個idle bank volume都是0；這段Hum直接取variants，未走一般Sfx.bank volume疊加，不能用修改idle bank volume而期待這條路自動套用。
- 原Player `_melee_strike`先真hit_pass，當下未landed才播swing；命中聲在 `_melee_hit_pass` 真DAMAGED後播。發布版已移到MeleeModule `_strike`／hit_pass，仍是未landed才swing、landed_now才hit_layers，並每hit window去重；多段／hold已是後續新語義，不能稱整份Player或播放時序跟原版byte相同。
- 戟／錘／鞭first-swing ID經Sfx.play_named→play_event→_pick_variant，兩個以上變體不連續選同一個；刀／匕首連段直接a/b/heavy。所有原attack聲音ID仍能解析到bank或事件。
- 真命中另外走HitFeedback.play(target.material_id(),...,weak)。materials與HitFeedback整份相同，guard BLOCKED由既有Hurtbox/擋下owner處理，並非把所有材質改成一個武器hit。此輪只核源碼／資料，沒有逐材質新試聽或新實際命中。

## 原使用者試聽紀錄與七條驗收

`source/original/pm/Nest-Egg/[NE-261]…md`已包含2026-10-12補記「使用者聽過附件的錄音，確認聲音可以」，原commit的CommitDate為2026-10-12；精確原行號／文字在source-index。這是既有票內的使用者驗收紀錄，不說成我或Root本輪聽過，也不自行宣稱有該使用者對話錄音。

| 原驗收 | 狹義來源能證明 | 不可擴張的部分 |
|---|---|---|
| 五把可辨、重聲更低長 | 30檔不變、獨立ID／原使用者聽過紀錄存在；配方保留rate/filter/max_len | 本輪沒新逐檔重心／長度解碼或新盲聽；檔名／配方不是聽覺實測 |
| 小待機、不蓋腳步／環境、收起停 | 5個不同idle、真loop與fade/stop來源路徑相同 | 音量與停止實證需可信sample對齊錄音，原wallclock index有真缺口 |
| 每段不同／尾重／揮空不命中 | 原combo選定sounds與first事件同；分支仍把miss和hit分開 | 原錄音不含新增5hold；current module/window語義不等於原Player |
| 材質差異 | materials與HitFeedback同、依真material_id分支 | 原錄音主要armor靶，不是全flesh/mechanical/shield音訊矩陣 |
| CC0逐檔與素材檢查 | 30輸出／35components／12pack登記鏈、SHA與cache均一致 | 無新網路license查驗；舊AudioSuite通過數不由本源碼審查補造 |
| 與槍聲平衡 | bank／pipeline音量同、SFX bus路由存在 | Root已發現原index越過OGG尾；原report problems0不能作完整可信驗收 |
| 原生五把錄音／波形 | 原兩OGG與24段index在兩提交間byte相同，原檔確實存在 | 原始WAV／encoding command／sample錨點未封，需區分壓縮解碼診斷與原PCM |

Commit2的28份高負載／每份152 checks與單跑1522只有票內文字；原附件樹仍只有2OGG＋index，沒有這些測試raw。源碼確有改成狀態接招（最多3試、等待可接／尾段完成），但不能由差異或新reader把原28輪／1522補報綠。

## 時間源真缺口與下一步

原probe所有段落用 `Time.get_ticks_usec()` wallclock，兩Record啟動之後才設 `_start_usec`；沒有實際PCM frame錨點。尾端更是先停兩Record、存兩WAV、還原upgrade，之後才`total=_now()`並設最後holster.end，所以最後邊界包含停錄後I/O。Root已量原兩OGG45.738667s而最後end46.000338，嚴格reader真拒絕。缺原WAV／encoder command／stop timestamp，不能斷言.261671全是排空、I/O或壓縮裁切；整段wallclock與PCM也沒有可證對齊。

Master先有Settings掛的HardLimiter，原Record再append；因此Master是post-limiter，SFX是pre-master。原report直接master-sfx推bed，還假定同rate／同start且slice不越界。這些假定沒有原bus拓撲／sample錨點證據，不能直接視為精確背景音。本輪不改原資料或門檻。

最小候選另在 `timing-candidate/`：先只用獨立2秒audio-only project，實際headless/dummy rendering＋WASAPI，Record旁Capture的pushed/discarded/frame錨點對Record PCM，最後end先固定再save；任何drop／越界／不匹配必須紅。不建立通用框架、不修改C或受保護D runtime。只有這個小原型已獲Root授權，遊戲整輪重錄、背景bus與native畫面另階段安排。
