# 人形敵人立繪與步態審查

2026-10-10；基準 `24bac9f1dc509a6c800ea09ae1c4e9f8b5d6ece7`。本次是 NE-90 的分工審查證據，沒有修改角色定稿、分件、骨架、動作或遊戲程式，也沒有把 NE-90 改成完成。

提交前已 fetch 並整合到 `e1d3507a`；與量測基準相比，本組角色、骨架、動作、敵人資料和分件工具沒有變更，因此保留本次實測證據。

## 覆蓋

以 `data/enemies/**/*.tres` 的實際 `rig_skin`、`rig_weapon` 與 `Enemy._build_rig` 載入契約盤點，沒有只看資料夾名稱。

| 外觀 | 實際敵人 | 武器 |
|---|---|---|
| trooper | grunt、sweeper、strike/chainsaw_arm | smg、pistol、空手 |
| trooper_elite | elite_grunt | rifle |
| grenadier | mortar | launcher |
| sniper | sniper | sniper |
| slasher | slasher | 空手 |
| stalker | stalker、strike/plasma_whip | rifle、空手 |
| flamer | flamer | flamethrower |
| reclaimer | reclaimer | 空手 |

共 8 個外觀、11 個敵人、11 組外觀／武器模式。Rin、NPC、enforcer、heavy_gunner、warden 與非人形敵人由其他分工負責，這份報告不給它們通過。

`asset-ledger.json` 包含全部敵人映射（含排除項）、本組每張原圖與實際貼圖的尺寸／RGBA／alpha／SHA-256、各貼圖支點、近遠側 slot、骨架父子鏈、配方與動作資料。它保存目前配方內容；沒有從缺失的 manifest 欄位推造原始模型／seed 紀錄。

## 通過的檢查

| 檢查 | 實際結果 | 可證明的範圍 |
|---|---|---|
| 8 組 check_spec，含 joints | 0 errors、0 warnings | 配方與規格的資料檢查 |
| 8 組 check_parts，含 normals | 0 warnings | 現有工具的空圖、孔洞、游離片、遠離支點、發光與法線檢查 |
| 原生 Forward+ 擷取 | 11 張 2240×1080 PNG，退出碼 0，無腳本錯誤 | 每組左右面向、巡邏速度／滿速、各 8 個相位，3.4 倍審查倍率 |
| 步態資料取樣 | 44 組 × 360 格＝15,840 格 | 11 模式 × 左右 × 兩種速度，先待機 1 秒、移動暖機 3 秒，再量 6 秒 |
| 骨盆起伏 | 44/44 不超過 0.09 L | 專案既有敵人移動門檻 |
| 踩地滑步 | 44/44 不超過 0.03 L，雙腳都有接地樣本 | 骨架脚支點的世界位置；不能替代腳底材質的接地驗收 |
| 動作時骨長 | 44/44 最大變化 0 | 雙臂及雙腿的 8 段骨頭 |

原生擷取使用 Godot 4.7.2、Vulkan 1.4.356、Forward+、Intel Arc B580。擷取是由 SubViewport 原生渲染，沒有把較小的圖片放大。每張圖依序四列：右走、左走、右跑、左跑；列內 p0～p7。速度使用遊戲敵人的 `move_speed` 和 `max(40, move_speed × 2)`。這是審查舞台，不冒充真實關卡或人工試玩。

巡邏／滿速的幾何數字一致，仍不能給美術通過。下列問題在原尺寸單件圖與 Forward+ 圖實際看得到。

## 失敗與修復交接

### 1. 精銳保全的大腿主材質缺失

`trooper_elite/parts/leg_upper.png` 的 136×238 原尺寸圖中，上半大腿有效 alpha 只剩左側細條，下面连着褲袋與膝部塊。回到分件來源的原圖座標 `(325,593)～(443,854)`，用真正 alpha 合成深灰底後也看得到這個缺失；底部是膝部形狀，不能因外形像鞋就誤記為鞋。這份不完整材質掛在近、遠側大腿上，跑起來的腿輪廓像數個護甲塊重疊並折成尖角。這不是單純把骨頭換位置就能驗收的問題。

證據：`../../images/NE-90-humanoid-subagent/trooper_elite-parts-native.png`、`trooper_elite-upper-source-alpha.png`、`trooper_elite-rifle-gait.png`、`trooper_elite-rifle-p2-native-detail.png`。其餘檔案在同一 images 目錄；p2 是第一列第 3 格原尺寸裁切，沒有縮放。

建議最小修復：核對原圖、近腿遮罩與裸甲底層的來源歸屬，重新限制單一大腿的材質；不要刪掉整段腿或用漸層塊掩蓋。重新切割才同步生成貼圖尺寸／支點／法線，再驗兩面向與實際腿部动作。NE-90 已包含分割問題，無需重開同需求票。

### 2. 迷彩獵手前臂含完整手及衣片

`stalker/parts/arm_lower.png` 的原尺寸圖包含完整向下的手指與前臂左側三角布片；同時 `hand_front`、`hand_back` 又各掛了独立手圖。空手步態可看到布片跟前臂甩；持槍时手腕／握槍輪廓重疊。check_parts 沒有報錯，因為這些錯切内容仍連在主圖上。

證據：`stalker-parts-native.png`、`stalker-unarmed-gait.png`、`stalker-rifle-gait.png`、`stalker-rifle-p2-native-detail.png`。

建議最小修復：把來源手只分給手 slot，前臂僅保留前臂及正確腕接頭；三角布片回到实际衣物歸屬。先核對原圖與遮罩，不生成新的整張角色。重驗兩手、空手／rifle 與兩面向。屬 NE-90 原有範圍。

### 3. 切割者空手的手與前臂分離

slasher 的左右走／跑各相位都有黑色手形零件飄在前臂外；第一列 p2 的右手與前臂之間可直接看到背景。它的刀臂設計問題也已在 NE-90 原文與 Commit-1 保留，本次沒有把程式刀刃當作完整刀臂驗收。

證據：`slasher-unarmed-gait.png`、`slasher-unarmed-p2-native-detail.png`、`slasher-parts-native.png`。

建議最小修復：先以原圖手腕材質中心核對 spec 的 wrist 與手／前臂切線，修正来源分割、支點與必要底層；保留人物定稿。手要連著前臂後，才驗近戰刀臂与實際動作。屬 NE-90 原有範圍。

### 4. 保全的膝旁仍有手形尖角／碎片

trooper 的 smg、pistol、空手模式中，在第一列 p2、p3 与跑步的相應相位，抬腿側膝附近出現黑色手形尖角。左右方向均重現。近腿來源仍有原手遮擋區的輪廓；單件檢查沒有辨識出語意錯切。不能只用「碎布已消失」的舊 Commit 結論覆蓋這次畫面。

證據：`trooper-smg-p2-native-detail.png`、三組 `trooper-*-gait.png`、`trooper-parts-native.png`。

建議最小修復：對照近腿來源與補全遮罩，分清是殘留手形材質还是網格折片，修正确来源後按同一相位重拍。不要直接把所有深色像素當背景刪掉。屬 NE-90 原有範圍。

### 5. 五組雙手武器有握點超出手臂可達範圍

依実際武器 Sprite 的 grip／foregrip 世界位置，量前／後 HandBone 的掌心位置（包含 hand_grip_offset），再除掉角色整体倍率。下列最大距離不是截圖座標誤差；每組左右結果一致，骨長沒有被拉長。

| 外觀／武器 | 巡邏最大距離，世界 px | 滿速最大距離，世界 px |
|---|---:|---:|
| trooper_elite／rifle | 2.958 | 2.923 |
| flamer／flamethrower | 1.514 | 1.498 |
| grenadier／launcher | 2.114 | 2.088 |
| sniper／sniper | 4.363 | 4.284 |
| stalker／rifle | 2.298 | 2.263 |

現行共同可達範圍修正僅在前手有非零 hand_grip_offset 时啟用；這些舊角色仍走固定 reach，再各別夾限 IK。換成同一支 rifle 也不能代表其他角色的臂長合格。

建議最小修復：由共用骨架分工評估讓舊手部資料也能求兩手共同可達的武器位置，保留固定骨長、材質握點、槍口與射擊判定，回歸以上全部外觀／武器。零件手圖錯切与這項 IK 缺陷是不同問題，不能互相代替。共用接點／握持需求已在 NE-222，這份報告交接给該分工；不另改共用程式。

## 未驗證，不列入通過

- 八種戰鬥動作、全部專屬招式、完整状态切換、傷害脫甲与死亡的全彩逐格檢查。
- 所有接點隔離透明底的逐格零缺口／零孔洞檢查；本次 8 相位全身圖不能替代它。
- 真實章節／過場的光照、曝光、敵人行為、手感與輸入响应。
- 原圖每隻手指解剖與所有被遮住底層的完整批准；本次原圖 contact sheet 只是盤點，原圖 hash 與零件原尺寸圖供後續核對。
- 骨架脚支點通過以外的實際鞋底材質接地與斜坡。
- 新共用修正的效能前後比較；本次沒有做遊戲程式修正。

`source-contact-sheet.png` 是明確縮小的來源盤點圖；`*-parts-native.png` 是原尺寸貼圖放在淺／深底，沒有縮放；`*-gait.png` 是原生 Forward+；`*-p2-native-detail.png` 是其原尺寸單格裁切。四者用途不同。

## 重跑

從 repo 根目錄執行，Python 使用現有環境。所有 Godot 透過 `gpu_lock.py` 的跨 worktree 共用鎖，鎖路徑已核對為主 checkout 的 `assets_src/work/comfy.lock`。生成／啟停 ComfyUI 不在本分工内。

```powershell
$env:PYTHONUTF8 = '1'
& C:/ComfyUI/venv/Scripts/python.exe tools/humanoid_asset_ledger.py
& C:/ComfyUI/venv/Scripts/python.exe tools/comfyui/check_parts.py trooper trooper_elite grenadier sniper slasher stalker flamer reclaimer --normals
& C:/ComfyUI/venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-driver vulkan --rendering-method forward_plus res://tools/humanoid_scope_audit.tscn -- --config=<repo絕對路徑>/pm/Nest-Egg/attachments/NE-90-humanoid-subagent/capture-config.json --out=<repo絕對路徑>/pm/Nest-Egg/images/NE-90-humanoid-subagent
& C:/ComfyUI/venv/Scripts/python.exe tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/humanoid_scope_audit.tscn -- --config=<repo絕對路徑>/pm/Nest-Egg/attachments/NE-90-humanoid-subagent/capture-config.json --out=<repo絕對路徑>/pm/Nest-Egg/attachments/NE-90-humanoid-subagent --metrics
```

執行前／取得 GPU 鎖後检查 available RAM 至少 4 GiB。量測本次取得鎖後 available 14.16 GiB；Godot 完成即退出释放。本次沒有同時開兩個 Godot 渲染程序，也沒有啟動或停止他人的程序。

局部測試的命令与原始结果另附 `validation.log`；沒有跑完整測試，也沒有新增 known_failures。
