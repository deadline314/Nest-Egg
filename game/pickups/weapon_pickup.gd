class_name WeaponPickup
extends Pickup
## 武器道具：裝進特殊武器欄並補滿彈藥。

var weapon: WeaponData


func configure(p_weapon: WeaponData) -> void:
	weapon = p_weapon


func hint_text() -> String:
	if weapon == null:
		return ""
	return "%s：%s" % [weapon.display_name, weapon.description] if not weapon.description.is_empty() else weapon.display_name


func _ready() -> void:
	if weapon == null:
		push_error("[WeaponPickup] 未指定 WeaponData，已移除。")
		queue_free()
		return
	super._ready()


func _apply(player: Player) -> bool:
	player.loadout.equip(weapon)
	EventBus.toast_requested.emit("取得 %s" % weapon.display_name)
	return true


func _fx_color() -> Color:
	return weapon.color if weapon != null else Palette.CYAN


func _fx_kind() -> StringName:
	return &"weapon"


func _draw_icon() -> void:
	if _draw_world_sprite(world_icon_key()):
		return
	if weapon.is_melee():
		_draw_melee_icon()
		return
	var glow := LightKit.glow(weapon.color, 1.8 + 0.5 * sin(_time * 5.0))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)]),
			Color(Palette.UI_PANEL, 0.9))
	draw_polyline(PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0), Vector2(0, -7)]), glow, 1.0)
	draw_line(Vector2(-3, 0), Vector2(4, 0), glow, 2.0)
	draw_circle(Vector2(4, 0), 1.5, glow)


func world_icon_key() -> String:
	if weapon == null:
		return ""
	return str(weapon.id) if weapon.is_melee() else weapon.visual_id


## 近戰武器：同樣的菱形底座，中間放斜擺的武器剪影。
func _draw_melee_icon() -> void:
	var glow := LightKit.glow(weapon.color, 1.8 + 0.5 * sin(_time * 5.0))
	var frame := PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0), Vector2(0, -8)])
	draw_colored_polygon(frame, Color(Palette.UI_PANEL, 0.9))
	draw_polyline(frame, glow, 1.0)
	var scaled := minf(1.0, 11.0 / maxf(6.0, weapon.melee_length))
	draw_set_transform(Vector2(-4, 4), -PI * 0.25, Vector2.ONE * scaled)
	MeleeArt.draw(self, Vector2.ZERO, Vector2.RIGHT, weapon, 1.6)
	draw_set_transform(Vector2.ZERO)
