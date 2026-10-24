# NE-264 測試時鐘

只修改平滑位移驗證的更新時鐘，遊戲彈帶來源逐byte相同。24px與原斷言、輸入、等待、取樣數均保留。正式遊戲沒有改成60Hz UI更新；30fps原圖的26.7px不因測試修正而消失。

[時鐘診斷圖](../../images/NE-264-test-clock.png)來自兩段實際counter紀錄，P為物理計數、R為process計數；取自不同動作階段，沒有比較畫面改善。這是資料圖，不是遊戲原生截圖。

| 原始控制 | 結果 |
|---|---|
| NE-229受影響原失敗 | 64,112／1，跳躍28.8px；保留原完整分組log |
| 未修改對話的main、30fps、原前置流程 | 195／1，轉身26.7px；是同類時鐘問題，未冒稱同一28.8px格 |
| 最終時鐘、30與60fps、同前置 | 各195／0 |
| 明示單行故障：側向立即換邊 | 195／1，114.4px；真正UI來源還原核對相同 |
| 原受影響選擇器 | AmmoTraySuite，33／0，0新／已知失敗、41秒 |

`raw.zip`包含原與最終測試、原UI／故障UI、前置流程工具、原始失敗／通過log、時鐘圖來源與重建腳本、研究收據；逐檔SHA在manifest，固定來源與結果在validation。

在獨立65bccc552f98a708c767c6a290f20b0c8752afc9 checkout，覆上source/after，將probes/tray_clock.gd與.tscn放到work/batch1024，Godot4.7.2匯入後跑`res://work/batch1024/tray_clock.tscn`。它走真正SupplySuite、UiKitSuite、AmmoTraySuite，以30fps重播；改私人工具的max_fps為60可跑另一控制。不要覆寫工作中的checkout。故障控制只將原UI那行側向插值換成立即賦值，務必在finally恢復；這不是正式修正。

前置探針V1在scene setup期間建立Root關卡，SCRIPT ERROR、0檢查且洩漏，完整保留作拒收；改為延後啟動後才取得有效結果。原main的trace子類只增加列印；另保留未使用trace子類的正式原套件控制。研究實際取得Gaffer文章，短摘錄與HTTP／SHA收據在references；不以文章替代真正引擎counter證據。

[設計及界線](../../../../design/20-campaign-experience/AMMO_TRAY_TEST_CLOCK.md)。
