extends Node2D
## A noncombat encounter owns a bounded ground lane and a safe return point.
## The only persisted values here are room checkpoints. The coat NPC owns its story result.

const Data := preload("res://data/scripts/avoidance_encounter_data.gd")
const COAT_LABEL_FRACTION := 0.18
const REST_SECONDS := 0.65
const HOLD_SECONDS := 0.52
const ESCAPE_PRESSES := 3
const CARRY_SECONDS := 0.95
const RETURN_SPEED := 86.0
const GRAB_DISTANCE := 18.0
const RECOVER_SECONDS := 0.55

enum Phase { WAITING, TELL, COMMIT, RECOVER, HELD, CARRIED, REST, LEAVING, COMPLETE }

var phase := Phase.WAITING
var exerted := 0
var _spec: Data
var _rider: Player
var _performer: CutsceneActor
var _coat_source: NpcActor
var _coat_prop: PropNode
var _coat_sprite: Sprite2D
var _hud: CanvasLayer
var _copy: Label
var _meter: Label
var _home := Vector2.ZERO
var _retry := Vector2.ZERO
var _first_home_x := 0.0
var _phase_shift := 0.0
var _active_x := 0.0
var _far_x := 0.0
var _high_y := 0.0
var _last_input := false
var _elapsed := 0.0
var _hold := 0.0
var _taps := 0
var _origin_x := 0.0
var _target_x := 0.0
var _incoming := 1
var _passed := false
var _attempt: Dictionary


func configure(spec: Data, layout: LevelLayout, rider: Player, coat_source: NpcActor, coat_prop: PropNode) -> bool:
	_spec = spec
	_rider = rider
	_coat_source = coat_source
	_coat_prop = coat_prop
	if coat_source == null or coat_prop == null:
		push_warning("[AvoidanceEncounter] %s missing the coat prop or interaction source" % spec.id)
		return false
	var tile := float(layout.tile_size)
	var floor_y := layout.player_start.y
	_home = Vector2((spec.home_column + 0.5) * tile, floor_y)
	_first_home_x = _home.x
	_phase_shift = tile
	_retry = Vector2((spec.retry_column + 0.5) * tile, floor_y)
	_active_x = (spec.start_column + 0.5) * tile
	_far_x = (layout.width - 3.0) * tile
	_high_y = floor_y - tile * 1.5
	for x in range(spec.retry_column, layout.width - 2):
		var ground_cell := roundi(floor_y / tile)
		if layout.cell(x, ground_cell) not in ["#", "=", "~"]:
			push_warning("[AvoidanceEncounter] %s unsupported ground at column %d" % [spec.id, x])
			return false
	var identified := GameState.has_flag(_spec.identified)
	if not identified:
		_performer = CutsceneActor.new()
		_performer.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(_performer)
		if not _performer.setup(&"greycoat", spec.rig_id, "", 1.0, ""):
			push_warning("[AvoidanceEncounter] %s could not load rig %s" % [spec.id, spec.rig_id])
			return false
		_performer.rig.use_level_lighting = true
		_performer.position = _home
		_performer.ground_y = floor_y
		_performer.face(-1)
	for child: Node in coat_prop.get_children():
		if child is Sprite2D:
			_coat_sprite = child as Sprite2D
			break
	_setup_hud()
	_coat_source.set_local_available(false)
	_coat_prop.hide()
	add_to_group(WorldState.GROUP)
	GameState.flag_changed.connect(_on_flag_changed)
	_rider.set_noncombat_room(true)
	if identified:
		retire()
	return true


func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var dock := VBoxContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	dock.offset_left = -150.0
	dock.offset_right = 150.0
	dock.offset_top = 34.0
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(dock)
	_meter = UiKit.label("", 11, Color(0.99, 0.82, 0.60))
	_copy = UiKit.label("", 11)
	for label: Label in [_meter, _copy]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08))
		label.add_theme_constant_override("outline_size", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_child(label)
	_hud.hide()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_rider) or _rider.is_dead() or GameplayLock.is_locked() or get_tree().paused:
		return
	_elapsed += delta
	match phase:
		Phase.WAITING:
			if _rider.global_position.x >= _active_x:
				begin_tell()
		Phase.TELL:
			if _elapsed >= float(_attempt["tell"]):
				begin_commit()
		Phase.COMMIT:
			step_commit()
		Phase.HELD:
			step_escape(delta)
		Phase.CARRIED:
			step_carry()
		Phase.RECOVER, Phase.REST:
			_performer.position.x = move_toward(_performer.position.x, _home.x, RETURN_SPEED * delta)
			if _elapsed >= (REST_SECONDS if phase == Phase.REST else RECOVER_SECONDS) and is_equal_approx(_performer.position.x, _home.x):
				reset_wait()
		Phase.LEAVING:
			_performer.position.x = move_toward(_performer.position.x, _far_x, RETURN_SPEED * delta)
			if is_equal_approx(_performer.position.x, _far_x):
				retire()


func begin_tell() -> void:
	_attempt = _spec.actions[exerted]
	_target_x = clampf(_rider.global_position.x, _active_x + 8.0, _far_x - 12.0)
	_incoming = 1 if _target_x > _home.x else -1
	_performer.face(_incoming)
	_performer.set_pose(&"idle")
	_performer.play_gesture(StringName(_attempt["gesture"]), true)
	set_phase(Phase.TELL, str(_attempt["kind"]))
	Sfx.play(&"step_wet", -14.0)


func begin_commit() -> void:
	_origin_x = _performer.position.x
	_target_x = clampf(_target_x, _origin_x - float(_attempt["reach"]), _origin_x + float(_attempt["reach"]))
	_passed = false
	if _attempt["kind"] == "grab":
		_performer.set_pose(&"run")
	else:
		_performer.set_pose(&"idle")
	set_phase(Phase.COMMIT, str(_attempt["kind"]))
	Sfx.play(&"step_wet", -9.0)


func step_commit() -> void:
	var kind := str(_attempt["kind"])
	var feet := _rider.global_position
	var progress := minf(1.0, _elapsed / float(_attempt["commit"]))
	if kind == "grab":
		_performer.position.x = lerpf(_origin_x, _target_x, progress)
	var high := feet.y <= _high_y
	var passed := feet.x >= _active_x - GRAB_DISTANCE
	_passed = _passed or (passed and (kind != "smoke" or absf(feet.x - _origin_x) > GRAB_DISTANCE or high))
	if progress > 0.14 and not high and _rider.state != Player.State.DASH:
		var hits := false
		match kind:
			"grab": hits = absf(feet.x - _performer.position.x) < GRAB_DISTANCE
			"rope": hits = progress > 0.4 and feet.y >= _home.y - 7.0 and absf(feet.x - _origin_x) < float(_attempt["reach"])
			"block": hits = progress > 0.4 and absf(feet.x - _target_x) < GRAB_DISTANCE
		if hits:
			begin_hold()
			return
	if progress >= 1.0:
		_performer.release_gesture()
		if _passed:
			spend()
		else:
			begin_recovery()


func begin_hold() -> void:
	_rider.set_avoidance_held(true)
	_hold = 0.0
	_taps = 0
	_last_input = Input.is_action_pressed(&"interact")
	_performer.release_gesture()
	_performer.set_pose(&"idle")
	_performer.play_gesture(&"both_hands", true)
	set_phase(Phase.HELD, "held")


func step_escape(delta: float) -> void:
	var pressed := Input.is_action_pressed(&"interact")
	if pressed:
		_hold += delta
		if not _last_input:
			_taps += 1
	else:
		_hold = 0.0
	_last_input = pressed
	if _hold >= HOLD_SECONDS or _taps >= ESCAPE_PRESSES:
		_rider.set_avoidance_held(false)
		_performer.release_gesture()
		spend()
		return
	if _elapsed >= 1.9:
		_origin_x = _performer.position.x
		_performer.face(-1)
		_performer.set_pose(&"walk")
		set_phase(Phase.CARRIED, "carried")


func step_carry() -> void:
	var progress := minf(1.0, _elapsed / CARRY_SECONDS)
	_performer.position.x = lerpf(_origin_x, _retry.x, smoothstep(0.0, 1.0, progress))
	_rider.global_position = _performer.position + Vector2(6.0, 0.0)
	if progress >= 1.0:
		_rider.set_avoidance_held(false)
		_performer.release_gesture()
		_performer.face(1)
		set_phase(Phase.REST, "rest")


func spend() -> void:
	exerted += 1
	if exerted >= _spec.actions.size():
		_performer.face(1)
		_performer.set_pose(&"walk")
		set_phase(Phase.LEAVING, "leaving")
		return
	if exerted == 2:
		_home.x = _first_home_x + _phase_shift
	begin_recovery("second" if exerted == 2 else "evaded")


func begin_recovery(key := "evaded") -> void:
	_performer.face(1 if _performer.position.x < _home.x else -1)
	_performer.set_pose(&"walk")
	set_phase(Phase.RECOVER, key)


func reset_wait() -> void:
	_performer.set_pose(&"idle")
	set_phase(Phase.WAITING, "start")
	_hud.visible = exerted > 0


func retire() -> void:
	phase = Phase.COMPLETE
	set_physics_process(false)
	if _performer != null:
		_performer.hide()
		_performer.set_process(false)
	_coat_source.set_local_available(true)
	_coat_prop.show()
	_sync_coat_fold()
	_hud.hide()
	queue_redraw()


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag == _spec.identified and phase == Phase.COMPLETE:
		_sync_coat_fold()


func _sync_coat_fold() -> void:
	if not is_instance_valid(_coat_sprite) or _coat_sprite.texture == null:
		return
	if GameState.has_flag(_spec.identified):
		_coat_sprite.region_enabled = false
		_coat_sprite.position.y = 0.0
	else:
		# The world copy keeps the stitched label below the fold. The inspection owns the name reveal.
		var dimensions := _coat_sprite.texture.get_size()
		var fold := ceilf(dimensions.y * COAT_LABEL_FRACTION)
		_coat_sprite.region_rect = Rect2(0.0, fold, dimensions.x, dimensions.y - fold)
		_coat_sprite.region_enabled = true
		_coat_sprite.position.y = fold * _coat_sprite.scale.y


func set_phase(next: Phase, key: String) -> void:
	phase = next
	_elapsed = 0.0
	_hud.show()
	_meter.text = "%s  %s" % [_spec.copy_for("meter", Story.language),
		"■".repeat(_spec.actions.size() - exerted) + "□".repeat(exerted)]
	_copy.text = _spec.copy_for(key, Story.language).replace("{interact}", InputBindings.primary_label(&"interact"))
	queue_redraw()


func _draw() -> void:
	if phase not in [Phase.TELL, Phase.COMMIT]:
		return
	var kind := str(_attempt["kind"])
	if kind == "smoke" and phase == Phase.COMMIT:
		draw_texture_rect(LightKit.soft_texture(), Rect2(_home.x - 70.0, _home.y - 43.0, 140.0, 48.0), false, Color(0.53, 0.58, 0.65, 0.27))
	elif kind in ["rope", "block"]:
		var width := float(_attempt["reach"]) if kind == "rope" else GRAB_DISTANCE
		var x := _home.x if kind == "rope" else _target_x
		draw_line(Vector2(x - width, _home.y - 5.0), Vector2(x + width, _home.y - 5.0), Color(0.93, 0.64, 0.39, 0.68), 1.5, true)


func state_key() -> String:
	return String(_spec.id)


func capture_state() -> Variant:
	return exerted >= 2


func restore_state(value: Variant) -> void:
	if not value is bool:
		push_warning("[AvoidanceEncounter] %s has an invalid room checkpoint" % _spec.id)
		return
	exerted = 2 if value else 0
	_home.x = _first_home_x + (_phase_shift if value else 0.0)
	if _performer != null:
		_performer.position = _home
	if GameState.has_flag(_spec.identified):
		exerted = _spec.actions.size()
		retire()
