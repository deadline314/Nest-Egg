# 自由遭遇驗證

來源為 `5300e7c06c68cd2852e731041ac44a8334ddab66` 上的 22 檔凍結候選。`source-manifest.json` 列出 Git baseline 與候選 LF SHA，patch 為 68,081 bytes、SHA `482bdb18f4fdc454a1cef47cd9830aee0201120a9331ea37c3ece64077af32fe`。

本機 Godot 4.7.2、Windows Forward+、Intel Arc B580。匯入退出 0、無腳本錯誤；EncounterSuite 與 RunSaveSuite 共 531 檢查、0 新／已知失敗、退出 0。原始 changed selector 的結果另外保存，不以這兩套件取代其選擇。

原生探針用正式 street／vault 的四個遭遇區、真敵人與 Input 動作。每區兩個原封路邊界，每邊左右走路／衝刺，共 32 次跨越；每次檢查從玩家身體完整位於邊界另一側開始，到另一側結束，各区離開後仍 active 且敵人存活。85 檢查、0 失敗、退出 0；8 張原樣 PNG 在 images/。

這是安排的局部物理／畫面驗證：抑制故事 intro／trigger／章節卡，暫時無敵以保留敵人；保留實際 AI，不是完整章節通關或人工手感驗收。Root 看過全部八張，原升牆位置沒有牆體。現有顆粒、照明與角色素材問題仍按 BG-27、BG-30 與角色票處理，不能以本票的通行證據宣稱畫面整體完成。

存檔回歸使用真 Level、實際域外追擊成員與無關域內敵人，實際 DiskStore 保存／載入，新 Main 恢復與原件 bytes 比較；不把位置當成新格式的敵人身份。初始化失敗不公布半成品，也不覆寫良好存檔，會回到主選單。舊存檔保留明確的舊空間恢復路徑；跨區沿用已清除遭遇／已消耗作者物件，未完成波次不新增跨區常駐功能。

`superseded-rejected/` 保留首次修補的失敗：斷言通過但 typed Array 收到非 Enemy 引起腳本錯誤，整輪不算通過。修正型別邊界後再跑最終 531 檢查；不更改 runner、selector、known failures 或移除舊斷言。

命令、raw log、退出碼及 hashes 保存在本目錄。人工 fault 的 WARN 為容錯負控制，仍原樣保存；不將警告刪掉或改成成功事件。

原始 changed selector 選取 ALL，首輪81群組／58,429項，只有四條第一章普通入口必須升牆的舊預期失敗；raw與退出1保存在 superseded-rejected/。修正為普通門不建立碰撞／牆板、真實敵人成員存在、波次全倒才完成，並將生成設計資料的 wave_zone 與 lock 分開。地圖重測1,412項，0新／已知失敗、退出0；只生成設計資料，實際地圖、遭遇成員、資源未改。中途變數範圍解析錯誤亦原樣保留，該輪不算通過。

目前24檔版本待原始 selector 最終回歸；本次為 feature review checkpoint，票保持進行中、條件尚未勾選。原生85項与存檔531項的22檔版本manifest另保留；24檔增加地圖測試與設計清單，原生玩法程式保持相同。
