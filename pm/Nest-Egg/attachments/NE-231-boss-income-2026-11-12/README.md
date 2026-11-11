# NE-231：不掉錢的故事演員不重算死亡賞金

這是跨章帳本的資料校正子交付，NE-231 整票仍在進行中。原有五條未勾條件保留；沒有宣稱自然通關、打擊感、實體裝置或效能驗收。

## 原因與最小候選

原 `EconomyReport` 依 `EnemyData.credit_value` 計算地圖收入。阿勇資料填 120，守門人填 1，但正式行為不會產生這兩筆掉落：

- 阿勇的斷連與保留路線均制伏在 Health 1／floor 1，沒有 Health.died，也沒有發布 CreditPickup。
- 守門人的裝置穩定度歸零確實發出一次 Health.died；覆寫的回呼轉為停機與拔插銷，沒有走一般敵人的金錢掉落。不能把這個結果改寫成「沒有 Health.died」。
- 正式故事交易分別付 120、100，第二次均拒絕重付；這些實付款項不變。

候選只把兩個不會掉落的遺留欄位改為 0。Progression 資料契約只要求這兩位為 0，其他敵人仍須為正值；Economy 新增真資源／純 LevelLayout 檢查，並以普通敵人資源的實際正值作正控制，不鎖死未來平衡值。沒有修改戰鬥、故事報酬或選擇器。

四檔最小差異見 [source.diff](source.diff)，最終原始來源 SHA 與 before／after 對照見 [index.json](index.json)。

## 真正執行的控制

| 階段 | 結果與來源界線 |
|---|---|
| 原帳本 | FAA5 published 經濟源；當時 UI 六個工作檔另記 context。8.344 秒、exit 0、零診斷，來源前後相同 |
| 真角色／交易 | 83319fef＋已發布 NE-291 fixture，UI 六檔已還原。37／0、30.205 秒、零診斷；沿既有受控 cut／keep／halt-pin 流程，非自然戰鬥 |
| 掉落正控制 | 普通 grunt 真正發布 8 元 CreditPickup；觀察 child_entered_tree，所以不會因物件被撿走而假稱沒有掉落 |
| Progression 四格 | 每格 68 檢查：原契約／原資料 0 拒絕；新契約／原資料 2；原契約／0 資料 2；新契約／0 資料 0 |
| 真 EconomyReport／純 layout | 每格 6 檢查：原資料 2 拒絕，0 資料 0；普通敵人的正收入保持 |
| 最終 v3 窄控制 | 9.408 秒、exit 0、零診斷；經濟輸入、全部 tracked test 腳本、工具、HEAD 與 context 前後相同 |
| 獨立文字／地圖重算 | 原／候選各 607 檢查通過；每版 247 個封存文字／地圖輸入，不讀正在變動的 managed 來源 |
| 正式受影響回歸 | 原入口42組、58,211項、0新／0已知失敗、exit0；508.782秒，3942來源前後固定 |

窄候選控制實際讀取 D 的 TRES 檔，再以 `Resource.take_over_path` 在該 headless 程序中替代原路徑；原／新契約副本只移除重複的全域 class_name，原檢查方法照常執行。這個 seam 已明示，不冒稱正式完整套件或 C 已採用。

原角色控制有記錄 Git833 與唯一 tracked fixture 差異，但當時沒有逐檔事前計算 Ch2／Ch3 測試腳本 SHA；封包之後從該 immutable Git 取得它們的未修改 bytes。這個時間界線逐檔列在 `frozen-inputs/manifest.json`，沒有補稱為事前 hash。最終 v3 則直接守住全部 tracked test 腳本。

## 帳目差異

| 章 | 原主路地圖 | 候選主路地圖 | 故事主款 | 付款 | 補給 | 候選三死扣款 | 原累計餘額 | 候選累計餘額 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 第一章 | 868 | 868 | 0 | −200 | 200 | 66 | 402 | 402 |
| 第二章 | 260 | 140 | 1,090 | −40 | 200 | 197 | 1,298 | 1,195 |
| 第三章 | 81 | 80 | 280 | 0 | 200 | 192 | 1,253 | 1,163 |

第二章真正的普通敵人掉落合計 120，第三章 60；其餘地上收入維持 20。探索／支線保持 20／240／60。必要補給為醫療針兩支與護盾電池一件，共 200；典當後贖回每件淨虧 6／8，不算收入。成長目錄總價 2,300（槍械 370、近戰 540、防禦 1,090、義體 300）。

這些餘額是沿靜態主路、每筆拿一次、支付最壞分支並每章假設三次死亡後，尚未花在自主成長或典當利息的可選預算。出入口鎖的可解開性是既有靜態報表的假設；沒有凍結或實際走通所有門，也沒有證明每種購買組合後都能通關。

## 離線重算與原件

`raw.zip`：561 members、1,678,334 bytes，SHA-256 `f09e499b19cf2e130a8ddf14cdec50ac030614ac7b9803ab0382dd1c5ca200cc`。原引擎日誌、命令、return code、來源前後紀錄、v2 原候選與最終 v3 均保留原 bytes；ZIP 內容不做 CRLF 正規化。

```powershell
python pm/Nest-Egg/attachments/NE-231-boss-income-2026-11-12/verify.py
python -m unittest discover -s pm/Nest-Egg/attachments/NE-231-boss-income-2026-11-12 -p 'test_*.py' -v
```

Reader 會校驗 ZIP／逐檔 SHA／CRC，再從包內來源重算兩份帳本、真 Health／掉落／重複交易控制與預期紅綠矩陣；不啟動 Godot。第一個作者端 input freeze 因少了測試腳本的個別事前 hash 而拒絕，未產生成功 manifest；其不完整原件仍在 `work/ne231-ledger-published/frozen-inputs-incomplete-v2`，沒有當成功驗證。

本子交付沒有玩家畫面變更，也沒有新增圖形程序或截圖。

## 最後原受影響回歸

正式來源為已發布931a＋本票四資料／測試來源及NE228六介面來源的精確聯合，沒有Primary C的NE277／NPC未發布產品。首輪42組58,212項／1新失敗是圖鑑末卡被新詳情版面裁切；原件保留，不能寫成全綠。NE228修正真版面排序後，以相同收入四源重跑原入口：42組58,211項／0新／0已知、exit0、508.782秒。原生六介面樣本與本票收入資料分開，沒有把尚未完成的介面210格冒稱已通過。

[完整首次失敗](../NE-228-ui-hints-scroll-motion-2026-11-12/official-ui-economy-joint-v1-first-red-index.json)、[最後原始輸出與全部3942來源](../NE-228-ui-hints-scroll-motion-2026-11-12/official-ui-economy-joint-v2-index.json)、[最後獨立讀取器](../NE-228-ui-hints-scroll-motion-2026-11-12/verify_official_ui_economy_joint_v2.py)。最後四分片185條原過濾器接受的ERROR保留，0 SCRIPT ERROR，不稱整份raw零ERROR。兩輪check數因真資料分支不同而照原值記錄，不拼成同一份結果。

本次正式採用四源與上述聯合測試快照逐byte一致；Primary C原355來源完全保留，加入四源後359份守門。圖片由封存的原引擎帳本資料產生，沒有改圖或當成遊戲擷取。
