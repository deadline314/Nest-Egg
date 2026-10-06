# 2D 骨架角色移動動作：業界最佳實務與可檢查數值規則

> 來源：2026-10-06 使用者回報主角走路時身體一直上下抖，要求「參考業界最佳實例整理成資料、做成 skill，之後做骨架都要參考」。這份是整理後的參考資料；skill 在 `.claude/skills/rig-animation/`，那邊是做事的流程與檢查清單，這裡是數字與出處。
> 注意：整理時網路代理擋掉了網頁全文，所有數字來自搜尋摘要，條目已標【出處】【推導】【建議】【沒找到】。標【建議】的數值是我們的起點，要在遊戲畫面上實測調整；引用前請點出處核對。


適用：Godot 4 橫向 2D 動作遊戲，側面全身立繪切 10 多塊零件掛骨頭，程式驅動（正弦、IK、彈簧骨），無逐格動畫。
目標：解決「走路時身體一直上下抖」，並整理成可寫進自動測試的規則。

## 0. 閱讀須知（可信度標記）

- 本次研究環境的 WebFetch 全部被網路代理擋下（維基、PMC、GDC Vault、Unity 部落格、各大學課程頁都打不開），所以**所有數字都只來自 WebSearch 回傳的摘要**，沒有逐頁讀原文。引用的連結都是搜尋結果實際出現過的網址，但原文細節請在採用前自行點開核對。
- 標記說明：
  - 【出處】= 搜尋摘要中明確寫出的數字／說法，附連結。
  - 【推導】= 由出處數字做的算術或物理推導，算式寫在旁邊。
  - 【建議】= 我們的建議值，不是業界數字，需要用實際畫面調整。
  - 【沒找到】= 搜尋沒有找到可靠數字，不編造。
- 長度單位：L = 腿長（髖關節到腳底，站直）、H = 身高。人體解剖常用 L ≈ 0.53 H（這個比例本次**沒有**搜尋驗證，視為常識性近似）。

---

## 1. 經典走路循環（Richard Williams《The Animator's Survival Kit》）

1. 走路循環由 contact（雙腳著地、步幅最大）、down（重心下沉、體重壓上前腳）、passing（後腳經過支撐腳旁）、up（支撐腳蹬地、身體升高）四個關鍵姿勢構成，每一步從 contact 開始、到下一個 contact 結束，一個完整循環共 8 個姿勢。【出處】https://courses.cs.washington.edu/courses/cse459/19au/assignments/assignment_5/index.html （搜尋摘要）
2. Williams 的標準 24 格循環：contact 在第 1、13、25 格，down 在第 4、16 格，push-off（up）在第 10、22 格；passing 在兩個 contact 正中間（第 7、19 格，這兩格是由「正中間」推得，摘要未直接列出）。【出處】同上；https://animation.monmouth.edu/instruct/?p=351
3. 24 格 / 一個循環 = 兩步 = 每步 12 格；以 24 fps 算每步 0.5 秒、步頻 2 步/秒（120 步/分）。【推導】（搜尋摘要寫「3 steps per second」與 12 格/步在 24fps 下算術不符，不採用該句；https://www.awn.com/comment/1008092 附近的摘要）
4. 身體與頭在 contact／down 位置最低、在 passing／up 位置較高（所以垂直起伏每步一個週期，每個循環兩次）。【出處】https://courses.cs.washington.edu/courses/cse459/19au/assignments/assignment_5/index.html
5. 走路永遠至少一腳著地；跑步才有雙腳離地的騰空相（flight phase）。【出處】https://animation.monmouth.edu/instruct/?p=351 搜尋摘要
6. 跑步騰空相要點：髖保持高度、前腿向前伸、肩高、背弧開胸、頭抬高（Williams 系教材摘要）。【出處】同上
7. Williams 風格跑步每步幾格：搜尋摘要給「寫實成人 12–14 格/步、快跑 10 格/步」，但以 24fps 換算會是 110–120 步/分，低於生物力學的跑步步頻（見 §1.9），疑似是以其他計數方式（每 stride 或不同 fps），**不採用**，原始數字【沒找到】可靠版本。（摘要來源：https://baks.verde.ag/24-fps-run-cycle.html ，可信度低）
8. 步態週期（生物力學）：站立相約 60%、擺盪相約 40%；雙支撐各約 10%（初始 10% + 末端 10%），單支撐約 40%；雙支撐比例隨速度減少。【出處】https://orthobullets.com/foot-and-ankle/7001/gait-cycle 、https://now.aapmr.org/biomechanics-normal-gait/
9. 步頻（cadence）與速度：
   - 正常走路 100–115 步/分（約 1.7–1.9 Hz），速度約 1.4 m/s，步長約 0.7 m。【出處】https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf
   - 走→跑自然轉換發生在約 140 步/分（2.33 Hz）；弗勞德數 Fr = v²/(L·g) ≈ 0.5 也預測轉換點。【出處】https://en.wikipedia.org/wiki/Transition_from_walking_to_running 、https://ir.ua.edu/items/259f6614-7b4d-4d81-8708-0bdaf54b37c1/full
   - 跑步步頻約 2.75–3.25 Hz（165–195 步/分），好跑者約 180；速度增加時步長與步頻都增加、觸地時間下降、騰空時間增加；觸地時間約 150 ms（很快）到 400 ms（很慢）。【出處】https://eprints.leedsbeckett.ac.uk/id/eprint/7491/6/TheBiomechanicsOfDistanceRunningAM-HANLEY.pdf 、https://www.healthline.com/health/fitness/what-is-cadence-in-running%23what-it-is
   - 步長與速度關係 s ∝ v^0.42（Grieve）：速度加倍時步長只增約 34%，其餘靠步頻。【出處】搜尋摘要（Grieve），原文連結未取得
   - 步長（走）超過 100% 腿長可能不省力。【出處】搜尋摘要，來源 https://digitalcommons.cwu.edu/ijurca/vol4/iss1/1
   - 速度 = 步長 × 步頻。【推導】
10. 骨盆：水平面旋轉約每側 4°（擺盪腿側向前、支撐腿側向後）；冠狀面骨盆傾斜（pelvic list）約 5°（擺盪側下沉）。【出處】https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf
11. 肩與骨盆反向旋轉、手臂與對側腿同步擺動，作用是抵銷角動量、降低垂直地面反作用力矩與耗能（手臂擺動可省約 8% 能耗）。【出處】https://pubmed.ncbi.nlm.nih.gov/19181900/
12. 手肘：走路手臂大致伸直、跑步手肘彎曲（跑步彎肘可降低肩部力矩）。【出處】https://hsrc.himmelfarb.gwu.edu/smhs_psych_facpubs/1801 。具體角度（常見說法走 ~20°、跑 ~90°）【沒找到】可靠數字，下表角度為【建議】。
13. 膝在站立相約彎 15°（stance knee flexion，Saunders 六大決定因子之一，用來壓低重心起伏）。【出處】https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf
14. 腳掌滾動：heel strike（腳跟先著地）→ 全腳掌 → heel rise → toe off；教科書稱 rocker 1/2/3。數字（角度）【沒找到】；下表為【建議】。【出處】概念：https://en.wikipedia.org/wiki/Bipedal_gait_cycle
15. 跑步身體前傾角度【沒找到】可靠數字，下表為【建議】。

## 2. 垂直起伏的物理與動畫原理

16. 人以舒適速度走路時，全身質心（COM）軌跡平滑起伏，垂直與左右峰谷幅度都約 5 cm（peak-to-peak）。【出處】https://pure.psu.edu/en/publications/the-vertical-displacement-of-the-center-of-mass-during-walking-a-/ 與 https://clinicalgaitanalysis.com/faq/determinants.html 摘要
17. 走路時 COM 最高點在單支撐中點（midstance，passing 姿勢）、最低點在雙支撐中點（contact／down 姿勢），所以每步（不是每 stride）一個完整正弦週期，每個 stride 兩次最高點。【出處】https://www.mov-sport-sciences.org/10.1051/sm/2013047 摘要
18. 倒單擺幾何：支撐腿為長 L 的剛性桿，半步長 s/2，則質心在 passing 比 contact 高 h = L − √(L² − (s/2)²) = L(1 − cos θ)，其中 sin θ = s/(2L)。【推導】（倒單擺雙支撐模型見 https://arxiv.org/pdf/1702.07312 摘要的步長公式 L_step = 2√(2·l·h − h²) 同源）
19. 代入：L = 0.9 m、s = 0.7 m → θ = 22.9°、h ≈ 7.1 cm。實測只有約 5 cm，因為骨盆旋轉、骨盆傾斜、站立膝彎、腳踝滾動、側向位移這些「決定因子」把起伏壓低；純剛性腿模型會高估。所以：**程式驅動骨架若用剛性腿硬湊，起伏會比真人大約 40%，必須人為縮小**。【推導】+【出處】Saunders/Inman/Eberhart 1953 決定因子，見 https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/saunders.htm
20. 此處實測 5 cm ÷ 腿長 0.9 m ≈ 0.055 L（約 0.03 H）。【推導】
21. 跑步 COM 垂直起伏約 6–8 cm（跑步經濟性最佳範圍），Garmin／跑步圈常用 6–9 cm 當目標；跑步的 COM 在騰空相最高、在站立中點最低（彈簧—質量模型），和走路的倒單擺曲線**相位相反**。【出處】https://runnersconnect.net/improve-your-vertical-oscillation-for-better-running-performance/ ；彈簧—質量模型：https://pmc.ncbi.nlm.nih.gov/articles/PMC1664632 摘要
22. 為什麼過度起伏看起來像「抖」：
   - 起伏頻率是步頻的 2 倍（走路視覺上約 1.7–2.0 Hz 的垂直擺動），幅度一大、加速度就以頻率平方放大：a_peak = (A/2)(2πf)²。【推導】
   - 在 2D 側視、角色大、螢幕上每影格位移是整數像素時，高度若每步又被腳補償（IK 修身體）疊加第二個頻率，頻譜就出現非步頻諧波，眼睛讀成「抖」。【推導／經驗】
   - 真人身體垂直起伏被刻意壓低，是演化選擇；動畫放大到 7% 腿長以上就會讀成「彈跳」。【建議，無出處】
23. 速度改變時的平滑：不要每影格用「腳的位置」重算身體高度；身體高度 = 平滑後的地面參考 + 由步態相位解析算出的起伏。地面參考變化用臨界阻尼彈簧或指數衰減追隨：x ← x + (target − x)(1 − e^(−λΔt))（與影格率無關）；Unity SmoothDamp 為 Game Programming Gems 4 第 1.10 章的臨界阻尼實作。【出處】https://docs.unity3d.com/ScriptReference/Mathf.SmoothDamp.html 、https://howlingmoonsoftware.com/improved-lerp-smoothing/ 、Freya Holmér「Lerp smoothing is broken」（搜尋摘要：https://www.gamedeveloper.com/programming/improved-lerp-smoothing-）
24. 起伏幅度要隨速度縮放（慢走幅度小、快走大）且連續，不可在速度門檻上跳變。【建議】

## 3. 程式驅動／IK 腳步（遊戲業界做法）

25. Overgrowth（David Rosen, Wolfire）：全遊戲只用 13 個骨骼關鍵姿勢；走與跑各只有 4 個姿勢（左右各一個 pass 與 reach），另有一個蹲、一個待機，其餘由程式在姿勢間內插並依速度與地形調整。【出處】https://discussions.unity.com/t/an-indie-approach-to-procedural-animation-gdc-video-talk/538228 ；GDC 2014 Animation Bootcamp「An Indie Approach to Procedural Animation」https://www.gdcvault.com/play/1020583/Advanced-Animation-with （摘要，影片本身未能開啟）
26. Rosen 主張「動畫與程式要更緊密合作，程式負責分擔重複工作」。【出處】https://gamedeveloper.com/design/video-an-indie-approach-to-procedural-animation 摘要
27. Rain World（Joar Jakobsson）：生物是「空間中的點，以固定距離連接」，肢體與尾巴以程式依輸入與地形即時生成，不是逐格畫。**沒有找到**其腳步放置演算法的具體數字。【出處】https://unity.com/en/blog/exploring-procedural-design-rain-world 摘要
28. Hollow Knight：Ari Gibson 逐格手繪，主角移動模型參考洛克人／洛克人 X：水平移動沒有加減速、跳躍起跳提升大、放開按鍵快速切斷上升速度。【出處】https://gameinformer.com/2018/10/16/the-making-of-hollow-knight 與搜尋摘要（移動模型一句來源頁未能確認）
29. Dead Cells：先畫 2D 像素模型表，再用 3D 骨架（3ds Max）做動畫後轉成 2D；說明程式驅動 3D 骨架並烘成 2D 是可行路線。細節數字【沒找到】。【出處】https://habr.com/post/416589
30. Celeste：土狼時間（coyote）寬限約 6 格（約 0.1 秒）、跳躍頂點把重力減半（讓落地前更好調整且畫面更舒服）。這屬於手感而非骨架，但是跳／落地姿勢要對應這些時間點。【出處】https://gigazine.net/gsc_news/en/20200317-celeste-action-feel-things
31. Metal Slug：**沒找到**可靠的走路／跑步數字（它是逐格手繪，與我們的程式驅動不同）。
32. 距離相位步態（stride wheel）：步態相位不是依時間，而是依走過的距離累加：phase += |Δx| / stride_length。這樣支撐腳在相對身體的位置後退速度恰好等於身體前進速度，世界座標不動，是代數恆等式，任何速度、加減速中都不會滑步。【出處】https://bugnet.io/blog/how-to-fix-unreal-control-rig-foot-ik-sliding-during-locomotion 摘要（及 https://docs.vulkan.org/tutorial/latest/Advanced_glTF/Procedural_Animation_IK/04_foot_placement.html 的足部放置概念）
33. IK 只負責把腳「垂直接地」；水平滑步來自播放速率與位移不匹配，要靠 stride warp（調整播放速率配合速度）與「踩地期間鎖定腳的世界位置」解決。【出處】同上摘要；Unreal 版參考 https://dev.epicgames.com/documentation/en-us/unreal-engine/fix-foot-sliding-with-ik-retargeter-in-unreal-engine
34. 腳的 IK 修正要乘一個「踩地權重」（踩地時 1、騰空時 0，平滑過渡），並對 IK 目標做時間平滑，否則腳會瞬移、身體被帶著抖。【出處】同上摘要
35. Godot 4 內建 SkeletonModification2DTwoBoneIK（餘弦定理，只能兩骨，適合腿與手臂，比 FABRIK 輕）與 SkeletonModification2DFABRIK（支援角度限制、多骨）。【出處】https://docs.godotengine.org/en/4.3/classes/class_skeletonmodification2dtwoboneik.html 、https://docs.godotengine.org/en/4.2/classes/class_skeletonmodification2dfabrik.html 。註：官方文件把此 API 標為「Attention: Here be dragons」，4.x 後期可能被改版，採用前查你們實際的 Godot 4.7 文件。
36. 步幅由速度與腿長決定：先決定步頻 f(v)，再 s = v / f，且 s ≤ 約 1.0 L；不是用腳位置回推身體高度。【推導】

## 4. 2D 骨架動畫常見坑與解法

37. 剛體零件關節穿幫（肘、膝、髖露出縫或缺口）：用網格權重變形（Spine 的 weights／Smooth 平均相鄰頂點權重）或讓相鄰零件重疊、把關節放在被遮蓋處。【出處】https://esotericsoftware.com/spine-weights 摘要。Godot 對應：Polygon2D + Skeleton2D 權重，或零件加圓形「關節蓋」。
38. 頭與胸要穩定：真人行走時頭會用俯仰補償垂直位移，使視線穩定（Frankfort 平面旋轉補償，最大不超過 20°）。所以頭的旋轉要反向抵銷軀幹傾斜，頭的垂直位移幅度小於骨盆。【出處】Pozzo, Berthoz, Lefort 1990，摘要見 https://link.springer.com/chapter/10.1007/978-3-7091-1379-0_44 等
39. 重疊動作與跟隨（overlapping action / follow-through）：主體停下後，手臂、頭髮、衣擺、尾巴繼續一會兒再追上；轉向時衣物比身體晚數格轉過去。【出處】Thomas & Johnston《The Illusion of Life》1981，摘要見 https://people.wku.edu/joon.sung/edu/anim/3d/animation/principles.html
40. 預備（anticipation）：跳、起跑前先彎膝、下沉；落地後恢復。【出處】同上
41. 次級動態：頭髮、衣物、尾巴用彈簧骨（鏈式阻尼彈簧），輸入是軀幹加速度而不是位置，頻率低於步頻（常見做法）。數值【建議】見 §7。
42. 動畫混合（待機↔走↔跑）：不同循環要用「相位對齊」（sync markers／sync groups／同一個正規化時間）混合，否則一個循環左腳著地、另一個右腳著地，內插出滑步與腳交叉。【出處】https://dev.epicgames.com/documentation/unreal-engine/animation-sync-groups-in-unreal-engine 、https://kybernetik.com.au/animancer/docs/manual/blending/mixers/synchronization 摘要。我們是程式驅動，等價做法：**走與跑共用同一個相位變數**，只改幅度參數（步長、起伏、膝角、前傾），不換相位。【建議】
43. 轉身處理：沒有找到業界數字。建議：停下或減速再轉；轉身期間保持支撐腳世界位置不動；Godot 用 scale.x 翻轉要同時處理零件左右不對稱與 z 順序。【建議，見 §7】
44. 啟動與煞車的加減速姿勢：加速時身體前傾，煞車時後仰。物理上，為了平衡，傾角約 atan(a/g)（a 為水平加速度）；遊戲內需縮放並限幅。【推導】數值【建議】見 §7。

## 5. 待機與 NPC「像人」

45. 呼吸：成人靜息呼吸 12–20 次/分（週期 3–5 秒）。【出處】https://lifestack.ai/blog/respiratory-rate 等摘要
46. 眨眼：靜息平均約 17 次/分、對話時約 26、閱讀時約 4.5；每次 100–400 ms（自發眨眼多落在 100–150 ms）。【出處】https://bionumbers.hms.harvard.edu/bionumber.aspx?id=113196 、https://pmc.ncbi.nlm.nih.gov/articles/PMC8500445 摘要
47. 眨眼間隔分布為對數常態（右偏）：多數間隔短，偶爾很長。所以間隔不要用固定值或均勻亂數，用對數常態或「基準 + 指數亂數」。【出處】https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6207319/ 摘要
48. 避免機械感：週期加隨機抖動、各骨頭不同相位與不同週期（用互質頻率組合）、緩動曲線不用純正弦（吸氣較快、呼氣較慢並停頓）。【建議，無出處】
49. 重心轉移（weight shift）：每 4–12 秒隨機換一次重心腳，骨盆水平位移 ±0.02 L、緩入緩出約 0.6–1.0 秒。【建議，無出處】
50. 視線與說話手勢：眼先動、頭後動、身體最後（時間差 0.05–0.15 秒）。【建議】說話手勢以「重音」觸發，不用連續循環。【建議】

## 6. 驗收指標（可寫成自動測試）

測試情境：固定速度 v 在平地走 ≥ 8 秒（≥ 15 步），60 fps，取穩態段；取樣量包含骨盆 y、每隻腳世界座標、左右腳著地旗標。以下門檻中「業界」指有出處數字支撐，其餘為【建議】。

| # | 指標 | 門檻 | 性質 |
|---|---|---|---|
| T1 | 骨盆 y 頻譜：主峰頻率 = 步頻 f_step（誤差 ≤ 5%） | 主峰在 f_step | 業界原理（§2 條 17） |
| T2 | 骨盆 y 能量集中度：f_step 及其 2 倍、3 倍諧波能量 ÷ 去直流總能量 | ≥ 90% | 建議 |
| T3 | 高頻能量：頻率 > 3·f_step 的能量 ÷ 總能量 | ≤ 3% | 建議 |
| T4 | 骨盆 y 峰谷幅度（p-p，走）| 0.03–0.06 L | 業界 5 cm ≈ 0.055 L 為上界（§2 條 20） |
| T5 | 骨盆 y 峰谷幅度（跑）| 0.06–0.09 L | 業界 6–8 cm（§2 條 21） |
| T6 | 每步內骨盆 y 速度符號變化次數（先 5 Hz 低通） | = 2（一峰一谷） | 建議（防「多重彈跳」） |
| T7 | 垂直加速度峰值 | ≤ 1.5 × (A_pp/2)(2π·f_step)² | 建議（正弦理論值的 1.5 倍） |
| T8 | 垂直速度峰值 | ≤ 1.5 × (A_pp/2)(2π·f_step) | 建議 |
| T9 | 每影格骨盆 y 變化量 | ≤ 1.5 × T8 門檻 ÷ 60 | 建議 |
| T10 | 垂直 jerk 峰值 | ≤ 2.5 × (A_pp/2)(2π·f_step)³ | 建議 |
| T11 | 踩地期間支撐腳世界水平速度 | ≤ 0.05·|v|（即身體座標系下腳速 ≈ −v，誤差 5%） | 業界原理（§3 條 32）；門檻為建議 |
| T12 | 單次踩地期間腳的世界位移（滑步） | ≤ 0.02 L | 建議 |
| T13 | 腳高度：踩地期間腳底 y 與地面差 | ≤ 1 px 或 0.01 L | 建議 |
| T14 | 腿伸展比 d/L（髖到踝距離 ÷ 腿總長） | 0.60–0.98，且不出現被 IK 夾斷（clamp）的影格 | 建議 |
| T15 | 左右步對稱：奇數步與偶數步骨盆 y 峰值差 | ≤ 10% | 建議（相關概念：harmonic ratio，見 https://link.springer.com/article/10.1186/s12984-018-0398-3） |
| T16 | 骨盆 y 與解析曲線的 RMS 誤差（y_actual 對 h0 + (A/2)·sin 相位） | ≤ 0.01 L | 建議 |
| T17 | 與地形無關：把地面抬高/降低 0.05 L 的台階，骨盆 y 變化改由平滑的地面參考處理，變化量最大每影格 | ≤ 0.015 L | 建議 |
| T18 | 變速：v 在 0.3 秒內由 0 升到走速，骨盆 y 無過衝（overshoot）、每影格 Δy 同 T9 | 無過衝 | 建議 |
| T19 | 步頻範圍：走 1.4–2.4 Hz（f_step）、跑 2.4–3.2 Hz | 落在範圍 | 業界（§1 條 9）取整 |
| T20 | 走→跑切換前後骨盆 y 相位連續（相位差 ≤ 0.05 週期） | 通過 | 建議 |
| T21 | 頭 y 的 p-p ≤ 骨盆 y 的 p-p | 通過 | 建議（§4 條 38） |
| T22 | 動作平滑度：SPARC 或 LDLJ（對數無因次 jerk）不低於「純正弦基準」的 90% | 通過 | 業界指標（https://link.springer.com/article/10.1186/s12984-018-0398-3 ），門檻為建議 |

說明：
- A_pp = 實際設定的 p-p 幅度；公式以「純正弦」為基準，可容許 1.5 倍裕度（對應多一點不對稱）。
- 例（L = 120 px、f_step = 1.9 Hz、A_pp = 0.05 L = 6 px）：a_peak ≈ 0.5·6·(2π·1.9)² ≈ 427 px/s²；T7 上限 ≈ 640 px/s²；T9：每影格 ≤ 約 0.45 px。注意：若整數像素吸附（pixel snap）會讓 T9 失敗，應對骨盆 y 不要取整，或在最後渲染層才取整。【建議】

## 7. 給我們的建議參數表（L = 腿長、H = 身高；全部為【建議】，除註明出處者）

### 7.1 步態與步頻

| 參數 | 待機 | 走 | 慢跑 | 全速跑 | 備註 |
|---|---|---|---|---|---|
| 速度 v | 0 | 0.8–1.8 L/s | 2.0–3.0 L/s | 3.5–5.0 L/s | 真人走 1.4 m/s ÷ 腿 0.9 m ≈ 1.55 L/s（推導） |
| 步頻 f_step | — | 1.4–2.0 Hz | 2.4–2.8 Hz | 2.8–3.2 Hz | 走/跑切換約 2.33 Hz（出處 §1 條 9） |
| 步長 s = v / f | — | 0.55–0.85 L | 0.8–1.2 L | 1.2–1.6 L | 走路 s ≤ 1.0 L |
| 站立相占比 | — | 60%（出處） | 40% | 30% | 跑步有騰空相 |
| 雙支撐 | — | 各 10%（出處） | 0 | 0 | |
| 騰空相 | — | 0 | 10–15% | 20–30% | |

走路相位用「距離累加」：phase += |Δx| / (2·s)（一個 stride 為兩步）。

### 7.2 骨盆與軀幹

| 參數 | 走 | 跑 | 備註 |
|---|---|---|---|
| 骨盆基準高度 h0（站立） | 0.93 L | 0.88 L | 站直 = 1.0 L，保證腿永遠不全伸 |
| 骨盆垂直起伏 p-p | 0.04–0.05 L（速度慢→小） | 0.07–0.08 L | 走：出處 ≈ 5 cm ≈ 0.055 L 為上界；跑：6–8 cm |
| 起伏曲線 | 正弦，最高在 passing | 倒過來：最低在站立中點、最高在騰空 | 走為倒單擺，跑為彈簧—質量 |
| 起伏隨速度縮放 | 線性插值，連續 | 同 | 不可有門檻跳變 |
| 地面參考平滑 | SmoothDamp，smoothTime 0.10–0.15 s | 0.08–0.12 s | 僅用於地形高度變化，不套在起伏上 |
| 骨盆水平擺動 | ±0.01–0.02 L（側視可省略） | 同 | |
| 骨盆旋轉（水平面，側視用肩寬壓縮表現） | ±4°（出處） | ±8° | 側視可轉成零件 x 縮放 |
| 骨盆傾斜（冠狀面） | 5°（出處） | 5° | 側視可省略 |
| 軀幹前傾 | 2–4° | 8–15° | 跑步前傾角度數字【沒找到】 |
| 肩與髖反向旋轉 | 肩 ≈ −1.0× 髖角 | −1.5× | 手臂跟對側腿 |
| 頭穩定 | 頭俯仰 = −0.8 × 軀幹俯仰 | 同 | 頭 y 起伏 ≤ 0.6 × 骨盆（出處概念 §4 條 38） |

### 7.3 四肢與腳

| 參數 | 走 | 跑 |
|---|---|---|
| 膝角（站立相最小彎曲） | 15°（出處） | 25–35° |
| 腳擺盪高度（腳底離地） | 0.08–0.12 L | 0.2–0.3 L |
| heel strike 腳尖上翹 | 10–15° | 0–10°（前掌著地也可） |
| toe off 腳跟抬起 | 30–45° | 40–60° |
| 腳踩地鎖定 | 世界座標固定，T11/T12 | 同 |
| 手臂擺幅（肩角） | ±20–30° | ±40–55° |
| 手肘彎曲 | 10–25°（出處概念：走近乎直） | 80–100°（出處概念：跑彎肘） |
| 手臂相位 | 與對側腿同相（出處） | 同 |

### 7.4 跳、落地、蹲、轉身、啟停

| 動作 | 建議 |
|---|---|
| 起跳預備 | 骨盆下沉 0.08–0.12 L、時間 0.05–0.08 s，再以 0.05 s 伸展 |
| 空中 | 上升腿收、頂點（Celeste：重力減半）軀幹水平；下降腿前伸準備落地 |
| 落地 | 骨盆下沉量 = 0.05 L + 0.03 L × 落地速度/最大落地速度，臨界阻尼回復 0.15–0.25 s；零件加彈簧骨 follow-through |
| 土狼時間 | 約 6 格（0.1 s，出處 Celeste） |
| 蹲 | 骨盆降到 0.6–0.7 L，軀幹前傾 10–20°，時間 0.1–0.15 s；蹲走步長 0.5×、起伏 0.5× |
| 轉身 | 速度先降到 < 0.3 L/s 再翻轉，翻轉時間 0.08–0.12 s；翻轉當下支撐腳世界位置不變；頭先轉、身體後轉（0.05 s 差） |
| 啟動 | 前傾角 = clamp(k·a_x, 0, 12°)，k 取使加速到走速時傾約 4–6°；第一步先邁出離前進方向較近的腳 |
| 煞車 | 後仰 ≤ 8°，雙腳著地（雙支撐）滑一小段，再回待機 |
| 走↔跑 | 共用同一相位變數；以 0.15–0.25 s 內插膝角、起伏、前傾 |

### 7.5 待機與次級動態

| 參數 | 建議 |
|---|---|
| 呼吸 | 週期 3–5 s（出處 12–20 次/分）、胸腔 y ±0.006 L、肩 ±0.004 L；週期每次 ±10% 隨機；吸氣 40% 呼氣 60% |
| 眨眼 | 間隔對數常態，中位數約 3.5 s（出處 17 次/分平均）；一次 120–150 ms（出處 100–400 ms） |
| 重心轉移 | 4–12 s 隨機一次、0.6–1.0 s 緩動、骨盆 ±0.02 L |
| 各骨相位 | 脊椎各節、頭、手臂以不同相位與互質頻率疊加，避免同步 |
| 頭髮、衣物彈簧骨 | 自然頻率 3–5 Hz、阻尼比 0.3–0.6；輸入為軀幹加速度，不用位置 |

## 8. 常見錯誤對照表

| 症狀 | 常見原因 | 修正（見章節） |
|---|---|---|
| 走路時身體持續上下抖 | 骨盆高度由腳位置每影格重算，加上 IK 再修正，兩個頻率疊加 | 骨盆 y = 平滑地面參考 + 相位解析起伏；IK 只修腳（§2 條 23、§3 條 33） |
| 起伏看起來像彈跳／Q 彈 | 幅度 > 0.07 L（走）；或用剛性腿硬湊 | 幅度 0.04–0.05 L，並把站立膝彎 15° 納入（§2 條 19） |
| 每步高度不一致（左右不對稱） | 左右腿長/骨長不同，IK 目標不同 | T15 對稱門檻；左右用同一組參數 |
| 腳滑步 | 相位依時間而非距離；踩地沒鎖世界座標 | 距離相位 + 鎖定（§3 條 32–33） |
| 腳瞬移／腳尖點地抖動 | IK 目標不平滑、踩地權重突變 | 踩地權重平滑、IK 目標低通（§3 條 34） |
| 腿被拉直又彈回（膝爆） | h0 太高，腿全伸被 IK clamp | h0 ≤ 0.93 L、T14（§7.2） |
| 速度變化時身體抽動 | 起伏幅度用門檻切換或直接用速度重算 | 幅度連續函式 + 臨界阻尼（§2 條 23–24） |
| 走跑切換時腳交叉／跳一下 | 兩套循環相位不同 | 共用相位變數（§4 條 42） |
| 頭晃得很厲害 | 頭完全剛性跟隨軀幹 | 頭穩定：反向補償俯仰（§4 條 38） |
| 關節出現縫隙 | 剛體零件在彎曲處分開 | 網格權重或遮蓋（§4 條 37） |
| 待機像機器人 | 單一正弦、固定週期、各骨同相位 | 隨機週期、不同相位、非對稱緩動（§5 條 48） |
| 轉身時腳滑、零件突然跳面 | 直接 scale.x = −1 且沒鎖腳 | 低速轉身、鎖支撐腳、頭先轉（§7.4） |
| 像素角色高度閃爍 | 骨盆 y 在中間就取整 | 只在最後渲染取整，或用子像素合成 |
| 動作單調、沒有「重量感」 | 缺預備／跟隨 | 預備下沉、落地回彈、次級彈簧骨（§4 條 39–41） |

## 9. 實作建議摘要（給程式）

1. 相位變數：phase（0–1 為一個 stride），phase += |Δx| / (2·s)；s = v / f_step，f_step 為速度的連續函數。
2. 骨盆 y：`pelvis_y = ground_ref_smoothed - (h0 + bob(phase, v))`，bob 為解析公式（走：正弦；跑：反相、幅度較大）；ground_ref 以 critically damped spring 追隨地形高度。
3. 腳：每隻腳有「踩地權重」；踩地時世界座標鎖定（水平不動），擺盪時走貝茲軌跡；然後用 2 骨 IK 解膝。**不要**用 IK 結果反推骨盆高度。
4. 腿長保護：保證 d/L ≤ 0.98；超出時縮短步長，不是抬高骨盆。
5. 軀幹、頭、手臂：由相位推導的次級動作，頭做反向補償；頭髮與衣物走彈簧骨。
6. 輸出測試所需資料（骨盆 y、腳世界座標、踩地旗標）以便 §6 的自動測試取樣。

## 10. 出處清單（皆為搜尋結果實際出現的連結，未逐頁核實）

- Williams 四關鍵姿勢與格數：https://courses.cs.washington.edu/courses/cse459/19au/assignments/assignment_5/index.html 、https://animation.monmouth.edu/instruct/?p=351
- 正常步態數值：https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf 、https://now.aapmr.org/biomechanics-normal-gait/ 、https://orthobullets.com/foot-and-ankle/7001/gait-cycle
- 決定因子與質心起伏：https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/saunders.htm 、https://clinicalgaitanalysis.com/faq/determinants.html 、https://pure.psu.edu/en/publications/the-vertical-displacement-of-the-center-of-mass-during-walking-a-/
- 倒單擺：https://arxiv.org/pdf/1702.07312
- 走跑轉換：https://en.wikipedia.org/wiki/Transition_from_walking_to_running
- 跑步起伏與步頻：https://runnersconnect.net/improve-your-vertical-oscillation-for-better-running-performance/ 、https://eprints.leedsbeckett.ac.uk/id/eprint/7491/6/TheBiomechanicsOfDistanceRunningAM-HANLEY.pdf
- 手臂擺動：https://pubmed.ncbi.nlm.nih.gov/19181900/ 、https://hsrc.himmelfarb.gwu.edu/smhs_psych_facpubs/1801
- 頭穩定：https://link.springer.com/chapter/10.1007/978-3-7091-1379-0_44
- 平滑與阻尼：https://docs.unity3d.com/ScriptReference/Mathf.SmoothDamp.html 、https://howlingmoonsoftware.com/improved-lerp-smoothing/
- 平滑度指標：https://link.springer.com/article/10.1186/s12984-018-0398-3
- Overgrowth：https://www.gdcvault.com/play/1020583/Advanced-Animation-with 、https://discussions.unity.com/t/an-indie-approach-to-procedural-animation-gdc-video-talk/538228
- Rain World：https://unity.com/en/blog/exploring-procedural-design-rain-world
- Hollow Knight：https://gameinformer.com/2018/10/16/the-making-of-hollow-knight
- Dead Cells：https://habr.com/post/416589
- Celeste：https://gigazine.net/gsc_news/en/20200317-celeste-action-feel-things
- 同步與混合：https://dev.epicgames.com/documentation/unreal-engine/animation-sync-groups-in-unreal-engine
- 腳 IK／滑步：https://bugnet.io/blog/how-to-fix-unreal-control-rig-foot-ik-sliding-during-locomotion 、https://docs.vulkan.org/tutorial/latest/Advanced_glTF/Procedural_Animation_IK/04_foot_placement.html
- Godot 2D IK：https://docs.godotengine.org/en/4.3/classes/class_skeletonmodification2dtwoboneik.html
- Spine 權重：https://esotericsoftware.com/spine-weights
- 十二原則：https://people.wku.edu/joon.sung/edu/anim/3d/animation/principles.html
- 眨眼／呼吸：https://bionumbers.hms.harvard.edu/bionumber.aspx?id=113196 、https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6207319/ 、https://lifestack.ai/blog/respiratory-rate

### 明確「沒找到」清單
- Williams 跑步循環每步幾格的可靠數字；Metal Slug／Hollow Knight／Dead Cells／Celeste 的走路或跑步步頻、起伏數字；Rain World 腳步演算法細節；走路手肘與肩擺角度；跑步前傾角度；腳掌 heel strike／toe off 角度；轉身處理的業界數字；Rosen GDC 影片本身的內容細節（只有摘要）。
