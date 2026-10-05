class_name CollectiblePickup
extends Pickup
## 文件與錄音（背景故事收集品）：撿起放進背包的劇情道具分頁，並顯示本章收集進度。
## 已經取得的不會再出現（收集跟著本輪進度，不隨檢查點回溯）；錄音撿到時可以播放一段通訊。

var item: StoryItemData


func configure(p_item: StoryItemData) -> void:
	item = p_item


func hint_text() -> String:
	return "%s：%s" % [item.display_name, item.description] if item != null else ""


func _ready() -> void:
	# 文件與錄音，或在關卡裡撿的關鍵道具（取得時機 MANUAL，例如資料盤）。
	if item == null or not (item.is_collectible() or item.trigger == StoryItemData.Trigger.MANUAL):
		push_error("[CollectiblePickup] 沒有指定文件、錄音或可撿取的關鍵道具資料，已移除。")
		queue_free()
		return
	super._ready()


func _apply(_player: Player) -> bool:
	if not StoryItems.acquire(item.id):
		# 已經有了（例如其他途徑取得）：直接消失，不再提示。
		return true
	if item.play_scene != &"":
		Story.play(item.play_scene)
	return true


func _fx_color() -> Color:
	return item.color if item != null else Palette.CYAN


func _fx_kind() -> StringName:
	return &"story"


func _draw_icon() -> void:
	if _draw_world_sprite(item.icon):
		return
	var glow := LightKit.glow(item.color, 1.8 + 0.4 * sin(_time * 5.0))
	if item.category == StoryItemData.Category.RECORDING:
		# 錄音晶片：小方塊加音波。
		draw_rect(Rect2(-4, -5, 8, 10), Color(Palette.UI_PANEL, 0.9))
		draw_rect(Rect2(-4, -5, 8, 10), glow, false, 1.0)
		for i in 3:
			var h := 2.0 + 2.0 * absf(sin(_time * 6.0 + i))
			draw_line(Vector2(-2 + i * 2.0, -h * 0.5), Vector2(-2 + i * 2.0, h * 0.5), glow, 1.0)
	else:
		# 文件：折角的紙。
		var page := PackedVector2Array([Vector2(-4, -6), Vector2(2, -6), Vector2(5, -3), Vector2(5, 6), Vector2(-4, 6)])
		draw_colored_polygon(page, Color(Palette.UI_PANEL, 0.9))
		draw_polyline(page + PackedVector2Array([page[0]]), glow, 1.0)
		for y in [-2.0, 0.5, 3.0]:
			draw_line(Vector2(-2, y), Vector2(3, y), Color(glow, 0.7), 1.0)
