# NE-256：原生跳躍餘裕與量測修正

基準 `d851153e281afe709a1cc19a3ca91f7813d82cd1`；Godot 4.7.2、Forward+、RX 9070 XT。本次是部分交付：第二項動作／前方視野已有實證；第三項自然走完第一章各區、比較畫外受擊仍未完成，不以格網擺位或故事探針代替。

`python verify_archives.py` 只用標準庫，實讀兩卷所有成員並核對 SHA，重算日誌門檻、來源前後一致、三舞台實際變換及已知負控；不解壓到任意路徑。原始 PNG 可從 tar.gz 讀取。manifest 列每一檔，不修改失敗的退出碼或原始說明。

## 有效結果

- 六地點原生720p：主角230～232px／31.9%～32.2%；1080p：346～347px／32.0%～32.1%。前方301～303世界像素；舊wide同位置約25%、299。wide因不符合新31%門檻而自然exit1是預期控制，不是畫面無法生成。
- 原生公開移動／跳躍／轉身／上下瞄準：六點最小上緣28、最小左右59、最小下緣48設計像素；平移最高576px/s。既有門檻仍24px／620px/s。動態探針用既有無敵介面隔離受擊擊退、hitstop和震動；這不驗證遊戲的實際受傷震動。正式產品只把垂直偏移及同一fallback -40改-43。
- 十區格網：97落差、37單向平台；37個平台端點都可見，向下瞄準仍有46個格網落點不可見，與原current相同。格網含深井及非通行路徑，不能宣稱所有自然跳躍都驗過。敵人樣本可自行移動，不能用兩次隨機計數證明畫外受擊沒有增加。
- 原 `prologue_play_probe` 從真Main用實際操作輸入完成全部練習並走入當鋪，0失誤；修正一項過期斷言後，原 `ch1_flow_probe` 71項全過、0失誤。後者依真劇本互動，但含擺位及機關事件，不是自然整章戰鬥。
- 鷺／診間醒來／回家，三場各current及wide：真CutscenePlayer stage位置、倍率、holder變換、圖層58、follow_viewport=false逐值相同；底下LevelCamera確實1.92與1.5不同。私有v2只明示安排completed再走既有不寫進度的Story.replay。這是過場構圖控制，不是自然觸發／完成條件驗收。
- 正式 `run_tests_changed.sh d851153e...`：27群組、48,991checks、新失敗0、已知0、736秒，自然exit0。原三份候選來源SHA保持。其後只改兩個獨立開發工具：選擇器挑0既有套件，各以最終工具真實完整執行驗證；不冒稱這兩項有被前27套件載入。

## 保留的失敗與適用範圍

原三個正常原生動態重現及固定fps整組失敗均保留；私有無敵控制證明平移異常來自受擊，但頭頂20～21px仍不過24px，所以需要3px校準。私有instrumented／controlled部分request承襲了「unmodified」字樣，以及若干driver末行承襲「six stage」說明，僅為舊標籤；實際CLI、完整私有來源、來源hash、退出碼及原生log才界定當次執行，這些私有修改不冒稱原工具未改。

v1直接Story.play的鷺／回家因先決旗標不足拒播，舞台guard自然exit1；醒來才是有效舞台。全部失敗圖仍保留，沒有以這些圖判構圖通過。v2不帶舞台的對話亦被真replay API拒絕、自然exit1。

原camera_walk部分執行雖exit0，結尾仍有20ObjectDB/6resources或34ObjectDB/12resources；該輪不作乾淨通過依據。verbose診斷偶爾自然乾淨，支持程序收尾時序的定位。單因子私有控制只加既有AudioRelease.settle，current及wide十區均無ERROR／洩漏；最終公開工具current亦自然0、EOF乾淨，量測流程不變。

原故事工具硬寫第二死4步，但當前NE-274劇本明定第一死4、第二死3、第三死2，因此原完整跑失敗1。最小修正要求實際deaths==2、畫面sequence與當前章節第二死完整定義逐值一致，保留復原旗標，沒有放寬為只要有畫面就過；最終自然0、無ERROR。

正式27群組原始shard保留0 SCRIPT ERROR及既有負測試ERROR；shard1結尾仍有1CanvasItem／9ObjectDB／5resources診斷，未冒稱所有raw log乾淨。`source-freeze`存原git基準及最終五份來源；官方執行中另外新增未被套件載入的私有構圖fixture，`private-source/root-debug/isolated-source-after.json`明列此事，不能把三檔SHA保持寫成整棵worktree狀態完全未變。

兩卷包括所有主要原生圖、失敗歷史、主stdout/shard、CLI、來源前後及結果；不包含新建private-profile資料夾和官方runner合成user-data測試檔。未碰玩家原存檔。四張公開PNG是原檔複製，沒有縮圖冒充原生解析度。

父讀者重驗430成員／0失敗；另將隔離副本第一卷截成1024bytes，讀者自然exit1拒絕，原兩卷未動。首版讀者在實讀SHA後，因未容納原生CRLF行尾而在數字解析產生假失敗；只修正行尾正規式後全數通過，原始log與判定門檻沒有修改。
