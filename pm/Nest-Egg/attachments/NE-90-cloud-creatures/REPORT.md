# NE-90 雲端非人形實際稽核／NE218 接口交接

審查用證據，**不是 NE90/NE218 已交付或完整驗收通過**。本分支只含本 Session 的 attachments/images 和私有 runner 安裝來源，不修改票正文、共同selector、game/art/source。root 承接 NE90/NE218 與 main；NE224 做 Forward+HDR／實機 perf／真輸入。沒有新duplicate票。

## 可核對的實測結果

基線 c0250bff9dd6a44a8b1c9df557eaab18b0a12996；最新fetch/rebase資訊見 synchronization.md。真 repo／環境／CI要求／錯誤見 environment-start.md、environment-status.json、原log。實際引擎4.7.stable.official.5b4e0cb0f；4.6.3明確拒收（rejected-engine.log）。headless Dummy 真執行；軟體Compatibility+Xvfb真渲染，native1280×720、接點atlas2048寬，driver opengl3 / llvmpipe LLVM19.1.7。無GPU／Comfy。

- 17 JSON＝16正式既有模型＋test_creature fixture；38 EnemyData，另watchdog為預期四足但仍人形。所有16模型都盤點，不漏第三章保留未配置的飛行單位／模型。buoy_worm_small真倍率0.62另測；沒有把無腿／飛行體要求走路。
- 全57原始PNG／62 runtime PNG的SHA與原生RGBA尺寸、alpha bbox、部件pivot/pos/parent/z、gait、掛點及caller見inventory.json。31張實際selected來源按既有make_creature_parts轉製在記憶體重現，RGBA byte一致31/31（source-check.json）；不修改來源／mask／runtime PNG。alpha0 RGB另計、不當extra parts。灰底composite維持原始source尺寸。
- Godot實載11種PartCreature、30個part node；各normal與diffuse尺寸一致。Chain/Worm材料品質沒有由此代驗；LitTextures只認_n，並沒有自動_glow掛載契約，發光自調色與HDR gate分開。
- 精確affected：PartCreatureSuite、ChainCreatureSuite、ExoticEnemiesSuite、Chapter1EnemiesSuite、AssaultEnemiesSuite，681 checks/0 assertion failures，~103.6秒。bad-data no_such_creature及exit資源/RID ERROR保留，按既有test_filters排除；沒有SCRIPT ERROR，不改known_failures。rebase後同5個explicit Suite實跑686 checks/0 failures、107.681秒，見rerun-affected.log與command-affected.json；不硬把assert數改成舊681。完整CI未驗（statuses=[]不是pass）。更新後首次缺.ctex的失敗log也保留，重import後才計數。
- finite transforms：所有真JSON states×120frames×兩face×兩zoom，43,200樣本0非有限值／空part失敗，2590ms（最新重跑值見numeric.json）。只證數值／非空，不證解剖、rest長、骨架、材質接地。
- 非human registry從真part父子／每個chain bone生成，15種模型、628,800樣本、2,160張原生atlas；render846.601秒，既有alpha checker268.911秒，138,875旗標（checker exit1）。alpha≥128、8世界像素radius、連通件、一像素洞門檻不變。全部旗標保留contact-failures.jsonl.gz，不提高門檻、不known_failure、不遮暗。rail_cannon的4800 band無旗標只算這個band gate。
- 負控制：同樣真渲染移開child32world px，與乾淨原樣本逐key比較，6個**新增**失敗；不借既存失敗證工具有效。controls.py可重跑；原checker的一像素洞／斷件self_check通過。
- FootGait兩assertion通過；salvage_arm/buoy_worm/小蟲48組（idle/half/full/turn、兩face、1/3.4）、每組120格：兩格都踩地的world target slip=0、target ground error=0。這不是材質腳掌pass。全worst frame/leg/target/tip/rest segment記gait.json；12張原生幾何診斷PNG復現全部worst error。轉身重定位／大誤差屬rig/gait待查，不改runtime。官方原始犬步態來源請求404/403，未取得、已停，不宣稱官方相位驗證。

## 每物種結果

數字是「band樣本／旗標」，**旗標不是全部已確認art defect**。下表全部模型的source reproduction與finite gate已測；未列可通過的完整物種。dead/stagger缺少真資料列missing；attack與move按真資料招式，不硬補walk给飛行體。各Enemy FSM、creature_states及行為繼承在runtime-metadata.json；不能把有JSON key當真runtime caller已播放。

| 模型 | Runtime | 正式資源掛載 | 實際動畫keys | band／旗標 | FAIL／未驗與來源回查 |
|---|---|---|---|---|---|
| bomber | PartCreature | bomber | idle, chase, fuse | 10080/3359 | 六腳part；灰底可見至少三腿，其餘遮擋。鉸鏈標記待來源／遮擋回查；未證全六腳接地。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| buoy_worm | ChainCreature | buoy_worm, buoy_worm_small | idle, walk, swell, spit, dead | 43200/2324 | 六短觸足；FootGait target鎖定通過，腳尖偏差／翻面待修查。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| cloud_jelly | ChainCreature | cloud_jelly | idle, drift, charge, discharge, dead | 129600/43018 | 六觸鬚（遠近遮擋）；漂浮，不要求走路。鐘罩／觸鬚根及透明網格標記待回查。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| cloud_serpent | WormCreature | cloud_serpent | idle, lurk, rumble, erupt, dive, dead | 0/0 | 頭＋連續身帶；不要求走路。Worm top_level mesh未納入接點checker，1/3.4真顯示尺度未驗。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| drone | PartCreature | drone | idle, hover, lock, dive, climb | 7200/2787 | FAIL：idle frame119 face1灰底上方wing與機身可見分離。2翼node／來源兩對翼規格須再核；不要求走路。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| mimic | PartCreature | mimic | idle, dormant, shake, lunge, recover, exposed, shake_open | 3360/3360 | closed/open切換件，只顯示state指定件；pivot空白單圖band不是joint裂縫。張嘴／撲咬全彩序列未驗。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| rail_cannon | PartCreature | rail_cannon | idle, slide, track, lock, dead | 4800/0 | 滑座＋砲身；band0旗標只代表該門檻通過。槍口／後座／死亡全彩未驗。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| repair_drone | PartCreature | repair_drone | idle, follow, channel | 4320/1032 | 機身＋兩機械臂；idle近側工具與身體相交可見。飛行／channel接點旗標待回查。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| salvage_arm | ChainCreature | salvage_arm | idle, alert, walk, sweep_windup, sweep, slam_windup, slam, dead, exposed | 259200/2201 | 六觸足而非犬腿；FootGait target鎖定通過，轉身幾何tip-target偏差58.937（face1×3.4）。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| searchlight_drone | PartCreature | searchlight_drone | idle, patrol, spot, alarm, unpowered, reboot | 8640/1368 | 機身＋兩推進器；旗標待source與遮擋回查，非步行角色。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| shaft_bat | PartCreature | shaft_bat | idle, hover, lock, dive, climb, glide, turn, dizzy, dead | 12960/3453 | 機身＋兩翼；一翼展開另一翼側視有遮擋；飛行狀態旗標待回查，不要求走路。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| shock_hound | PartCreature | shock_hound | idle, prowl, circle, growl, pounce, recover | 5760/5658 | FAIL：真犬體四肢融合在body，只有body/tail、gait.legs=[]；growl/pounce用sx/sy改體長，無獨立四feet／接地。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| swarm_bee | PartCreature | swarm_bee | fly, buzz, sting, recover, dead | 2400/1072 | 一張完整蜂含腿／翼，飛行body channel不等於獨立翅拍；单图band空心不當joint失败。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| tangle_wire | ChainCreature | tangle_wire | idle, hidden, warn, lash, retract, dead | 129600/64443 | 五鏈由牆固定的附肢；非承重步行，口／尖端／網格旗標待source回查。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| turret | PartCreature | turret | idle, track, lock | 4320/1440 | base/head/barrel父鏈；idle可見槍身完整。旗標需比對槍械轉軸與底層，真muzzle/input未驗。 缺：dead, stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| wall_gecko | PartCreature | wall_gecko | idle, crawl, hang, windup, leap, land, dead | 3360/3360 | FAIL：完整壁虎含腳爪尾都融合body，gait.legs=[]；crawl/leap/dead整圖sx/sy非四脚獨立步態／倒下。 缺：stagger（受擊動作，不以flash代驗）；其餘門檻未驗。 |
| buoy_worm_small | ChainCreature，共用buoy_worm | buoy_worm_small、creature_scale=0.62 | 同buoy_worm | 接點atlas只基礎1.0；0.62獨立48組步態其中16組 | worldtarget gate通過；轉身tip偏差37.343（face1×3.4）；小蟲全狀態全彩未驗。 |
| watchdog | 實際CharacterRig warden | watchdog、custodian→warden_boss→Enemy | dormant現場；reachable表見interface | 不拿人形14點代驗四足 | **FAIL NE218**：native PNG真載rig=true、creature=false，人形二腳。無四foot／quadruped素材。 |
| test_creature | PartCreature fixture | 無 | 測試用 | 排除正式模型驗收 | fixture不充交付件。 |

正式第一章只drone/watchdog為此組；其餘人形六種名單在chapter_rosters。舊Demo/第二章/保留未配置都分列在inventory.json level_resource_refs/chapter_rosters；level reference不是實際spawn數或真輸入。art/portraits只既有人形／system，無上述16模型專屬立繪；不能把warden肖像當watchdog四足。盾衛犬舊註解／敗北卡稱謂與shield_rusher.tres「天穹鎮暴員」人形enforcer不一致，按最新正式data留給human組，不在本分支改故事或重開四足規格。

## 已確認阻塞與最小歸因

watchdog：data rig_skin優先使PartCreature永遠不建；真Enemy screenshot已確認，不是預覽假掛載。NE218-interface.md與minimal-mount.patch供root接線；patch未套用，沒有watchdog.json時禁止當可交付patch。需要真四足部件、固定上／下肢rest長、四腳來源pivot與foot contact、兩面向遮擋底層、neck/head/jaw/tail/weapon/core、normal/glow同對位。不得以監管者或兩腳一尾替代。

shock_hound/wall_gecko：source灰底與native snapshot可見完整犬／壁虎身體，四肢／爪／尾不是被alpha0 RGB虛增；source轉製31/31排除轉檔破壞。真正缺口在切件／rig-gait資料：沒有可獨立四腳，sx/sy拉伸改體長。root於原NE90/NE100/NE99處理，勿讓現有宣稱四肢交替的description變成假pass。

drone：原生idle frame119 face1 zoom3.4全彩可见上方wing懸離body；frame119近側wing_near接點旗標見confirmed-failures.json（含native SHA／來源SHA／最小repro）。source轉製一致，優先回查wing的source hinge pivot=[6,62]、body上的pos=(-5,-3)/(-1,-3)與state rotation；不是missing PNG。不能只是減小radius或改透明threshold讓它消失。root按NE90/NE91修source pivot／mask／rig對位，無戰鬥改動。source hinge視覺候選(433,642)，真alpha裁框(339,86,458,686)，換算runtime約(10.269,59.307)；既有pivot(6,62) alpha=0、反推source(393.923,667.25)，候選(10,59) alpha=250。見drone-source-coordinate.json；候選尚未套用，不當作已修pass。

Chain轉身：gait.json與gait-render.log原生重現target與geometry tip誤差，salvage_arm turn58.937、buoy_worm turn45.128、small37.343（face1×3.4）。紅圈=世界FootGait target，青圈=geometry tip，白線=ground_probe y0；marker是診斷不當正常美術。tip不是材質最低點，因此仍須source-mask接地驗證，不直接把每個數字當腳掌離地。初始idle frame0也記錄，不能丟掉預熱前失敗。

## 旗標的信任範圍與未驗門檻

hinge/body_chain是實際部件/鏈根接點；continuous_mesh_band是同一mesh內的骨點；single_source_band是單圖pivot，**不是兩件接縫**。mimic、wall_gecko、swarm的單圖pivot空白旗標不能診斷為art裂縫。合法輪廓缺口／嘴洞／遮擋也可能觸發原alpha inspector，需source-mask與全彩追查。非空registry和真負控制僅證檢查器可抓斷接，不證全部解剖契約。因此138875保留FLAGGED_BAND_REQUIRES_SOURCE_REVIEW而非全判素材FAIL。

全彩截圖只各模型首狀態frame119兩面向，以及12組步態worst診斷；**不是所有120frames全彩逐格通過**。contact atlas各state兩face兩zoom120格，隔離部件/網格的alpha檢查不能替代全彩輪廓、原始source肢數全遮擋追蹤、weapon/recoil/muzzle真輸入、受擊／倒下、armor底層／方向反轉、normal/glow實照、ForwardHDR或perf。全量全彩人工逐格、cloud_serpent專屬可信接點、各物種材質接地／rest長與膝肘解剖判定仍未驗。完整未驗表直接留給root／NE224，不標已完成。

## 重跑與保存

Python Pillow/numpy、現有Godot4.7與已import的project；不安裝新工具、不調GPU。runner/* 是可提交來源；rerun.py先複製到忽略的.godot/cloud-creature-audit，只選指定私有scene或上列5個真Suite。source/check/controls只寫本owned evidence。任何empty set或錯引擎拒收。先正常editor import（已有import-latest.log命令條件），絕不拿missing.ctex結果當素材失敗。

```bash
python3 pm/Nest-Egg/attachments/NE-90-cloud-creatures/rerun.py --repo "$PWD" --godot /workspace/.nest-egg-env/godot/Godot_v4.7-stable_linux.x86_64 --step numeric
# 同一CLI step: inventory/source/affected/gait/metadata/check/controls
# render步驟需 DISPLAY=:94 LIBGL_ALWAYS_SOFTWARE=1、既有render library LD_LIBRARY_PATH
# render step: capture/watchdog/gait_capture/joints/negative/repro
```

--step joints 會全量120格，約15分鐘；check exit1是本次旗標結果，不能改成0代驗。repro只shock_hound tail/idle/face1/3.4/1frame，tag保護全量資料不被覆寫。drone完整最小重現是capture.gd scene的frame119；接點CLI：joints.tscn -- --id=drone --state=idle --part=wing_far --frames=120 --face=1 --zoom=3.4 --tag=repro-drone-wing（frame119）。所有原生atlas保存在專案images；gzip完整旗標、native圖sha和manifest可定位任一state/frame/face/zoom/part，來源SHA由inventory映射，20個代表例額外直接附sourcehash。

原門檻不改、未改共享test/selector/known_failures，無新票／用户同意勾選。票正文／下一Commit-N／審查中由root接收原票整合後處理。本地main/work他人檔不reset、不stash，不删未合branch/worktree。
