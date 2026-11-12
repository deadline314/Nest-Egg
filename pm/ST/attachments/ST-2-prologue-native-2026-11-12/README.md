# ST-2：序章兩處翻譯的真實新遊戲畫面

本機Godot4.7.2／Forward+／Vulkan／RX9070XT，以各自獨立設定與存檔啟動真正Main新遊戲，經原序章入口播放ch1_p01_door；JA／EN各保存完整旁白與標題副標。原步驟、節奏、舞台、光影、字型及UI縮放不變，沒有安排旗標或玩家位置。觀察節點ALWAYS、Main維持正常PAUSABLE；畫面完整後才讀取，兩格讀完後正常收尾，不代稱完整通關。

四張1280×720原PNG已由主協調逐張檢視，日文旁白與「巣卵質店」、英文旁白與「Nest Egg Pawnshop」完整可讀；標題、文字與副標沒有裁切或縮字。既有Esc中文提示仍屬原UI範圍，不是全UI三語或母語審稿驗收。

兩程序自然exit0，0警告／ERROR／腳本錯誤／退出洩漏。C387/v20、D8682份執行依賴及原七檔、四個producer前後逐SHA一致，原始guard相同bytes只存一次；不把較晚v21回填。外／內鎖前後都是真0/0queue與另一port真10061，使用canonical非阻塞主鎖、不操作他專案服務。同期ST3有兩個headless程序，因此本包只作功能／畫面證據。

單層原包包含四張原PNG、四份真正RGBH/HDR raw、來源、命令、原log與退出、queue、guard、CPU反例及原讀取器。包長5,244,862B，SHA256：`2a5d151ba7aefaccb41ae52c128c33a0f45da73056bbf7c05ddd0c9c775be936`。兩份外附讀取器與ZIP內原件逐位元相同，不需來源worktree、引擎或網路：

```powershell
python -X utf8 pm/ST/attachments/ST-2-prologue-native-2026-11-12/readers/verify_index.py pm/ST/attachments/ST-2-prologue-native-2026-11-12/ST2-native-proof.zip
python -X utf8 pm/ST/attachments/ST-2-prologue-native-2026-11-12/readers/verify_capture_precision.py pm/ST/attachments/ST-2-prologue-native-2026-11-12/ST2-native-proof.zip
```

第一份核對44份indexed原件、四格正式語系／場景／完整顯示／正常暫停與來源。第二份沿用既有NumPy/Pillow讀取器，逐一重算4×921600像素的原float到sRGB／alpha編碼。Root從公開位置重讀成功；這是原始資料驗證，不另出圖或重新啟引擎。四格的滿顯旁白到滿顯標題／副標相隔3304／3306ms，與原2.4秒hold、0.4秒out、0.5秒in對應；僅端點觀察，不宣稱逐幀ramp／效能量測。
