# 洪先生頸部與上下袖口來源修補

基準 `6ddf32b5f5a188914cd008af9904286f29718067`。本單位只採三片局部來源、六張遊戲貼圖及單一重建登記，共17個唯一檔案。沿用原RGBA、骨架、動作、支點與取樣格，角色身份及其他部件保持。不是整角色、S20、真人或整票批准。

## 已驗證

- 原來源同座標頸部256像素；同一上臂既有袖料172像素；同一下臂袖口35像素。批准原PNG、來源版本、材料映射、同件所有權與遮罩外RGBA保護都在來源包。
- 主代理實際執行來源自檢、callback、正式textures→normals及前後匯入，全部退出0、0 SCRIPT/ERROR。三片diffuse及normal和批准bytes相同；整套其他runtime保持。10,181個整合來源逐檔保持。
- 14接點，左右、zoom1/3.7、120格，含S20坐深0.45、站坐說聽揮手／坐站／靠牆／蹲／攪拌／敲擊。73,920個相同key由811降32，修復779、新增0。32個膝髖失敗及其五項metrics原值保持；原checker依然退出1，沒有豁免或放寬。
- 主代理從已封裝ZIP獨立解出全部147,840個修前／修後原檢查，12份報告與原件完全相同；原1px負控通過。每個ZIP所有member再次讀取並核對SHA，單檔低於95MB。
- 主代理先前已實看8頁、32張1:1原生修前／修後圖；本次另實看三片黑灰白底原尺寸比較、五張原圖／原分件／批准來源黑灰白底診斷及S20實景全部10張1280×720圖。未見新增肢體、袖條或材質凸塊；原骨盆量體問題保持。
- 正式 `tools/run_tests_changed.sh 6ddf32b5f5a188914cd008af9904286f29718067`：88組、100,928項、0新／0已知失敗、退出0、565秒。原filter保留；不把原始log內預期負控／既有清理訊息說成不存在。

## S20 實景拒收紀錄

主代理在整合來源以正式CutscenePlayer播原letter/story/done，僅合成推進對話，未提交Story結果；Godot4.7.2／Forward+ Vulkan／RX9070XT。10張原圖全實看，來源保持、0SCRIPT/ERROR，但原1px支撐門檻抓到3項：letter坐姿臀部+1.737533569px、done坐姿+1.073425293px、done站定後足+1.988250732px。正delta代表材質向下超出支撐面。

再於獨立普通檔案副本恢復原main Hong來源與六張PNG，實際editor import退出0；同一observer原bytes及三個完整S20場景dict保持，26份相關core雜湊核對。原main實錄同樣退出1、0SCRIPT/ERROR，十個快照的座面與雙腳metric字典以及三個失敗訊息／數值全部精確相同，確認此次沒有新增支撐回歸。此副本仍有舊S08呈現，不宣稱整份當前main快照。兩輪失敗都保留，不算S20批准，未改閾值或座椅分類。完整20張PNG、HDR raw、場景／normal綁定／支撐資料、命令與log在integrated-verification.zip。

## 證據

ARCHIVES.json列出9個ZIP的外部SHA、大小與成員數；各ZIP內CONTENTS.json列原始member SHA。performance因原始圖量分為before／after兩包，其餘五組各一包。source-and-native.zip含原始來源、批准來源、整套原生32圖、normal綁定與凍結交接；integrated-verification.zip含正式回歸、獨立重播、整合建置、S20拒收及主代理診斷。

沒有改checker、known failures、generic工具、骨架、動作或戰鬥。新來源損毀、不同版本、未知後置覆寫、錯誤批准PNG與異常既有衍生輸出皆保留並拒收；三片發布先驗證全部輸出，重跑mtime保持。三張衍生來源由callback產生，不重複提交。
