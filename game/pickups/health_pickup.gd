class_name HealthPickup
extends Pickup
## 回復道具：回復生命（滿血時不會被吃掉）。

const HEAL_AMOUNT := 2


func hint_text() -> String:
	return "修復裝甲 +%d" % HEAL_AMOUNT


func _apply(player: Player) -> bool:
	return player.health.heal(HEAL_AMOUNT) > 0


func _draw_icon() -> void:
	var glow := LightKit.glow(Palette.CYAN, 1.8 + 0.4 * sin(_time * 6.0))
	draw_rect(Rect2(-5, -5, 10, 10), Color(Palette.UI_PANEL, 0.9))
	draw_rect(Rect2(-5, -5, 10, 10), glow, false, 1.0)
	draw_line(Vector2(-3, 0), Vector2(3, 0), glow, 2.0)
	draw_line(Vector2(0, -3), Vector2(0, 3), glow, 2.0)
