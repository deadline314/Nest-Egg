# NE-229：同一步受擊停格不漏掉載具互動

先讀User-guide及[相近作品與既有輸入研究](../../../../design/20-campaign-experience/VEHICLE_HITSTOP_INPUT.md)。保留原停格、距離、空車、上下車保護、長按與暫停規則。互動接收者先輪詢、之後同一步戰鬥停用角色時，原本會先記住按住卻沒有真正執行；改在戰鬥與角色之後觀察同一步局部停格。

[完整收據](validation.json)、[逐檔SHA](manifest.json)、[全部原檔](raw.zip)。原InputFeel的所有既有斷言、輸入與等待逐位元重建一致；新增5項，原Smoke、Fx、玩家、載具與runner／selector／filters／known failures保持。

| 同一控制 | 修前 | 修後 |
|---|---|---|
| 原runner隔離輸入套件，80ms同一步停格 | 123項／2新失敗 | 123項／0新／已知失敗 |
| 原生舊level_01同一原遊戲流程 | 20項／1失敗 | 20項／0失敗 |

原選擇器基準f5469ea3只選InputFeelSuite，修後123／0，16秒。額外原main完整流程為2292項／0新／已知失敗，112秒；不是把核心流程排除在驗證外。最初未介入原遊戲流程六輪96／0；觀測用輸入列印僅在那六輪存在，正式產品沒有列印。另一次直接非隔離修後嘗試91／2（選單焦點、難度確認）原log保留，不補造根因；正式原runner隔離資料後123／0。兩輪原生皆0引擎ERROR、0退出洩漏診斷，exit1／0；六張真正1280×720視窗PNG逐張檢視，記錄SHA。Headless輸入壞資料案例會刻意印原有InputFeel ERROR及InputBindings警告；原main另有9筆ERROR（原壞資料／物理查詢），由原filters辨識，沒有SCRIPT ERROR，不稱完全無ERROR。

f5469ea3的完整[CI40075701152](https://github.com/deadline314/Nest-Egg/actions/runs/40075701152)實際96,395項／3新失敗、652秒。原artifact與job全log留存。第一個失敗時玩家健康5、NORMAL、無鎖／暫停，玩家及空載具皆被Fx停用；第二個原想下車的輸入卻成搭乘，第三個仍在載具。這次有真實停格狀態，但CI未記錄更早接收者的順序；80ms同一步介入證明額外真缺口，不宣稱已從原CI還原唯一callback順序。新提交完整CI須另核對，未以局部通過代稱完整綠燈。

照片在原斷言後延遲讀回，GAMEPLAY_DIAG與CAPTURE_STATE分開，不稱同一物理格。修後搭乘圖可見真正機甲血條；其餘圖可能已有自然戰鬥受擊／射擊，並非刻意清空敵人的擺拍。原生未停掉原遊戲流程的敵人。軟體Vulkan／Forward+／Dummy音訊、合成按鍵及明示80ms控制，不代稱硬體GPU、實體手把、人物接點或整票完成。真正停格owner與deadline保持，未靠提早解凍或加長原等待。

原檔54項、3,838,893 bytes；zip SHA `9f839f0c02d832f757194e349cc1cfdc53b09b157982cc4e3eeebedd53dcb68a`，每項已解出核對。
