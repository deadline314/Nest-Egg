# NE-262 弱點框交付驗收

原產品提交為 `0f1df75f`。本次獨立核對原始差異，並在 RX 9070 XT / Godot 4.7.2 / Vulkan Forward+ HDR 2D 補上固定場景原生證據。正常時頭部及其他弱點沒有四角框；debug 保留弱點黃色與普通部位青色受擊框。傷害與弱點回饋另由真受擊 API 驗證。

完整交付原件在 [original-packet/README.md](original-packet/README.md)，19 個檔案與原 [delivery-files.json](original-packet/delivery-files.json) 逐 byte 保存。原 `raw.zip` 48,740,300 bytes、539 members 直接隨 Git 交付，原 `source.zip` 90 members；本次沒有採用原稿建議的外存方式，不需額外下載原件。

## 獨立核對

Root 親看三張完整 1280×720 PNG，並另開程序重算 CPU 正／負案例、正常原生、未移除框故障、debug 關閉故障與 24px 錯投影，全部得到預期退出碼。接著從封存包直接重算 539+90 檔的 SHA/CRC、實際 24+12 條線段、完整 A/A、四輪 C364 與模型服務 queue 收據；10 個讀取器控制通過。

```powershell
python -X utf8 pm/Nest-Egg/attachments/NE-262-weak-bracket-2026-11-12/original-packet/verify_pack.py
```

[Root 獨立程序收據](root-checks/result.json)及 stdout/stderr 原件一併保存。身體冒稱頭部由引擎得到 4 項真失敗；讀取器成功辨認這個已知負案例，兩個退出碼不可混用。

B 僅還原舊繪製行為，使用目前固定角色／姿勢／鏡頭，並非完整歷史版本。CPU 觀察到真傷害 2/1、弱點旗標、火花生成、聲音事件及準星 timer；沒有錄音或人工試聽宣稱。原票 550 項缺少原始執行收據，保留歷史原文，不補造其結果。其他已發布的正式回歸只在原包內以正確來源範圍引用。

本次為證據與文件交付，產品來源保持；原工具粒子期待錯誤與 zoom3 出框失敗完整留存。
