class_name FeelLab
extends Node
## 打擊感實驗室（NE-133、134、149）：用正式的玩家、關卡、敵人、特效、聲音與鏡頭做的獨立場地，反覆測同一個回饋。
## 開啟：godot --path . res://tools/feel_lab/feel_lab.tscn（只能從命令列，主選單與遊戲流程都不會進來；匯出時排除 tools/）。
## 右側面板：重生敵人（每種都能一鍵生）、材質靶與移動靶、切換玩家武器、壓力模式（定時湧入多隻敵人）、
## 回饋強度滑桿（與設定頁同一份）、單獨播放任何回饋／聲音／材質事件、診斷（計數、最近事件時間軸）。F2 顯示或隱藏面板。

const ENEMY_DIR := "res://data/enemies/"
const WEAPON_DIR := "res://data/weapons/"
const PLAYER_TILE := 14.0
const PRESSURE_INTERVAL := 4.0
const PRESSURE_COUNT := 4
const TARGET_DISTANCE_TILES := 6.0
const FLOOR_Y := 20.0 * 16.0

var level: Level
var player: Player
var panel: PanelContainer

var _enemy_option: OptionButton
var _weapon_option: OptionButton
var _event_option: OptionButton
var _sound_option: OptionButton
var _material_option: OptionButton
var _info: Label
var _preset_option: OptionButton
var _param_box: VBoxContainer
var _usage_label: Label
var _pressure := false
var _pressure_left := 0.0
var _info_left := 0.0
var _next_target_slot := 0


func _ready() -> void:
	add_child(LightKit.create_environment())
	var data := NewEnemiesSuite.arena_data()
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load("res://data/lighting/neutral.tres")
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	_setup.call_deferred()


func _setup() -> void:
	await get_tree().create_timer(0.3).timeout
	player = level.player
	player.health.setup(999999, 0.0)
	player.global_position = Vector2(PLAYER_TILE * 16.0, FLOOR_Y)
	level.hud.visible = true
	_build_panel()


func _process(delta: float) -> void:
	if player == null:
		return
	if _pressure:
		_pressure_left -= delta
		if _pressure_left <= 0.0:
			_pressure_left = PRESSURE_INTERVAL
			for i in PRESSURE_COUNT:
				spawn_enemy("grunt" if i % 2 == 0 else "elite_grunt", 8.0 + float(i) * 2.0)
	player.loadout.refill_all()
	_info_left -= delta
	if _info_left <= 0.0:
		_info_left = 0.2
		_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2 and panel != null:
		panel.visible = not panel.visible


# ---------------------------------------------------------------------------
# 場上物件
# ---------------------------------------------------------------------------

func enemy_ids() -> PackedStringArray:
	return _resource_ids(ENEMY_DIR)


func weapon_ids() -> PackedStringArray:
	return _resource_ids(WEAPON_DIR)


func _resource_ids(dir: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			ids.append(file.trim_suffix(".tres"))
	ids.sort()
	return ids


## 在玩家前方（x_tile 是離玩家的格數，正在右、負在左）重生一隻敵人。
func spawn_enemy(id: String, tiles_from_player := TARGET_DISTANCE_TILES) -> Enemy:
	var path := ENEMY_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("[FeelLab] 沒有這個敵人：%s" % path)
		return null
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(player.global_position.x + tiles_from_player * 16.0, FLOOR_Y)
	level._entities.add_child(enemy)
	return enemy


func spawn_material_target(material: StringName, moving := false, telegraph := false) -> MaterialDummy:
	var dummy := MaterialDummy.new()
	dummy.setup(material, moving, telegraph)
	_next_target_slot = (_next_target_slot + 1) % 6
	dummy.position = Vector2(player.global_position.x + (TARGET_DISTANCE_TILES + float(_next_target_slot) * 2.2) * 16.0, FLOOR_Y)
	level._entities.add_child(dummy)
	return dummy


func clear_all() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group(&"feel_lab_targets"):
		node.queue_free()


func equip_weapon(id: String) -> bool:
	var path := WEAPON_DIR + id + ".tres"
	var weapon := load(path) as WeaponData if ResourceLoader.exists(path) else null
	if weapon == null:
		push_error("[FeelLab] 沒有這把武器：%s" % path)
		return false
	player.loadout.equip(weapon)
	return true


func set_pressure(on: bool) -> void:
	_pressure = on
	_pressure_left = 0.0


# ---------------------------------------------------------------------------
# 面板
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	panel = PanelContainer.new()
	panel.theme = _compact_theme()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -150.0
	panel.offset_right = -4.0
	panel.offset_top = 4.0
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 340.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(UiKit.label("打擊感實驗室（F2 隱藏）", 9, Palette.CYAN))
	_enemy_option = _option(box, "敵人", enemy_ids(), "選一種敵人，按「重生」放在前方")
	box.add_child(_row([_button("重生", func() -> void: spawn_enemy(_enemy_option.get_item_text(_enemy_option.selected)), "在前方重生選中的敵人"),
			_button("清除", clear_all, "清掉場上所有敵人與靶")]))
	_material_option = _option(box, "靶", PackedStringArray(HitFeedback.material_ids()), "帶材質的木樁：打它看火花與聲音")
	box.add_child(_row([_button("立靶", func() -> void: spawn_material_target(StringName(_material_option.get_item_text(_material_option.selected))), "放一個不會動的靶"),
			_button("移動靶", func() -> void: spawn_material_target(StringName(_material_option.get_item_text(_material_option.selected)), true), "放一個左右來回走的靶"),
			_button("預兆靶", func() -> void: spawn_material_target(StringName(_material_option.get_item_text(_material_option.selected)), false, true), "放一個會預告再開火的靶，測預兆提示與格擋")]))
	_weapon_option = _option(box, "武器", weapon_ids(), "切換玩家手上的武器（彈藥無限）")
	_weapon_option.item_selected.connect(func(index: int) -> void: equip_weapon(_weapon_option.get_item_text(index)))
	var pressure := CheckButton.new()
	pressure.text = "壓力模式"
	pressure.tooltip_text = "每幾秒湧入一批敵人，測多目標時的回饋與預算"
	pressure.toggled.connect(set_pressure)
	box.add_child(pressure)
	for entry: Array in SettingsScreen.FEEL_ROWS:
		box.add_child(_slider(entry[0], entry[1], entry[2]))
	_preset_option = _option(box, "手感", PackedStringArray(FeelParams.presets().keys()), "預設組合：整體倍率一起改（標準、克制、厚重、街機、無障礙）")
	_preset_option.item_selected.connect(func(index: int) -> void: Feel.set_preset(StringName(_preset_option.get_item_text(index))))
	_event_option = _option(box, "回饋", PackedStringArray(Feel.event_ids()), "選一個回饋事件，下面會列出它所有可調的數值")
	_event_option.item_selected.connect(func(_i: int) -> void: rebuild_params())
	box.add_child(_row([_button("預覽差異", func() -> void: _show_save_preview(true), "列出和檔案不同的參數，不寫入"),
			_button("儲存", func() -> void: _show_save_preview(false), "驗證後寫回 data/feel/events.json（先備份）")]))
	_param_box = VBoxContainer.new()
	box.add_child(_param_box)
	_usage_label = UiKit.label("", 6, Palette.UI_MUTED)
	box.add_child(_usage_label)
	rebuild_params()
	box.add_child(_button("播放回饋", func() -> void: Feel.play(StringName(_event_option.get_item_text(_event_option.selected)), {"targets": [player]}), "不用打到東西，直接播放"))
	_sound_option = _option(box, "聲音", PackedStringArray(Sfx.event_ids()), "單獨播放一個聲音事件")
	box.add_child(_button("播放聲音", func() -> void: Sfx.play_event(StringName(_sound_option.get_item_text(_sound_option.selected))), "連按可以聽變體與連鎖升音"))
	box.add_child(_button("材質回饋在準星", func() -> void: HitFeedback.play(StringName(_material_option.get_item_text(_material_option.selected)), player.aim_point, Vector2.UP, Palette.CYAN), "在準星位置播放選中的材質命中"))
	_info = UiKit.label("", 5, Palette.UI_MUTED)
	_info.position = Vector2(6.0, 60.0)
	var info_layer := CanvasLayer.new()
	info_layer.layer = 49
	add_child(info_layer)
	info_layer.add_child(_info)


## 預覽或儲存：顯示差異與結果（驗證失敗會指出位置，不寫入）。
func _show_save_preview(dry_run: bool) -> void:
	var result := FeelParams.save_events(Feel.PATH, dry_run)
	var lines := PackedStringArray()
	if not (result["errors"] as PackedStringArray).is_empty():
		lines.append("沒有寫入：")
		lines.append_array(result["errors"])
	else:
		lines.append("（預覽）" if dry_run else ("已儲存，備份在 %s" % result["backup"] if result["backup"] != "" else "沒有差異"))
		lines.append_array(result["diff"])
	_info.text = "\n".join(lines)
	_info_left = 4.0


## 依選中事件的資料自動產生滑桿；新增資料欄位不用改這裡。改動立刻寫進記憶體中的事件資料，按「播放回饋」就能看到。
func rebuild_params() -> void:
	if _param_box == null:
		return
	for child in _param_box.get_children():
		child.queue_free()
	var id := StringName(_event_option.get_item_text(_event_option.selected))
	var def := Feel.event_def(id)
	for param: Dictionary in FeelParams.parameters(def):
		var row := HBoxContainer.new()
		row.add_child(UiKit.label(String(param["name"]), 7))
		var slider := HSlider.new()
		slider.min_value = param["min"]
		slider.max_value = param["max"]
		slider.step = param["step"]
		slider.value = param["value"]
		slider.custom_minimum_size = Vector2(70, 10)
		var path: Array = param["path"]
		slider.value_changed.connect(func(value: float) -> void: FeelParams.set_value(def, path, value))
		row.add_child(slider)
		_param_box.add_child(row)
	var users := FeelParams.users_of(String(id))
	_usage_label.text = "使用處：" + (", ".join(PackedStringArray(users.map(func(p: String) -> String: return p.get_file()))) if not users.is_empty() else "（沒有）")


func _option(parent: Control, title: String, items: PackedStringArray, tooltip: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_child(UiKit.label(title, 8))
	var option := OptionButton.new()
	option.tooltip_text = tooltip
	option.custom_minimum_size = Vector2(96, 0)
	for item in items:
		option.add_item(item)
	row.add_child(option)
	parent.add_child(row)
	return option


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for child: Control in children:
		row.add_child(child)
	return row


func _button(text: String, action: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	return button


## 實驗室專用的小字體主題（面板要窄，才不擋住畫面）。
static func _compact_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = UiKit.font()
	theme.default_font_size = 8
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	box.set_content_margin_all(3)
	theme.set_stylebox(&"panel", &"PanelContainer", box)
	return theme


func _slider(key: String, text: String, tooltip: String) -> Control:
	var row := HBoxContainer.new()
	row.tooltip_text = tooltip
	row.add_child(UiKit.label(text, 8))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 10
	slider.value = roundf(Settings.get_feel_scale(key) * 100.0)
	slider.custom_minimum_size = Vector2(80, 10)
	slider.value_changed.connect(func(value: float) -> void: Settings.set_feel_scale(key, value / 100.0))
	row.add_child(slider)
	return row


## 診斷：各系統計數與最近的回饋事件時間軸。
func _refresh_info() -> void:
	if _info == null:
		return
	var lines := PackedStringArray()
	var counters := Feel.read_counters()
	lines.append("FPS %d  粒子預算裁掉 %d" % [Engine.get_frames_per_second(), HitFeedback.trimmed_particles])
	for key: String in counters.keys():
		lines.append("%s: %s" % [key, counters[key]])
	var warning := FlashGuard.warning()
	if warning != "":
		lines.append("警示：" + warning)
	lines.append("— 最近事件 —")
	lines.append_array(Feel.recent)
	_info.text = "\n".join(lines)
