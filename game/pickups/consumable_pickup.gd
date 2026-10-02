class_name ConsumablePickup
extends Pickup
## 消耗品道具：放進背包；已達攜帶上限時保留在原地並提示一次。

var item: ConsumableData
var _full_notified := false


func configure(p_item: ConsumableData) -> void:
	item = p_item


func hint_text() -> String:
	return "%s：%s" % [item.display_name, item.description] if item != null else ""


func _ready() -> void:
	if item == null:
		push_error("[ConsumablePickup] 未指定 ConsumableData，已移除。")
		queue_free()
		return
	super._ready()
	body_exited.connect(func(_body: Node2D) -> void: _full_notified = false)


func _apply(player: Player) -> bool:
	if player.consumables.add(item):
		EventBus.toast_requested.emit("取得 %s（%d/%d）" % [item.display_name, player.consumables.count(item.id), item.max_carry])
		return true
	if not _full_notified:
		_full_notified = true
		EventBus.toast_requested.emit("%s 已達上限 %d" % [item.display_name, item.max_carry])
	return false


func _draw_icon() -> void:
	var glow := LightKit.glow(item.color, 1.8 + 0.4 * sin(_time * 6.0))
	var body := Rect2(-3, -6, 6, 11)
	draw_rect(body, Color(Palette.UI_PANEL, 0.9))
	draw_rect(body, glow, false, 1.0)
	if item.restores_guard:
		# 電池：上方電極與中間的閃電。
		draw_rect(Rect2(-1.5, -8, 3, 2), glow)
		draw_polyline(PackedVector2Array([Vector2(1, -4), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 4)]), glow, 1.0)
	else:
		# 醫療針：針頭與藥劑。
		draw_line(Vector2(0, -6), Vector2(0, -9), glow, 1.0)
		draw_rect(Rect2(-2, -2, 4, 6), Color(glow, 0.8))
