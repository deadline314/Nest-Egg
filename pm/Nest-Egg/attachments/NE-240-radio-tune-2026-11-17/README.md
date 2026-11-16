# NE-240：正式收音機調頻手部演出

2026-11-17，Godot 4.7.2，AMD Radeon RX 9070 XT，原生 Vulkan / Forward+。
本次只交付第二章當舖既有修理支線的一個情境：玩家選好三個接點，再讓真實主角握收音機旋鈕調頻。
錯誤刻線會轉動、短回彈並返回原雜訊提示；正確刻線轉完、放手、起身，再接原廣播與原選擇。
未生成素材、修改骨架、拉長手臂或替換角色；低旋鈕使用既有蹲姿。原入口提示與選項 hover 繼續說明調頻、離開、保存片段的結果。

## 驗證結果

| 範圍 | 結果 |
|---|---|
| 正式來源重新編譯 | 190 場景、10 任務，成功；只新增兩個 world_action 步驟 |
| Python 故事契約 | 19 / 19 |
| Chapter2StorySuite（局部） | 266 / 266，無 SCRIPT ERROR；刻意物件遺失、來源離場與寫入拒絕警告保留 |
| 原生修前 | 9 PASS，0 FAIL；同一 NPC / edge → middle → off，沒有手部動作 |
| 原生修後（階段畫面） | 11 PASS，0 FAIL；轉錯與調對各階段出現 |
| 原生最終連續 | 12 PASS，0 FAIL；194 幀紀錄，65 幀 turn / recoil，掌心誤差最高 0.0001258272 世界 px（既有容許 0.25） |
| 原生最終輸出 | 45 張原始全畫面 PNG，無引擎 ERROR、SCRIPT ERROR 或洩漏輸出 |
| 封存遷移資料 | 141463 bytes；SHA-256 `e86b82e0a7e5d9f6988290cb7b61eb55f7459849901771d6bc95848acf93a8c8`，原樣保留 |

正式 affected 在1fb788dfc基準的獨立工作樹，只複製本票精確來源：44組、54,690 checks，0新失敗、0已知失敗、退出0、1124秒。14份快照來源均與最終來源bytes相同；不含其他未提交音訊UI或新角色。原生取樣工具另由native程序驗證。原始故障fixture與resources-at-exit診斷完整保留，沒有宣稱整份遊戲回歸log零ERROR。詳見official-result.json與official三份log。

## 畫面與連續性

- [修前／修後](../../images/NE-240-radio-before-after.png)：左側是原廣播選擇，右側是新增調頻接觸；不是同一時間點的畫素差分。
- [10 fps 連續畫面](../../images/NE-240-radio-continuous.jpg)：逐六個原生幀，依序接近、蹲下伸手、轉動、回彈、鬆手起身，再次正確調頻。approach 用全畫面；其他圖只裁切接觸區並加影格／階段標籤。
- `before/`、`after/`、`continuous-final/` 保留完整未加工畫面。`continuous-final/frames.json` 是每個觀察幀的階段、蹲姿輸入、手部輸入、真實掌心、骨頭原點與角色位置。
- 足部欄位是骨頭原點，不是鞋底接觸線，不能將骨頭 y 直接當作鞋底高度。接近時鏡頭也在移動；沒有把裁切畫面的像素位置當作世界座標。
- 194 幀有逐幀資料，32 張每六幀截圖；其餘 13 張是階段、選項與恢復遊玩畫面。數值只核對 turn / recoil 實際接觸，沒有拿 reach 過渡的當下誤差代替接觸驗收。

## 真實中斷、保存與原版對照

CPU 測試建立真實當舖 Level、真實 `ch2_radio` NPC，透過原 power / antenna / speaker / middle / save 選項推進；不直接呼叫故事結果提交。Main 的 `_ready` 在測試 host 略過選單啟動，但使用原故事保存 owner、Main 場景保存回呼、真實 RunSaveStore 及驗證器。

取消、互動道具刪除、死亡、NPC 來源離場、略過後選離開：動作期間不發修好旗標、錄音片段或 20 元；結束釋放手部與蹲姿，武器配置逐位元相同，活人恢復原武器、死亡者不重新亮武器。靜態旋鈕可省略 reaction；明確宣告不存在的 reaction 以及借用另一個來源 NPC 都在真實 active request 拒絕。

本支線原本是 sealed legacy route，**不是原子故事提交**。原版對照是在同一候選 runtime 中，僅移除所選路線唯一新增的廣播前視覺步驟，透過同一 NPC、選項、Main 保存回呼與真實磁碟 writer 重跑；沒有改封存契約或偽造歷史 checkout。兩版結果相同：

- 在此專屬 slot 的 `.tmp` 路徑建立目錄，實際拒絕普通 autosave。兩版結束後都是 live 修好、持有片段、增加 20 元，但磁碟原 bytes 不變、pending `{}`、cinematic 空、autosave queued `false`、無原子重試 prompt。這是既有保存語義，不能稱為「保存成功才發結果」。
- 移除自己建立的目錄後，呼叫原 Main 普通保存；新 reader 的旗標、物品、交易收據、pending、cinematic 與 autosave 狀態兩版完全相同。再從該 snapshot 載入，修好與片段均保留，回訪不重領 20 元。
- `ne240-radio-unit-final3.log` 保留 `RADIO_LEGACY_REFUSED` / `RADIO_LEGACY_SAVED` 的完整兩版對照值。

編譯器及 Godot 兩側都把 world_action 視為與既有 reach / prop 同類的 stage-only 呈現步驟；沒有加入 PURE_STEPS。兩側回歸仍拒絕場景旗標、物品結果、then、選項旗標與選項流向的額外改動；action ID / overlay / scene 由既有 CutsceneChecker 及 WorldPropAction 檢查，真實來源仍在 start 時核對。

## 歷史錯誤保留

- `ne240-radio-compiler-initial.log`：尚未同步 stage-only 投影前，原 sealed migration 正確拒絕新步驟；final 編譯成功，封存檔完全沒改。
- `ne240-radio-unit.log`：新 helper 誤用未註冊的類別名而 parse error。該輪即使末尾顯示 172 / 0 也不算通過；改為 preload 後才進入有效回歸。
- `ne240-radio-unit-final.log`：250 項、3 失敗，抓到「原支線已由 atomic owner 保存」的錯誤測試推定。沒有刪除記錄；後續改驗真正既有 legacy 語義，`final2` 264 / 0、最終 `final3` 266 / 0。
- `ne240-radio-native-continuous.log`：首次連續原生接觸檢查通過，但採樣 coroutine 在 teardown 後醒來碰已釋放的 Level，產生 SCRIPT ERROR，此輪不算最終通過。工具補 await 後存活檢查，`continuous-final` 自然結束、0 ERROR。

## 重現

```powershell
$env:PYTHONUTF8='1'
python tools/story/build_ch2_story.py
python -m unittest discover -s tools/story -p test_story_contracts.py
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn -- --only=Chapter2StorySuite
python tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method forward_plus --rendering-driver vulkan --fixed-fps 60 res://tools/radio_tune_probe.tscn -- --expect-action --out=C:/NE-radio-native
```

測試及原生執行使用各自獨立的 APPDATA / LOCALAPPDATA 目錄；上方重現亦應先指定自己的測試資料目錄，避免影響個人進度。
`verification.json` 是摘要，`source-hashes.json` 固定本次來源；`python pm/Nest-Egg/attachments/NE-240-radio-tune-2026-11-17/verify_evidence.py` 可唯讀重算影格／接觸／原圖數、兩版保存對照及來源 SHA。接觸重算篩 phase 為 turn 或 recoil，計數並對 error 取 max。截圖不取代實體手把、鍵鼠或完整章節遊測；票維持進行中。

## Git換行與原件

source-hashes.json保留實際測試／原生執行時13份來源的原bytes指紋，原件另存raw-source/。Git依既有規範將產品文字轉為LF；git-source-hashes.json只作CRLF→LF映射，不改任何其他位元組。唯讀重算同時驗原件SHA、正規化映射與當前產品，不能把換行差異稱為完全相同bytes；沒有重新生成原生圖片。附件設為raw，保存PNG、原log及來源bytes。
