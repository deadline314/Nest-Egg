class_name Spikes
extends Node2D
## 尖刺：接觸受傷並往上彈開。rect 為像素範圍（尖刺貼在格子底部）。

const DAMAGE := 1
const HEIGHT_RATIO := 0.5
const KNOCKBACK := Vector2(90, -260)

var rect := Rect2()


func setup(p_rect: Rect2) -> void:
	rect = p_rect


func _ready() -> void:
	LightKit.mark_emissive(self)
	position = rect.position
	var height := rect.size.y * HEIGHT_RATIO
	var hitbox := ContactHitbox.new()
	add_child(hitbox)
	hitbox.setup(Combat.Team.ENEMY, DAMAGE, &"spikes", Vector2(rect.size.x - 2.0, height - 2.0),
			Vector2(rect.size.x * 0.5, rect.size.y - height * 0.5))
	hitbox.knockback_override = KNOCKBACK


func _draw() -> void:
	var height := rect.size.y * HEIGHT_RATIO
	var count := maxi(1, int(rect.size.x / 6.0))
	var width := rect.size.x / count
	for i in count:
		var x := i * width
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, rect.size.y), Vector2(x + width * 0.5, rect.size.y - height), Vector2(x + width, rect.size.y),
		]), Palette.TERRAIN_TOP)
		draw_line(Vector2(x + width * 0.5, rect.size.y - height), Vector2(x + width * 0.5, rect.size.y - height + 2),
				LightKit.glow(Palette.DANGER, 1.5), 1.0)
