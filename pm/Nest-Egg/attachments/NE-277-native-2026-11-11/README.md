# NE-277：原生連續動作、握位與接地交接

這份附件保存實際執行的來源、逐物理步觀察、原始日誌與影像。ZIP 直接複製原始位元組，避免 Git 換行正規化改掉日誌、JSON 或當時使用的來源；大小與 SHA256 見 [archive-index.json](archive-index.json)。

## 實際發現與修正

- 戟的前手兩側是互不相連的後手可握區。原本逐格挑最近肩膀的解，會讓後手瞬間換邊。雙手招式現在可宣告握桿側，在真正可達區間內沿上次接受的握位滑動，收招後保持連續。
- 長刀蓄力轉前衝、前衝轉待機時，低權重走跑直接取代待機接地，卻混回未接地的腿角。現在先混合兩組腳部目標，再一次求解；原長刀踏步 14、前衝、時間、傷害和距離保持。
- 匕首第一刺屬 LIGHT，不會使敵人畏縮或暈眩；原本只停主角。第一個真正造成傷害的接觸現在同步暫停雙方，保留原反應分級。後續接觸不再重凍攻擊者。
- 舊接點稽核會放過零影格、缺指標與超標，並重複放寬角度倍率。現在拒絕這些情況，沿用原門檻；獨立讀取器另從原始骨角重算單步角度。

## 已執行的 CPU 證據

| 原始封包 | 實際結果 |
|---|---|
| [cpu-motion-final.zip](cpu-motion-final.zip) | 原長刀踏步 14；五武器雙向 42 列、2,590 物理步，524 檢查／0 失敗，exit 0，無 ERROR／SCRIPT ERROR／退出洩漏 |
| [cpu-gait-final.zip](cpu-gait-final.zip) | 正反向、待機／走跑／待機及原強度踏步，共 8 列、720 固定步；4 正常接受、4 故意丟失待機接地目標均拒絕；獨立骨角／腳位重算通過 |
| [cpu-locomotion-final.zip](cpu-locomotion-final.zip) | 正式 LocomotionSuite 125 檢查／0 失敗；包含既有走跑、其他接地角色及新增交接與負控制；無引擎錯誤／退出洩漏 |
| [cpu-feedback-final.zip](cpu-feedback-final.zip) | 36 個實際命中案例，324 檢查／0 失敗；原 LIGHT／畏縮／暈眩分級及首格雙方停頓、實際聲層事件與設定讀回通過 |
| [python-verifier-final.zip](python-verifier-final.zip) | 10 個 Python 測試方法及其缺欄、假成功、缺輸入、假減動態、角度跳動、缺格、非有限值、鞭節點裁切等子案例通過 |

正常交接控制的腿／腳最大單步變化 0.493 rad，腳支點下穿上限 0.000003 px；故意壞交接可達 2.086 rad／6.091 px。此處只量腳支點，不能代替鞋底材質接地。42 列中原有角度、網格翻面與變窄門檻保持；最大變窄為錘的 0.7443，原上限 0.75。

封包中的引擎檢查數與原來源保持。整理時另外發現舊清單漏了膝反折判定；原觀察已逐格量到膝反折與腳位，所以用新版讀取器重驗全部 42 列 CPU 及五武器原生資料，八項指標、原膝反折 0.1 門檻與接地腳位均通過。[離線重驗收據](offline-motion-recheck.json) 記錄原 ZIP 和新讀取器 SHA；這不冒稱舊輪當時已使用新清單或重新執行引擎。

正式受影響測試另由 NE-284 的隔離候選執行：70 組、71,186 檢查、0 新失敗／0 已知失敗、exit 0，無 SCRIPT ERROR。原白名單允許的退出診斷保留：shard 1 有 9 ObjectDB／5 resources，shard 2 有 6 AreaRID／16 ObjectDB／8 resources，不能寫成 0 ERROR／0 洩漏。原始命令、20 份固定候選來源、4 份日誌與過濾器均在 [affected-green-raw.zip](../NE-284-process-phase-2026-11-11/affected-green-raw.zip)（SHA256 `1cda969cef40e4e8ab3504f9aca00fd0458457bb5fba5d74721687533ff62124`）；其中本票 10 份產品／測試來源與 [final-runtime.json](final-runtime.json) 完全一致。原 71,186／1 滴水測試時序失敗的收據由該票保留；此綠輪不包含 NE-267。

## 新固定來源的原生逐格矩陣

RX 9070 XT、Godot 4.7.2、Vulkan Forward+、1280×720。每一個觀察物理步各存完整角色／武器裁切與手部裁切，另存每招第一格的完整視窗；全部保持原生像素，不縮放。程序前後來源／素材 SHA 必須完全一致，任何引擎 ERROR 或退出洩漏都拒絕。

| 封包 | 連續列／步 | PNG | 檢查 |
|---|---:|---:|---:|
| [native-blade-final.zip](native-blade-final.zip) | 10／530 | 1,070 | 1,724／0 失敗 |
| [native-dagger-final.zip](native-dagger-final.zip) | 10／320 | 650 | 1,104／0 失敗 |
| [native-glaive-final.zip](native-glaive-final.zip) | 8／510 | 1,028 | 1,646／0 失敗 |
| [native-maul-final.zip](native-maul-final.zip) | 8／808 | 1,624 | 2,540／0 失敗 |
| [native-whip-final.zip](native-whip-final.zip) | 6／422 | 850 | 1,354／0 失敗 |

合計 42 列、2,590 步、5,222 PNG、8,368 檢查。每一輪嚴格工具接受其有限檢查，均無 ERROR／SCRIPT ERROR／退出洩漏；這不等於所有視覺條件通過。鞭身使用真正世界節點，20 個節點皆在每格裁切內；保持原倍率 2，固定鏡頭上偏 48 世界單位並明確發布實際視圖，以容納完整頭頂弧線與原 8 世界單位留白。

長刀兩向各查看第 40→41 與 53→54 格。右向相同轉折與原踏步 14 的修前原生圖並排：[進入前衝](../../images/NE-277-grounded-entry-before-after.png)、[回到待機](../../images/NE-277-grounded-exit-before-after.png)。只比較姿勢與接地，未固定的自然雨相位不作像素差值結論。

戟的舊後手換邊與新連續握位見 [第 5→6 格手部原生對照](../../images/NE-277-shaft-grip-before-after.png)。另查看其最大角度變化附近的手部格，以及錘下砸、匕首連刺、鞭頭頂弧線與持續甩動的原尺寸裁切；不宣稱已人工逐張檢視全部 5,222 圖或全部接點像素零缺口。

## 首傷格視覺時序：本輪未通過

[native-feedback-final.zip](native-feedback-final.zip) 的 36 個接觸案例、362 項檢查、真實傷害、首個觀察格雙方停頓與解析後低／高聲層均通過；原生首傷格仍重現 [錘頭在上方](../../images/NE-277-first-hit-maul-unverified.png)、[鞭梢遠在目標上方](../../images/NE-277-first-hit-whip-unverified.png) 時，敵人已出現傷害特效。這是可見武器與實際命中時序的產品缺口，不歸類為真人偏好，相關驗收保留未勾。原因需對照真實物理更新、可見姿勢、延後停頓與呈現次序，不能只用傷害事件的 phase 推定姿勢已更新。

此矩陣明示安排第一／最後連段招、正式 9,999 HP 靜止 grunt、停用其啟用範圍裁切；共 9 招 × 兩向 × 正常／減少設定，並非所有按住／延伸招的自然對戰。固定構圖停掉鏡頭跟隨，因此震動驗的是事件門限與設定讀回，不能冒充真實鏡頭位移驗收。正常 18 案例共有 30 個震動事件，減少組 18 案例為 0。

## 原始混音與切片

[完整原始 WAV](audio/master.wav)：48,000 Hz、雙聲道、16-bit PCM、46.517333 秒。36 個切片逐一與原 PCM 對應 byte 區間獨立比對一致，沒有重採樣或增益處理；全部切片、波形、報告與切片程式在 [audio-derived.zip](audio-derived.zip)，原始 master 也原封存於命中 raw ZIP。

五個可直接播放的正常模式片段：[長刀](audio/blade-1-cut_3-reduced-false.wav)、[匕首 LIGHT](audio/dagger-1-stab_1-reduced-false.wav)、[戰戟](audio/glaive-1-sweep-reduced-false.wav)、[錘](audio/maul-1-smash-reduced-false.wav)、[鞭](audio/whip-1-lash-reduced-false.wav)。[混音波形](waveforms.png) 與 [音訊報告](audio-report.json) 只描述實際錄音，不能代替真人試聽或分層響度判斷。[36 個首傷格縮圖](../../images/NE-277-hit-overview.png) 只作索引；原 1280×720 圖在命中 raw ZIP。

## 必須保留的失敗與中間版本

| 封包 | 判定與來源界線 |
|---|---|
| [before-glaive-native.zip](before-glaive-native.zip) | RX 9070 XT／Forward+；原握位缺陷，8 列、414 步、836 PNG，8 個角度超標。當時只保留有限來源快照，不宣稱完整輸入清單；後來只封裝原始 bytes。 |
| [before-blade-native.zip](before-blade-native.zip) | 原踏步 14 的右向 5 列，蓄力衝刺斬第 40→41 格膝部突變；原日誌亦有退出資源警告。保留為失敗，不能稱乾淨通過。 |
| [intermediate-glaive-pre-lf.zip](intermediate-glaive-pre-lf.zip) | 戟握位候選的 1,028 張原生 PNG；在 JSON 換行正規化與 LIGHT 接觸修正之前，不是最終 staged bytes。 |
| [intermediate-blade-step8.zip](intermediate-blade-step8.zip) | LF 候選，10 列數值通過且日誌乾淨；實看膝部仍跳、腳部下穿，視覺退件。不能用其數字代稱修好。 |
| [history-reports.zip](history-reports.zip) | 歷次原始報告、日誌與當時已有的來源快照；包含無起手、壞姿勢、未真按住、安排靶未啟用、聲音事件／leaf 誤判、Ogg 退出警告、未交付 Story 缺檔、失敗的交接候選及錯誤還原招式資料。未含全部歷史 PNG／WAV；不當最終驗收。 |
| [line-ending-originals.zip](line-ending-originals.zip)／[line-ending-receipt.json](line-ending-receipt.json) | 原 CRLF bytes 與正規化前後 SHA。熱能長刀最終已恢復 HEAD 原 LF bytes，原 SHA256 為 8ac6a971b4dffde7ce40ffbdf6f4b1d17d2d1a0a2b648a02e2cee871c6134aaf。 |
| [invalid-whip-local-space.zip](invalid-whip-local-space.zip) | 把 draw-local 快取當世界節點的工具錯誤，422 格均被完整裁切守門拒絕。 |
| [invalid-whip-world-margin.zip](invalid-whip-world-margin.zip) | 世界座標修正後，只剩 2 格頭頂留白越框；不降低留白或全包含條件。 |
| [invalid-whip-stale-camera.zip](invalid-whip-stale-camera.zip) | 相機節點請求位置改了，但原 smoothing 視圖未發布，實際節點螢幕位置與前輪相同，仍拒絕同 2 格；修後明確停 smoothing／reset／發布實際視圖。 |

## 解讀界線

- 個別招式明示安排起手及指定資料；按住段另走真正公開按住／放開，從第一招自然進入。不是真人完整連段或實體手把驗收。
- 固定步運動學控制、無頭 Player 執行、實際 Forward+ 影像各自判斷。數值、PNG 幾何與選格目視不能代稱全部零件每格像素零缺口。
- 世界震動倍率、鏡頭脈衝與減閃光分別設定；「減少介面動態」本身不代表世界震動關閉。
- 命中錄音是實際主匯流排混音，含環境音、音樂及既有共用受擊音；切片不改增益，不作獨立聲層響度或真人試聽結論。
- 有其他專案 GPU 工作負載，不宣稱全機空閒，也不以全引擎監視器證明近戰模組成本。
- 最終固定來源見 [final-runtime.json](final-runtime.json)，逐輪摘要見 [native-summary.json](native-summary.json)。使用者辨識、真人試聽、實體操作、完整接點像素及有效成本對照均不由此附件代勾；首傷格可見武器未到位亦維持未通過。
