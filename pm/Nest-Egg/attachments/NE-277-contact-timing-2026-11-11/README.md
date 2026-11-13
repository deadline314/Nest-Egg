# NE-277 可見接觸與回饋驗證

目前功能與回歸已完成；效能驗收尚未完成，整票仍在進行中。原生逐格資料屬 v6；v8 只補非有限幾何守門，具有自己的原／新控制與聯合回歸，不把舊原生收據改稱 v8。

| 證據 | 實際結果 | 界線 |
|---|---|---|
| 五武器、兩面向、全部招式與公開按住／放開 | 42 列、2,724 連續物理步、9,069 最終接觸檢查，0 失敗 | `contact-result.json` 比較；早先 `result.json` 的動作檢查是 9,054，最後另有 15 項錄音／收尾檢查 |
| 真首傷與可見表面 | 原 alpha／錘頭範圍／實際繩節及前後步 sweep，由獨立 SAT 與接點判定重算 | 早判、晚判負控制均須拒絕；柄端不能代替錘頭 |
| 命中回饋 | 36 列、362 檢查；實際雙方頓幀、反應、音效葉節點、震動與減量設定 | 36 WAV 是原 master PCM 的精確連續片段，含其他聲音；沒有冒稱真人試聽或分離音軌音量 |
| 每招修前／後頁 | 42 對應案例、四階段共 168 頁；4,032 個身體／手部圖塊逐像素相同於原始來源 | 每側各保留六連步、原 tick／phase；兩次自然拍攝不是 pixel A/A |
| v6 正式 affected | 65 組、88,777 檢查，0 新／已知失敗，exit 0 | `affected-final-index.json`；允許的預期診斷保留，不稱 0 ERROR |
| v8＋純 published NE-290 clock 聯合 affected | 70 組、94,097 檢查，0 新／已知失敗，exit 0 | `affected-v8-clock-joint-index.json`；33 源不變，排除 NPC WIP；這是回歸，並非效能結果 |
| v8 非有限幾何控制 | 原版三個有限假接點與兩個反矩陣 API 診斷；守門後七例全過；INF 矩形尺寸原假命中，v8 三例全過；最終幾何 113／0 | 原始拒絕／錯誤不刪除，合法反射、極小非零行列式及零尺寸接點不放寬 |

Root 已看過五把代表首傷、手部近拍、五把修前／後 active 連頁及五組 normal／reduced 全尺寸圖。動作輪廓可區分，錘／鞭首傷已在可見部位接觸時發生，減量圖仍能讀到命中。補充逐頁檢視另記在工作收據；沒有宣稱手動看完所有原始像素、實體手把操作或真人試聽。

## 大型原件與重算

16 個新原件 ZIP 共 547,018,407 bytes 已完整另存：

`D:/NestEggDeliveries/NE277-20261112`

逐檔 SHA 與原件相同，清單見 `external-raw-index.json`。Repo 工作目錄原件也未刪除，但新 raw 已精確忽略以避免誤入 Git。已發布的舊 before ZIP 與兩個小型正式回歸 raw 保留原路徑／歷史。

```powershell
python pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/verify.py --raw-root D:/NestEggDeliveries/NE277-20261112
python pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/verify_comparison_pages.py --raw-root D:/NestEggDeliveries/NE277-20261112
python pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/verify_affected_final.py
python pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/verify_affected_v8_clock_joint.py
python -m unittest discover -s pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11 -p 'test_*.py' -v
```

前兩個 reader 已分別真重算 229／0 與 12,860／0；六項 reader 控制包含改像素、錯位、缺／跳步、錯 PCM 格式及不安全 ZIP 路徑。新舊同名 ZIP 不混取：before 使用已發布 repo 路徑，after 使用明示的 `--raw-root`。

非有限幾何原／新收據另封 `guard-v8-raw.zip`（48 members、7,511,159 bytes，SHA `add80cfe4e2e2b71f1484794117f47296c39c588066a99a85b7417193a358af3`），完整另存於同一個外部目錄，repo 原件未刪除但精確忽略。Git 只保留 78,375-byte 的 `guard-v8-selected.zip`：原日誌／結果、前後來源與 fixture 44 members；四份完整私有專案 manifest 由外部 raw 保留，沒有假稱精選包含它們。整合 runner 後來改名以避免 Python 單元測試誤啟引擎，包內 `authoring-current` 明示為目前可重現副本，不補稱事前執行檔 hash。

```powershell
# 完整 raw 加精選來源／原錯誤／最終 113／0 的離線核對；不啟引擎。
python pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11/verify_guard_v8.py --raw-root D:/NestEggDeliveries/NE277-20261112
```

此命令已真通過。省略 `--raw-root` 仍可核對精選的全部邏輯證據，但輸出會明確標示未核對完整 raw，不能改稱已檢查四份私有 manifest。

## 效能前提

原生實際 Player physics、PlayerVisual physics、MeleeHeld draw 的配對 runner 已完成來源與功能預檢；三個外層成本不重複加總 nested module tick。另保留原 e7aaf 實際舊 Player／Rig 路徑與 c78 增量對照；歷史不存在的按住招式不填成零成本。純 published 聯合樹的副本已獨立固定，資格輪不讀仍在編輯的 C/NPC 來源。

最後預檢兩版皆讀回 HIGH、亮度 .5、HDR2D、實際 2560×1440 backing buffer 與有效焦點。CLI 請求尺寸不當成實際 viewport 尺寸。第一次 qualified 起跑在任何 Godot 啟動前，被仍有工作的外部 8188 佇列拒絕；沒有取消別人工作，也沒有產生可採用的效能數字。待 Root／UI／NPC 及實際外部工作再次全部清空後，才執行 A/A 與原／新交替計時。
