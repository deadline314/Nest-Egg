# NE-292 覆寫貼圖完整性

[原始已發布候選、完整壞檔／成品對照與讀取器](original-packet/README.md)。該子目錄完整保留原交付的全部bytes與原manifest，包含原.gitattributes；父目錄另以局部Git屬性保存原生CRLF日誌及patch的空白context，沒有改寫原輸出或放寬產品程式檢查。

[主工作樹整合、受影響入口與範圍](ROOT_REVIEW.md)。

執行 `python original-packet/verify_ne292.py`、`python original-packet/reader_controls.py`、`python verify_root_checks.py` 可離線重算。圖片是原始CPU結果的資料圖，不是遊戲畫面。
