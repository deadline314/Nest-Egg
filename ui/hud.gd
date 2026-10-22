class_name Hud
extends CanvasLayer
## 遊戲 HUD：數值透過 EventBus 更新；操作 cue 只持有同關卡 owner 的 WeakRef。
## 滑鼠移到各區塊上會顯示一句重點說明（tooltip）。
## 生命、護盾、彈藥改由動態元件顯示（跟著角色與準星），見 design/05-dynamic-hud。

const TOAST_TIME := 2.2
const CONTROLS_HINT_TIME := 5.0
## {動作} 會換成玩家目前設定的按鍵（見 InputBindings.format）。
const CONTROLS_TEMPLATE := "移動 {move_left}/{move_right}　跳 {jump}　射擊 {shoot}　格擋 {block}　衝刺 {dash}　近戰／終結 {melee}　換彈 {reload}　換武器 {weapon_next}／1～4　搭乘 {interact}　背包 {inventory}　暫停 {pause}"
## 按住與連按的規則（NE-229），一行一件事；設定的「按鍵」「手把」分頁顯示，按鍵名稱跟著目前裝置與改鍵。
## 對應的判定：放開跳躍會截短跳躍、按住射擊依射速連射、按住格擋持續舉盾、近戰與衝刺有輸入緩衝（data/feel/input.json）。
const HOLD_RULES: Array[String] = [
	"按住 {jump} 跳得更高，提早放開就跳得低。",
	"按住 {shoot} 依射速連射；按住 {block} 持續舉盾。",
	"出招中先按 {melee} 會接下一段；衝刺快冷卻完時先按 {dash} 會排隊。",
]

var vitals_tag: VitalsTag
var ammo_ring: AmmoRing
var ammo_tray: AmmoTray
var _gauges: _Gauges
var weapon_bar: WeaponBar
var hover_guard: BackgroundHoverGuard
var pickup_feed: PickupFeed
var _items_label: Label
var _lives_label: Label
var _timer_label: Label
var credits_tag: CreditsTag
var cyber_gauge: CyberGauge
var boss_bar: BossBar
var toast_banner: UiBanner
var quest_guidance: QuestGuidance
var _controls: Label
var _controls_card: PanelContainer
var _controls_read_time := CONTROLS_HINT_TIME
var _controls_dismissing := false
var _controls_framed := false
var _framing_edge_root: Control
var _items_template := ""
var _hint_template := "{pause} 開啟操作說明"
var _hint_owner: WeakRef
var _hint_cleanup: Callable
var _hint_token := 0
var _hint_tween: Tween
var _hint_expired := false
var _hint_row: HBoxContainer
var _hint_caps: Array[PanelContainer] = []
const HINT_ACTIONS := ["move_left", "move_right", "move_down", "jump", "shoot", "block", "dash", "melee", "reload", "interact", "inventory", "pause", "use_item", "ability", "weapon_next", "weapon_prev"]



func _ready() -> void:
	layer = UiLayers.HUD
	var root := UiKit.full_rect_root(self)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 暫停頁、交談與通訊出現時，背景說明不能蓋住講者、正文或選單。
	hover_guard = BackgroundHoverGuard.new(root)
	root.add_child(hover_guard)
	quest_guidance = QuestGuidance.new()
	root.add_child(quest_guidance)

	_gauges = _Gauges.new()
	_gauges.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_gauges)

	_lives_label = UiKit.label("", 10, Palette.UI_MUTED)
	_lives_label.position = Vector2(12, 6)
	root.add_child(_lives_label)

	weapon_bar = WeaponBar.new()
	# 往下貼齊底邊留白（四列到 348）：主角站在地面時腳邊和武器欄之間留出空隙（NE-264）。
	weapon_bar.position = Vector2(12, 270)
	root.add_child(weapon_bar)

	vitals_tag = VitalsTag.new()
	root.add_child(vitals_tag)
	_items_label = UiKit.label("", 10, Palette.UI_MUTED)
	_items_label.position = Vector2(12, 254)
	_items_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_items_label.tooltip_text = "攜帶的消耗品；快速鍵使用醫療針，其他在背包使用"
	root.add_child(_items_label)
	# 拾取紀錄在右上角信用點下方：角色常站的左下與中央都不擋。
	pickup_feed = PickupFeed.new()
	pickup_feed.position = Vector2(330, 40)
	pickup_feed.size = Vector2(300, 72)
	root.add_child(pickup_feed)

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

	_controls_card = PanelContainer.new()
	_controls_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_controls_card)
	_controls_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_controls_card.offset_left = -252
	_controls_card.offset_right = -12
	_controls_card.offset_top = -34
	_controls_card.offset_bottom = -12
	_controls_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hint_box := ChamferBox.make(UiTheme.PANEL_BODY, UiTheme.PANEL_EDGE, 3)
	hint_box.margins(8, 4, 8, 4)
	_controls_card.add_theme_stylebox_override(&"panel", hint_box)
	_controls = UiKit.label(quick_controls_hint(), UiKit.FS_BODY, Palette.UI_TEXT)
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override(&"separation", 6)
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_card.add_child(_hint_row)
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_row.add_child(_controls)
	_render_hint()
	_controls.minimum_size_changed.connect(_layout_controls)
	root.resized.connect(_layout_controls)
	_layout_controls()

	# 整個edge元件一起隱藏，避免黑邊切半行；子元件原有visible/值/動畫不變。
	_framing_edge_root = UiKit.full_rect_root(root)
	_framing_edge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item: Control in [_lives_label, _timer_label, credits_tag, cyber_gauge, boss_bar, weapon_bar]:
		item.reparent(_framing_edge_root, false)
	# Fixed status controls keep their complete slots clear for world reading.
	for item: Control in [_lives_label, _timer_label, credits_tag, cyber_gauge, boss_bar, weapon_bar, _items_label, _controls_card]:
		PromptLayout.add_obstacle(item, _fixed_reading_rect.bind(item))
	EventBus.player_loadout_changed.connect(_on_loadout_changed)
	GameplayLock.started.connect(_controls_card.hide)
	Story.framing.safe_rect_changed.connect(_on_framing_safe_rect)
	_on_framing_safe_rect(Story.framing.safe_rect())
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
	var level := get_parent() as Level
	# 真入區／重生／續玩不重播開場說明；新機關 cue 仍可隨時取得。
	if level != null and (level._entry_portal != &"" or level._from_checkpoint or not level._resume.is_empty()):
		_hint_expired = true
		_controls_card.hide()


## Reserve the full slot, including a boss bar expanding from its center.
func _fixed_reading_rect(control: Control) -> Rect2:
	if not control.is_visible_in_tree() or control.modulate.a <= 0.01 or (control is Label and (control as Label).text.is_empty()):
		return Rect2()
	var parent := control.get_parent() as CanvasItem
	if parent == null:
		return Rect2()
	var to_world := get_viewport().get_canvas_transform().affine_inverse() * parent.get_global_transform_with_canvas()
	return to_world * Rect2(control.position, control.size.max(control.get_minimum_size()))


func _refresh_controls() -> void:
	_render_hint()
	_layout_controls()
	_items_label.text = InputBindings.format(_items_template)
	cyber_gauge.tooltip_text = InputBindings.format("義體能力：{ability} 使用；電量隨時間與擊敗敵人回復")


func _layout_controls() -> void:
	var width := 0.0
	var font := _controls.get_theme_font(&"font")
	var font_size := _controls.get_theme_font_size(&"font_size")
	for line in _controls.text.split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for cap in _hint_caps:
		width += cap.get_combined_minimum_size().x + 6.0
	var available := maxf(64.0, minf(280.0, get_viewport().get_visible_rect().size.x - 164.0))
	var left := -minf(ceilf(width + 16.0), available) - 12.0
	if not is_equal_approx(_controls_card.offset_left, left):
		_controls_card.offset_left = left


func _dismiss_controls() -> void:
	_controls_dismissing = true
	if Settings.get_reduce_ui_motion():
		_controls_card.modulate.a = 0.0
		_controls_card.hide()
	else:
		_hint_tween = create_tween()
		_hint_tween.tween_property(_controls_card, "modulate:a", 0.0, 0.35)


static func controls_hint() -> String:
	var template := CONTROLS_TEMPLATE
	if InputBindings.using_gamepad:
		template = template.replace("／1～4", "")
	return InputBindings.format(template)


## 按住與連按的規則，已換成目前裝置的按鍵名稱。
static func hold_rules() -> String:
	var lines := PackedStringArray()
	for rule in HOLD_RULES:
		lines.append(InputBindings.format(rule))
	return "\n".join(lines)


## 完整清單在暫停頁；預設只提示如何重看，不推定玩家完成了教學。
static func quick_controls_hint() -> String:
	return InputBindings.format("{pause} 開啟操作說明")


## Runtime-only：真機關判定適用情境後呼叫。HUD 不判定成功、不保存教學進度。
## owner 必須位於同關卡子樹。離開觸發區／成功時 caller clear(token)。
## 至多兩種動作；過期只是收起提示，不能當成完成教學。
func show_context_hint(owner: Node, template: String, seconds := 8.0) -> int:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
		return 0
	var level := get_parent() as Level
	if level == null or owner == self or not level.is_ancestor_of(owner) or not _valid_hint(template, seconds):
		return 0
	_detach_hint_owner()
	_hint_token += 1
	_hint_owner = weakref(owner)
	_hint_cleanup = clear_context_hint.bind(_hint_token)
	owner.tree_exiting.connect(_hint_cleanup, CONNECT_ONE_SHOT)
	_hint_template = template
	_controls_read_time = seconds
	_controls_dismissing = false
	_hint_expired = false
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_controls_card.modulate.a = 1.0
	_refresh_controls()
	return _hint_token


static func _valid_hint(template: String, seconds: float) -> bool:
	if not is_finite(seconds) or seconds <= 0.0 or seconds > 15.0 or template.length() > 96 or template.strip_edges().is_empty() or template.contains("\n") or template.contains("\r"):
		return false
	var actions: Dictionary = {}
	var remainder := template
	var matches := RegEx.create_from_string("\\{([a-z_0-9]+)\\}").search_all(template)
	if matches.is_empty() or matches.size() > 2:
		return false
	# Keycaps precede the instruction visually. Accept a complete plain instruction
	# with only whitespace-separated trailing tokens, never embedded fragments.
	var instruction := template.substr(0, matches[0].get_start()).strip_edges()
	if instruction.is_empty():
		return false
	var tail := template.substr(matches[0].get_start())
	for found in matches:
		var action := found.get_string(1)
		if action not in HINT_ACTIONS:
			return false
		actions[action] = true
		remainder = remainder.replace(found.get_string(), "")
		tail = tail.replace(found.get_string(), "")
	return tail.strip_edges().is_empty() and not remainder.contains("{") and not remainder.contains("}")


func clear_context_hint(token: int) -> void:
	if token != _hint_token or _hint_owner == null:
		return
	_detach_hint_owner()
	_hint_expired = true
	_controls_card.hide()


func _detach_hint_owner() -> void:
	var owner: Node = _hint_owner.get_ref() as Node if _hint_owner != null else null
	if is_instance_valid(owner) and owner.tree_exiting.is_connected(_hint_cleanup):
		owner.tree_exiting.disconnect(_hint_cleanup)
	_hint_owner = null


func _render_hint() -> void:
	# 只在 cue／綁定變更時建立至多兩個按鍵帽，沒有每影格字串掃描／節點配置。
	for cap in _hint_caps:
		_hint_row.remove_child(cap)
		cap.queue_free()
	_hint_caps.clear()
	var instruction := _hint_template
	var shown: Dictionary = {}
	for found in RegEx.create_from_string("\\{([a-z_0-9]+)\\}").search_all(_hint_template):
		var action := StringName(found.get_string(1))
		instruction = instruction.replace(found.get_string(), "")
		if shown.has(action):
			continue
		shown[action] = true
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := ChamferBox.make(Color("20333f"), Color("6c8997"), 2)
		box.margins(4, 1, 4, 1)
		cap.add_theme_stylebox_override(&"panel", box)
		cap.add_child(UiKit.label(InputBindings.primary_label(action), UiKit.FS_BODY, Palette.UI_TEXT))
		_hint_row.add_child(cap)
		_hint_row.move_child(cap, _hint_caps.size())
		_hint_caps.append(cap)
	_controls.text = instruction.strip_edges()


func _exit_tree() -> void:
	_detach_hint_owner()


func _on_framing_safe_rect(rect: Rect2) -> void:
	_controls_framed = rect.position.y > 0.01
	_framing_edge_root.visible = not _controls_framed and not Story.is_cinematic_active()
	if _controls_framed:
		_controls_card.hide()


func _notification(what: int) -> void:
	# 暫停後 HUD 不再跑 _process：操作邀請卡要在暫停當下收起，恢復後由 _process 依情境重新判斷。
	if what == NOTIFICATION_PAUSED and _controls_card != null:
		_controls_card.visible = false


func _process(delta: float) -> void:
	_timer_label.text = UiKit.format_time(GameState.run_time)
	# Object reading has no black bars, but still owns a modal's header and skip key.
	_framing_edge_root.visible = not _controls_framed and not Story.is_cinematic_active()
	if _hint_owner != null:
		var owner: Node = _hint_owner.get_ref() as Node
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion() or not get_parent().is_ancestor_of(owner):
			clear_context_hint(_hint_token)
	var level := get_parent() as Level
	var dead := level != null and (level.died or (is_instance_valid(level.player) and level.player.is_dead()))
	if _controls_card.modulate.a > 0.0:
		_controls_card.visible = not _hint_expired and not dead and not get_tree().paused and not Story.is_cinematic_active() and not GameplayLock.is_locked() and not _controls_framed and Music.engaged_enemies() == 0 and not toast_banner.is_showing()
		if _controls_card.visible and not _controls_dismissing:
			_controls_read_time -= delta
			if _controls_read_time <= 0.0:
				_dismiss_controls()


## 取得類放進左上角的拾取紀錄（不擋戰鬥畫面）；檢查點、警告與其他提示用畫面中央的橫幅。
func show_toast(text: String) -> void:
	var kind := _toast_kind(text)
	if kind == UiBanner.Kind.ITEM and pickup_feed != null:
		pickup_feed.push(text)
		return
	toast_banner.show_text(text, kind, TOAST_TIME)


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
			parts.append("%s ×%d%s" % [item.display_name, count, "　{use_item}" if item.quick_use else ""])
	_items_template = "　".join(parts)
	_items_label.text = InputBindings.format(_items_template)


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
