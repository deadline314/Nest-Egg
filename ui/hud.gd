class_name Hud
extends CanvasLayer
## 遊戲 HUD：完全透過 EventBus 更新，不持有任何遊戲物件參照（物件被移除也不會出錯）。
## 滑鼠移到各區塊上會顯示一句重點說明（tooltip）。
## 生命、護盾、彈藥改由動態元件顯示（跟著角色與準星），見 design/05-dynamic-hud。

const TOAST_TIME := 2.2
const CONTROLS_HINT_TIME := 14.0
## {動作} 會換成玩家目前設定的按鍵（見 InputBindings.format）。
const CONTROLS_TEMPLATE := "移動 {move_left}/{move_right}　跳 {jump}　射擊 {shoot}　格擋 {block}　衝刺 {dash}　終結 {melee}　換彈 {reload}　換武器 {weapon_next}／1～4　搭乘 {interact}　背包 {inventory}　暫停 {pause}"

var vitals_tag: VitalsTag
var ammo_ring: AmmoRing
var _gauges: _Gauges
var weapon_bar: WeaponBar
var _items_label: Label
var _lives_label: Label
var _timer_label: Label
var _credits_label: Label
var _cyber_gauge: _CyberGauge
var _credits_tween: Tween
var _boss_name: Label
var _toast: Label
var _controls: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 10
	var root := UiKit.full_rect_root(self)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_gauges = _Gauges.new()
	_gauges.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_gauges)

	_lives_label = UiKit.label("", 10, Palette.UI_MUTED)
	_lives_label.position = Vector2(12, 6)
	root.add_child(_lives_label)

	weapon_bar = WeaponBar.new()
	weapon_bar.position = Vector2(12, 262)
	root.add_child(weapon_bar)

	vitals_tag = VitalsTag.new()
	root.add_child(vitals_tag)
	_items_label = UiKit.label("", 10, Palette.UI_MUTED)
	_items_label.position = Vector2(12, 254)
	_items_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_items_label.tooltip_text = "攜帶的消耗品；快速鍵使用醫療針，其他在背包使用"
	root.add_child(_items_label)

	add_child(Crosshair.new())
	ammo_ring = AmmoRing.new()
	add_child(ammo_ring)

	_timer_label = UiKit.label("00:00.00", 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer_label.position = Vector2(528, 8)
	_timer_label.size = Vector2(100, 16)
	root.add_child(_timer_label)

	_credits_label = UiKit.label("", 11, Palette.NEON_YELLOW, HORIZONTAL_ALIGNMENT_RIGHT)
	_credits_label.position = Vector2(528, 22)
	_credits_label.size = Vector2(100, 16)
	_credits_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_credits_label.tooltip_text = "信用點：撿取與擊敗敵人取得，在背包改裝武器"
	root.add_child(_credits_label)

	_cyber_gauge = _CyberGauge.new()
	_cyber_gauge.position = Vector2(508, 40)
	_cyber_gauge.size = Vector2(120, 22)
	_cyber_gauge.visible = false
	_cyber_gauge.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_cyber_gauge)

	_boss_name = UiKit.label("", 11, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_name.position = Vector2(170, 4)
	_boss_name.size = Vector2(300, 16)
	_boss_name.visible = false
	root.add_child(_boss_name)

	_toast = UiKit.label("", 14, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.position = Vector2(0, 64)
	_toast.size = Vector2(640, 20)
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_controls = UiKit.label(controls_hint(), 9, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	# 先開啟折行再設定尺寸，否則單行文字會把寬度撐開。
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls.custom_minimum_size = Vector2(500, 0)
	_controls.position = Vector2(130, 330)
	_controls.size = Vector2(500, 26)
	root.add_child(_controls)
	var fade := create_tween()
	fade.tween_interval(CONTROLS_HINT_TIME)
	fade.tween_property(_controls, "modulate:a", 0.0, 1.0)

	EventBus.player_loadout_changed.connect(_on_loadout_changed)
	EventBus.player_consumables_changed.connect(_on_consumables_changed)
	EventBus.vehicle_mounted.connect(_on_vehicle_mounted)
	EventBus.vehicle_dismounted.connect(_on_vehicle_dismounted)
	EventBus.vehicle_health_changed.connect(_on_vehicle_health_changed)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.toast_requested.connect(show_toast)
	EventBus.lives_changed.connect(_on_lives_changed)
	InputBindings.bindings_changed.connect(_refresh_controls)
	EventBus.player_cyber_changed.connect(_on_cyber_changed)
	Progression.credits_changed.connect(_on_credits_changed)
	_on_credits_changed(Progression.credits, 0)
	_on_lives_changed(GameState.lives_left)


func _refresh_controls() -> void:
	_controls.text = controls_hint()


static func controls_hint() -> String:
	return InputBindings.format(CONTROLS_TEMPLATE)


func _process(_delta: float) -> void:
	_timer_label.text = UiKit.format_time(GameState.run_time)


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_credits_changed(credits: int, delta: int) -> void:
	_credits_label.text = "¥ %d" % credits
	if delta == 0:
		return
	# 增加時閃一下金色，花費時閃一下紅色。
	if _credits_tween != null and _credits_tween.is_valid():
		_credits_tween.kill()
	_credits_label.add_theme_color_override(&"font_color", Palette.WHITE if delta > 0 else Palette.DANGER)
	_credits_tween = create_tween()
	_credits_tween.tween_interval(0.12)
	_credits_tween.tween_callback(func() -> void: _credits_label.add_theme_color_override(&"font_color", Palette.NEON_YELLOW))


func _on_cyber_changed(charge: float, ready: bool, ability_name: String, progress: float) -> void:
	_cyber_gauge.visible = not ability_name.is_empty()
	_cyber_gauge.update_state(charge, ready, ability_name, progress)
	_cyber_gauge.tooltip_text = InputBindings.format("義體能力：{ability} 使用；電量隨時間與擊敗敵人回復")


func _on_lives_changed(lives: int) -> void:
	_lives_label.visible = lives > 0
	_lives_label.text = "殘機 ×%d" % lives
	_lives_label.tooltip_text = "用完會從關卡開頭重來"


func _on_loadout_changed(loadout: Loadout) -> void:
	weapon_bar.update_from(loadout)


func _on_consumables_changed(bag: ConsumableBag) -> void:
	var parts := PackedStringArray()
	for item in ConsumableBag.catalog():
		var count := bag.count(item.id)
		if count > 0:
			parts.append("%s ×%d%s" % [item.display_name, count, InputBindings.format("　{use_item}") if item.quick_use else ""])
	_items_label.text = "　".join(parts)


func _on_vehicle_mounted(_vehicle: Node2D) -> void:
	_gauges.vehicle_visible = true
	_gauges.queue_redraw()


func _on_vehicle_dismounted() -> void:
	_gauges.vehicle_visible = false
	_gauges.queue_redraw()


func _on_vehicle_health_changed(current: int, maximum: int) -> void:
	_gauges.vehicle_ratio = float(current) / maxf(1.0, float(maximum))
	_gauges.queue_redraw()


func _on_boss_started(display_name: String, max_health: int) -> void:
	_boss_name.text = display_name
	_boss_name.visible = true
	_gauges.boss_visible = true
	_gauges.boss_ratio = 1.0 if max_health > 0 else 0.0
	_gauges.queue_redraw()


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_gauges.boss_ratio = float(current) / maxf(1.0, float(maximum))
	_gauges.queue_redraw()


func _on_boss_defeated() -> void:
	_boss_name.visible = false
	_gauges.boss_visible = false
	_gauges.queue_redraw()


## 自繪量表：機甲耐久、頭目血條。
class _Gauges:
	extends Control

	var vehicle_visible := false
	var vehicle_ratio := 1.0
	var boss_visible := false
	var boss_ratio := 1.0

	func _draw() -> void:
		_draw_vehicle_and_boss()

	func _draw_vehicle_and_boss() -> void:
		if vehicle_visible:
			draw_rect(Rect2(12, 22, 90, 5), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(12, 22, 90 * vehicle_ratio, 5), LightKit.glow(Palette.WARNING, 1.4))
			draw_rect(Rect2(12, 22, 90, 5), Palette.TERRAIN_TOP, false, 1.0)
			draw_string(UiKit.font(), Vector2(106, 28), "機甲", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.WARNING)
		if boss_visible:
			draw_rect(Rect2(170, 22, 300, 6), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(170, 22, 300 * boss_ratio, 6), LightKit.glow(Palette.DANGER, 1.6))
			draw_line(Vector2(320, 20), Vector2(320, 30), Palette.UI_MUTED, 1.0)
			draw_rect(Rect2(170, 22, 300, 6), Palette.TERRAIN_TOP, false, 1.0)


## 義體電量：能力名稱、電量條（可用時發亮）、冷卻或持續進度的細線。
class _CyberGauge:
	extends Control

	const BAR_SIZE := Vector2(116, 5)

	var _charge := 0.0
	var _ready_to_use := false
	var _name := ""
	var _progress := 1.0
	var _font: Font

	func _ready() -> void:
		_font = UiKit.font()

	func update_state(charge: float, ready: bool, ability_name: String, progress: float) -> void:
		_charge = charge
		_ready_to_use = ready
		_name = ability_name
		_progress = progress
		queue_redraw()

	func _draw() -> void:
		if _font == null:
			return
		var color := Palette.CYAN if _ready_to_use else Palette.UI_MUTED
		var label := "%s%s" % [_name, "　就緒" if _ready_to_use else ""]
		draw_string(_font, Vector2(size.x - _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
		var origin := Vector2(size.x - BAR_SIZE.x, 13)
		draw_rect(Rect2(origin, BAR_SIZE), Color(Palette.UI_PANEL, 0.8))
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * clampf(_charge / 100.0, 0.0, 1.0), BAR_SIZE.y)), LightKit.glow(color, 1.4 if _ready_to_use else 0.8))
		draw_rect(Rect2(origin, BAR_SIZE), Color(color, 0.6), false, 1.0)
		if _progress < 1.0:
			draw_line(origin + Vector2(0, BAR_SIZE.y + 2), origin + Vector2(BAR_SIZE.x * _progress, BAR_SIZE.y + 2), Palette.MAGENTA, 1.0)
