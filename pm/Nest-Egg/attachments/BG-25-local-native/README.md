# BG-25 本機原生水管驗收

實際執行既有環境 probe，使用隔離 APPDATA 與共用 GPU 鎖，一次一個引擎；退出碼 0。未更動程式、測試選擇器、既有失敗名單或系統權限。本次為雲端水管階段的本機複驗，不能代稱所有場景動態交付。

- 原生 Intel Arc B580／Godot 4.7.2／Forward+，1280×720；低中高品質各三個連續時刻，共 13 PNG。
- 暫停水流時鐘 9.817981 → 9.817981，恢复後继续。
- 十次切區均 `local_released=true`；清理後節點均為 89，engine static allocation 約 134 MB，沒有連續增長。
- 原始 log 沒有 ERROR 或 WARNING。已查看低／高品質管口與接地畫面，硬管固定、水花在地面。
- 60 個 process-frame 間隔是同次運行的 CPU／呈現間隔，不能當 GPU 計時或前後性能比較。RenderingServer texture bytes 158617600 是引擎追蹤的部分貼圖量；Windows RSS 回傳 -1，總 VRAM 未取得，不能宣稱總顯存通過。
- 四張關鍵畫面存進 pm/Nest-Egg/images；全部 13 張當地檔案 SHA 留在 integrity.json，其餘仍在 C:/tmp/bg25-root-native/frames，未表示全部已進 Git。

來源與 retained screenshots SHA 在 integrity.json；native.log 保留原始 bytes。
