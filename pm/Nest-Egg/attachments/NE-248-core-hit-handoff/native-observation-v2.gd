extends "res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.gd"

var _out_dir := ""
var _revision := ""

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--head="):
			_revision = arg.trim_prefix("--head=")
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{40}$")
	if not _out_dir.is_absolute_path() or pattern.search(_revision) == null:
		printerr("ERROR: absolute --out and hexadecimal --head required")
		get_tree().quit(2)
		return
	if DirAccess.dir_exists_absolute(_out_dir) and (not DirAccess.get_files_at(_out_dir).is_empty() or not DirAccess.get_directories_at(_out_dir).is_empty()):
		printerr("ERROR: output directory must be empty")
		get_tree().quit(2)
		return
	_capture_dir = _out_dir.path_join("images")
	if DirAccess.make_dir_recursive_absolute(_capture_dir) != OK:
		printerr("ERROR: cannot create output directory")
		get_tree().quit(2)
		return
	_started_msec = Time.get_ticks_msec()
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	await _run_warden_case()
	_finish()

func _record(kind: String, data: Dictionary) -> void:
	super._record(kind, data)
	if kind == "NE81_core_player_hit":
		_check(bool(data.get("resolved_core_part", false)), "real exposed-core projectile resolves core with weak_hit=true")

func _fire_at_enemy(player: Player, target: Vector2, label: String, follow_enemy := false, follow_part: Hurtbox = null) -> Dictionary:
	if label == "NE81_exposed_core_damage":
		# Keep the diagnostic shot on the unobstructed right side after real knockback
		# has driven the encounter to the left wall; leave boss state/HP untouched.
		player.global_position = _enemy.global_position + Vector2(80.0, 0.0)
		player.velocity = Vector2.ZERO
		player.facing = -1
		player.aim_dir = (follow_part.center() - player.global_position - Vector2(0.0,-40.0)).normalized()
		await _physics_frames(2)
		_record("controlled_core_shot_position", {"player":_vec(player.global_position), "enemy":_vec(_enemy.global_position)})
	return await super._fire_at_enemy(player,target,label,follow_enemy,follow_part)

func _finish() -> void:
	var report := {"head":_revision, "checks":_checks, "failures":_failures, "events":_events,
		"godot":Engine.get_version_info(), "status":"REGRESSION_RED_NOT_ACCEPTED",
		"source_sha256":{}}
	for path: String in ["res://.godot/ne81-core-real-hit/native_probe.gd", "res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.gd", "res://game/projectiles/projectile.gd", "res://core/components/hurtbox.gd", "res://game/enemies/enemy.gd", "res://game/enemies/warden_boss.gd", "res://data/enemies/warden.tres"]:
		report["source_sha256"][path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(_out_dir.path_join("red-report.json"), FileAccess.WRITE)
	if file == null:
		printerr("ERROR: cannot save regression report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CORE_PROBE checks=%d failures=%d" % [_checks,_failures.size()])
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2,true,false,true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
