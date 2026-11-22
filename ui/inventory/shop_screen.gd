class_name ShopScreen
extends InventoryScreen
## 補給點畫面沿用背包的版面與操作，依櫃台功能切換分頁。由補給點開啟。
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
	return shop.display_name if shop != null else Labels.get_text(&"counter_title")


func _opens_with_key() -> bool:
	return false


func _legend_template() -> String:
	var tabs_hint := "　" + Labels.get_text(&"tabs") if _pages.size() > 1 else ""
	var key := &"shop_pad" if InputBindings.using_gamepad else &"shop_keys"
	return Labels.get_text(key) % tabs_hint


## 空櫃台沿用空貨架畫面，玩家仍可離開。
func _build_pages() -> Array[InventoryPage]:
	var pages: Array[InventoryPage] = []
	if shop == null or not shop.stock.is_empty() or not (shop.pawn or shop.workbench):
		var page := ShopPage.new()
		page.shop = shop
		pages.append(page)
	if shop != null and shop.pawn:
		pages.append(PawnPage.new())
	if shop != null and shop.workbench:
		pages.append(UpgradesPage.new())
	return pages
