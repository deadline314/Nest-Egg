# 跟隨角色 HUD 的安全通道

NE-264補驗記錄，延續既有HUD排版與AMMO_TRAY_TEST_CLOCK，不把固定1/60的單元回歸當自然繪製。需求仍是完整顯示、不遮頭臉／瞄準、自然移動平滑與站立腳邊讓位。

直接在背側與頭頂位置之間lerp，會穿過真頭部；跳躍首格把移動中的名義guide硬投影到頭界，也會超過原每draw24px。完整備彈字形含shadow比原icon框更寬，僅clamp icon仍可能把文字裁掉。上瞄時以固定背側排版，還會跨過真槍口射線。

兩個既有caller共用HudPlacement.FollowState，快取真head drawable並在skin／rig／Player失效時重取，無find_children或每draw容器。完整head affine quad含AA、原字形／icon／plate範圍同時約束viewport及側向空間；空間不足走安全通道，不在最後clamp時被推回頭。guide保留字行緩衝，實際垂直清開且guide變化已可平滑跟上時才橫移；原大位移復位另外用actor／anchor判斷，不將路徑角點當傳送。

頭頂preferred位置依真head外緣向畫面內預留整列，避免上瞄首格臨時大投影。抬高瞄準選可用側並保持到該瞄準結束；轉回水平時，當前在槍口上側的Vitals沿上路、下側Ammo沿下路繞回。兩caller共用策略及速度，可以分層，並非強制永遠一起在頭頂。保留108／4／120、原字級與內容；不以23.9硬cap遮慢格，不淡出／隱藏HUD來通過。原published的完整weight是200ms，本次選擇weight與side各完整300ms以讓分段避讓可讀；總翻側包含各段及guide穩定，不能稱整段總300ms。

自然draw驗證保存public事件、首input前baseline、每個postdraw、真head texture alpha／transform／mip、原HDR ROI、logical與screen映射。full viewport只在真正保存全畫面時稱完整；局部ROI衍生圖一律標示。head以保守完整quad＋AA證明零交疊，ray以actual muzzle／aim的forward射線與整組primitive上界驗；非零交疊直接拒收。原紅與工具metadata錯誤分開保存。

實測720／1080×30／60、混合翻側起跳、首draw瞄準切換及公開射擊換彈均過；原affected22與最新main三suite接合分開記來源，不把註解不同的final檔SHA倒填native。詳[實際交付README與來源／raw索引](../../pm/Nest-Egg/attachments/NE-264-native-2026-11-12/README.md)。
