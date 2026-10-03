class_name InventoryEntry
extends RefCounted
## 背包清單中的一個項目（武器、消耗品、劇情道具共用的顯示資料）。
## 各分頁把遊戲資料轉成 InventoryEntry，清單與詳情面板只認這個格式，新增分頁不必改版面程式。

var id: StringName = &""
var title := ""
## 卡片第二行（例如「12／∞　實彈」）。
var subtitle := ""
var accent := Palette.CYAN
var icon: Texture2D
## 卡片上與詳情面板上圖示的整數放大倍數。
var card_icon_scale := 1
var detail_icon_scale := 3
## 卡片右上角的小標籤（NEW、手上、×2…），空字串不顯示。
var badge := ""
var badge_color := Palette.CYAN
## 彈種圖示（武器卡片用，null 不顯示）。
var ammo_icon: Texture2D
## 沒有內容的項目（空欄位、數量 0）：整張卡片變暗。
var dimmed := false
## 一句重點說明：卡片 tooltip 與畫面底部說明列都用這句。
var hint := ""
## 詳情面板
var detail_tag := ""
var detail_stats: PackedStringArray = []
var detail_body := ""
## 動作按鈕文字；空字串代表沒有可執行的動作（不顯示按鈕）。
var action_label := ""
var action_enabled := true
var action_hint := ""
