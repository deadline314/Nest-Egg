# 自由遭遇驗證

交付來源為已提交的 `48752f1edb6ca18517e2ddd5a9b0ff70898bcbc9`，24 檔凍結來源在 `source-manifest.json`；保留建立候選時的 baseline `5300e7c06c68cd2852e731041ac44a8334ddab66` 與各檔 LF SHA。24 檔 patch 為 78,625 bytes、SHA `06aa1b31f3369c514cad09a1aa0e43def590cf0883c2f994a71021458ec10b7e`。Cloud 原始 selector 比較的 origin/main 為 `7b7b3fad166a0f6f007a6fd330df88dd9471c772`；不把這份歷史測試結果改寫成其他 HEAD 的完整測試。

本機 Godot 4.7.2、Windows Forward+、Intel Arc B580。匯入退出 0、無腳本錯誤；EncounterSuite 與 RunSaveSuite 共 531 檢查、0 新／已知失敗、退出 0。原始 changed selector 的結果另外保存，不以這兩套件取代其選擇。

原生探針用正式 street／vault 的四個遭遇區、真敵人與 Input 動作。每區兩個原封路邊界，每邊左右走路／衝刺，共 32 次跨越；每次檢查從玩家身體完整位於邊界另一側開始，到另一側結束，各区離開後仍 active 且敵人存活。85 檢查、0 失敗、退出 0；8 張原樣 PNG 在 images/。

這是安排的局部物理／畫面驗證：抑制故事 intro／trigger／章節卡，暫時無敵以保留敵人；保留實際 AI，不是完整章節通關或人工手感驗收。Root 看過全部八張，原升牆位置沒有牆體。現有顆粒、照明與角色素材問題仍按 BG-27、BG-30 與角色票處理，不能以本票的通行證據宣稱畫面整體完成。

存檔回歸使用真 Level、實際域外追擊成員與無關域內敵人，實際 DiskStore 保存／載入，新 Main 恢復與原件 bytes 比較；不把位置當成新格式的敵人身份。初始化失敗不公布半成品，也不覆寫良好存檔，會回到主選單。舊存檔保留明確的舊空間恢復路徑；跨區沿用已清除遭遇／已消耗作者物件，未完成波次不新增跨區常駐功能。

`superseded-rejected/` 保留首次修補的失敗：斷言通過但 typed Array 收到非 Enemy 引起腳本錯誤，整輪不算通過。修正型別邊界後再跑最終 531 檢查；不更改 runner、selector、known failures 或移除舊斷言。

命令、raw log、退出碼及 hashes 保存在本目錄。人工 fault 的 WARN 為容錯負控制，仍原樣保存；不將警告刪掉或改成成功事件。

原始 changed selector 選取 ALL，首輪81群組／58,429項，只有四條第一章普通入口必須升牆的舊預期失敗；raw與退出1保存在 superseded-rejected/。修正為普通門不建立碰撞／牆板、真實敵人成員存在、波次全倒才完成，並將生成設計資料的 wave_zone 與 lock 分開。地圖重測1,412項，0新／已知失敗、退出0；只生成設計資料，實際地圖、遭遇成員、資源未改。中途變數範圍解析錯誤亦原樣保留，該輪不算通過。

24 檔版本已由原始 changed selector 選取 ALL，81 群組確實分派並逐一執行，58,494 檢查，0 新／已知失敗、0 SCRIPT／Parse／Compile Error，原 runner 退出 0。三份 raw shard 分別為 10,220／34,796／13,478 檢查；原 runner 未另外保存各 child 退出碼，不補造。執行前、匯入後及測試後的 24 檔 LF audit 相符，20,855 個 tracked 檔案無變動；runner、selector、known failures 原樣保留。


原生 85 項、局部存檔 531 項與八張圖屬原 22 檔凍結版本，manifest 保留在 `superseded-rejected/source-manifest-native-narrow-v3.json`，其原生來源本身不是失敗證據。相較這份版本，24 檔增加地圖測試與設計清單，並更新設計生成器的 wave_zone／lock 標示；21 個原有來源（含正式玩法與地圖資源）相同。不能把 Cloud headless 當成新的原生畫面驗收，也不把安排的局部通行與保存測試當成完整序章／第一章或 Main 全流程遊測。

Cloud 五份原樣交付資料在 `cloud-git-delivery/`：manifest、summary、runtime，以及 v4 正式與 v3 拒收封包。v4 的 45 個、v3 的 59 個 tar 成員均為唯一、安全相對路徑的普通檔案；索引逐檔 bytes／SHA 相符。v4 索引本身由外層封包 SHA 綁定；v3 完整 import stdout 另由原 annex hash 綁定。v3 的 81 群組／58,456 檢查與四條舊升牆預期失敗、退出 1 完整保存，不列為通過。這與本機較早的 58,429／4 失敗為不同輪次。

Cloud 第一次 import 雖退出 0，仍有四條 TCP socket ERROR；原始 stdout／stderr 與 errno=1 EPERM 診斷完整保留。取得 managed network permission 後沿原指令重試同一份 cached import，退出 0、無 ERROR／SCRIPT／Parse／Compile Error，來源未改。最終測試 raw 有既有容錯負控制與引擎退出資源診斷；原 runner 依既有規則接受，全部 raw 仍保存，不寫成「raw 無 ERROR」。

實際 cgroup 配額為 4 CPU、16 GiB；nproc=5 不代表 5 CPU 配額。187 份記憶體樣本與 runtime 的 oom／oom_kill／oom_group_kill 均為 0。runner 的 cgroup memory.current 峰值 17,178,742,784 bytes 接近配額，含大量 file cache；process-group RSS 峰值為 2,168,639,488 bytes。這是採樣與 cgroup 記錄，不能宣稱沒有記憶體壓力或額外未採樣的峰值。

完成文件由嚴格 24 檔 LF guard 後更新；任何後續票對共用測試或來源的改動須另行驗證，不沿用這份 ALL 通過結果。`source-manifest.json` 始終保留原 24 檔，禁止再執行會回寫為 22 檔的舊 finalize_local.py。所有附件與八張原圖的 bytes／SHA 在 `evidence-index.json`。
