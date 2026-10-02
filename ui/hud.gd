class_name Hud
extends CanvasLayer
## 遊戲 HUD：完全透過 EventBus 更新，不持有任何遊戲物件參照（物件被移除也不會出錯）。
## 滑鼠移到各區塊上會顯示一句重點說明（tooltip）。

const TOAST_TIME := 2.2
const CONTROLS_HINT_TIME := 14.0
## {動作} 會換成玩家目前設定的按鍵（見 InputBindings.format）。
const CONTROLS_TEMPLATE := "移動 {move_left}/{move_right}　跳 {jump}　射擊 {shoot}　格擋 {block}　衝刺 {dash}　終結 {melee}　換武器 {weapon_next}／1～4　搭乘 {interact}　暫停 {pause}"

var _gauges: _Gauges
var _weapon_labels: Array[Label] = []
var _weapon_panel: Control
var _lives_label: Label
var _timer_label: Label
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

	_add_tooltip_zone(root, Rect2(8, 6, 110, 18), "生命：裝甲片剝落代表受傷，歸零即失敗")
	_add_tooltip_zone(root, Rect2(8, 22, 110, 8), "護盾能量：格擋時消耗，放開後回復；耗盡會破防")
	_lives_label = UiKit.label("", 10, Palette.UI_MUTED)
	_lives_label.position = Vector2(12, 30)
	root.add_child(_lives_label)

	_weapon_panel = VBoxContainer.new()
	_weapon_panel.position = Vector2(12, 268)
	_weapon_panel.add_theme_constant_override(&"separation", 0)
	_weapon_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_weapon_panel)
	for i in Loadout.MAX_SLOTS:
		var l := UiKit.label("", 11)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_weapon_panel.add_child(l)
		_weapon_labels.append(l)

	add_child(Crosshair.new())

	_timer_label = UiKit.label("00:00.00", 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer_label.position = Vector2(528, 8)
	_timer_label.size = Vector2(100, 16)
	root.add_child(_timer_label)

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
	_controls.custom_minimum_size = Vector2(470, 0)
	_controls.position = Vector2(160, 330)
	_controls.size = Vector2(470, 26)
	root.add_child(_controls)
	var fade := create_tween()
	fade.tween_interval(CONTROLS_HINT_TIME)
	fade.tween_property(_controls, "modulate:a", 0.0, 1.0)

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_loadout_changed.connect(_on_loadout_changed)
	EventBus.vehicle_mounted.connect(_on_vehicle_mounted)
	EventBus.vehicle_dismounted.connect(_on_vehicle_dismounted)
	EventBus.vehicle_health_changed.connect(_on_vehicle_health_changed)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.toast_requested.connect(show_toast)
	EventBus.lives_changed.connect(_on_lives_changed)
	EventBus.player_guard_changed.connect(_on_guard_changed)
	InputBindings.bindings_changed.connect(_refresh_controls)
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


func _add_tooltip_zone(parent: Control, rect: Rect2, tooltip: String) -> Control:
	var zone := Control.new()
	zone.position = rect.position
	zone.size = rect.size
	zone.tooltip_text = tooltip
	zone.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(zone)
	return zone


func _on_health_changed(current: int, maximum: int) -> void:
	_gauges.health = current
	_gauges.max_health = maximum
	_gauges.queue_redraw()


func _on_guard_changed(current: float, maximum: float, broken: bool) -> void:
	_gauges.guard_ratio = current / maxf(1.0, maximum)
	_gauges.guard_broken = broken
	_gauges.queue_redraw()


func _on_lives_changed(lives: int) -> void:
	_lives_label.visible = lives > 0
	_lives_label.text = "殘機 ×%d" % lives
	_lives_label.tooltip_text = "用完會從關卡開頭重來"


func _on_loadout_changed(loadout: Loadout) -> void:
	for slot in _weapon_labels.size():
		var label := _weapon_labels[slot]
		var weapon := loadout.weapon_in(slot)
		if weapon == null:
			label.text = "%d  ——" % (slot + 1)
			label.add_theme_color_override(&"font_color", Color(Palette.UI_MUTED, 0.5))
			label.tooltip_text = "撿取武器後放在這裡；滾輪或數字鍵切換"
			continue
		var ammo := loadout.ammo_in(slot)
		var active := slot == loadout.active_slot
		label.text = "%d %s %s  %s" % [slot + 1, "▶" if active else " ", weapon.display_name, "∞" if ammo < 0 else str(ammo)]
		label.add_theme_color_override(&"font_color", weapon.color if active else Palette.UI_MUTED)
		label.tooltip_text = weapon.description


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


## 自繪量表：生命格、機甲耐久、頭目血條。
class _Gauges:
	extends Control

	var health := 0
	var max_health := 0
	var vehicle_visible := false
	var vehicle_ratio := 1.0
	var boss_visible := false
	var guard_ratio := 1.0
	var guard_broken := false
	var boss_ratio := 1.0

	## 生命上限超過此數改用長條顯示，避免格子溢出畫面。
	const MAX_PIPS := 12

	func _draw() -> void:
		_draw_guard()
		_draw_health()
		_draw_vehicle_and_boss()

	func _draw_health() -> void:
		if max_health > MAX_PIPS:
			var ratio := float(health) / float(max_health)
			draw_rect(Rect2(12, 10, 150, 8), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(12, 10, 150 * ratio, 8), LightKit.glow(Palette.CYAN, 1.4))
			draw_rect(Rect2(12, 10, 150, 8), Palette.CYAN_DIM, false, 1.0)
			return
		for i in max_health:
			var x := 12.0 + i * 13.0
			var points := PackedVector2Array([Vector2(x + 3, 10), Vector2(x + 12, 10), Vector2(x + 9, 20), Vector2(x, 20)])
			if i < health:
				draw_colored_polygon(points, LightKit.glow(Palette.CYAN, 1.4))
			else:
				points.append(points[0])
				draw_polyline(points, Palette.CYAN_DIM, 1.0)

	func _draw_vehicle_and_boss() -> void:
		if vehicle_visible:
			draw_rect(Rect2(12, 40, 90, 5), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(12, 40, 90 * vehicle_ratio, 5), LightKit.glow(Palette.WARNING, 1.4))
			draw_rect(Rect2(12, 40, 90, 5), Palette.TERRAIN_TOP, false, 1.0)
			draw_string(UiKit.font(), Vector2(106, 46), "機甲", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.WARNING)
		if boss_visible:
			draw_rect(Rect2(170, 22, 300, 6), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(170, 22, 300 * boss_ratio, 6), LightKit.glow(Palette.DANGER, 1.6))
			draw_line(Vector2(320, 20), Vector2(320, 30), Palette.UI_MUTED, 1.0)
			draw_rect(Rect2(170, 22, 300, 6), Palette.TERRAIN_TOP, false, 1.0)

	func _draw_guard() -> void:
		var rect := Rect2(12, 23, 90, 3)
		draw_rect(rect, Color(Palette.UI_PANEL, 0.9))
		var color := Palette.DANGER if guard_broken else LightKit.glow(Palette.CYAN, 1.2)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * guard_ratio, rect.size.y)), color)

