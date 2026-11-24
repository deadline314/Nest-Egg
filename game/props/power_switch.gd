class_name PowerSwitch
extends MechanismSwitch
## 電力開關：切斷（active = true）或恢復所在區域的電力。斷電的區域熄燈，雷射柵欄、砲台與升降梯停擺。
## 區域範圍由 MechanismData.power_range_tiles 決定；啟動時向電力網登記。


const RESTORE_HINT: Dictionary[String, String] = {
	"en": "{interact} Restore power and rearm security.",
	"ja": "{interact} 電源を復旧：照明と警備が再起動する",
}
const POWER_CUT: Dictionary[String, String] = {
	"en": "Power cut. Lights and security are offline.",
	"ja": "電源を遮断。照明と警備が停止した。",
}
const POWER_RESTORED: Dictionary[String, String] = {
	"en": "Power restored.",
	"ja": "電源が復旧した。",
}


func _ready() -> void:
	super._ready()
	if data == null:
		return
	var grid := PowerGrid.of(self)
	if grid == null:
		push_warning("[PowerSwitch] 找不到電力網，開關不會有作用：%s" % state_key())
		return
	grid.register_zone(data.channel, cell.x - data.power_range_tiles.x, cell.x + data.power_range_tiles.y + 1, data.blackout_profile)


func _hint_text() -> String:
	if active:
		return StoryLocale.optional_text(RESTORE_HINT, Story.language, "{interact} 恢復供電：照明與保全重新啟動")
	return super._hint_text()


func _apply(is_active: bool, silent: bool) -> void:
	var grid := PowerGrid.of(self)
	if grid == null:
		return
	grid.set_zone_powered(data.channel, not is_active, silent)
	if not silent:
		var notice := StoryLocale.optional_text(POWER_CUT, Story.language, "電力已切斷：區域熄燈、保全停擺") if is_active \
			else StoryLocale.optional_text(POWER_RESTORED, Story.language, "電力恢復")
		EventBus.toast_requested.emit(notice)
		Sfx.play(&"power_down" if is_active else &"power_up", -2.0)


func _art_prefix() -> StringName:
	return &"power_switch"


func _art_rect() -> Rect2:
	return Rect2(-11, -28, 22, 28)


func _status_rect() -> Rect2:
	return Rect2(-2, -14, 4, 2)


func _status_color() -> Color:
	return Palette.DANGER if active else Palette.CYAN
