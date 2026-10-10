extends Node
## Arranged native physics checks on authored maps; not a chapter playthrough.
## Suppress story cues in this visual-only fixture, never grant story results.
const Capture := preload("res://tools/viewport_capture.gd")
const MAPS := ["res://data/levels/ch1_street.tres", "res://data/levels/ch1_vault.tres"]
var _out := ""
var _checks := 0
var _failures := 0
var _records: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/")
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[FreeEncounterProbe] requires native renderer and absolute output")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _check(value: bool, text: String) -> void:
	_checks += 1
	_failures += int(not value)
	print("FREE_ENCOUNTER_CHECK:", "PASS" if value else "FAIL", ":", text)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := Capture.image(get_viewport()).save_png(_out.path_join(name + ".png"))
	_check(error == OK, "native PNG written: " + name)

func _run() -> void:
	for bound_action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(bound_action)
		Input.action_release(bound_action)
	GameState.story_autosave = false
	var zone_count := 0
	for path: String in MAPS:
		Story.reset_progress()
		GameState.start_new_run(GameState.difficulties[1])
		var data := (load(path) as LevelData).duplicate() as LevelData
		data.intro_scene = &""
		data.show_chapter_card = false
		var level := Level.new()
		level.configure(data)
		add_child(level)
		level._layout.story_triggers.clear()
		var zones: Array[EncounterZone] = []
		for child: Node in level._entities.get_children():
			if child is EncounterZone:
				var zone := child as EncounterZone
				zone.data = zone.data.duplicate() as MechanismData
				zone.data.start_scene = &""
				zones.append(zone)
		await _frames(3)
		for zone: EncounterZone in zones:
			zone_count += 1
			var gates: Array[Gate] = []
			for child: Node in level._entities.get_children():
				if child is Gate and child.data.arena_gate and child.data.channel == zone.data.channel:
					gates.append(child as Gate)
			_check(gates.size() == 2, "%s has two original authored gate locations" % zone.data.id)
			if gates.size() != 2:
				continue
			gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.position.x < b.position.x)
			_check(gates.all(func(g: Gate) -> bool: return g.is_open and not g.visible and g.collision_layer == 0 and g._shape_node == null), "%s former gates contain no collision or visual" % zone.data.id)
			for gate: Gate in gates:
				for direction: float in [-1.0, 1.0]:
					for dash: bool in [false, true]:
						for bound_action: StringName in InputMap.get_actions():
							Input.action_release(bound_action)
						level.player.position = gate.position + Vector2(-direction * 40.0, -2.0)
						level.player.velocity = Vector2.ZERO
						level.player.health.grant_invulnerability(10.0)
						await _frames(8)
						level.camera.snap_to_target()
						var before: Vector2 = level.player.position
						var started_outside: bool = direction * (before.x - gate.position.x) < -Player.BODY_SIZE.x
						_check(started_outside, "%s begins physical crossing on requested side at %s" % [zone.data.id, gate.cell])
						var move_action := &"move_right" if direction > 0.0 else &"move_left"
						Input.action_press(move_action)
						if dash:
							Input.action_press(&"dash")
							await _frames(1)
							Input.action_release(&"dash")
						await _frames(28)
						Input.action_release(move_action)
						var after: Vector2 = level.player.position
						var crossed: bool = direction * (after.x - gate.position.x) > Player.BODY_SIZE.x
						_check(crossed, "%s physical %s %s through original gate at %s" % [zone.data.id, "dash" if dash else "walk", "right" if direction > 0.0 else "left", gate.cell])
						_records.append({"level": path, "encounter": String(zone.data.id), "gate_cell": [gate.cell.x, gate.cell.y], "direction": direction, "dash": dash, "before": [before.x, before.y], "after": [after.x, after.y], "crossed": crossed, "state": String(zone.state), "living_members": zone.living_members()})
						if not dash and ((gate == gates[0] and direction > 0.0) or (gate == gates[1] and direction < 0.0)):
							await _capture("NE-245-" + String(zone.data.id) + ("-left" if gate == gates[0] else "-right"))
						await _frames(45)
			_check(zone.state == &"active" and zone.living_members() > 0, "%s remains active with living members after free escape and return" % zone.data.id)
		level.queue_free()
		await _frames(4)
	_check(zone_count == 4, "all four authored chapter-one encounters were visited")
	Story.reset_progress()
	var report := {"checks": _checks, "failures": _failures, "records": _records, "native_driver": DisplayServer.get_name(), "engine": Engine.get_version_info(), "scope": "arranged actual authored Levels and Input actions; story intro/triggers/start cues suppressed; temporary invulnerability; not human/full Main playthrough"}
	var file := FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FREE_ENCOUNTER_SUMMARY:", JSON.stringify(report))
	get_tree().quit(0 if _failures == 0 else 1)
