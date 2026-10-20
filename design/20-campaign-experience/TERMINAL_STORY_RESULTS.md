# 第一章獨立段落的保存邊界

2026-10-21。承接 ST-9：先將晚飯與交接櫃三次明確操作接上真正整輪保存，不宣稱所有故事結果已完成。政策 `main_terminal_results_v1` 由正式 compiler 指定，限定有真 Main／當前 persistent Level、無選項、無 then、無待定交物的獨立段落。回家保留原旗標政策；世界拾取、診間托盤與含續段的餐費本批不借用此政策。

保存前以既有純 StoryResultPlan 計算完整旗標、錢包／正式收據、物品持有／交付與完成史，所有 owner 先準備，再寫完整現況快照。交盤的目的地必須來自正式交接櫃資料，其他紙物由已載入劇本的段落發放；不生成世界 pickup 或猜測座標。沒有改動區域狀態，因此保持 Level 的現有共享區域參照。

保存拒絕時保留真請求及全部原件，僅顯示可重試的事件提示。保存成功後無回呼地安裝錢包、物品、旗標與完成史，然後退休請求、發布通知。發布期間禁止新故事交易、交物、播放及路由；普通花費與閱讀 NEW 合法，完成後重抓現況補存，不重新安裝舊候選。跨程序以正式 reader 驗已提交結果不重發。

完整 runtime 的保持比較，兩側須經 writer 相同的 JSON 與第二次驗證邊界，避免方向向量少一次 float32 單位化造成誤拒絕；不放寬數值門檻或省略欄位。主檔替換及回滾同時失敗時，既有提示改為載入完整原備份，真 Main 重建 Level 並只釋放本模組自己的鎖；本次結果仍未提交，不宣稱已保存。

另修現有 legacy 預檢：整段交易必須在獨立帳本與累計餘額中依序模擬，不能每筆都拿原餘額驗。重複、互斥與後筆缺錢均在第一筆 live 寫入前拒絕。

## 參考與界線

實際重看 [五款橫向動作／探索作品的來源圖](../../pm/Nest-Egg/attachments/NE-278-references/sources.json)：Katana ZERO 的明確選項與行動對應；Hollow Knight 保留人物／環境閱讀空間；Ghost Song 的講者與繼續提示；Blasphemous 2 的物件與人物關係；Ori 的關鍵資訊層次。圖片原件保留原來源，不當成本作驗收或偏好民調。

[Godot 官方存讀檔](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)支持完整持久狀態的捕捉；本作沿用既有有結果碼的整輪 writer，不據該教學宣稱具斷電 fsync 保證。[Hades 更新紀錄](https://www.supergiantgames.com/blog/hades-updates/)呈現對話資格與進度的修復案例，作為回訪驗證參考，不推論其內部實作。
