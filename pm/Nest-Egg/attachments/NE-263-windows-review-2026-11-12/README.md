# NE-263 當前 Windows 獨立審查

2026-11-12。於已發布98e90c74的相同工具來源，在本機Windows/Python3.13/Git Bash執行原 `tools/test_select_tests.py`：19 tests、0 failures、0 skips、exit0，23.551秒。啟動前沒有 `PYTHONUTF8`／`PYTHONIOENCODING`，實際locale與stdout皆cp950、UTF8 mode0；PATH只選定原本的Git Bash/Python可執行檔，沒有套用Python編碼避開方案。

19項涵蓋中文檔名、Git引號、只改票、基準不存在、非repo、缺git、挑選工具當掉與中文錯誤傳遞，以及後來加入的忽略邊界/重複類別/引擎配方範圍。CLI測試刻意使用假的平行測試執行器記錄要求的套件，驗證選擇、輸出與退出，不冒稱本輪跑了遊戲回歸。

`original-windows-review.zip`完整保存未改寫的原log、環境及退出收據，以及六份原工具/過濾器/已知失敗來源。執行 `python verify.py` 可獨立校驗全部ZIP/member bytes/SHA、未使用UTF8 workaround的環境及19項真結果。

票內原Windows兩種設定各1983項真遊戲測試與Linux95組選擇相同的歷史證據維持原版本/範圍；本次不是新Linux或新1983項重跑，也不將19項邊界檢查冒稱全遊戲測試。沒有產品或測試程式變動，沿用票內既有終端圖。
