class_name WeaponBar
extends VBoxContainer
## HUD 的武器欄：每個武器欄一列（欄號、槍的圖示、名稱），手上武器高亮。不顯示子彈數量：
## 子彈常駐在主角身旁（見 AmmoTray）。空欄位暗淡；滑鼠移到那一列顯示武器說明。
## 彈匣狀態（滿、低量、空）仍記在每一列的 state（供測試與其他介面查詢），近戰武器與沒有槍外觀的武器用彈種圖示。

const ROW_SIZE := Vector2(132, 18)
const LOW_RATIO := 0.25

## 主角和武器欄真的重疊時（例如站在畫面左下角的低處），武器欄讓位變淡，不蓋住腳邊（NE-264）。
const MAKE_WAY_ALPHA := 0.3
const MAKE_WAY_SPEED := 5.0
## 主角在畫面上佔的範圍（相對腳底的世界座標）。
const PLAYER_BOX := Rect2(-12, -60, 24, 62)

var _rows: Array[_Row] = []
var _player_ref := PlayerRef.new()


func _ready() -> void:
	add_theme_constant_override(&"separation", 2)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for slot in Loadout.MAX_SLOTS:
		var row := _Row.new()
		row.slot = slot
		add_child(row)
		_rows.append(row)


func _process(delta: float) -> void:
	var target := 1.0
	var player := _player_ref.get_player(get_tree())
	if player != null and is_visible_in_tree():
		var to_screen := get_viewport().get_canvas_transform()
		var feet := to_screen * (player.global_position + PLAYER_BOX.position)
		var box := Rect2(feet, PLAYER_BOX.size * to_screen.get_scale())
		if box.intersects(get_global_rect()):
			target = MAKE_WAY_ALPHA
	modulate.a = move_toward(modulate.a, target, delta * MAKE_WAY_SPEED)


## 目前是否在讓位（測試與截圖用）。
func is_making_way() -> bool:
	return modulate.a < 0.99


## 依目前的武器配置更新所有列。
func update_from(loadout: Loadout) -> void:
	for row in _rows:
		var weapon := loadout.weapon_in(row.slot)
		row.weapon = weapon
		row.active = weapon != null and row.slot == loadout.active_slot
		if weapon == null:
			row.state = AmmoIcons.State.EMPTY
			row.tooltip_text = "撿取武器後放在這裡；滾輪或數字鍵切換"
		else:
			if weapon.has_magazine():
				row.state = _state_for(loadout.mag_in(row.slot), weapon.magazine_size)
			else:
				row.state = AmmoIcons.State.FULL
			row.tooltip_text = weapon.description
		row.queue_redraw()


func row_count() -> int:
	return _rows.size()


func row_state(slot: int) -> AmmoIcons.State:
	return _rows[slot].state if slot >= 0 and slot < _rows.size() else AmmoIcons.State.EMPTY


static func _state_for(mag: int, capacity: int) -> AmmoIcons.State:
	if mag <= 0:
		return AmmoIcons.State.EMPTY
	if float(mag) / float(maxi(1, capacity)) <= LOW_RATIO:
		return AmmoIcons.State.LOW
	return AmmoIcons.State.FULL


class _Row:
	extends Control

	var slot := 0
	var weapon: WeaponData
	var active := false
	var state: AmmoIcons.State = AmmoIcons.State.EMPTY

	func _init() -> void:
		custom_minimum_size = WeaponBar.ROW_SIZE
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var font := UiKit.font()
		var muted := Color(Palette.UI_MUTED, 0.5)
		if active:
			var box := ChamferBox.make(Color(Palette.UI_PANEL_HI, 0.85), Palette.CYAN_DIM, 3)
			box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
			draw_rect(Rect2(0, 3, 2, size.y - 6), Palette.CYAN)
		draw_string(font, Vector2(7, 13), str(slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, Palette.CYAN if active else muted)
		if weapon == null:
			draw_string(font, Vector2(24, 13), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, muted)
			return
		var tint := Color.WHITE if active else Color(1, 1, 1, 0.6)
		var gun := WeaponIcons.texture(weapon)
		if gun != null:
			var fitted := WeaponIcons.fit(gun)
			draw_texture_rect(gun, Rect2(Vector2(20, 2) + fitted.position, fitted.size), false, tint)
		else:
			draw_texture_rect(AmmoIcons.for_weapon(weapon, state), Rect2(Vector2(28, 2), AmmoIcons.CELL), false, tint)
		var color := weapon.color if active else Palette.UI_MUTED
		draw_string(font, Vector2(54, 13), weapon.short_name if not weapon.short_name.is_empty() else weapon.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, 70, UiKit.FS_BODY, color)
