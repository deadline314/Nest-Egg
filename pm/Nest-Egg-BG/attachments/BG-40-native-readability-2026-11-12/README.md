# BG40：三包物件的本機可讀性收尾

2026-11-12，Godot4.7.2、Radeon RX9070XT、Vulkan Forward+／HDR2D、1280×720、亮度0.5，高低品質各完整39格。這是腳本控制的正式場景與真碰撞接地，非人工遊玩／實體手把；不作效能結論。

## 正確需求與沿用證據

BG40三區是當舖收音機ch2_pawnshop、復原館外客人簿ch2_lounge_front、天穹接待廊ch3_office_hall。二樓帳房與前室不在此票三包範圍，帳房敵人真紅保留於BG42；不把那個紅格當作三區唯一條件。

BG53已證明舊像素面積數字失效；其四區新表雖面積正確，仍沿用SceneTour的floor-minus-two，且沒有完整held owner／原HDR重算鏈，故不拿來補真接地。已發布f52cb415的BG48復原館外高低各完整九格是真接地／真owner／正確HDR，原霧1.0與現0.5同場控制均通過；本票只驗索引中的原ZIP SHA並沿用該方法／原圖，不重拍那份霧比較。[來源鏈](related-origins.json)指向原公開附件。

缺少的是BG40移入物件之前的同條件參照，因此本次在同一現況幾何與runtime，只切換BG40的原props差異：收音機三件、客人簿兩件、接待廊七件↔舊沙發／燈柱／樹。後續BG45取件格等共同物件保持；沒有冒稱歷史checkout。原3e9ddccd6前後map bytes與差異放在producer來源ZIP，非props欄位逐值相同。

## 高低品質完整格網

| 三區 | 每品質原格／可站主角 | 高：主角／地面最小 | 低：主角／地面最小 |
|---|---:|---:|---:|
| 第二章當舖 | 18／12 | 0.881173／3.053076 | 0.853853／2.972798 |
| 第二章復原館外 | 9／6 | 2.271691／3.413033 | 2.274084／3.446825 |
| 第三章天穹接待廊 | 12／8 | 1.107204／3.141039 | 1.327062／3.098826 |

原0.6／0.45／1.0門檻不變。高低各26格有主角真支撐，空中13格保存原圖但不造玩家數值。三區實際Enemy inventory各格均為0，敵人對比與實體曝光是N/A，不寫0.45或2%通過，也不另造敵人fixture。原PNG、原RGBAH bytes、格式／大小及五步逐字節保留。

A0→A1→B→恢復A→B2：A/A/恢復A的整張HDR SHA相同、B/B2相同；固定原角色、shader TIME、雨霧，逐次更新LightBudget、WallShadows、接觸陰影與槍燈。每格實際move_and_collide接地，保留safe margin、支撐ray、floor/feet/gap與真physics space；不偽造is_on_floor快取。隱藏的另一版本prop光源同時停用，避免消耗LightBudget的名額。所有同格其他props及演員/雨霧/相機狀態原樣保留。物件及光照才是本次單因素，不要求A/B兩種擺設的選燈字典相等。

兩個正式native都真正exit0、無ERROR／SCRIPT ERROR／WARNING／退出洩漏，來源before/after相同；約58秒是擷取耗時，不稱fps或獨占效能。獨立NumPy從原float重建floor/ceil及裁切、body/ring/edge/below全部原像素與分母，兩品質78格全部原門檻成立。故意錯移body盒1px／破壞owner valid各真正exit1拒絕，僅改解析後記憶體副本、不改原文件。

## 下降值與原尺寸畫面

數值沒有全部上升。新增紙燈／客人簿讓主角外圈更亮，接待廊窄長凳也改變原白沙發附近的外圈；完整下降位置及未取整值在高低獨立報告，沒有當作跨程序noise或隱藏。

煙測接待廊c1:r1為2.002355→1.412735，仍高於0.6；同格原尺寸圖顯示頭髮、背腰、兩腿與落點可辨，新增物件在人物後方。此處的「不退步」判實際可讀性與原門檻，沒有新增「所有高於門檻的標量逐格單調」條件，也不宣稱contrast未下降。

[全部精選原圖及canonical盒](selected-final-images.json)包含高低各區現況主角最小與下降最大點；並排左原props、右現props，每個面板逐像素等於原PNG、沒有縮放或重繪。當舖低品質沒有下降格，故只選現況最小；高品質收音機點的約6.4e-8微降仍列原值。已實看10組原尺寸canonical outer並排及煙測全圖／近拍，沒有物件覆蓋人物；不宣稱人工檢視全部78張全圖。

## 原始來源、外部資料與重算

全部5個程序原件在`D:/NestEggDeliveries/BG40-20261112/`，13個ZIP共385,143,770 bytes、5,802會員。每個ZIP及原member SHA／長度都實讀核對；[索引](raw-index.json)、[獨立收據](package-independent.json)可驗。Git只收索引／reader／精選原圖與小型producer source ZIP，不收完整HDR生成資料。原生資料保存真正換行與每輪工具版本，CPU最初validate與後續native工具版本不冒稱相同；兩次精選圖片工具的float切片／RGBA通道拒絕版本也保留source，最終pair用完整RGBA逐像素比對。

實際D Git基底及當前C差異列於[source-compatibility](source-compatibility.json)。兩輪39格使用相同固定D來源；三區map／theme／LevelData與目前C逐byte相同，CharacterRig、HumanoidAnimator、shader／量測／held owner同SHA。其餘12個已明列的C差異不冒充同版；測量不是過場、NPC或近戰攻擊，保留每輪完整實際source。BG56可選補光在這三區保持0，其預設0原像素控制另有已發布BG56證據。這次未改任何產品、主tools或永久測試，正式交付只有票／設計補證與附件，依AGENTS文件更動不另跑遊戲套件。

結案前另逐一只讀核對12項：[活躍路徑與材質審核](source-audit.json)、[原C／D bytes及exact／內容diff小包](source-audit-index.json)。TerrainMaterialData的D原件SHA `b93838f0c08091ce24c2c304bd36690f33aae2c858d39bb7230346c858d2f051` 正是已發布Git blob（1846 bytes、0 CRLF）；C工作檔為1885 bytes、39 CRLF，僅換行導致不同SHA，並非D落後發布版本。三區concrete／asphalt／facility_floor的材質資源同樣只差C的CRLF，所有欄位值與已發布原件一致；實際body／top／side及自動normal貼圖另外逐byte核對相同。Terrain／TerrainEdges繪製來源不變，沒有需要重拍的地形語義差異。

其餘11項均列原始diff與具體入口：NpcAnimator只新增兩個不改動畫的只讀getter；PlayerVisual只在rig更新後呼叫新的after_visible_pose，固定預設pistol且沒有出招時pending全false、phase NONE，沒有寫姿態／材質／光影；MeleeHeld走未顯示的early-return，MeleeArt／MeleeSet的新接觸與近戰繪圖路徑不執行，三區沒有武器拾取；Hurtbox新增三角接觸、三份Cutscene reach/move與JANUS設定搬移均不在此無敵人／無出招／無過場的活躍路徑。NPC原動畫本身仍可在前置warmup執行，沒有把「無NPC」當理由。這是本場景路徑審核，不宣稱完整C／D語義相同；原生封包與既有報告未改寫。

從repo執行，需Python NumPy／Pillow；未給`--raw-root`時仍讀附件相對raw目錄：

```powershell
python -X utf8 pm/Nest-Egg-BG/attachments/BG-40-native-readability-2026-11-12/replay/verify_package.py pm/Nest-Egg-BG/attachments/BG-40-native-readability-2026-11-12 --raw-root D:/NestEggDeliveries/BG40-20261112
python -X utf8 pm/Nest-Egg-BG/attachments/BG-40-native-readability-2026-11-12/replay/verify_package.py pm/Nest-Egg-BG/attachments/BG-40-native-readability-2026-11-12 --raw-root D:/NestEggDeliveries/BG40-20261112 --case bg40-all-high-v1 --restore D:/BG40Review
python -X utf8 pm/Nest-Egg-BG/attachments/BG-40-native-readability-2026-11-12/replay/verify_bg40_native.py D:/BG40Review/bg40-all-high-v1 --out D:/BG40Review/high-independent.json
```

低品質換bg40-all-low-v1；fresh clone需取得索引同SHA外部ZIP，沒有把缺少外部artifact說成可離線完整重算。所有歷史錯算法數字、原圖與帳房紅格保留，不作新修前值。
