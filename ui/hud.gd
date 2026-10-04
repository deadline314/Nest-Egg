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
var ammo_tray: AmmoTray
var _gauges: _Gauges
var weapon_bar: WeaponBar
var _items_label: Label
var _lives_label: Label
var _timer_label: Label
var credits_tag: CreditsTag
var cyber_gauge: CyberGauge
var boss_bar: BossBar
var toast_banner: UiBanner
var _controls: Label


func _ready() -> void:
	layer = UiLayers.HUD
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
	ammo_tray = AmmoTray.new()
	add_child(ammo_tray)

	_timer_label = UiKit.label("00:00.00", 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer_label.position = Vector2(528, 8)
	_timer_label.size = Vector2(100, 16)
	root.add_child(_timer_label)

	credits_tag = CreditsTag.new()
	credits_tag.position = Vector2(518, 22)
	root.add_child(credits_tag)

	cyber_gauge = CyberGauge.new()
	cyber_gauge.position = Vector2(508, 40)
	cyber_gauge.visible = false
	cyber_gauge.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(cyber_gauge)

	boss_bar = BossBar.new()
	boss_bar.position = Vector2((640.0 - BossBar.SIZE.x) * 0.5, 8)
	root.add_child(boss_bar)

	toast_banner = UiBanner.new()
	toast_banner.position = Vector2(220, 112)
	toast_banner.center_x = 320.0
	root.add_child(toast_banner)

	_controls = UiKit.label(controls_hint(), UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
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
	EventBus.boss_bar_closed.connect(boss_bar.close)
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


## 取得、檢查點、警告都用橫幅；種類依文字判斷（取得／警告），其餘是一般提示。
func show_toast(text: String) -> void:
	toast_banner.show_text(text, _toast_kind(text), TOAST_TIME)


static func _toast_kind(text: String) -> UiBanner.Kind:
	if text.begins_with("取得") or text.begins_with("撿到") or text.contains("＋"):
		return UiBanner.Kind.ITEM
	if text.contains("警告") or text.contains("危險") or text.contains("失敗"):
		return UiBanner.Kind.WARNING
	return UiBanner.Kind.INFO


func _on_credits_changed(credits: int, delta: int) -> void:
	credits_tag.set_credits(credits, delta)


func _on_cyber_changed(charge: float, ready: bool, ability_name: String, progress: float) -> void:
	cyber_gauge.visible = not ability_name.is_empty()
	cyber_gauge.update_state(charge, ready, ability_name, progress)
	cyber_gauge.tooltip_text = InputBindings.format("義體能力：{ability} 使用；電量隨時間與擊敗敵人回復")


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
	boss_bar.open(display_name, 1.0 if max_health > 0 else 0.0)


func _on_boss_health_changed(current: int, maximum: int) -> void:
	boss_bar.set_ratio(float(current) / maxf(1.0, float(maximum)))


func _on_boss_defeated() -> void:
	boss_bar.close()


## 自繪量表：機甲耐久。
class _Gauges:
	extends Control

	var vehicle_visible := false
	var vehicle_ratio := 1.0

	func _draw() -> void:
		_draw_vehicle_and_boss()

	func _draw_vehicle_and_boss() -> void:
		if vehicle_visible:
			draw_rect(Rect2(12, 22, 90, 5), Color(Palette.UI_PANEL, 0.9))
			draw_rect(Rect2(12, 22, 90 * vehicle_ratio, 5), LightKit.glow(Palette.WARNING, 1.4))
			draw_rect(Rect2(12, 22, 90, 5), Palette.TERRAIN_TOP, false, 1.0)
			draw_string(UiKit.font(), Vector2(106, 28), "機甲", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.WARNING)
