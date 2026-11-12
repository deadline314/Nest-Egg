# 一般死亡的重試與完整控制驗證

在已發布20f9主線上採納精準八份程式／測試：一般死亡短暫說明後即可重試，原台詞與記憶卡仍可自願看完；說明首次顯示即完整，自然播完保留玩家已移動的選單焦點。同輪任務導覽重用已驗證目錄，並保留新遊戲、語言／來源重載、損壞來源修復與UI副本隔離。

| 最終驗證 | 結果 |
|---|---|
| 真Main生命歸零→原保存／原計時轉場→新玩家接受移動 | 第二次2956.851ms，第三次2583.626ms |
| 真正暫存檔拒寫→公開重試 | 原死亡世界與檔案／結算保留，修復後恢復一次；2884.077ms |
| 原受影響70組 | 94,431檢查，0新／0已知失敗；exit0；28,035份輸入名稱／大小／SHA前後相同 |
| 初次提示永久回歸 | 19/2失敗→19/0；原兩套件486/0，保留1個刻意無電話亭ERROR |
| 六張原生圖 | Forward+、RX9070XT、1280×720、RGBH14/HDR2D，0引擎／腳本／退出診斷 |
| 原生完整像素重算 | 5,529,600像素，RGB最大誤差0.0039213085，alpha誤差0 |

根代理親看六張最終原圖並獨立執行最終來源／正式測試與封存canonical像素reader。採納紀錄見[source-adoption.json](source-adoption.json)。原生排版不是三秒控制量時；情境包含明示的首死建檔、錄音與復原點前提，並非人工走完診間。這是合成公開操作的功能結果，未代稱實體手把或獨占效能。

## 原件與重算

[完整原件說明](original/README.md)與[逐檔清單](original/PUBLIC-MANIFEST.json)保留交付前的候選稱呼及當時事實。兩份ZIP共1,142個原件，逐member CRC／SHA驗過；舊失敗計時、焦點、截圖與來源門禁拒絕均保存。舊70組雖有94,397/0，其來源門禁仍為false，沒有被最終70組取代或改綠。最終原log的容錯ERROR分類保持，沒有宣稱所有原始ERROR均為零。

六張完整PNG在[original/images](original/images)。兩份完整浮點ZIP永久保留於 `D:/NestEggVerification/proofs/st13-restoration-clock-20261112/native-layout-v3-count{2,3}/native-raw.zip`；[原始SHA及大小](original/external-raw-index.json)。可原樣複製到另一raw root，不依賴受保護的managed checkout。

使用已安裝Pillow／NumPy的Python，輸出必須是新目錄：

```powershell
python -X utf8 ./original/replay_public_candidate.py --raw-root D:/NestEggVerification/proofs/st13-restoration-clock-20261112 --out D:/NestEggVerification/proofs/st13-restoration-clock-20261112/my-new-replay-v1
```

此命令核對ZIP、完整解到新目錄後執行原封存reader，保存實際命令／退出碼／stdout／stderr，不啟動引擎。初次portable重播收據在[original/portable-replay-receipts](original/portable-replay-receipts)。

第二次2.957秒接近三秒上限，原值保留；冷啟動成本尚未由本次重試修正解決。主選單沿用原保存語義，不能把本票重試的硬保存門禁套用到它。

根代理從本公開封包實際解到全新root-public-replay-v1的[完整收據](root-independent-replay/receipt.json)：兩份ZIP共1,142原件逐SHA／CRC通過，兩原reader均exit0／空stderr，不依賴managed checkout。
