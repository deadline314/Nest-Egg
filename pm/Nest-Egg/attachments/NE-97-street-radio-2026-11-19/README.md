# NE-97 第一章街道通訊時機

固定比較基準 `1f2e744632a1795acb60d4089b35cc71d55974dd`。兩次使用同一份從實際 Main 產生的隔離存檔，正常難度、6 HP、0 死亡。原執行先用遊戲操作完成序章，再走到廚房、屋頂聽簡報、實際啟動電話亭並回街道。保存內容可在 [證據包](evidence.zip) 的 `fixture/slot.json` 讀取。正式重播點真正的 Continue 按鈕，移動、跳躍及通訊確認走既有輸入；不覆寫角色位置、世界旗標或敵人血量。

Godot 4.7.2、RX 9070 XT Vulkan Forward+，同樣 1280 × 720。`before-radio-v2` 與 `after-radio` 的 `report.json` 分別保留通訊穩定顯示後的腳底接地、位置與垂直速度。兩次皆讀完通訊、攀上四段地形到第一場戰鬥前。正式選擇器固定用上述基準，53 套 58,903 項，0 新失敗、0 已知失敗。`native-combat-v2` 與 `native-blockade-v3` 再用正式敵人與普通難度走完街道，後一程序從前一程序真的保存的進度接續。原路障波次寫入通行後，從原出口進倉庫。兩章完整通關仍屬 NE-97 的獨立驗收。

重跑時把 `fixture/slot.json` 複製到新的隔離存檔目錄，依 `command.json` 調整 Godot、專案與輸出絕對路徑。解壓後的 `route.tscn` 指向同資料夾的 `route.gd`。使用 `--from-save --street --landmark-only`，原本跑序章用的選項可留空。依專案慣例使用獨立設定資料夾和既有 GPU 鎖。
