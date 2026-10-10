extends "res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.gd"
## Expected red: actual player projectile must resolve the naturally exposed core.

func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	await _run_warden_case()
	_finish()

func _record(kind: String, data: Dictionary) -> void:
	super._record(kind, data)
	if kind == "NE81_core_player_hit":
		_check(bool(data.get("resolved_core_part", false)), "real exposed-core projectile resolves core with weak_hit=true")

func _finish() -> void:
	var file := FileAccess.open("res://.godot/ne81-core-real-hit/red-report.json", FileAccess.WRITE)
	_check(file != null, "focused core diagnostic output opens")
	if file != null:
		file.store_string(JSON.stringify({"purpose": "actual projectile exposed-core probe; expected red if main Hurtbox masks core", "head": "212768fa4a98e9db5bb1b3f4c067ef6027c7547d", "checks": _checks, "failures": _failures, "events": _events, "fixture_sha256": FileAccess.get_sha256("res://.godot/ne79-ne80-ne81-organic-combat/enforcer_preflight.gd")}, "\t"))
	print("CORE_PROBE checks=%d failures=%d" % [_checks, _failures.size()])
	await get_tree().create_timer(0.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
