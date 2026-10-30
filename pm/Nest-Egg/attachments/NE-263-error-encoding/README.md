# NE-263：錯誤輸出的編碼邊界

基準 d76ef55a。Windows 原生 Commit-2 已證實正常挑選一致，但原本還有 1 個工具當掉測試因 cp950 traceback／UTF-8 日誌混用而失敗。本次在 Linux 用明示的 cp950 pipe 預設重現，沒有聲稱再次跑過 Windows。

修正只在 shell 呼叫的 Python 子程序設定 UTF-8 IO，連 main 前的未捕捉例外都一致。不設定全域 locale，不更動挑選圖、套件清單、判定門檻或測試過濾。新樣本尊重 Python IO 設定；使用者端不提供環境變數。

最終測試以嚴格 UTF-8 解碼；原 shell 在 13 項中產生 1 個解碼錯誤，修後 13 / 13 通過。中文路徑、中文票、錯誤基準、缺 git、完整引擎修補變更與真正工具當掉均保留測試；錯誤仍 exit 2、不執行測試且明講沒有跑任何測試。

`evidence.zip` 內 final-before.log 是原 shell + 最終嚴格測試；final-after.log 是隔離副本；final-production.log 是最終正式檔案。較早 before.log / after.log 是替換原 crash 樣本的探索紀錄，與最終新增獨立樣本分開。final-source 是交付原檔，tools 是隔離樣本。

受影響入口成功執行但沒有選到 Godot 套件，不把這個零套件結果當成遊戲回歸。此修改的直接驗證是上述 13 個獨立暫存 repo 邊界測試與 Bash 語法檢查；本次沒有新增遊戲畫面。
