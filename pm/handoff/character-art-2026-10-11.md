# 角色美術 Session 停工交接（2026-10-11）

使用者要求收尾、整理、清理無意義檔案，然後停止。本次不再啟動生成、修玩法、重跑角色動畫或擴大任務。整體偏好、SOP、拒收圖與原始參考見 [user_guide](../user_guide.md)。

## 接手基準與已合入範圍

停工整理開始時 main／origin/main／工作分支均為 `7daaa5784421b9d671a915dd67e606e4504bcbb1`。本文件隨後以 NE-222 的文件交接提交；接手先 fetch，以最新 main 建獨立分支，不複製整個舊目錄。

| 最新範圍 | commit | 公開證據 | 可採用的結論 |
|---|---|---|---|
| NE-222 診間補光、共用 LIGHT_ENERGY | `54b6f05dcb2dbac25b9467ed2458ac81a792fd19` | [曝光packet](../Nest-Egg/attachments/NE-222-cutscene-exposure/README.md) | 67受影響組／46,532checks零新失敗；真RTX4070SUPER、Godot4.7.2、Forward+／HDR2D，補光與逐燈響應改善。正式鏡頭裁到髮尾、臀腿與全動作不計通過 |
| NE-222 新坐姿來源長暗帶 | `7daaa5784421b9d671a915dd67e606e4504bcbb1` | [IG02來源與比對](../../art_src/characters/rin_sit_lower_ig02/README.md) | 暗帶已在IG01原圖中；IG02改善但目標區外451,667px及143,109alpha改動，未放入遊戲。來源／文件選0Godot套件，不冒稱實機通過 |
| NE-222 材質軸／bind校準 | `76180645419ae5010a222a8622352714ec53cf05` | [校準](../../art_src/characters/rin_walk_source_ig01/registration/README.md)、[單手原生反例](../Nest-Egg/attachments/NE-222-material-axis/README.md) | 正式20骨非零FK及材質方向可核對；錯+Y負控制近90度，正确机械手近+X。只證明單件校準 |
| NE-90 Slasher單靴／踝接點 | `7e3289808d00e339c0662f26d1ab61c02de0f9d6` | [單靴packet](../Nest-Egg/attachments/NE-90-single-boot/README.md) | 單來源重建與一像素反例可重跑，兩踝7,680樣本零失敗；不涵蓋全身、足底接地或所有人体。1,002px重疊中76個RGBA差異如實保留 |

更多票的現況／交付hash見指南第7節；[六票唯讀稽核快照](character-art-2026-10-11/enemy-ticket-summary.md) 保留 NE-17／181／79／80／81／ST-8 的已驗範圍。此報告中「不清理」是較早唯讀子任務的界線；之後使用者授權的清理以本交接清單為準。

## 尚未採用的新走路材料

本次保存六個原始檔及SAM拒收紀錄，置於 [未採用走路候選歸檔](character-art-2026-10-11/unadopted-walk-ig02/README.md)。為交接保存來源，不是新增正式角色或生成新素材。歸檔有 `.gdignore`，不作正式Godot資源匯入。原始metadata保留生成時的相對路徑語境，歸檔位置的映射另列，不能把它直接當發布配方。

- 新走路IG02：1037×1517 RGBA，SHA `bf3eb04ae13460f9ffe1349cfcdcf511f08fc964fbec78532e36e75a030d92c5`。由內建image_gen生成，seed／model／graph未知；s33和IG01保留。
- 底層：1037×1516 RGBA，SHA `ff9bda4aed98116d01b1ba9763796dcafa5e9652410e88fcc46abeb759fb0cc6`。重構圖、未對位；不是「只差一列」的新舊坐標。
- 真SAM3.1的四個mask正／負點符合，但語意拒收：28,503核心像素中1,646未認領、2,660多重認領；外套28連通件；自然手側衣袖誤收457個露膚像素。不能依點位通過或最近owner填空來直接切件。
- 原底層領口／腰位置与新走路圖不同；沒有完成近遠側、肩袖隱藏根部、源姿勢關節、正式骨長、原位組合與完整走路。下一步應先做來源／語意分件，不直接調IK。

## 其他私有試作與實際等待條件

下列是本機保留資料，不是全部已上傳的證據；雲端若沒有這些目錄，不可宣稱讀過或測過。公開packet已有對應主結論；需要本機原始序列才向該目錄查證。它們留在驗證區，不能整包帶進新feature分支。

| 本機資料位置 | 有意義的資訊／限制 |
|---|---|
| `D:/NestEggVerification/ne222-neutral-walk-ig02/` | 原始SAM request、result、workflow、mask、語意review與repeat檢查；歸檔保留選定原始輸入及主要拒收證據 |
| `D:/NestEggVerification/ne222-hip-source-diagnosis/` | 原正式來源與新坐姿暗帶定位；歷史00_bind_reference/sit/armor資料不是目前正式atlas，不能當正式骨架實況 |
| `D:/NestEggVerification/ne222-sit-lower-ig01-review/` | 候選骨長與來源檢視，關節未完整核准；正式股骨10.31、小腿11.4等比例僅作校準契約，不以圖好看就通過 |
| `D:/NestEggVerification/ne222-sit-lower-ig02-review/` | 原始暗帶修正與外區改動結果；已公開的C39比對能離線重跑 |
| `D:/NestEggVerification/ne221-garment-ledger/runtime-plan/` | 阿婆圍裙可用既有root_attach／bend_partner／springs，無需新框架；來源尚有14,909／89,069 RGB差異及手臂隱藏區。需先修底層，不採用未驗衣襬 |
| `.godot/ne221-cloth-cpu/`（舊主工作區內） | v1測6,480格，4個錯Sprite fixture失敗；沒有v2 PASS，不能改寫成成功 |
| `D:/NestEggVerification/ne90-single-foot-review/native/` | 原生1,920張踝部PNG，公開packet保存清單／報告／代表圖，完整raw留本機，不把它宣稱全身已人工驗收 |

NE-81弱點真玩家命中／傷害由既有NE-248負責，保留11checks／1failure及原生無命中事件；不要移核心、擴大hitbox或重開跨組核心票來掩蓋。第一章角色身份與故事文字仍由故事組處理。NE-222已交付的開場產生器修正先從main核對，這次沒有再改產生器或正式舞台。

## 驗證及執行環境

- Godot：`C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`，版本標記 `ed1daf0bf`。
- Python：`D:/ComfyUI/.venv/Scripts/python.exe`。PowerShell設定 `$env:PYTHONUTF8='1'`，避免中文stdout因cp950失敗。
- Bash：`C:/Program Files/Git/bin/bash.exe`。`run_tests_changed.sh`的基準參數是本票開始時固定SHA，不能只用已前進的origin/main造成空集合。
- COMFYUI_DIR：`D:/ComfyUI`；本次停工時8188服務已停止，不再啟動。共享GPU鎖與Comfy啟停規則見指南。
- CPU可重跑來源例：`art_src/characters/rin_sit_lower_ig02/compare_sources.py`、NE-90 packet的`audit.py`／`verify_packet.py`。按各README輸出至私有scratch，不改來源。
- 本次交接只做文件、連結、來源SHA、圖片可解碼、票狀態及Git內容檢查；沒有重新測遊戲、生成、錄影、試聽或效能。

已確認 [C38 CI](https://github.com/deadline314/Nest-Egg/actions/runs/38076249101) 成功；停工交接再次核對 [C39 CI 38077136718](https://github.com/deadline314/Nest-Egg/actions/runs/38077136718) 亦為 completed／success，head=`7daaa578`。沒有未核對套件數的新宣稱；CI成功不取代未通過的角色視覺驗收。

## 本機保護與清理

原工作區：`C:/Users/stanl/.codex/worktrees/character-art-baseline/Nest-Egg`，分支 `codex/session-character-poses`。兩個不屬本次收尾的tracked修改保留，不提交／還原：

| 檔案 | 原工作區SHA256 |
|---|---|
| `art/portraits/rin.png` | `dcb57512a46fa99b2a6b1aab1ae463f8892c5c0b2f04df05464a28e107b654ed` |
| `game/enemies/watchdog.gd` | `65ea2dfd0e599004ef3d37da8bba09c240c5fbc7e41c159c55a0e4cda6b4fc69` |

該區另有歷史來源、拒收候選與未辨明所有權的WIP；不使用`git add .`、`git clean`、hard reset或整包刪除。新Session從乾淨main建自己的worktree，這些untracked不會自動进入新分支。

本次僅清理已核對內容皆已合入main的自有最近兩個驗證checkout及其分支；先記錄路徑、未提交內容與對應Git blob，保留必要原始證據，才移除重複checkout／Godot匯入快取。實際刪除和保留結果記入 [清理紀錄](character-art-2026-10-11/cleanup.json)。舊的其他worktree／分支及未知WIP不強删；保留不是要求新Session拿它們作起點。

收尾提交後核對primary checkout tracked乾淨，普通快轉main，再fetch確認main＝origin/main。若遭遠端權限拒絕或primary存在別人的修改就停止，不用force、reset或绕过。
