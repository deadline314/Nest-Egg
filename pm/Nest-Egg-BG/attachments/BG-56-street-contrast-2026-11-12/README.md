# BG56 港區街道原生驗收

2026-11-11～12。本機 Godot 4.7.2、Radeon RX 9070 XT、Forward+／Vulkan／HDR2D、亮度0.5。這是自動化真場景驗證；靜態凍結採樣與原AI／公開Hurtbox元件實驗分開記錄。測試主角耐久999，作者敵人身份、位置、生命、攻擊與傷害資料保留。

## 正式結果

| 品質 | 主角最低 | 敵人最低 | 邊緣最低 | 實體全白比例最高保守上限 |
|---|---:|---:|---:|---:|
| high | 1.493795 | 0.480648 | 1.657118 | 1.8031% |
| low | 1.443194 | 0.466708 | 1.219430 | 1.8446% |

原門檻維持0.6／0.45／1.0及2%。每品質33原相機格＋6漏測平台落點＋1漏測蜂，共40點，其中28點具有可站主角；8座平台、16名實際存活可見敵人均覆蓋，34次敵人觀測包含重複，不冒充34名敵人。完整數值及實例帳本見[結果摘要](acceptance-summary.json)。

正式靜態來源是 `street-shared-authored-edge98-final-high40-v1`／`-low40-v1`。各輪原native退出0、0引擎／腳本錯誤、來源before/after不變。NumPy重新讀取原RGBAH、依6數字矩陣重建floor/ceil／裁切、原body／ring／edge框及全部分母像素，獨立核對對比、接地、真燈光／陰影／槍燈owner。兩品質各170組曝光觀測全通，最終34組保守上限均≤2%。

A是同一runtime／幾何下的原profile及原材質，B是本票局部資料；A/A、B/A/B原float精確還原。每輪actual Git base、明列overlay及實際Source SHA均保留；D工作樹Git基底為be43e4f5加各輪清單，先前所稱c78d／Animator2236是固定runtime參照，不能冒稱D HEAD或C整棵來源。正式後段另只同步已發布NE285 Fx d2377979／SHA93994b4193b9433fcc43795b4b93d955c9e3c098d069cc5ed91dad250259f99f；舊context、舊false樣本保留。

## 原圖與原尺寸並排

每個pair左原資料、右候選，保持每一個來源像素，無縮放；完整原viewport PNG另留。`-crop-pair`是同盒1:1近拍，兩邊逐像素等於原圖指定區域。精確盒與raw SHA見[selected-images](selected-images.json)、[pair對照](image-pairs.json)。

| 位置 | 高品質 | 低品質 |
|---|---|---|
| 主角、打手及原2008平台 | [全圖並排](../../images/BG-56-high-brute-platform-pair.png)／[實體近拍](../../images/BG-56-high-brute-platform-crop-pair.png) | [全圖並排](../../images/BG-56-low-brute-platform-pair.png)／[實體近拍](../../images/BG-56-low-brute-platform-crop-pair.png) |
| 清掃兵1352 | [原尺寸並排](../../images/BG-56-high-sweeper-crop-pair.png) | [原尺寸並排](../../images/BG-56-low-sweeper-crop-pair.png) |
| 監視蜂2984 | [原尺寸並排](../../images/BG-56-high-drone-crop-pair.png) | [原尺寸並排](../../images/BG-56-low-drone-crop-pair.png) |
| 原紅平台98 | [全圖並排](../../images/BG-56-high-platform98-pair.png) | [全圖並排](../../images/BG-56-low-platform98-pair.png) |
| 高台槍手曝光 | [實體近拍](../../images/BG-56-high-platform175-crop-pair.png) | [實體近拍](../../images/BG-56-low-platform175-crop-pair.png) |

## 物理遮罩及其他控制

曝光分母H只計至少一個來源片段alpha≥0.999的實體像素，透明片段自行疊加不會湊H；同角色透明片段不抹去其下層已不透明實體，其他角色依原alpha保留黑色遮擋。完整native骨架、UV、權重、逐bone變換、draw排序與所有實際可見物理drawable均逐項核對；僅明確glow紋理省略為實體分母，發光仍留在原main畫面。前景整個重複／擺動包絡從H保守排除，原前景保持。W包含色差／抗鋸齒邊界與可能背景白點，W/H是上限，exact_ratio為null。

同一native shader的四個已知答案通過：兩片0.99半透明的coverage可四捨五入至0.999512，但opaque=0；opaque下層加自身semi仍1；另一角色semi遮擋為0.5；空為0。空mask與8px錯位各native exit1、獨立reader exit1，原資料不改。

預設0高低各四生物／2400次真公開API呼叫，五張native float逐byte相同、未配置材質。區段往返高低各五步，在真接地x2680／2984間切換0→0.6→0，四生物綁定及原圖完整還原。原AI高低各實際打手windup／leap／recover、清掃兵aim／projectiles／recover、蜂hover／lock／dive／climb，原HP／stats保持；新版Fx下全部sample的physics space含受擊freeze皆有效。動態原框低值逐張保留，外觀框僅作輔助，不替代靜態原框。

公開Hurtbox元件實驗高低各7張原圖，實際生命3→2→0、第一渲染幀閃白、恢復、原spin／fall／fade／free均驗；這個實驗不稱為玩家射擊。正式使用`damage-final-high-v2`／`-low-v2`，首版晚取一幀已被獨立檢查拒絕，保留。

碼頭原200欄與電話亭原26欄高低各原點五步，全部main RGBA逐byte同、原門檻通過；碼頭保留原規範的明示清掃兵光影fixture。市集入口高低各完整21格、四名實際敵人全門檻通過，每格五步main RGBA完全同。原asphalt／全域harbor與所有31既有非street profile均保持；真Ambience／Music／Footsteps owner、原燈具及背牆幾何CPU核對，只有本票三profile／二材質alias追加。

## 歷史失敗保留

`raw-index.json`列出每一個閉合case，role=history-diagnostic不列作正式通過。包括長caption污染ROI、Godot自動Sprite名稱淨化造成mask配對拒絕、opaque分母過嚴導致上限尚不能證≤2%、原資料完整格真紅、RAM39點過但蜂仍紅、平台98真接地edge0.958236、舊Fx受擊時body-space=false、區段端點誤認0.6、首輪flash晚取及工具parse錯誤。所有native exit0只表示該輪程序／控制完成，獨立像素驗收另有原報告；未把這些歷史0當產品完成。

## CPU與整合

直接API64／0、資料1818／0、既有PartCreatureSuite108／0；該套有原本故意缺資源的1條ERROR，無新腳本／退出錯誤。原controller曲線833點16660／0且其他BLENDED欄位逐值相同；真舊／新writer的10個default theme輸出逐byte相同。刪music alias負控制1808／1，真正exit1拒絕。

正式`run_tests_changed.sh`在已發布83a基底的乾淨managed候選僅採18個產品／永久測試檔執行：74套、95,701 checks、0新失敗／0已知失敗、真正exit0，914.403秒，18個來源前後不變。原runner、selector、完整分片與逐檔來源見[正式原byte封包](official-index.json)，可執行`python -X utf8 verify_official.py`核對；保留原filters允許的預期／退出診斷，不宣稱整份log零ERROR。此正式scope只涵蓋18檔；一次性producer及獨立Python reader不冒充產品套件範圍。18個base／final／own diff見[整合清單](product-integration.json)及[原byte producer／整合來源封包](replay/producers-and-refs.raw.zip)，五共用檔／PartCreatureSuite只帶自有hunks，其餘只在C原SHA仍相同時整檔採入。C產品與Git索引由root統一整合。

## 原byte驗證與重算

每包小於95,000,000 bytes，逐member長度及SHA讀回核對，ZIP保存原JSON／log／source換行。各驗證器歷史版本按原報告SHA收齊；原報告與原source SHA不重寫。完整索引見[raw-index](raw-index.json)。

111個原始ZIP（2,438,067,153 bytes）完整保存在`D:/NestEggDeliveries/BG56-20261112/`，每個外部檔案逐SHA核對，原件未刪，見[外部原byte交付收據](external-raw-receipt.json)。Git只保存索引、精選原圖、reader及小型來源封包。`--raw-root`可指定搬移後的原ZIP目錄；不給時仍讀附件相對`raw/`。這是本機artifact交付，fresh clone沒有外部目錄時需取得同SHA原ZIP才能重算完整HDR。全部51個一次性GD／UID／scene／reference僅封存在上述producer ZIP及各輪source，不加入主遊戲`res://tools/`；9個Python reader及固定依賴放附件`replay/`。

壓縮體積主要為native float／遮罩1.595GB、PNG0.436GB、來源快照0.318GB；47,777個來源快照只有817個唯一SHA，46,960個為跨case重複，細項見[實際ZIP面積分析](archive-size-analysis.json)。

```powershell
python -X utf8 pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12/replay/verify_bg56_street_package.py pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12 --raw-root D:/NestEggDeliveries/BG56-20261112
python -X utf8 pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12/replay/verify_bg56_street_package.py pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12 --raw-root D:/NestEggDeliveries/BG56-20261112 --case street-shared-authored-edge98-final-high40-v1 --restore D:/BG56Review
python -X utf8 pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12/replay/verify_street_shared_coverage.py D:/BG56Review/street-shared-authored-edge98-final-high40-v1 --require-thresholds --require-drawable-bounds --out D:/BG56Review/high-coverage.json
python -X utf8 pm/Nest-Egg-BG/attachments/BG-56-street-contrast-2026-11-12/replay/verify_street_actor_masks.py D:/BG56Review/street-shared-authored-edge98-final-high40-v1 --out D:/BG56Review/high-exposure.json
```

低品質換對應case即可。NumPy重算不啟Godot；原生重播以該輪base-git／原source-before與overlay及原command為準，使用單一gpu_lock。各role的實際工具版本分別保留，沒有宣稱跨role全部source SHA相同。
