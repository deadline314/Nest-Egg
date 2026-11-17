# NE-275：目前版本的雙向握點與手部圖證

日期：2026-11-18。基底 `eb96adda6381dafa1fd9edff59a76a622a1cde89`；Godot 4.7.2、Forward+、Vulkan、AMD Radeon RX 9070 XT、640×360、固定 60 更新率。這次只交付驗證資料與票的校正，正式遊戲、角色、招式、設定與測試程式沒有改動。10,095 份執行來源的原始 SHA256 在每次原生程序前後一致。

## 結果與可重算來源

- 原有 EnvironmentSuite、CharactersSuite、ProtagonistMotionSuite、AnimAuditSuite 共 10,724 項檢查，0 新失敗、0 已知失敗；原 changed selector 對本票開始前基底返回無受影響套件。原測試未修改。原始分片中的刻意壞資料診斷按原 runner 規則處理，不能把它們說成完全沒有 ERROR。
- 原接點工具左右各 21 招、869 個物理步，兩次實際退出 0，8 項原門檻全部通過。最接近上限的是 maul/quake 的 limb_pinch 0.744／0.75；未放寬。全引擎物理耗時只作診斷，不能當成近戰模組成本或效能對照。
- 私有拍攝轉接器沿用已發佈的完整姿勢取景與原生擷取。五把武器 × 待機／走／跑／蹲／跳／衝刺 × 左右共 60 個基本姿勢；左右各 21 招，包含資料中的延伸與按住招式，安排指定招式起手，收招後再量 20 個物理步。這不是從公開按住輸入自然進入持續招式的驗收，也不是自然戰鬥或真人操作。
- 每側 1,989 筆數值、346 張完整原生 PNG；合計 3,978 筆、692 張。真走速 45、跑速 150 世界像素／秒。前手握拳狀態、實際使用的握拳材質與原繪製順序逐筆核對；由原腕矩陣、掌心偏移與武器 origin 獨立重算，最大誤差 0.0000168851 世界像素，小於原 0.01。後手距離如實保留，不把數值缺項或姿勢例外填成零。
- 692 張取景的原世界 bounds、當格 world-to-image、手腕位置與凍結玩家見證均保留，完整範圍通過原框界檢查。47 頁手部接圖全部實際逐張檢視：每張從原圖的真正手腕座標各裁 56×56，再以最近鄰放大 3 倍；只供看手、腕與握把，不能代稱全身全部接點、每個渲染影格 alpha 接縫或曝光通過。完整圖留在封包。
- 刻意將真正持物 origin 位移 1 世界像素的原生負控制實際退出 1；未發出引擎／腳本錯誤，checker 偵測約 1.000007 的握點偏離。封包重新串接、逐檔校雜湊後，從封包重新讀取矩陣／圖像並重算；另改壞一筆原始座標且保留舊綠色宣稱，同一 reader 拒絕。

## 保留的失敗與邊界

第一版朝右拍攝實際退出 1：glaive/sweep 第 27、30、33 步的取景範圍超出畫面，不能算通過；3,978 不是把這批失敗混入後的總數。拒收版原 log、完整數值、命令、原轉接器與三張圖收入 rejected-camera-limits。私有轉接器改用不受關卡邊界限制的拍攝鏡頭後，兩面向全量重新擷取，原框界檢查保持；兩次實際退出 0、0 SCRIPT ERROR、0 ERROR。

攻擊中的武器可按既有招式穿過地面（例如下砸），不將這些畫面稱作「所有攻擊都在地面上」。待機與蹲下的地面安全由未修改的正式測試驗證。遠側拳頭仍可能被桿遮住手指；後手可達例外保留，未增加假手。兩面向是原生根翻向，不是後製鏡像。

right/glaive-cross_sweep 第 18 步的原圖中可見較亮的頭部／殘影區域；本批 PNG 沒有同格真頭 alpha／HDR，不能由它斷言曝光數值或把 NE-260 的核心連段曝光結果擴張到所有延伸招式。原圖保留，完整光度判斷仍是後續驗證範圍。

舊 Commit-1 的 Arc B580 成對耗時及第一招影格保留為歷史記錄。本次沒有合格的歷史實作／目前實作成對效能量測，亦沒有全部招式修前的同格連續影像；因此對應兩條驗收撤回勾選，票維持進行中。本次檢視未增加正式 runtime 工作，不能因此推論整票歷史效能門檻已通過。NE-260 既有刃光／減閃光結果僅沿用其明示範圍。

## 封包與重跑

`packet.json` 記錄分段、整體 ZIP 與逐檔 manifest 的 SHA256。依 parts 的順序以二進位串接後得到單一標準 ZIP，先驗證各段及整體 SHA，再解壓。封包包含原始圖、命令、原生 log、測試分片、來源 manifest、轉接器及獨立 reader。`replay/` 內保留本機絕對路徑，換機重跑需指定現有 Godot、repo 與輸出目錄；不可直接覆寫玩家的設定檔，四個設定環境路徑均需獨立。GPU 工作沿用專案共享鎖。

本機封包 reader 結果：正確封包通過；原生持物位移與改壞原始座標均被拒絕。這不是檔案上雲後的遠端下載測試。

## 已檢視圖集

- [blade-poses.png](../../images/NE-275-20261118/blade-poses.png)
- [dagger-poses.png](../../images/NE-275-20261118/dagger-poses.png)
- [glaive-poses.png](../../images/NE-275-20261118/glaive-poses.png)
- [maul-poses.png](../../images/NE-275-20261118/maul-poses.png)
- [whip-poses.png](../../images/NE-275-20261118/whip-poses.png)
- [right-blade-cut_1.png](../../images/NE-275-20261118/right-blade-cut_1.png)
- [right-blade-cut_2.png](../../images/NE-275-20261118/right-blade-cut_2.png)
- [right-blade-cut_3.png](../../images/NE-275-20261118/right-blade-cut_3.png)
- [right-blade-lunge.png](../../images/NE-275-20261118/right-blade-lunge.png)
- [right-blade-dash_cut.png](../../images/NE-275-20261118/right-blade-dash_cut.png)
- [right-dagger-stab_1.png](../../images/NE-275-20261118/right-dagger-stab_1.png)
- [right-dagger-stab_2.png](../../images/NE-275-20261118/right-dagger-stab_2.png)
- [right-dagger-flurry.png](../../images/NE-275-20261118/right-dagger-flurry.png)
- [right-dagger-return_cut.png](../../images/NE-275-20261118/right-dagger-return_cut.png)
- [right-dagger-frenzy.png](../../images/NE-275-20261118/right-dagger-frenzy.png)
- [right-glaive-thrust.png](../../images/NE-275-20261118/right-glaive-thrust.png)
- [right-glaive-sweep.png](../../images/NE-275-20261118/right-glaive-sweep.png)
- [right-glaive-cross_sweep.png](../../images/NE-275-20261118/right-glaive-cross_sweep.png)
- [right-glaive-guard_stance.png](../../images/NE-275-20261118/right-glaive-guard_stance.png)
- [right-maul-smash.png](../../images/NE-275-20261118/right-maul-smash.png)
- [right-maul-slam.png](../../images/NE-275-20261118/right-maul-slam.png)
- [right-maul-crush.png](../../images/NE-275-20261118/right-maul-crush.png)
- [right-maul-quake.png](../../images/NE-275-20261118/right-maul-quake.png)
- [right-whip-lash.png](../../images/NE-275-20261118/right-whip-lash.png)
- [right-whip-return_lash.png](../../images/NE-275-20261118/right-whip-return_lash.png)
- [right-whip-orbit.png](../../images/NE-275-20261118/right-whip-orbit.png)
- [left-blade-cut_1.png](../../images/NE-275-20261118/left-blade-cut_1.png)
- [left-blade-cut_2.png](../../images/NE-275-20261118/left-blade-cut_2.png)
- [left-blade-cut_3.png](../../images/NE-275-20261118/left-blade-cut_3.png)
- [left-blade-lunge.png](../../images/NE-275-20261118/left-blade-lunge.png)
- [left-blade-dash_cut.png](../../images/NE-275-20261118/left-blade-dash_cut.png)
- [left-dagger-stab_1.png](../../images/NE-275-20261118/left-dagger-stab_1.png)
- [left-dagger-stab_2.png](../../images/NE-275-20261118/left-dagger-stab_2.png)
- [left-dagger-flurry.png](../../images/NE-275-20261118/left-dagger-flurry.png)
- [left-dagger-return_cut.png](../../images/NE-275-20261118/left-dagger-return_cut.png)
- [left-dagger-frenzy.png](../../images/NE-275-20261118/left-dagger-frenzy.png)
- [left-glaive-thrust.png](../../images/NE-275-20261118/left-glaive-thrust.png)
- [left-glaive-sweep.png](../../images/NE-275-20261118/left-glaive-sweep.png)
- [left-glaive-cross_sweep.png](../../images/NE-275-20261118/left-glaive-cross_sweep.png)
- [left-glaive-guard_stance.png](../../images/NE-275-20261118/left-glaive-guard_stance.png)
- [left-maul-smash.png](../../images/NE-275-20261118/left-maul-smash.png)
- [left-maul-slam.png](../../images/NE-275-20261118/left-maul-slam.png)
- [left-maul-crush.png](../../images/NE-275-20261118/left-maul-crush.png)
- [left-maul-quake.png](../../images/NE-275-20261118/left-maul-quake.png)
- [left-whip-lash.png](../../images/NE-275-20261118/left-whip-lash.png)
- [left-whip-return_lash.png](../../images/NE-275-20261118/left-whip-return_lash.png)
- [left-whip-orbit.png](../../images/NE-275-20261118/left-whip-orbit.png)

封包：58635574 bytes、745 ZIP members、2 段。
