class_name CreditPickup
extends Pickup
## 信用點：撿起增加持有金額。地圖上放的信用點堆（有 cell）撿過後存進檢查點，重生不會再出現；
## 敵人與箱子掉的（沒有 cell）是一次性的。

var value := 10
var color := Color(1.0, 0.82, 0.25)
## 地圖上的所在格；Vector2i(-1, -1) 代表不是地圖放置的（掉落物），不存進檢查點。
var cell := Vector2i(-1, -1)
var collected := false


func configure_pile(pile: CreditPileData, p_cell: Vector2i) -> void:
	value = pile.value
	color = pile.color
	cell = p_cell


func hint_text() -> String:
	return ""


func _ready() -> void:
	super._ready()
	if cell != Vector2i(-1, -1):
		add_to_group(WorldState.GROUP)


func _apply(_player: Player) -> bool:
	Progression.add_credits(value)
	collected = true
	return true


## 地圖上的信用點堆撿過後保留節點（才能存進檢查點）；掉落物直接移除。
func _consume() -> void:
	if cell == Vector2i(-1, -1):
		queue_free()
		return
	visible = false
	set_process(false)
	set_deferred(&"monitoring", false)


func _fx_color() -> Color:
	return color


func _fx_kind() -> StringName:
	return &"credit"


func _draw_icon() -> void:
	var glow := LightKit.glow(color, 1.8 + 0.4 * sin(_time * 6.0))
	var chip := PackedVector2Array([Vector2(0, -5), Vector2(4, 0), Vector2(0, 5), Vector2(-4, 0)])
	draw_colored_polygon(chip, Color(color.darkened(0.55), 0.9))
	draw_polyline(chip + PackedVector2Array([chip[0]]), glow, 1.0)
	draw_line(Vector2(0, -2), Vector2(0, 2), glow, 1.0)


func state_key() -> String:
	return "credits@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return collected


func restore_state(state: Variant) -> void:
	if state == true and not collected:
		collected = true
		_consume()
