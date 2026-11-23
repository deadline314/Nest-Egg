# 本機驗收證據的保留期限

每次執行受影響測試時，會順便檢查 Nest Egg 登記的本機證據目錄。保留已交付的原始輸出至少 30 天。自到期日起，只有已在 `origin/main` 的票據附件裡留有完全相同位元組的副本，才會自動移除本機重複檔。新建或剛更新的檔案、未上傳的資料、尚未驗收的失敗輸出、分支和工作樹仍可繼續使用。

交付時，保留原封存產物，並在原始 `evidence-*` 目錄內寫入 `publish/result.json`。既有交付紀錄的 `commit` 欄位記錄推送的 Git 提交，`main_origin_head_equal` 表明已核對本機與遠端追蹤分支。只有該次提交新增在 `pm` 票據附件中的 ZIP，而且附件在 `origin/main` 仍是相同內容時，才用它查核。清理讀取 Git 儲存的封存資料，工作樹暫無附件副本時也能驗證。ZIP 的相對檔名須對應到本機證據目錄內的同名檔，且檔案大小及內容一致。沒有可信提交、路徑不安全或對應項目無法驗證時保留該檔案，讀取錯誤會指出位置。這個流程只移除符合條件的個別檔案，保留交付紀錄與其他檔案。

預設目錄為 `work/evidence`。本機驗收另放在專用磁碟時，用 `git config --local nestegg.evidenceRoot "D:/NestEggVerification"` 指定。支援用 `--root` 單次指定另一個專用目錄。

手動預覽用 `python tools/evidence_retention.py`。確認結果後可用 `python tools/evidence_retention.py --apply` 直接執行。日常 `tools/run_tests_changed.sh` 會沿用相同規則自動清理。清理失敗會列出原因，受影響測試會繼續執行。

## 原生診斷的預設輸出

場景舞台、震波圈和武器平衡工具預設把結果寫到 Godot 使用者資料夾的 verification。每個舞台用固定檔名，另外兩個工具各留一份最新輸出。工具會列出實際路徑。需要保留指定輪次時，以 --out 指定要保存的目錄或檔案。正式票只封存本次交付需要的輸出與測試紀錄。

## GitHub Actions 測試的工作目錄

測試工作先以 Git 的稀疏檢出取得根目錄檔案與工作流程。排程確認目前提交已有綠燈時，到這裡即可結束。需要跑測試時，再依實際提交展開 pm/ 以外的目錄。這只影響 CI 暫存的工作目錄，票據及正式附件仍由 Git 保存。發行與需要逐票讀取證據的工具繼續使用完整檢出。

[動作的稀疏檢出設定](https://github.com/actions/checkout/blob/v4/README.md#fetch-only-the-root-files-and-github-and-src-folder) · [Git cone 模式規則](https://git-scm.com/docs/git-sparse-checkout#_cone_pattern_set)
