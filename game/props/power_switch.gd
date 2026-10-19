class_name PowerSwitch
extends MechanismSwitch
## 電力開關：切斷（active = true）或恢復所在區域的電力。斷電的區域熄燈，雷射柵欄、砲台與升降梯停擺。
## 區域範圍由 MechanismData.power_range_tiles 決定；啟動時向電力網登記。


func _ready() -> void:
	super._ready()
	if data == null:
		return
	var grid := PowerGrid.of(self)
	if grid == null:
		push_warning("[PowerSwitch] 找不到電力網，開關不會有作用：%s" % state_key())
		return
	grid.register_zone(data.channel, cell.x - data.power_range_tiles.x, cell.x + data.power_range_tiles.y + 1, data.blackout_profile)


func _apply(is_active: bool, silent: bool) -> void:
	var grid := PowerGrid.of(self)
	if grid == null:
		return
	grid.set_zone_powered(data.channel, not is_active, silent)
	if not silent:
		EventBus.toast_requested.emit("電力已切斷：區域熄燈、保全停擺" if is_active else "電力恢復")
		Sfx.play(&"power_down" if is_active else &"power_up", -2.0)


func _art_prefix() -> StringName:
	return &"power_switch"


func _art_rect() -> Rect2:
	return Rect2(-11, -28, 22, 28)


func _status_rect() -> Rect2:
	return Rect2(-2, -14, 4, 2)


func _status_color() -> Color:
	return Palette.DANGER if active else Palette.CYAN
