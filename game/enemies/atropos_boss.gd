extends PatternBoss
## The health thresholds stop combat. Only the enrolled story sources commit
## the handoff and the unlock, so defeat and cancelled scenes cannot grant them.

const MIDPOINT := &"ch4_atropos_midpoint_ready"
const DEPARTED := &"ch4_egret_departed"
const RETREAT := &"ch4_atropos_retreat_ready"
const OFFICE := &"ch4_office_access"
const RAIL_HOST := &"ch4_egret_at_rail"
const SWEEPS := &"ch4_arena_sweeps"
const RETREAT_SPEED_SCALE := 1.9
const SHUTTER_DEPTH := 16.0

var _retreat_exit_x := 0.0
var _retreat_limit := 0.0


func _setup_states() -> void:
	super._setup_states()
	fsm.add(&"work_hold", _hold_tick, _hold_enter)
	fsm.add(&"work_retreat", _retreat_tick, _retreat_enter)
	GameState.flag_changed.connect(_on_arena_flag)
	EventBus.player_died.connect(_on_player_died)
	health.floor_health = 1 if GameState.has_flag(DEPARTED) else _phase_boundary()
	if GameState.has_flag(RETREAT) or GameState.has_flag(OFFICE):
		_hold_enter()
		queue_free()
	elif GameState.has_flag(DEPARTED):
		health.current = _phase_boundary()
		_apply_phase(pattern.phase_for(_health_ratio(), phase_set), false)
	elif GameState.has_flag(MIDPOINT):
		health.current = _phase_boundary()
		fsm.transition(&"work_hold")


func _phase_boundary() -> int:
	return clampi(floori(health.max_health * float(pattern.phase_list()[0]["until"])), 1, maxi(1, health.max_health - 1))


func _wake() -> void:
	if _awake or fsm.is_in(&"work_hold") or is_queued_for_deletion():
		return
	super._wake()
	EventBus.mechanism_toggled.emit(SWEEPS, true)


func _on_health_changed(current: int, maximum: int) -> void:
	if _awake:
		EventBus.boss_health_changed.emit(current, maximum)
	if fsm.is_in(&"work_hold") or fsm.is_in(&"work_retreat") or not _has_living_player():
		return
	if not GameState.has_flag(DEPARTED) and current == _phase_boundary():
		fsm.transition(&"work_hold")
		_present_handoff.call_deferred()
	elif GameState.has_flag(DEPARTED) and current == 1:
		fsm.transition(&"work_retreat")


func _has_living_player() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	return is_instance_valid(player) and not player.is_dead()


func _on_arena_flag(id: StringName, value: Variant) -> void:
	if id == DEPARTED and value == true and fsm.is_in(&"work_hold") and _has_living_player():
		health.floor_health = 1
		_apply_phase(pattern.phase_for(_health_ratio(), phase_set), false)
		hurtbox.enabled = true
		if contact != null:
			contact.active = true
		if _awake:
			fsm.transition(&"intro")
			EventBus.mechanism_toggled.emit(SWEEPS, true)
		else:
			fsm.transition(&"dormant")


func _on_player_died(_cause: StringName) -> void:
	if not is_queued_for_deletion():
		fsm.transition(&"work_hold")
		if _awake:
			EventBus.boss_bar_closed.emit()


func _hold_enter() -> void:
	velocity = Vector2.ZERO
	_telegraph_left = 0.0
	_marks.clear()
	queue_redraw()
	hurtbox.enabled = false
	if contact != null:
		contact.active = false
	EventBus.mechanism_toggled.emit(SWEEPS, false)
	ProjectilePool.clear_in_radius(global_position, pattern.wake_range * 2.0, Combat.Team.ENEMY)


func _hold_tick(_delta: float) -> void:
	velocity = Vector2.ZERO


func _present_handoff() -> void:
	if not is_inside_tree() or not _has_living_player() or not fsm.is_in(&"work_hold"):
		return
	GameState.set_flag(MIDPOINT, true)
	var level := get_parent()
	while level != null and not level is Level:
		level = level.get_parent()
	if level is Level:
		for actor: NpcActor in level.npc_sources:
			if actor.data.id == RAIL_HOST and actor.is_present():
				# Its normal interaction remains available after cancellation.
				await actor._talk()
				return
	push_error("[Atropos] Missing the active arena host: %s" % RAIL_HOST)


func _retreat_enter() -> void:
	if _awake:
		EventBus.boss_bar_closed.emit()
	_hold_enter()
	facing = 1
	_retreat_exit_x = float(pattern.hooks.get("retreat_x", _anchor.x + 100.0))
	_retreat_limit = maxf(1.0, (_retreat_exit_x - global_position.x) / maxf(1.0, data.move_speed * RETREAT_SPEED_SCALE) + 0.8)


func _retreat_tick(_delta: float) -> void:
	var remaining := _retreat_exit_x - global_position.x
	if remaining <= 0.0 or fsm.time_in_state >= _retreat_limit:
		if _has_living_player():
			GameState.set_flag(RETREAT, true)
			queue_free()
		return
	modulate.a = clampf(remaining / SHUTTER_DEPTH, 0.0, 1.0)
	velocity.x = data.move_speed * RETREAT_SPEED_SCALE


func _rig_state(input: RigInput) -> void:
	super._rig_state(input)
	input.dashing = fsm.is_in(&"act") and _move_id == &"lane_lunge"


func _muzzle() -> Vector2:
	if _move_id == &"signal_burst":
		var wrist := anchor_node(&"hand_front")
		if wrist != null:
			return wrist.global_position + Vector2(facing * 2.0, 0.0)
	return super._muzzle()
