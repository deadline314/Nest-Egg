# 次級動態的生命週期重設

## 行為

既有動畫器會處理翻面與超過48像素的瞬移，但同一位置重生、正式過場進入／取消／完成、地圖閱讀進出與回看結束沒有接到它。現在由真正Player／Story入口呼叫原重設，不把一般氣泡或普通通訊當成過場；離開節點時解除訂閱。回看不發正式scene_started／finished，因此另外使用真正replay_finished。

本次沒有改彈簧模型、幅度、速度門檻、30／60子步長、骨長或原有擺動素材；主角胸口、袖口及完整動態外觀條件仍依票的未勾項驗收。

## 證據

| 範圍 | 結果 |
|---|---|
| 正確負控制 | 原產品2623檢查、7個預期失敗；同位置重生、舞台進／取消／完成、閱讀進／出、回看出全部抓到 |
| 修後專項 | ProtagonistMotion／Npc／DeathFlow／UiScreens，共4056檢查、0新／已知，100秒 |
| 原選擇器 | 固定base ed6c40a7，19組、42590檢查、0新／已知，475秒；0腳本錯誤 |
| 同版原生觀察 | 舊產品18檢查7失敗；修後18檢查0失敗，七邊界角速度與對靜止角的偏差全歸零；普通通訊原狀保持 |

原生圖由相同測試方法的觀察子類讀取真正動畫器資料，在Godot4.7.2軟體Forward+畫出；不是預先填值，不是人眼／實體裝置或自然起停影片。兩圖共用0–0.25rad/s比例尺，raw JSON保留每根彈簧。測試用固定45格跑步建立動量；後續各列的起始數值會受前次重設歷史影響，不能拿不同列或不同圖的before大小推斷動作品質。

完成案例走真正可略過場景的正常收尾訊號；等待實際Story結束後，以實際完成取得回看資格，再使用真正replay與stop_replay。沒有手填completed／seen或使用假的Story owner。這是安排好的機制fixture，不是從序章正式路線通關，也沒有把它當成胸口／袖口與全動作的圖像驗收。

## 保留的失敗與限制

最初的測試只等2格便查回看資格，早於實際收尾；地圖閱讀還因玩家面向和跑步準備不同，誤撞到原有翻面重設，掩蓋缺口。舊測試2620檢查5失敗（4個產品缺口與1個過早查資格）原樣保留，精確來源SHA可核對。修正只固定同一面向、等實際owner收尾，原靜止角與角速度斷言不改；正確負控制完整得到7失敗。沒有放寬舊門檻或加known failure。

原生v1數值有效，但兩張圖各自縮放，會讓相同初始速度有不同圖寬；v2重新原生擷取，共用比例尺，v1未刪。19組log含刻意壞資料的ERROR與退出資源／物理RID釋放訊息，完整[錯誤清單](engine-errors.json)保留，不宣稱全輸出0ERROR；原生before/after則無ERROR／SCRIPT ERROR。

19組於ed6c40a7的候選跑完，後續rebase只帶入NE-218來源匯入整理，產品／測試SHA相同，原生v2在最新8655900f後執行。之前音效工作目錄的匯入快取曾和診斷控制硬連結；編輯器匯入前先將6865個快取檔私有化，逐檔內容保持。來源PNG硬連結仍只讀，不修改其他worktree。

## 來源與重跑

先讀User-guide與[五款同類遊戲實際圖片](../../../../design/08-lighting/READABILITY_REFERENCES.md)；技術依據另讀[Unity ClearTransformMotion](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/cloth/cleartransformmotion)、[Unreal ResetDynamics](https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Animation/Dynamics/ResetDynamics)及[KawaiiPhysics FAQ](https://pafuhana1213.github.io/KawaiiPhysics-Portal/en/docs/faq)，只借生命週期分開處理的原則，沒有引入其求解器。詳細[來源與採用理由](references.json)。

- 原範圍：`GODOT=<官方4.7.2> SHARDS=4 tools/run_tests_changed.sh ed6c40a7`；最新main單獨重驗可用原選擇器對該票base。
- 原生：暫存checkout8655900f、正常editor import，將[replay](replay)的測試放回`tests/suite/test_protagonist_motion.gd`、三個probe檔放`work/`。before／after分別使用保存的PlayerVisual，執行 `<Godot> --path <checkout> res://work/lifecycle_probe.tscn -- --out=<絕對目錄> --label=<標示>`。before應退出7、after退出0；各自Source SHA在JSON。操作只在自己的暫存checkout，結束恢復after，不修改使用中的main。

[raw.zip](raw.zip)／[逐檔SHA](manifest.json)／[實際來源](source.json)。完整失敗、兩版圖與逐格數值保留。
