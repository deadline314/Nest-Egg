# 來源圖匯入範圍

只新增兩個來源資料夾的`.gdignore`，移除三個未被遊戲引用的來源`.png.import`；原圖、遮罩、prompt、Python重建與正式runtime部件／法線的匯入資料保留。全部來源與runtime PNG的SHA逐檔相同。game／autoload／ui／data沒有這兩個來源目錄的res路徑依賴。

實際editor import退出0、無ERROR，來源import紀錄未再生成。原`run_tests_changed.sh ed6c40a7`判定沒有受影響的遊戲測試，因此依原規則不追加測試；沒有修改選擇器。角色獨立樹的6763項回歸與先前4800接點證據保留。
