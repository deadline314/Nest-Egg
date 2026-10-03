class_name WeaponBar
extends VBoxContainer
## HUD 的武器欄：每個武器欄一列（欄號、彈種圖示、名稱、彈匣／備彈），手上武器高亮。
## 空欄位暗淡；彈匣用完時圖示變成空槽、不到四分之一時變紅。滑鼠移到那一列顯示武器說明。

const ROW_SIZE := Vector2(172, 18)
const LOW_RATIO := 0.25

var _rows: Array[_Row] = []


func _ready() -> void:
	add_theme_constant_override(&"separation", 2)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for slot in Loadout.MAX_SLOTS:
		var row := _Row.new()
		row.slot = slot
		add_child(row)
		_rows.append(row)


## 依目前的武器配置更新所有列。
func update_from(loadout: Loadout) -> void:
	for row in _rows:
		var weapon := loadout.weapon_in(row.slot)
		row.weapon = weapon
		row.active = weapon != null and row.slot == loadout.active_slot
		if weapon == null:
			row.ammo_text = ""
			row.state = AmmoIcons.State.EMPTY
			row.tooltip_text = "撿取武器後放在這裡；滾輪或數字鍵切換"
		else:
			var reserve := loadout.reserve_in(row.slot)
			if weapon.has_magazine():
				var mag := loadout.mag_in(row.slot)
				row.ammo_text = "%d/%s" % [mag, "∞" if reserve < 0 else str(reserve)]
				row.state = _state_for(mag, weapon.magazine_size)
			else:
				row.ammo_text = "∞"
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
	var ammo_text := ""
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
		var icon := AmmoIcons.for_weapon(weapon, state)
		var tint := Color.WHITE if active else Color(1, 1, 1, 0.6)
		draw_texture_rect(icon, Rect2(Vector2(20, 2), AmmoIcons.CELL), false, tint)
		var color := weapon.color if active else Palette.UI_MUTED
		draw_string(font, Vector2(34, 13), weapon.short_name if not weapon.short_name.is_empty() else weapon.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, 70, UiKit.FS_BODY, color)
		var ammo_color := Palette.UI_TEXT if state == AmmoIcons.State.FULL else Palette.DANGER
		draw_string(font, Vector2(size.x - 6 - 68, 13), ammo_text, HORIZONTAL_ALIGNMENT_RIGHT, 68, UiKit.FS_BODY, ammo_color if active else Color(ammo_color, 0.7))
