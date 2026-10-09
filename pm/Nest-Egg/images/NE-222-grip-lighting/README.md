# NE-222：雙手可達範圍與凜部件明暗

本批只交付共用握點求解與凜五個遠側部件取消額外壓暗。新跪姿臀部、手指外觀、全部接縫與完整動作驗收仍未通過。使用者退件原圖在上一層的 `NE-222-user-kneel-anatomy-lighting.png` 及 `NE-222-user-posterior-part.png`。

## 握點與回歸

五組實際敵人／武器：trooper_elite/rifle、flamer/flamethrower、grenadier/launcher、sniper/sniper、stalker/rifle。原先只有非零掌心偏移的角色會進入雙手共同可達範圍計算；零偏移角色的後手會被IK夾限而離開武器。現在沿用同一求解器，雙手武器包含這些舊角色，缺骨鏈仍安全略過。

原失敗重現記錄在 [regression-before.log](logs/regression-before.log)。當時速度採實際巡邏／滿速，但兩種輸入都以自身速度當跑步上限；此重現證明舊握點失敗，不作巡邏步態驗收。最後回歸已改為兩種取樣共用實際敵人的滿速上限，與遊戲的巡邏／跑步分支一致。最後受影響測試日誌包含修正後的20種面向／速度組合。

兩面向各60格，前後手握點容差維持0.025世界像素，每格檢查兩條手臂骨長。保留凜非零掌心偏移、空手、單手手槍、護盾與真正NPC分支控制。零偏移角色的量測點是手部支點，沒有推定圖上的掌指表面接觸。

## 原生畫面

Godot 4.7.2、Forward+、HDR 2D、NVIDIA GeForce RTX 4070 SUPER；ComfyUI停止，原生作業使用共享GPU鎖。

- `enemies-before/` 與 `enemies-after/` 各五張原生2240×1080。每张四行依序右走、左走、右跑、左跑，每行八相位，倍率3.4；同一資料、光源、腳本與硬體，before僅換成保留的歷史握點方法。每個畫面為隔離步態檢查，不能替代實際戰鬥、八動作或全部接縫。
- `controlled/` 共十張原生1536×1216：兩面向baseline及八種明暗對照。倍率23.78，刻意只檢查頭、雙手、袖子及可見武器，腳不在此取景範圍，不計全身驗收。單一持續存在的rig、HDR viewport、LightKit及白光；保留正式diffuse、CanvasTexture法線、glow與材質。原baseline的五件都是0.62，三件組比較0.62／0.9／1.0，另有五件全部1.0控制。
- `arena-before/` 與 `arena-after/` 各三張原生1280×720；沿用正式 `rin_light` 情境的玩家、關卡及轉運站／停電／霓虹市集光照，不加入診斷補光。before僅在記憶體恢復五件0.62。天氣、呼吸和眨眼隨實際程序播放，兩次不同時刻，不將全圖RGB差分當成tint效果。

受控對照有8/8同姿勢檢查通過，未變動區域的取樣RGB一致，未增加黑色像素，後手掌心握點最大殘差約0.000069世界像素。[控制組報告](controlled-review.md)及[原始數據](controlled-summary.json)仍明確排除手指形狀、跪姿、臀部與接縫驗收。早期「身體變黑」的判讀已由raw PNG核對更正，不再當成材質失敗。

原生步態與受控明暗日誌無SCRIPT ERROR。正式arena after在退出時有16個ObjectDB實例與4個resources still in use訊息，完整保留在 [日誌](logs/ne222-current-light-native.log)；不宣稱該次輸出零ERROR，亦不將退出清理訊息視為已完成實機品質驗收。

## 可重跑匯出與效能

[匯出報告](export/report.json)：同一rin2精修來源、12個既有overrides，baseline spec取4a754af0，after取本批修改。兩次各30張PNG（含3張glow）逐位元組一致；20骨、27項texture metadata、30項部件用途、支點與兩個grip_offset不變，只有五項tint變動。155個來源／正式檔案前後hash一致。cut_layers不產生法線，本次沒有重建normal，不把零normal輸出誤寫成法線生成通過。

[效能資料](perf/results.json)：每皮膚10演員、120格暖機、3000固定格、三次交替before/after，無並行Godot或ComfyUI生成。只量headless動畫CPU，非渲染FPS。每演員每格中位數：

| 皮膚 | 修前µs | 修後µs | 差異 | 頂點 |
|---|---:|---:|---:|---:|
| trooper_elite | 156.429 | 165.057 | +5.52% | 276 |
| flamer | 154.160 | 158.630 | +2.90% | 300 |
| grenadier | 156.103 | 168.419 | +7.89% | 258 |
| sniper | 156.025 | 161.174 | +3.30% | 228 |
| stalker | 154.247 | 157.377 | +2.03% | 222 |

30個效能樣本的修前握點失敗、修後近零及相同骨／網格／頂點檢查通過；無SCRIPT ERROR或ERROR。這不是NE-222所有角色的總體效能驗收。

## 重現與追溯

原生after：`gpu_lock.py -- godot --path . --rendering-method forward_plus res://tools/humanoid_scope_audit.tscn -- --config=<enemies-after/config.json> --out=<新目錄>`。

關卡光照after：`gpu_lock.py -- godot --path . --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=rin_light --out=<新目錄>`。`arena-baseline.gd.txt`保留只在記憶體改五個tint的修前情境，恢復成private .gd及相應.tscn即可重跑；不覆蓋正式素材。

受控對照的原執行源為 `controlled-capture.gd.txt`，當時使用五件0.62的baseline資料；在本批之後重跑須先在記憶體恢復那五件baseline。原生manifest保留當時原路徑，不偽裝成重新擷取。效能的private歷史方法與探針保存為txt，原相對目錄及命令在 `perf/command.txt`，還原private .gd/.tscn再執行。正式角色製作流程不需要這些一次性診斷工具。

所有PNG保持原擷取尺寸，未插值放大、修圖或以來源圖冒充遊戲截圖。文字證據統一LF換行以便Git跨平台保存，內容與錯誤訊息不刪改；來源帳本中的hash描述當次Windows工作檔，交付檔的hash另列manifest。完整檔案SHA256與各次實際測試組數在 `manifest.json`。完整測試由CI執行。
