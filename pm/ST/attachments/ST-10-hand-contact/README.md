# ST-10：手部接觸指令與裝水素材候選

2026-10-26（Asia/Taipei）。手臂不再只能播預設手勢：新增的 `reach` 可讓近側或遠側手到達指定舞台點，平順換目標、隨人物平移並收回；兩段骨長保持，搆不到的目標保留原手臂並記錄一次警告。無效資料不清掉現有接觸，舊的近戰握持行為保持。

這是四段演出的基礎能力。正式故事尚未引用新指令，art／舞台沒有替換；目標在未啟用握持變體時是手腕，不能把診斷叉稱為掌心已握住壺柄。完整關爐、裝水、交盤與吃麵，以及既有角色全接點的條件仍未完成，票維持進行中。

## 驗證與保留的失敗

- 初輪焦點套件473／0，補齊換點、座標空間與收手後601／0。第一輪76組回歸94,534／0新／0已知、515秒；這是途中收手修正前的預檢，對應 source/pre-release-fix，不能取代最終版本。
- 途中收手原實作的獨立反例：1項1失敗、目標仍漂移28.284271舞台像素、exit1；修正後相同案例1項0失敗、漂移0、exit0。不是正式遊戲舊版曾有此功能，而是本批尚未發布版本的邊界缺陷，原始來源與輸出都保存。
- 最終焦點CutsceneSuite：667項、0新／0已知失敗、20秒。最終原受影響選擇器：76組、94,561項、0新／0已知失敗、510秒，exit0。涵蓋凜／Old K、兩朝向、站／坐、前後手的真實手腕與骨長、父節點旋轉、人物倍率、方向、緩入、換點、跟隨平移、損毀輸入、途中收手、奇異矩陣及播放預算；沒有放寬既有門檻。
- 原生對照是同一探針把兩個reach步驟換成等長等待，**是停用新功能的控制組，不是舊production的bug重現**。17項4預期失敗→17項0失敗；兩輪都exit1／0相符，0引擎ERROR／洩漏。最終八張圖已逐張檢視。最終圖有可見性斷言，黑幕不能通過。
- 初版探針將scene fade設為0，初始黑幕沒有退掉；13／4及13／0的幾何結果仍留，但該兩輪黑圖不作視覺驗收。改成0.3後的第二輪13／0四圖實看通過，最終再補畫面可見性檢查。早期probe未另存完整原檔，差異是fade參數；保存的最終probe包含可見性檢查，沒有冒充早期原檔。
- 前次main `00f6e6c4f09df6a4cfce048d8d4b6ce3971061db` 完整CI：96,678／0新／0已知、650秒，run40224621385／job121263371209成功；原始job log與SHA回執附入。這不是本批推送後的CI結果。

Godot4.7.2、Forward+ HDR、Vulkan llvmpipe軟體、1280×720。單獨CutscenePlayer使用正式返家背景、鏡頭與人物定義，但調整站位、用診斷目標，沒有走整章Main路線；取消前後比對故事旗標、物品、錢與進度不變。淺青叉只屬探針，產品沒有診斷標記。軟體原生擷取不代稱實體GPU、手把或人工全章驗收。

## 畫面

![左朝向接觸診斷目標](../../images/ST-10-hand-contact-left.png)
![右朝向接觸診斷目標](../../images/ST-10-hand-contact-right.png)
![右朝向收手交回原動畫](../../images/ST-10-hand-contact-released.png)

## 研究與候選

重新實看Spiritfarer官方Steam圖的多層地板／梯子支撐，以及DAVE THE DIVER的座位、檯面與服務區；兩張原圖及URL／SHA在research。這些靜態圖只供比例、支撐與畫面分區參考，不能證明其手部動畫算法或玩家民調。另核對同版Godot Transform2D文件的affine_inverse、basis_xform與非奇異基底要求。

另凍結[帶龍頭的甕、空白紙籤修正、開蓋壺及開桿候選](../../../../assets_src/candidates/st10_contacts_1026/README.md)。原圖、完整提示詞、來源鏈、實際尺寸與SHA保留。首張紙籤無意義文字退件；整甕開關圖會帶動甕身／支架位移，不能直接交替採用，須固定甕身並獨立控制桿。它們尚未正式採用、加工法線或完成動作。

## 重跑

基準為00f6e6c4。套用source/final的同名檔，先用Godot4.7.2 editor匯入以更新class cache。執行 `GODOT=<4.7.2路徑> tools/run_tests_changed.sh 00f6e6c4f09df6a4cfce048d8d4b6ce3971061db`；原始76組選擇清單與各shard完整輸出保存，選擇器未改。

把replay的probe.gd／probe.tscn／edge_probe.gd／edge_probe.tscn／reach-v2.gd.txt複製到專案work/st10-reach。原生執行 `godot --path . res://work/st10-reach/probe.tscn -- --out=<絕對目錄>`，加 `--baseline` 產生停用功能控制組。使用獨立XDG_DATA_HOME；不與測試或其他重工作同跑。`edge_probe.tscn` 可以headless執行，加 `--before` 讀凍結的途中收手舊實作，無參數讀正式修正版。引擎exit及全部log均須核對，不能只看包裝器的exit。

evidence.zip保存本目錄除ZIP本身與外部validation.json外的全部檔案（含manifest）；逐entry回讀核對bytes／SHA。候選原始PNG另依上面的repo來源連結與manifest核對，不重複塞進zip。ZIP大小、SHA與回讀結果見validation.json；該回執不放入ZIP，避免自參照。
