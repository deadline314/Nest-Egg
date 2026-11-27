extends Node
## A live attempt only owns the clock and source availability. The actual arrival
## conversation still goes through the existing authenticated Main result owner.

const Data := preload("res://data/scripts/traversal_trial_data.gd")
enum Phase { IDLE, ARMED, RUNNING, ARRIVED, EXPIRED }

var _phase := Phase.IDLE
var _data: Data
var _player: Player
var _origin: NpcActor
var _arrival: NpcActor
var _start := Vector2.ZERO
var _tile := 16.0
var _time_left := 0.0
var _visible_seconds := -1
var _label: Label
var _copy: Dictionary


func configure(spec: Data, layout: LevelLayout, player: Player, sources: Dictionary, hud: CanvasLayer) -> bool:
	_data = spec
	_player = player
	_origin = sources.get(spec.start_source)
	_arrival = sources.get(spec.arrival_source)
	_tile = float(layout.tile_size)
	_start = Vector2((float(spec.start_cell.x) + 0.5) * _tile, (spec.start_cell.y + 1) * _tile)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec.text_path))
	if _origin == null or _arrival == null or _arrival.position.x <= _start.x + _tile * 3.0 or not raw is Dictionary:
		return false
	for language in ["zh", "en", "ja"]:
		var strings: Variant = raw.get(language)
		if not strings is Dictionary:
			return false
		for key in ["armed", "running", "arrived", "expired"]:
			var line: Variant = strings.get(key)
			if not line is String or line.is_empty() or line.length() > 140 or (key == "running" and line.count("{seconds}") != 1):
				return false
	_copy = raw
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 28
	_label.offset_bottom = 52
	_label.hide()
	_arrival.set_local_available(false)
	Story.scene_finished.connect(_arm)
	GameState.flag_changed.connect(_result_changed)
	set_physics_process(false)
	return true


func _arm(scene: StringName) -> void:
	if scene != _data.normal_scene and scene != _data.guided_scene:
		return
	if not _origin._talking or not _player.is_on_floor() or not _available() \
			or absf(_player.global_position.x - _origin.global_position.x) > NpcActor.INTERACT_RANGE:
		return
	_phase = Phase.ARMED
	_time_left = _data.guided_seconds if scene == _data.guided_scene else _data.normal_seconds
	_visible_seconds = -1
	_arrival.set_local_available(false)
	_show("armed")
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _player.is_dead() or not _available():
		_clear()
		return
	if get_tree().paused or GameplayLock.is_locked() or Story.is_cinematic_active():
		return
	var feet := _player.global_position
	if _phase == Phase.ARMED:
		if feet.x < _start.x or feet.x >= _start.x + _tile * 8.0 or feet.y > _start.y + 3.0 or not _player.is_on_floor():
			return
		_phase = Phase.RUNNING
	if _phase != Phase.RUNNING:
		return
	var target := _arrival.global_position
	if _player.is_on_floor() and absf(feet.x - target.x) <= _tile * 1.25 and absf(feet.y - target.y) <= 4.0:
		_phase = Phase.ARRIVED
		_arrival.set_local_available(true)
		_show("arrived")
		set_physics_process(false)
		return
	_time_left = maxf(0.0, _time_left - delta)
	if _time_left <= 0.0:
		_phase = Phase.EXPIRED
		_show("expired")
		set_physics_process(false)
		return
	var seconds := ceili(_time_left)
	if _visible_seconds != seconds:
		_visible_seconds = seconds
		_show("running", seconds)


func _available() -> bool:
	return GameState.get_flag(_data.gate_flag, false) == true and not GameState.has_flag(_data.resolved_flag)


func _show(state: String, seconds := 0) -> void:
	var language := Story.language if _copy.has(Story.language) else "zh"
	_label.text = str(_copy[language][state]).replace("{seconds}", str(seconds))
	_label.show()


func _result_changed(flag: StringName, _value: Variant) -> void:
	if flag == _data.resolved_flag or (flag == _data.gate_flag and not _available()):
		_clear()


func _clear() -> void:
	_phase = Phase.IDLE
	_arrival.set_local_available(false)
	_label.hide()
	set_physics_process(false)
