# 任務地圖索引的交付核對

任務指引使用由關卡及圖例資源產生的地圖資料。Godot 開發版會驗證來源的摘要。任一摘要過期時，當次指引改由完整關卡資料建立。這會讓含有舊摘要的專案在不同章節啟動時都需要付出額外的載入成本。

關卡或圖例資源改動後，在最後要交付的來源組合執行索引檢查。需要更新時，使用同一份專案重新產生索引，再檢查結果。新增、修改和已暫存的刪除都要觸發地圖驗證。

```sh
godot --headless --path . res://tools/build_level_index.tscn
godot --headless --path . res://tools/build_level_index.tscn -- --check
```
