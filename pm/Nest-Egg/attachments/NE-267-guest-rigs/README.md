# NE-267：三客來源與鄭先生 S18 製作單位（進行中）

本目錄的工具流程／合成輸入與數值觀測不是人工驗收。NE-267 仍進行中；陳女士、洪先生及其餘配角尚未完成全身演出。原三張批准頭像和原始全身來源 PNG 的 bytes 均保持，未知原 seed／model job 維持 null。新 SAM／Qwen 分件、移臂底層及眼部則另有真實 graph、seed、server metadata 和前後來源 hash。

最新材質已 CPU 重建，完整新接點、三十張新全彩與 LF 正式 S18 均完成專項驗證；
受影響範圍原選擇器回歸仍待整合。NE-267 其餘角色尚未完成，原 checker 的
622／40 失敗不覆寫。

## 最新材質、取樣格與完整原生驗證

- `crop-phase-cpu-v2`：凍結舊 cutter 在新契約上拒絕，修後 8／0；省略可選欄位時
  九部件舊 affine、像素與 PNG bytes 相同。獨立 v1／v2 失敗原型保留；v3 原格點
  footprint 方法使新 canvas 180×100，pivot 整數平移 [9,0]。原指尖同 source 點
  現登記 (158.156589,42.000018)，不是換一根手指或縮放來源。
- `cpu-material-final-v2`：最終65個Python CPU測試全過（早輪 `cpu-material-v1` 亦65／0），另原圖／頭像／眼圖與劇情結果
  投影守門 exit0。包括 source9、resolution3、alpha11、mask10、material3、contact3、
  crop8、註冊冪等／錯源拒絕3、context對抗9、guest cast6。
- `torso-local-job-raw-v1.zip`：新單張 seed433 真工作，20 members、逐 member SHA；
  512×512 RGBA 原輸入輸出、graph、實際 server metadata、自己 job 的 history 與
  佇列觀測原 bytes。共享服務 lifecycle 禁用、graph retries0；未操作他人 job。
  只將原袖窿選區的 RGB 替換為布料，source alpha／選區外 RGBA 精確保持；
  三底色原生 crop 已實看。原 P／原全身圖／批准頭像都未改。
- `material-import-v1`：正式 Godot normal＋editor import，26.828 秒，exit0／0 ERROR。
  `repair_candidates/adoption-v1/actual-normal-comparison.json` 逐 pixel 比對真正 Godot
  11 張 normal：手指 diffuse／normal 零差，全部部件在改動 kernel 外 normal 零差，
  未改七部件 diffuse／normal 整張相同；這次不再只引用 CPU normal 原型。
- `scene-material-v7`：正式三段 S18，22.547 秒、0 failure／0 ERROR、來源前後固定。
  持紙、放桌、站起三張原圖已實看，紙在手、桌面平放與身體支撐合理；不是逐格
  完整驗收。九張原生 RGBH 浮點資料封在新 raw.zip，獨立 float16→sRGB 核對最多
  一碼捨入差；不沿用舊圖轉色，也不覆寫 v6。此輪之後五個交付 JSON 轉為 Git LF，
  轉換前 bytes 另封 `material-lf-freeze-v1-original-text.zip`；完整後續原生以 LF 為來源。

取樣格契約及未採用的錯誤解法見 `design/12-cast-redraw/NATIVE_CROP_PHASE.md`；
context 範圍依真正動畫骨點、直接相鄰關節與一原生像素重疊判定，真正封閉孔、
缺中心與斷開一律拒絕。

- `npc-performance-material-v2`：五狀態各360固定格、兩方向、1／2.2／3.4／3.7，
  7200張原生感測圖、201600樣本。擷取172.500秒、0ERROR／來源固定；其後原raw
  checker保留575個跨鄰關節外輪廓失敗，完整native骨點／鄰件範圍分析201600／0。
- `npc-transitions-material-v2`：坐下／站起各120固定格、相同方向與倍率，960張、
  26880樣本；擷取34.234秒、0ERROR／來源固定。原raw保留12個外輪廓失敗，完整
  範圍分析26880／0。所有鄰件必須同格覆蓋並分別稽核，沒有edge_notch白名單。
- 擷取receipt先明示acceptance pending；原raw與scope全部純CPU逐圖完成後，
  才另寫 `*-acceptance-complete.json`，不把capture exit0當動作通過。
- `material-true-hole-native-v2`：180×100新格點的真孔控制，雙朝向各保留一個
  enclosed像素，原checker與scope均2／28拒絕。`material-historical-six-holes.json`
  再直接重讀原生舊PNG，舊六個enclosed孔仍6／6拒絕。未降低128 alpha、原生精度
  或孔洞面積要求。
- 純白RGB感測shader的採用前A/A保存於 `alpha-only-AA-v1`：原來源20組、560接點，
  9175040個原生alpha像素全0差。完整新感測圖只提供逐格alpha／接點證據；全彩人體
  與正式受光另外驗，不把感測圖當美術驗收。
- `material-native-crop-registration.json`：實際原生Sprite資料顯示新舊rect origin
  只差整數[9,0]；兩方向的原手指域四角與來源指尖在native cell座標全0誤差。
  這是實機UV／接觸對位，沒有宣稱兩輪全畫面RGB逐pixel相同。
- `npc-colour-material-v2` 的30張原尺寸頁已全部逐張實看：2.2／3.4／3.7、兩方向、
  坐入、說聽、站起、揮入與揮退，每頁四時間點。全身、手與腳完整，沒有額外肢體，
  新布料折線取代平色塊。`material-parts-native-v1` 另有本輪四部件的8張來源／runtime
  三底色原像素頁，也已全部實看。這是agent檢視，不是人工或真人操作驗收。
- `scene-material-lf-v8`：LF正式三段S18，20.562秒、0ERROR／來源固定。實際坐下108格、
  站起79格，九快照每個15份正確diffuse＋normal掛載；143個持紙格最大誤差0.000061
  舞台像素，腳底−0.725～+0.158、坐姿臀底−0.404～+0.657，1像素要求保持。
  最終持紙／平放／站起原圖已實看並原bytes複製至 `images/NE-267-zheng-material/`。
  Root另抽查坐說3.7正向、坐入3.4反向、揮退3.7反向與LF S18持紙四張，觀察合理；
  此為四張獨立抽查，不冒稱Root看完30張或使用者批准。
- `guest-book-flow-material-v2`：最終資料重跑43個真互動邏輯檢查，0failure／0ERROR，
  略過、返回、重入、錯答與三客合計+100只結算一次保持。此為無頭邏輯探針；S18
  原生工具沒有Level，不用tree.paused斷言冒稱世界真的凍結。

上述原生使用各自source ZIP與before/after SHA固定的C工作樹union，含當時NE277共享
來源及Animator2236；不是宣稱精準對應某個已發布HEAD。原選擇器整合回歸另記。

完整新感測原bytes另保留在持久本機目錄，不屬於會清理的worktree：

- `D:/NestEggVerification/archives/NE-267/npc-performance-material-v2-native-rgba.zip`，
  SHA `618f6bfdb5cdf10eaa23dac08e0f6786f711d39ebf08e5b09bc59a4a92546be5`。
- `D:/NestEggVerification/archives/NE-267/npc-transitions-material-v2-native-rgba.zip`，
  SHA `9c512a80802f80ef10c396cec6472a2fab1c6c2f2913f9d46ac5c45333849d6d`。

各 run 的 `remote-evidence-manifest.json` 連結全部7200／960格的lossless LA衍生圖，
每個原生alpha逐pixel精確相同；所有raw失敗格的原RGBA也保留，去重288／6張，
包含外輪廓，不只留下看起來好的格。獨立reader已逐volume SHA、每張alpha SHA與
失敗PNG原bytes全驗證；命令與結果在 `material-remote-verification-v2.json`。
全部remote ZIP小於45MiB，完整原ZIP及PNG均未刪除。舊原彩完整536MiB／72MiB封包
及其遠端alpha／真失敗子集也保持；新純白RGB感測圖不冒充原彩來源。

本輪同機還有其他專案／隔離測試工作，以上秒數只記擷取耗時，不作獨占機器FPS或
「不卡」主張。角色本次是S18非戰鬥演員，未驗證的陳／洪或其他角色不借用本結果。

## 來源與重建

- 三客各 `01_design/source.json` 固定 1024×1536 RGBA 原圖 SHA、image_gen.imagegen artifact 與原 generation.json；三底色九張原尺寸合成已檢視。`source-and-eye-verification.json` 再驗原圖、base、頭像 bytes，不能拿新分件當頭像已重新批准。
- 鄭的 keypoints 是明示人工 authored rig references；隱藏遠肩／肘／腕、衣物內的解剖點另標未知，不冒稱 SAM 3D 預測。`02_pose/reviewed_masks.json` 固定三個實際 SAM mask 與群組採用。
- `03_generation_jobs` 逐 job 保留 graph 原 bytes、SHA、實際 server stats、client Python 與失敗記錄。成功批次經既有 8188 正常佇列，client 禁止 lifecycle、retries=0，沒有啟停、卸載或取消他人服務。D:/ComfyUI 舊 Python 只作 API／像素 client，模型實際在既有 ROCm 服務；不是宣稱在舊 CUDA 環境推理。
- stage P 要求 resolution=0、實際仍 1024×1536 RGBA，直接保存生成 PNG bytes；錯尺寸／RGB 拒絕，不 resize 補過。舊角色的預設 1024 行為未改、未重建。
- `configure_spec.py`、配方與 spec 是可重跑來源。runtime 為 16 bones、15 render parts、11 diffuse／眼變體與對應 normal；native k=1。近遠臂與腿重用單一已分清所有權的近側材質，不把原遠腳再切入近腿。

## 部件帳本與實看範圍

| 原生部件 | 掛載／接點 | 獨立來源與 runtime 檢視 |
|---|---|---|
| pelvis | hip，腰、兩髖 | 棋盤／淺灰／深灰，單一骨盆及有限腿根重疊 |
| torso | chest，腰、雙肩、頸 | 同上；移臂 stage P、領口／袖窿底層另核對 |
| head、half、closed | head，頸 | 同上；兩眼只在已核對眼框內變動，alpha／框外完全相同 |
| leg_upper | 兩條 upper leg，髖／膝 | 同上；一條近腿材質，遠腿獨立旋轉重用 |
| leg_lower | 兩條 lower leg，膝／踝 | 同上；保留腳踝必要覆蓋，鞋帶突邊只留在 foot |
| foot | 兩腳，踝 | 同上；原遠鞋殘線已局部移除，單件一隻完整近鞋 |
| arm_upper | 兩上臂，肩／肘 | 同上；root attachment 留在各自肩點 |
| arm_lower | 兩前臂，肘／腕 | 同上；保留實際袖口與手腕材質 |
| hand | 兩手，腕 | 同上；單手／五指，局部皮膚延伸藏在袖口下，原生指尖保持、裁切變更自動重註冊 |

`parts-native-review/manifest.json` 有 9 張來源、11 張 runtime 的三底色檢視，全部 pixel_scale=1，不縮圖取代來源。額外 `source-ownership.png` 是早期 QA 索引，不計入 20 個部件檢視。`check_spec --joints` 0 error／warning、`check_seams --strict` 0 finding。重組唯一未覆蓋元件是原遠腿／遠鞋（框與原因在 reassembly_allow.json）；其他孔洞仍要求 0，沒有放寬 max-hole。最新皮膚材質修後覆蓋區有 7684 個 RGB 差異像素（早期候選 7477），沒有宣稱補全／修邊像素與原圖完全一樣。

## 已完成的分項與紅例

- source contract 9／0，stage resolution contract 3／0；來源 alpha 11／0、mask delivery assert 程式 exit0。第一次 cp950／wrapper 錯誤保留，只有修正環境後的有效回合計入。
- 客人簿 CPU source guard 現 6／0，含 Windows 反斜線拒絕、res:// POSIX 路徑及 96×96 RGBA 八 state 來源。首次錯路徑、normals 先於新 state import、探針縮排錯誤均保留為拒絕回合，不能用其 exit0 數字算通過；之後先 editor bootstrap，來源程式先固定 LF。
- `guest-book-flow-headless-v1`：43 PASS、0 failure、0 engine／script ERROR，真區域／人物互動與原選項；略過、返回、重入、錯答重試與三客 +100 只結算一次，最後 tree.paused=false。這是安排前提的無頭功能探針，未宣稱真人或原生美術驗收。
- `scene-first-v1`：原腳底 +1.2106 stage px 的真正紅例。校準新角色 ground_y=1519、H=56、k=1 後，兩腳 −0.0678 px。`scene-ground-v2` 新增實際變形 UV 材質量測，揭露原 sag=.34 臀底比座面低 3.17～4.40 px；該輪舊守門只管腳底，不能說座面已過。
- `scene-seat-paper-v5`：正式三段 S18 的穩定坐姿、實際站起與劇本道具。Radeon RX 9070 XT／Godot 4.7.2／Forward+／1280×720，0 failure／0 ERROR，來源前後 hash 完全相同；後續發現開場尚無實際坐下轉換，所以此輪不能代表坐下已驗收。雙腳 −0.0678 px、坐姿臀底 −0.609～+0.624 px，137 個持紙格接點最大誤差 0.000061 px；八個同來源幾何平放 state 的桌面誤差最大 0.96353 px，釋放後紙底 y=180.00003。原直立紙／搆不到舊落點的失敗均保留，未放寬 1 px 接觸要求。
- `joints-diagnostic-v2`：14 接點、兩面向、1／2.2／3.4 三倍率、五 NPC 狀態各一格，6／420 真失敗；全是坐／坐說／坐聽的遠腕，3.4 倍兩朝向各一個封閉像素孔。這只是短診斷，不能說完整動作通過。第一個 pivot 中心 49px 前臂 underlap 候選雖保持原 hand SHA，`joints-diagnostic-v3` 仍 6／420，已撤掉。
- `wrist-source-trace-v1`：實際 render(-5,+1) 孔反投影至 hand 來源 (456.61,747.40)，此處原 hand alpha0、前臂 alpha253；不是中心腕點少料。局部 hand-under-cuff 206px 修正後，`wrist-local-skin-trace-v1` 同 checker 6／10→0／10，native 0ERROR／來源 hash 前後不變。兩輪都含五姿勢、雙朝向、3.4 倍；仍是單格診斷，未代替全接點／完整時間。
- 新手裁切159→171px，密度與 k 不變。原始指尖參考 (515.5529568,875.1217090) 保留；`register_hand_contact.py` 依實際裁切 affine 把舊 runtime(137,42) 註冊為(149.156589,42.000018)，同一材質點沒有拉伸或改手勢。既有 source_rebuilds 保證重建不會漂移；獨立 CPU contact source guard 3／0，包含舊 UV 會偏移超過10 source px 的真正負控制與正式編譯 reach 接點核對。原始手 PNG SHA 只適用歷史候選，不冒稱新裁切一 byte 不變。
- `native-pages/wrist-positive` 20／0 與故意移動 hand_front 的 20／20 拒絕，證明同 checker 能抓到破壞。它是早期單格前腕控制，不能代替後來六個遠腕紅例或完整時間覆蓋。

- 三底色另發現最近像素延伸把棕色袖口當成皮膚，不能以 alpha 閉合算外觀正確。新增可選 underlap.material_point，從實際來源皮膚 (483,785) 取 RGB；預設仍用原最近材質。凍結舊工具 3 項／7 failure → 修後 3／0（含 6 個無效或透明點拒絕、既有 PNG bytes 相同）。新 hand 只變 270 個 runtime RGB 像素，alpha／幾何／指尖 RGBA byte 相同；新三底色已實看。
- 開場 actor idle 與 pose sit 原本同 frame，NpcAnimator 第一個更新直接初始化 sit，因此 v5 的實際坐下轉換樣本是 0；不冒稱已演出。作者來源加入 .25 秒站姿初始化等待，CPU 六項舊 1 failure → 全綠；新原生觀察器要求真正坐下及站起進度樣本。HDR frame 在 post_draw 保留原浮點，整段演出結束後才編碼，避免逐像素編碼擾動演出時鐘；同格 raw／format／SHA 與 PNG 分別保留。

## 尚未交付的驗收

新共享 HumanoidAnimator 的 gait／idle 交接由 NE-277 專責修復，本角色不改該檔；修後短輪已使用固定 SHA `2236b4d7dfdb948542672a5cc3797c6bb7d51e0a1fd230336a9b932fb1a758cf`。仍需修後全接點完整逐格、全彩雙朝向完整手腳／動作相位、實際 normal 綁定、正式 S18 重拍與受影響測試。未使用的戰鬥、裝甲、武器、死亡玩法不新增到成年客人；本單位只宣稱 S18 既定非戰鬥演出，不宣稱整張 NE-267 或其餘兩客已完成。

正式全動作另納入演員實際 scale=3.7，不僅檢查通用過場 3.4。完整接點計畫為 1／2.2／3.4／3.7 四倍率、兩朝向；全彩分頁為 2.2／3.4／3.7，均四個完整身體一頁，不裁手腳。正式原生尚未執行前，這段只列待驗範圍。

## 完整逐格揭露的剩餘缺口（不通過）

`scene-final-lf-v6` 已真正原生三段：105 格坐下進度、78 格站起進度，9 個原生快照各有 15 部件實際 diffuse+normal 綁定；140 格真持紙接點，0 failure／0 ERROR，來源前後一致。完整原生持紙／放桌／站起已檢視並 byte-exact 複製到 images/NE-267-zheng-rig。9 個原始浮點是 format14=RGBH（6 bytes/pixel），封在 raw.zip 並逐 member SHA；獨立 numpy float16/sRGB 比同格 PNG 的最大差是 1 code rounding，未拿它當美術門檻。最初 CPU decoder 誤假設 RGBAH，在 byte length assertion 被拒絕，沒有改任何圖或原資料。

`npc-performance-final-lf-v1` 原生 7200 格、201600 個接點樣本，**622 FAIL**；`npc-transitions-final-lf-v1` 原生 960 格、26880 樣本，**40 FAIL**。兩輪引擎 exit0／0 ERROR，checker 正確 exit1，不能把引擎 exit0 當接點通過。全是 edge_notch 診斷分類，仍照原 4-connected／alpha>=128、任何1像素即拒絕；0 enclosed／loose 不代表豁免。原始每格 PNG、來源 zip、frames、report 與 log 全保留。

全彩 `npc-colour-final-lf-v1` 是 30 個獨立串行原生程序，2.2／3.4／實際3.7、雙朝向，4個完整身體一頁、每頁保留真模擬時間；各程序 exit0／0 ERROR、來源 before/after 相同。這些圖片還需逐頁檢視，不因擷取成功當作美術通過。已看的3.7右向揮手頁揭露 torso 的大平棕色底層；原 stage P 畫了圓袖窿，舊 flat median 除去圓圈卻沒有合理布料。局部 RGB 候選與 alpha 接點修正分開處理，原始 P 不改。

331 個正向失敗格的 CPU 幾何重播／來源投影是診斷，尚待同格 native 矩陣核對。重播修正為每格與原工具相同的居中（兩種居中方法矩陣最大差 1.91e-5）；Sprite UV 僅在真 quad 內才算材質，不能外推到空白。`cpu-alpha-replay-bounded.json` 的 bilinear/alpha-over 與原生失敗像素平均差0.82、最大5.42/255，只證明位置大致可信，不代替原生判定。一部分肩／膝／腕 band 跨到領口／髖／肘，隔離時可能隱藏真正鄰接覆蓋，必須單一部件可見性對照，不能因這個假說盲目長肉或白名單放行。原前腕源點在補料左側約1px則另驗是否是真袖口缺口。

`cpu-final/receipt.json` 固定來源 CPU 守門45項全過，另三源／三頭像／眼框與全章非演出內容 hash 守門 exit0。它們不代替尚紅的原生接點。新 shared Animator 仍固定2236；未開始陳／洪全身採納，也未宣稱 NE-267 整票完成。


## 原55套件揭露的舞台離椅缺口與v3修正（尚未結案）

Root以原selector在凍結322來源完成55套件：62909 checks／3 new／0 known，983.757s。
兩項SceneSanity警告都是S18 ticket/done的站姿x410與右椅actor-plane x377.75..442.75重疊，另一項為總合；不是Janus新紅。
原紅log與322來源完整封存，舊持紙／站起圖沒有證明離椅，因此不能以舊快照關閉這三項。

`stage-clearance-walk-candidate-v1`雖原stage警告2→0，原生trace卻顯示sit直接改walk；到x470時身體重新下沉22.678 viewport座標，拒絕採用。
`stage-clearance-walk-candidate-v2`是work子類_init漏super導致47ERROR的無效工具回合，原log/sourcebytes保留。
`stage-clearance-walk-candidate-v3`改為在x410真正完成起身及腳IK收尾後才走，0ERROR／0leak／308來源前後相同；已看8張進出椅／坐／末站的原尺寸圖，椅背始終在角色身後。
原始RGBH各frame保存為raw-NN.zip（每包<45MiB），raw-manifest-v1逐member SHA及獨立sRGB編碼重算，任何舊失敗不覆寫。

正式v3加入NpcAnimator純讀posture_active()/posture_ready(target)：必須已消費target且_trans_t<0；progress=1仍有腳IK收尾，不能當ready。
CutscenePlayer先等真正站穩才walk/run，站姿／持槍／portrait保留同步fast path，wait=false仍非阻塞；弱引用及actor-id避免死亡、替換、取消或釋放後的arrival callback。
專屬helper的原產品60/7紅（另兩次真freed-lambda ERROR）與work83/0、dispatcher125/0、正式125/0全部保留。
正式來源驗證為validation-inputs-v3共314檔，新增共同碼使原selector自然選64組，Root正在同原基準2189222d跑，未調selector。
CPU契約新一輪cpu-stage-clearance-v3共66/0，三張原身體與三張批准頭像bytes保持，非演出全章投影SHA仍相同。
`scene-stage-clearance-v3`是已採入v3正式三段S18的新原生，0ERROR／0leak／廣域source固定、先起身後走及到站不重播坐姿的守門全過；仍不代表足滑或新walk範圍已完成。

新增walk尚須四倍率、雙朝向、實際world腳plant的完整接縫與轉折圖。
精確native尺度另更正：S18的actor scale3.7乘camera.84乘720/360，實際為6.216 native px/world；舊四zoom的3.7是sensor倍率，不能宣稱已覆蓋此合成倍率。
會只補真6.216的必要既有狀態／坐站與新walk，不重跑無關舊倍率；原228480樣本僅保留原1／2.2／3.4／3.7範圍。
新walk診斷另追離椅1.5秒速度10.81 world/s低於既有gait門檻12的風險，未證實前不把靜態綠當足滑通過，不更動品質門檻或HumanoidAnimator2236。


### Walk候選工具的拒絕與更正

`walk-motion-cause-v1/v2`工作fixture漏設RigInput.two_handed=false（預設true），故NPC暖機／姿勢A/A無效，另加fixture-rejection.json但原bytes不改。其Humanoid穩態結果不代稱NPC起步。
`walk-motion-cause-v3`明設false，暖機後assert真正posture_active/ready，兩程序0ERROR/0leak、314來源保持。
真正NPC對照：原1.5s步態phase0；只改節奏、只加grounding、grounding+短步幅四個單因素全部原ledger保存。
最後候選兩向穩態滑步.026007L（原LocomotionAudit暖機1.5s後、門檻.03），整段起步累積1.81247world px／最大單格.39419px（既有≤3／≤1），最大腿角單格.08960rad（既有.5）。
這是候選CPU世界座標資料，不是原生材質腳底或美術通過，尚未採C motion/source。
原五動作／兩坐站的真正NPC CPU A/A：所有local角0差；坐／說／聽／坐下relative骨0差，站／揮／站起relative誤差≤5.73e-6world，僅整體接地y補正<.184world，不能冒稱native alpha byte相同。

`walk-camera-aa-reference-v1`與`walk-camera-aa-camera-v1`原生均exit0/0ERROR/source固定，但舊holder居中與新world-camera的精確alpha A/A分別7／71 pixels不同（max5/255），該像素相同主張拒絕，原圖／frames／source zip保持。
同時量到舊／新相對骨位置差≤.000160 native pixels；尚在分離大座標float幾何與第二viewport合成，不調alpha>=128或一像素要求，也不採長矩陣以冒過。
下一控制會同一camera幾何比較一般RGB／純白sensor、直接cell／composite，並保留真正孔負控；不是把舊failed A/A改稱通過。

Root原64組68842項出1項廚房壺落墊新紅；單獨CutsceneSuite可過，Root受控priority100/fixed6fps已證明舊／新Player都會在reach尚未完成時返回。
這是另票NE-287的既有reach發布race，不歸因NE267 move，也不拿單套過關忽略正式紅。Root正獨立修實際reach completion等待，NE267依其共用來源更新後再跑原64。


### 真倍率走路／NPC交接候選（2026-11-12，未採C）

同一world/camera的`walk-camera-white-v2`與`walk-camera-rgb-v2`917504個alpha像素完全0差；112個direct-cell/composite也0差。舊holder↔camera的7/71像素差仍是拒絕，不改其收據。
`walk-colour-candidate-v1`則真正量到walk→sit骨盆單格1.053542world＝6.5488native px跳動，不能採用。原first colour左向還漏設aim_dir，該部分另標fixture錯誤；新版所有暖機／逐格都固定two_handed=false及面向瞄準。

只保存gait_level的第一版把跳格移到fade尾；直接平滑hip的第二版仍有DD尖峰及支撐腳拖行，均拒絕。現在work-only支撐交接保存上一已發布hip/foot，以既有NPC HANDOFF_TIME=.3在相同雙骨IK目標間接續，進入步態時只對齊一次支撐相位；不改HumanoidAnimator2236、骨長、joint或品質門檻。
`npc-gait-handoff-compat-v6`80個成對case、0ERROR／source326固定：grounding=false的40×360=14400格所有local/global骨矩陣0差；grounded正控四個實際角色均真正跨入gait。鄭walk→sit最大hip step .008L、sit→walk .0112L，DD峰/P99分別1.16/1.08；其餘純NPC交接DD也<3，腿角<.21rad、骨長0變。Human crouching fallback明列原問題，不擴改或冒稱通過。
短walk→姿勢只有72個移動格，沒有1.5秒steady窗口，獨立checker現明示null／0樣本；起身→走的steady從真正首移動frame+90算，鄭.0256L、OldK.0146、Rin.0146、Yong.0085。這是CPU踝點世界資料，不是材質腳底驗收。
`npc-gait-handoff-refactor-v7`預配置兩腳目標陣列並抽eligibility，對v6的80×360=28800格所有local/global骨矩陣完全0差；原NDJSON封lossless raw.zip並逐member SHA，原檔本機保留。

永久回歸候選`npc-gait-permanent-red-v1`原碼184/12、真exit1／0ERROR；新`green-v1`184/0，再加9類中斷雙向及getter純讀後`green-v2`256/0、真exit0／0ERROR／0leak，source326前後固定。工具仍在work，未把候選測試稱為正式NpcAnimationSuite。
`walk-colour-candidate-v2`新候選32頁（3.4/6.216、雙朝向、四個walk/坐切換、每頁四完整人物）已逐頁原尺寸檢視，0ERROR／0leak／source固定；轉折沒有原6.55px瞬跳、沒有新增裸孔／額外手臂或裁手腳。另OldK/Rin/Yong各12頁的walk→sit/NPC squat/stand雙向原生已全退，選定轉折頁已看，其餘逐頁目視仍待完成。
OldK工具v1縮排Parse ERROR、v2 metadata在controller.free後讀取均拒絕；只停止已核對完整command的本工具Godot，原log/source/已有PNG保留；v3才是乾淨有效回合。

`npc-gait-adoption-candidate-v1`提供NpcAnimator舊SHA與窄patch、永久helper及suite呼叫候選，尚未套C；Root正跑union正式範圍，C當前shared context已由326新增tests-only到327。新來源窗口後仍須採motion grounding/短步幅、S18離座1.2秒，並重拍真S18、實際6.216既有狀態與新walk全接縫。NE267全票及陳／洪均維持進行中。

### 實際材質接地與走路來源缺口（2026-11-12 後續）

D 正式採候選後的 NpcAnimation／Locomotion／SceneSanity 原三套件為 1472／0；grounded lift 原 2.1 在 60／120 速度有足滑真紅，單因素比較採最小通過的 2.8，未改骨長或原 .03L 支撐門檻。`npc-gait-shadow-v1/scene-integrated-v1` 真 S18 則另外量到材質腳底最深 4.573 stage px 穿地，不能被 CPU 踝點成功取代。固定／交替 render delta 的同來源控制證實 Actor／Tween 位置與時間發布不一致，已獨立拆 NE-290；該票由 Root 以 `faa5e4e` 發布純共用框架，沒有把這些 guest 素材混作 clock 原始碼依賴。

NE-290 的 `guest-scene-clock-v1` 保持原 guest 美術與 NPC adapter／motion，以相同 observer 重拍三段 S18：原 1 stage px 材質門檻下，舊 ticket 98 足穿地／40 格雙足失支撐、done 55／21，修後三段均為 0／0；最大 .969048 stage px。完整原生 19 張、實際來源／原始 RGBH／足底獨立 reader 在該票附件，clock 的接地成功不代表下面的分件接縫通過。

`npc-gait-shadow-v1/walk-joints-6p216-integrated-v1` 是新增四個 walk／坐站切換、雙向、360 格、14 接點的真 6.216 倍原生資料，共 40,320 個接點樣本。原 checker 真有 58 紅；相同 anatomical context 保留 50 個目標 open-notch 真紅、8 個鄰接外輪廓，不以白名單豁免。原始 RGBA 全包與逐 member SHA 保存在持久 `D:/NestEggVerification/archives/NE-267/walk-joints-6p216-integrated-v1-original-RGBA.zip`；Git 衍生 LA 的 alpha 逐 pixel 等於原圖，所有 raw failed 原 RGBA 子集亦保留，清楚區別衍生 alpha 與原 RGBA。

`walk-material-source-trace-v1` 以原 rig／mesh／UV／相機投影讀取失敗格，所有同格 native 骨點與原資料差異為 0。來源反算定位到 pelvis、foot、arm_lower 三個有界接合區的低 alpha，原生孔像素 alpha 1～113；不是骨架變動。`art_src/characters/guest_zheng/repair_candidates/walk-contours-v1` 的最小半徑 2 source px 候選只補這三區低 alpha，原 opaque RGBA、區外 RGBA、crop／pivot／取樣格全不變；原 finger 與足底最末 source row 不變。這仍只是候選，CPU 預測原 50 點皆 ≥239 不能冒稱原生接縫成功。

候選只在自有 D 專案試採。`walk-contour-adoption-v1` 的工具型別推斷 Parse ERROR 原 log／source／資產前後字典保留；修正明確 String 型別後 v2 真正用 Godot 生成法線，三部件遠處 normal 變動皆 0。`walk-pipeline-rebuild-v1` 嚴格 byte 守門又抓到生成器 JSON 的 CRLF 與原 LF 不同，解析資料／22 個 diffuse-normal PNG 全相同；原生成 bytes 另封存。沿既有交付 LF 凍結流程的 v2 才完成實際 source_rebuilds→原 cut_layers→Godot normal rebuild，26 個來源／輸出 byte 全相同。C 素材／recipe 未採，原生 import、完整新 walk 四倍率與實際 6.216 倍、其餘舊狀態新倍率及全彩接點仍待完成；陳／洪尚未開始 body 採納，整張 NE-267 保持進行中。

其後在外部模型占用的 CPU-only 窗，`walk-material-import-v2` 完成真正 headless editor import：94.212 秒、exit 0、零引擎／腳本／洩漏診斷、來源固定，沒有 renderer／模型或效能主張。v1 preflight 因原 candidate 字典未列未改的 Human dependency 而在啟動 Godot 前拒絕，原 script／說明保留；v2 明列完整 runtime 及 Human2236 守門。

新增來源登記的三項永久 CPU 測試使用實際原生來源位元組：重建可重複且不改 crop／pivot、第三個輸入過期時全部不寫、外來 override 絕不覆蓋，3／0。`walk-material-focused-v1` 再跑真正 NpcAnimation／Locomotion／SceneSanity／Cutscene 四套件，3396／0、129.391 秒、exit 0，D 與 C352 來源前後固定。27 條原有故意錯誤訊息按未改 `tools/test_filters.sh` 保留分類，零意外診斷／SCRIPT ERROR／洩漏。這些無頭成功不能取代尚待排程的 Forward+ 原生接縫矩陣。

三底色的 source 區域預覽提前發現 v1 矩形 feather 邊界有極小外凸，因此未做原生採納。v1 候選、已完成的 3396 收據與該套確切來源保留；不能事後將這份收據改稱 v2 材料測試。`walk-contours-v2` 使用同一有界區域、同一半徑 2，僅將權重改成中央固定、邊界平滑到零的 C2 橢圓。原 50 個孔的 CPU alpha 預測完全相同，三部件 runtime 改動由 232 降為 198 pixels；原 opaque、區外、crop／pivot／取樣格仍 0 差。新版三底色預覽包含完整來源區域，舊版預覽高度不足的裁切亦留作工具失敗，不當作完整審圖。

v2 只在 D 取代已核對 SHA 的自有 v1 override，原 v1 override／runtime bytes 另封 `walk-contour-v2-transition/prior-registered-v1.zip`，原 refined 層不改。`walk-contour-adoption-v3` 真 Godot 法線與三區外材質 0 差；`walk-pipeline-rebuild-v3` 再由實際登記來源切圖及全 11 張法線重建，26 項 bytes 可重現，登記永久測試 3／0。`walk-material-import-v3` warm import 11.639 秒、exit 0、零診斷／洩漏、來源固定；仍沒有 renderer 或原生接縫成功的主張。當前 preferred 候選為 v2，原生批次尚待共用 GPU／外部工作與效能資格窗協調。
