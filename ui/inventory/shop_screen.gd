class_name ShopScreen
extends InventoryScreen
## 補給點畫面：沿用背包的版面與操作，只有一個分頁（貨架）。由補給點開啟，不響應背包鍵。
## 關卡在死亡或過關時透過群組 OVERLAY_GROUP 一併關閉（見 Level._close_menus）。

const OVERLAY_GROUP := &"overlay_menu"

var shop: ShopData


func configure_shop(p_player: Player, p_shop: ShopData) -> void:
	configure(p_player)
	shop = p_shop


func _ready() -> void:
	super._ready()
	add_to_group(OVERLAY_GROUP)


func _screen_title() -> String:
	return shop.display_name if shop != null else "補給點"


func _opens_with_key() -> bool:
	return false


func _legend_template() -> String:
	if InputBindings.using_gamepad:
		return "{ui_cancel} 返回　{inventory_prev_tab}/{inventory_next_tab} 分頁　{ui_accept} 確認"
	return "{ui_cancel} 離開　{inventory_prev_tab}/{inventory_next_tab} 分頁　↑↓ 選擇　{ui_accept} 確認"


## 分頁依貨架的功能決定：有商品就有貨架、收購就有典當、工作檯就有改裝。
func _build_pages() -> Array[InventoryPage]:
	var pages: Array[InventoryPage] = []
	if shop == null or not shop.stock.is_empty():
		var page := ShopPage.new()
		page.shop = shop
		pages.append(page)
	if shop != null and shop.pawn:
		pages.append(PawnPage.new())
	if shop != null and shop.workbench:
		pages.append(UpgradesPage.new())
	return pages
