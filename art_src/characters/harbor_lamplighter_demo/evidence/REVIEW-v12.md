# v12 新讀者角色驗證紀錄

本角色為 `harbor_lamplighter_demo`，43 歲成人男性港區修燈工，身高 57 世界像素。只在隔離預覽與工具 fixture 使用；沒有新增正式故事講者、台詞、關卡或地圖人物。原圖為新生成的原生透明 832×1216 RGBA，base SHA256 `4cbdd4ff46e1ee28cabbfce08655e4052ff1cf7ef77dd72314eab6d20f855e59`。

## 固定版本與真結果

`production-v12-freeze-123.json` 列出正式 runtime47、authoring65、preview/fixture11 的逐檔 SHA256；其 123 路徑在官方測試期間固定。完整來源 epoch 在封包中保留 `source-v12-matrix/`，包含規格、原圖、P、SAM、06/07、眼圖、runtime、骨架、動作與工具 hash。原始圖沒有被修改。

| 原始 auditor 模式 | combat | NPC五姿態 | 站坐進出 | lean | crouch | hammer | 總樣本／失敗 |
|---|---:|---:|---:|---:|---:|---:|---:|
| as-worn | 8 | 342 | 2 | 0 | 0 | 6 | 120960 / 358 |
| pair-only | 8 | 342 | 2 | 0 | 0 | 6 | 120960 / 358 |

每組皆 120 格、正反面、1×及3.4×、14個實際接點；hammer週期1.1秒、vary0.12，120格涵蓋完整週期。188筆含8鄰接封閉像素的樣本全在wave主區。原 `check_joint_frames.py` 的門檻、exit1與報告維持原樣，`automatic_joint_acceptance:false`；這份紀錄不宣稱358自動歸零。

原 AnimAudit（全部combat與NPC stand/sit/lean/crouch/hammer）0失敗；原有NPC foot-floating倍率保留，空手grip與坐姿地面等原本不量的項目明列不適用。check_spec 0錯誤/0警告；check_seams strict 0 findings；check_parts含normal為OK。原圖重組使用原max-hole0，0個不允許洞；13467px被省略的遠側褲腿／鞋僅屬已檢視的靜態來源allowance，動態接點沒有任何allowance。

## 修好的實際素材問題

- 來源遠腿遮罩曾咬入近小腿／鞋，改遠鞋限定與近小腿front_line後，近側一件只含一腿一鞋；未複製第二套腳。
- 模板smooth_alpha曾丟掉原生邊緣像素，已移除本角色該操作。補回實際漏認的原肩背素材，沒有調寬reassembly門檻。
- 透明RGB被fill取樣造成洋紅污染，由已發布共用refine修正；本角色暫時local override已退役，配方沒有活動source-repair hook。
- 膝水平線經normal開/關×剛體/網格四控制定位為分片法線內部邊，不是alpha缺料。保留法線，使用標準painter之後的已登記連續來源法線；只改指定三腿件normal，diffuse/pivot/rig保持。舊四控制只有當時留下的診斷影像／metadata，不冒稱有完整當時來源快照。
- 廣腿underlap造成重複布片、arm矩形underlap造成袖stub，兩者均撤回，失敗版本留存。採用已驗過的窄limb_zone0.2，沒有改renderer或稽核限值。
- 頸部原皮膚被SAM交給torso，頭轉後真的露洞。v9先復原後頸，v10孤立小前喉窗退化；v11改成與下巴連續的原生前頸polygon。所有改動與既有fill/defringe額外變色、AA變化逐點收在pixel receipts，沒有寫成所有變更都等原圖。v12沿用v11頭部。
- 最後踝邊緣由原foot cap持有的近側褲口33px恢復到calf重疊區，33點全部原foot owner與原圖有料；其餘8片逐位元不變，非擴大caps。踝單類完整combat0/7680、transition0/1920；原眼圖因頭部未變而合法沿用。

## wave342：動作圍出的主開口

獨立審查原v7的報告與重算腳本亦原樣封存：`work/ne255-independent-ui-review-v7/{REPORT.md,verify.py,verification.json}`。該報告不冒充新版本通過證明。

本次v12重新跑480cell的pair/whole並對照全部原始孔位：342/342都含同一主區；1072個孔pixel occurrences全部在主區，沒有v7矩形stub造成的副區。whole對這1072點實際覆蓋0。frame26逐三角形UV回投：torso落原前頸外alpha0，arm落原torso衣料但SAM arm0/arm source0，符合下巴與抬袖之間的空氣輪廓。來源／原生全彩均檢視，不為壓數字而填下巴空氣。

這是全家族位置統計＋代表格來源對照，不是1072點全部逐格UV反投影。whole另將開放空氣圍閉，原raw382/480，不能用它替換原342或宣告自動通過。詳 `wave-v12-pair-whole-comparison.json`。

## 其餘16筆：逐筆真UV與AA覆蓋

`final-small-items/source-mapping-all-16.json` 對每筆保留：原full矩陣PNG/rect/SHA、未重採樣128×128原生crop、當格／當面向重新執行原auditor的geometry、全部凍結來源hash、實際RGBA、source owner及runtime texel2×2。16/16診斷與原full矩陣的>=128遮罩差異皆0。3×綠框locator只供定位，不能代替原圖。

| 狀態／接點 | frame | facing | 原生pixel alpha | 精確源點（四捨五入顯示；JSON有完整精度） |
|---|---:|---:|---:|---|
| dead / neck | 21 | 1 | 0 | torso 451.851,211.569 baseA=0 partA=0; head 447.058,191.389 baseA=0 partA=0 |
| dead / neck | 21 | -1 | 0 | torso 451.851,211.569 baseA=0 partA=0; head 447.058,191.389 baseA=0 partA=0 |
| dead / neck | 22 | 1 | 0 | torso 451.848,211.332 baseA=0 partA=0; head 446.714,190.605 baseA=0 partA=0 |
| dead / neck | 22 | -1 | 0 | torso 451.848,211.332 baseA=0 partA=0; head 446.714,190.605 baseA=0 partA=0 |
| dead / neck | 23 | 1 | 40 | torso 451.844,211.132 baseA=0 partA=0; head 446.417,189.954 baseA=23 partA=0 |
| dead / neck | 23 | -1 | 40 | torso 451.845,211.132 baseA=0 partA=0; head 446.417,189.954 baseA=23 partA=0 |
| dead / neck | 24 | 1 | 95 | torso 451.841,210.967 baseA=0 partA=0; head 446.167,189.424 baseA=71 partA=0 |
| dead / neck | 24 | -1 | 95 | torso 451.841,210.967 baseA=0 partA=0; head 446.167,189.424 baseA=71 partA=0 |
| stand_up / elbow_front | 25 | 1 | 69 | arm_upper 415.650,436.236 baseA=254 partA=0; arm_lower 415.882,437.210 baseA=254 partA=0 |
| stand_up / elbow_front | 25 | -1 | 69 | arm_upper 415.650,436.236 baseA=254 partA=0; arm_lower 415.882,437.210 baseA=254 partA=0 |
| loop:hammer / shoulder_front | 48 | 1 | 18 | torso 482.072,305.996 baseA=0 partA=0; arm_upper 325.983,379.796 baseA=253 partA=0 |
| loop:hammer / shoulder_front | 48 | -1 | 18 | torso 482.072,305.996 baseA=0 partA=0; arm_upper 325.983,379.796 baseA=253 partA=0 |
| loop:hammer / shoulder_front | 50 | 1 | 24 | torso 482.020,306.161 baseA=0 partA=0; arm_upper 325.646,379.659 baseA=253 partA=0 |
| loop:hammer / shoulder_front | 50 | -1 | 24 | torso 482.020,306.161 baseA=0 partA=0; arm_upper 325.646,379.659 baseA=253 partA=0 |
| loop:hammer / shoulder_front | 110 | 1 | 23 | torso 483.553,310.317 baseA=0 partA=0; arm_upper 325.555,382.596 baseA=253 partA=253 |
| loop:hammer / shoulder_front | 110 | -1 | 23 | torso 483.553,310.317 baseA=0 partA=0; arm_upper 325.555,382.596 baseA=253 partA=253 |

頸21/22兩來源base0；23/24的head在原輪廓AA上，base alpha23/71，runtime最近texel及2×2為0，原frame alpha40/95。不能概括頸8全部base0。肘兩arm源0，原素材owner是torso254，原frame alpha69。hammer48/50的arm源0而原torso有料，原frame alpha18/24；110的最近原arm源alpha253，但runtime UV約(4.889,142.843)的2×2 alpha是[[0,11],[0,107]]、原frame alpha23，屬外緣coverage候選，不是已覆蓋孔。

Root已獨立實看全部16原生crop、locator及四組真全彩姿態表，未見內部分離；保留原raw358與automatic=false，不以沒有來源像素就自動判合理，也沒有補原alpha0背景、移門檻或登記known failure。來源數值與人工外觀判斷分開記錄。

## 358筆分類與實際缺件判讀

按既有衣領／袖口、動作空氣與外輪廓AA條款，原始計數照留。`joint-classification-v12.json` 將358筆全數分配如下；這是原生／來源人工判讀，不是更改原checker的分數。

| 原始標記家族 | 筆數 | 原生／來源判讀 |
|---|---:|---|
| wave肩前 | 342（含全部188封閉樣本） | 下巴與抬袖圍出的主動作空氣；當前1072點皆同主區、whole覆蓋0，代表frame26來源回投與全彩形狀吻合 |
| dead頸21–24兩向／1× | 8 | 外頸開放輪廓／低覆蓋AA；21/22原base0，23/24原headA23/71，不能全說原圖透明 |
| stand_up肘25兩向／3.4× | 2 | 袖內開放輪廓，原點屬torso254而非arm；actualA69，未見內部斷接 |
| hammer肩48/50兩向／3.4× | 4 | 衣物外緣／AA，原base有torso料但arm無該點；actualA18/24，未見肩根斷接 |
| hammer肩110兩向／3.4× | 2 | 原生外輪廓的subpixel低覆蓋；保留原armA253與runtime2×2低alpha矛盾的精確上下文，actualA23，不冒稱有opaque材質遮住 |

全部16小項都有各自當格／當面向真geometry、原128crop／SHA、來源owner與threshold replay差0；Root獨立原生與來源審查未見內部缺件／分離。本輪人工確認的真實內部接點違規為0，原raw仍358、automatic仍false；使用者成品視覺確認不代勾。hammer110的2×2只供覆蓋判讀，未重現完整mip/filter；wave未逐一回投所有1072點，這些方法界線保持明列，不把它們說成全部UV精確驗證。

## 真遊戲載入與原生檢視

`tools/harbor_lamplighter_demo_gameplay.tscn` 由真Level讀工具專用map/NpcData，建立NpcActor→CutsceneActor→CharacterRig；不是替換Sprite。正常harbor_approach受光、正常角色層序、真map bench、坐下進入／完成／站回、完整原生NPC台詞、Story暫停／返回、六個tracked nodes及對話host/framing釋放，v12實跑0失敗。原有texture cache保留策略不改，不宣稱所有GPU資源全清或零快取。

v12十四張雙向正常／亮場、NPC八動作、戰鬥診斷八狀態與gait，以及六張Level fixture原生圖已逐張觀看；原生RGBA、來源各九件的淺灰／深灰／棋盤底及10×頸／膝／褲口亦檢視。正式故事／地圖沒有變。

## 誠實保留的流程缺口與失敗

- 初次SAM3D成功出70點但退出時有ModelPatcher清理AttributeError；原exit0不能算零診斷，原log保留。共用修正由root另行交付驗證。
- 指定ROCm client初缺cv2、標準CPU Python缺requests，實際失敗與暫用CPU/HTTP client記錄保留；之後只在指定ROCm環境最小補cv2，服務仍是既有8188／9070XT，沒有自行重啟服務。
- 眼圖執行中曾改spec被舊snapshot覆回，是本次操作錯誤；後續串行重建。自己的launcher又曾太早import comfy_api造成OUT_DIR cache錯位，已修正並實證v10/v11真cache命中；眼圖來源契約由原工具重登記，未偽填hash。外層再套gpu_lock造成同鎖等待的錯誤亦原樣記錄，只終止已核對的自己child，未停服務。
- fixture第一輪誤把RefCounted CameraTuning當Resource duplicate，SCRIPT ERROR由40s watchdog拒收；改用原from_dictionary後才通過。一次對話圖太早／誤推到第二句的版本留存；v12實查首句完整文字、講者正確。
- 入口第6關的--sheet應明確寫成 `python tools/joint_audit_both.py <pair-only> <as-worn> --sheet=<png>`；check_joint_frames.py不接受--sheet。客戶端已自行取得生成鎖，不應再外包同一把gpu_lock；原生Godot等外部命令才用該wrapper。
- C槽full worktree checkout因歷史pm附件耗盡空間失敗，git自動清掉未完成工作樹；未刪外人資料。遵root指示轉D完整3713工作樹，實體獨立cache與123逐檔SHA；官方測試log在D。共享負載所有時間數字均不當硬體效能通過證明。

## 安靜時段原CLI腳本成本

UI high、角色88組與NE301官方長測均自然退出後，透過共用GPU鎖，以未修改的 `rig_perf_probe` 在D隔離3713+123、Godot4.7.2／Forward+／9070XT執行rin／新角交替各5輪，固定10隻、600次同步迭代、原rifle及run/crouch輸入。保留第一程序啟動與全部原值，不刪首輪；原有獨立Godot快取保留，不宣稱清空OS/GPU快取的全機冷啟。

| 輪次 | 新角 rigid→mesh（10隻µs） | 額外比例 | Rin rigid→mesh（10隻µs） |
|---:|---:|---:|---:|
| 1 | 1039.6→1293.3 | +24.40% | 1758.7→2174.5 |
| 2 | 1019.3→1270.3 | +24.62% | 1745.9→2138.5 |
| 3 | 1017.6→1288.4 | +26.61% | 1745.5→2124.1 |
| 4 | 1014.7→1277.0 | +25.85% | 1756.5→2144.3 |
| 5 | 1016.9→1293.5 | +27.20% | 1735.3→2154.5 |

新角213頂點、Rin423，全部≤500；所有10輪均符合各自rigid+50%原限。新角每隻額外25.4/25.1/27.1/26.2/27.7µs；原CLI分別round各mode與delta，所以相減可能差0.1µs，原報值／導出值分開保留。10輪exit0，SCRIPT ERROR/ERROR/WARNING皆0，source123前後逐檔不變，Comfy queue前後空，服務未重啟／卸載。

每輪以children(recursive=True)記錄真正Godot引擎與console PID；新角整個probe程序族的各PID peak working set保守總和583864320–585670656 bytes（不是per-mode RAM）。原rigid queue_free未在當幀釋放，不能由整程序拆出兩模式記憶體。全部raw log、RAM samples、前後source/service、環境狀態在後加performance小卷；小摘要 `performance-v12-summary.json` 可直接讀。

此原工具只同步量animate腳本，不是繪600幀，也不是GPU／整幀成本；真Level/NpcActor原生圖與資源釋放另見fixture。本報告不拿舊硬體36µs作現機硬閾值，也不宣稱新角色比不同零件數的Rin有通用最佳化效果。

## 官方受影響測試與封包

官方狀態：PASS（原執行器exit0；100552 checks／0新失敗／0已知失敗，88組）。基準full `3713db51062b14ed33ab61488559109fc41e2bfd`，獨立完整工作樹 `D:/NestEggVerification/role-20261117`，只有123新角色路徑覆蓋；原selector實際選ALL，88 groups/SHARDS2：新增角色自己的.gdignore、父art_src/characters未有祖先marker，按既有boundary_changed規則必須ALL；沒有移除marker、改selector或手選縮減。前後13700檔hash完全一致、123逐檔一致；隔離工作樹tracked diff空、untracked精確123，session70608最終exit0。原shard log內退出資源WARNING/ERROR與負控制診斷均保留，不冒稱整份log零診斷；FAIL與SCRIPT ERROR皆0。詳封包內official-3713/result.json及兩份原shard log。沒有以此共享負載聲稱隔離效能通過；最終使用者確認不代勾。

所有原始來源、原失敗／成功frames、原report/metadata/log、歷史來源快照和官方結果以raw.tar.xz逐epoch分卷（每卷<50,000,000 bytes）保留；每member與每archive都有SHA256，原檔不刪，只不把上千散件再次stage。早期沒留下完整來源快照的診斷不因封存就變成可重播的完整來源驗收。

## 最終封包與Git bytes

最終C交付65卷／45500個member，archive合計989709348 bytes，最大33830604 bytes<50000000；原64卷payload逐位元保留，新增performance小卷亦含更新版root獨立原生審查、全部10次原CLI、RAM程序族、23個Git LF映射及原65份CRLF metadata。D與copy到C後均以現行verifier全數通過（exit0），同時驗每archive/member/sidecar SHA、LF metadata及123 raw→Git canonical SHA／blob ID。正控制通過；outer與metadata正確但inner hash錯的負控制仍拒絕。

123 tested raw來源沒有改寫。Git依現有規則將23個文字檔CRLF轉LF，58張production PNG保持raw bytes；`git-canonical-production-v12.json` 分別記兩種hash，不聲稱全部Git staged bytes和Windows raw相同。Delivery sidecar/index固定LF，讓版本庫內的manifest hash保持有效；這是封包metadata修正，沒有normalize測試影格／素材。Root最後獨立核對actual staged bytes。

正常runtime47、authoring65、preview/fixture11仍為普通可建置檔。原有約45k散件在本機保留但不重複stage，精確清單見delivery-files.json；圖像只交27張代表原生圖／明示診斷圖。`pending_user_visual_signoff=true` 仍保留，不代稱其已看過，也不將它新增為本從零流程票的技術阻擋條件。
