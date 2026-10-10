extends "res://pm/Nest-Egg/attachments/NE-222-death-action-priority/replay/capture_helper.gd"

const CASES := [
	{"skin": "enforcer", "state": &"dazed", "data": "res://data/enemies/shield_rusher.tres", "final_time": 0.84},
	{"skin": "heavy_gunner", "state": &"vent", "data": "res://data/enemies/heavy_gunner.tres", "final_time": 0.84},
	{"skin": "warden", "state": &"phase_shift", "data": "res://data/enemies/warden.tres", "final_time": 1.20},
]
const DEATH_SAMPLES := [0.0, 0.2, 0.5, 0.8]
const MAX_WAIT_FRAMES := 300
const SOURCE_FILES := [
	"res://pm/Nest-Egg/attachments/NE-222-death-action-priority/replay/capture_helper.gd",
	"res://game/enemies/enemy.gd",
	"res://game/enemies/warden_boss.gd",
	"res://game/rig/humanoid_animator.gd",
	"res://art/rigs/action_poses.json",
]
var _preflight_only := false


func _ready() -> void:
	# Keep this orchestration node alive during a render-only SceneTree pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()


func _run() -> void:
	print("DEATH_ACTION_CAPTURE_START staged_fsm=true facing=1 incoming=front")
	_preflight_only = OS.get_cmdline_user_args().has("--preflight")
	if (not _capture_enabled and not _preflight_only) or (_capture_enabled and _output.is_empty()):
		_fail("requires --capture --out=<new absolute directory>")
		await _finish(1)
		return
	if _capture_enabled:
		var absolute := ProjectSettings.globalize_path(_output)
		if not absolute.is_absolute_path():
			_fail("capture output must resolve to an absolute path")
			await _finish(1)
			return
		_output = absolute
		if DirAccess.dir_exists_absolute(_output):
			_fail("refusing to reuse an existing capture directory: %s" % _output)
			await _finish(1)
			return
		DirAccess.make_dir_recursive_absolute(_output)
	await _start_level()
	if not is_instance_valid(_level) or not is_instance_valid(_level.player):
		_fail("actual Level fixture failed to construct")
		await _finish(1)
		return

	var manifest := {
		"purpose": "actual enemy death-animation timeline; staged preceding FSM states, not organic combat",
		"engine": Engine.get_version_info(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"checkout_head": _checkout_head(),
		"source_sha256": _selected_source_hashes(),
		"hit_direction": "front; source origin = enemy position + facing * 24px",
		"facing": 1,
		"enemy_physics_enabled": true,
		"samples_requested_seconds": [0.0, 0.2, 0.5, 0.8],
		"frames": [],
		"checks": 0,
		"failures": [],
	}
	_check(not str(manifest["checkout_head"]).is_empty(), "capture records checkout HEAD")
	_check((manifest["source_sha256"] as Dictionary).size() == SOURCE_FILES.size(), "capture pins all selected runtime/source files")
	for entry: Dictionary in CASES:
		var skin := str(entry["skin"])
		var state: StringName = entry["state"]
		var data := load(str(entry["data"])) as EnemyData
		_check(data != null and data.validate().is_empty(), "%s EnemyData loads and validates" % skin)
		if data == null:
			continue
		var enemy := await _spawn_actual_enemy(data, 1)
		if enemy == null or enemy.rig == null:
			_fail("%s failed to spawn an actual rigged enemy" % skin)
			continue
		enemy.fsm.transition(state)
		await _settle_actor()
		var old_action := String(enemy._rig_input.action)
		var old_action_t := enemy._rig_input.action_t
		_check(not old_action.is_empty(), "%s staged state selects an action before death" % skin)
		var death := DamageInfo.create(enemy.health.current, Combat.Team.PLAYER, &"death_timeline_capture")
		death.ignore_invulnerability = true
		death.bypass_guard = true
		death.origin = enemy.global_position + Vector2(float(enemy.facing) * 24.0, -12.0)
		var hit_direction_is_front := (enemy.global_position.x - death.origin.x) * enemy.facing < 0.0
		_check(hit_direction_is_front, "%s lethal hit source is on the facing/front side" % skin)
		var hit_result := enemy.hurtbox.receive(death)
		_check(hit_result == Hurtbox.Result.DAMAGED and enemy.is_dying(), "%s dies through the actual Hurtbox path" % skin)
		_check(enemy.is_physics_processing(), "%s keeps the real enemy physics loop enabled while dying" % skin)
		print("DEATH_CASE_BEGIN %s %s" % [skin, JSON.stringify({
			"staged_fsm_state": String(state),
			"action_at_hit": old_action,
			"action_t_at_hit": old_action_t,
			"hit_result": hit_result,
			"front_hit": hit_direction_is_front,
			"physics_processing": enemy.is_physics_processing(),
		})])

		var animator := enemy.rig.animator
		for target_time: float in DEATH_SAMPLES:
			if not await _wait_for_death_sample(enemy, target_time):
				_fail("%s failed to reach death sample %.2fs before timeout" % [skin, target_time])
				break
			if _capture_enabled:
				var row := await _capture_render_frozen(enemy, skin, "death_t%s" % _time_token(target_time), target_time, old_action, animator)
				manifest["frames"].append(row)
			else:
				_check(enemy._rig_input.dead and float(animator.get("_death_time")) >= target_time,
					"%s preflight reaches death timer %.2fs" % [skin, target_time])
		var final_time := float(entry["final_time"])
		if final_time > DEATH_SAMPLES.back():
			if await _wait_for_death_sample(enemy, final_time):
				if not _capture_enabled:
					_check(enemy._rig_input.dead and float(animator.get("_death_time")) >= final_time,
						"%s preflight reaches pre-fade timer %.2fs" % [skin, final_time])
				else:
					var final_row := await _capture_render_frozen(enemy, skin, "death_pre_fade_t%s" % _time_token(final_time), final_time, old_action, animator)
					final_row["pre_fade_sample"] = true
					manifest["frames"].append(final_row)
			else:
				_fail("%s failed to reach pre-fade sample %.2fs before timeout" % [skin, final_time])
		_check(enemy.is_physics_processing(), "%s enemy physics remains enabled through captured death timeline" % skin)
		if enemy.get_parent() != null:
			enemy.get_parent().remove_child(enemy)
		if is_instance_valid(enemy):
			enemy.free()
		_cleanup_capture_entities()
		await get_tree().process_frame

	await _end_level()
	_check(_selected_source_hashes() == manifest["source_sha256"], "selected source files remain unchanged during the capture run")
	manifest["frames_count"] = manifest["frames"].size()
	if _capture_enabled:
		manifest["unique_paths"] = _unique_frame_paths(manifest["frames"])
		_check(manifest["frames_count"] == 15, "three staged enemy timelines produced 15 samples including pre-fade frames")
		_check(manifest["unique_paths"] == manifest["frames_count"], "death timeline image paths are unique")
	manifest["checks"] = _checks
	manifest["failures"] = _failures.duplicate()
	if _capture_enabled:
		var manifest_file := FileAccess.open(_output.path_join("manifest.json"), FileAccess.WRITE)
		if manifest_file == null:
			_fail("cannot write death timeline manifest")
		else:
			manifest_file.store_string(JSON.stringify(manifest, "\t"))
			manifest_file.close()
	print("DEATH_ACTION_CAPTURE_RESULT checks=%d failures=%d frames=%d output=%s" % [_checks, _failures.size(), manifest["frames_count"], _output])
	await _finish(0 if _failures.is_empty() else 1)


func _wait_for_death_sample(enemy: Enemy, target_time: float) -> bool:
	for _frame in MAX_WAIT_FRAMES:
		if not is_instance_valid(enemy) or enemy.rig == null:
			return false
		if enemy._rig_input.dead and float(enemy.rig.animator.get("_death_time")) >= target_time:
			return true
		await get_tree().physics_frame
	return false


func _capture_render_frozen(enemy: Enemy, skin: String, state: String, target_time: float, old_action: String, animator: Object) -> Dictionary:
	var tree := get_tree()
	var was_paused := tree.paused
	var time_before_freeze := float(animator.get("_death_time"))
	# Pause the world only while the renderer resolves and reads this sample.
	# The enemy's physics/tween remain enabled but receive no simulation ticks.
	tree.paused = true
	var row := await _capture_frame(enemy, skin, state, 1, 3.4, "level", "actual-hurtbox-death-timeline")
	var time_after_draw := float(animator.get("_death_time"))
	_enrich_sample(row, enemy, animator, target_time, old_action)
	row["capture_scene_tree_paused"] = true
	row["capture_simulation_advanced"] = not is_equal_approx(time_before_freeze, time_after_draw)
	row["death_time_before_render_freeze"] = time_before_freeze
	row["death_time_after_render_freeze"] = time_after_draw
	row["enemy_physics_processing_enabled_during_freeze"] = enemy.is_physics_processing()
	_check(is_equal_approx(time_before_freeze, time_after_draw), "%s frozen render sample %.2fs did not advance death time" % [skin, target_time])
	tree.paused = was_paused
	return row


func _enrich_sample(row: Dictionary, enemy: Enemy, animator: Object, target_time: float, old_action: String) -> void:
	row["sample_target_death_time"] = target_time
	row["actual_death_time_at_capture"] = float(animator.get("_death_time"))
	row["rig_dead_input"] = enemy._rig_input.dead
	row["old_action_at_hit"] = old_action
	row["action_at_capture"] = String(enemy._rig_input.action)
	row["action_t_at_capture"] = enemy._rig_input.action_t
	row["action_weight_at_capture"] = float(animator.get("_action_w"))
	row["enemy_physics_processing"] = enemy.is_physics_processing()
	row["enemy_dying"] = enemy.is_dying()
	row["fsm_state_at_capture"] = String(enemy.fsm.current)
	row["fsm_time_at_capture"] = enemy.fsm.time_in_state
	_check(enemy._rig_input.dead, "%s sample at %.2fs has dead rig input" % [row["skin"], target_time])
	_check(enemy.is_physics_processing(), "%s sample at %.2fs retains enemy physics" % [row["skin"], target_time])
	row["old_action_still_selected"] = String(enemy._rig_input.action) == old_action


func _selected_source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in SOURCE_FILES:
		if FileAccess.file_exists(path):
			hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	return hashes
