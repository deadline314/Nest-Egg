# NE295 原受影響測試正式補件

本包保留所有原紅件與最終原入口。每份候選 source.zip／完整 runtime SHA 清單、命令、原 selector／filter／known failures、全部分片原 log、來源前後與 C／queue 守門均在 raw.zip；設計文件僅靜態 provenance，不誤稱有 runtime 門禁。

最終四票聯集：87 組／99550 checks／0 new／0 known／exit0。實際候選 80 路徑；其中 runtime 門禁 79，其餘設計檔逐 source.zip SHA。fixture 與原 Windows 退出診斷保留，不宣稱全部 ERROR 為零。

原生14點為固定actor原 sampler，並非自然通關。其遊戲／地圖／光影 runtime 與最終候選相同；完整 source 字典的測試 helper／私有 integration manifest 差異見所附 root comparison，不假稱所有 SHA 相同。focused wrapper 原 false／四個故意 warning 與獨立 accepted review 同存，沒有改為 true。NE297 原 pending index 的歷史 false 保持不變。

離線重讀（Python、Git Bash；不啟 Godot）：

```powershell
python verify.py --extract-to D:/NestEggVerification/NE295-official-independent
```

使用全新的解壓目錄。Root 另行核 SHA 後才可採 top-official-proposal.json；此腳本不修改原附件。
