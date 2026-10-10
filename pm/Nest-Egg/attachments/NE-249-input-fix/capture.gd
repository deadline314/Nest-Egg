extends "res://tests/smoke_test.gd"

var suite: EncounterSuite
var captured := false
var output := "user://NE-249-free-exit.png"
var snapshot: Dictionary = {}

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	AimInput.using_gamepad = true
	AimInput.restore_direction(Vector2.RIGHT)
	suite = EncounterSuite.new(self)
	await suite._test_free_encounter()
	_check(captured, "native capture completed at real free-exit assertion")
	await _finish()

func _check(condition: bool, message: String) -> void:
	super._check(condition, message)
	if message != "the player can physically leave while both members remain alive":
		return
	assert(condition)
	var zones := suite.level._entities.get_children().filter(func(n: Node) -> bool: return n is EncounterZone)
	var gates := suite.level._entities.get_children().filter(func(n: Node) -> bool: return n is Gate)
	var zone: EncounterZone = zones[0]
	var alive := zone._members.filter(func(w: WeakRef) -> bool: return is_instance_valid(w.get_ref()) and not w.get_ref().is_dying()).size()
	snapshot = {"player_x": suite.level.player.global_position.x, "zone": str(zone.state), "living_members": alive, "gate_collision": [gates[0].collision_layer, gates[1].collision_layer], "gate_x": gates[0].global_position.x, "entry_frames": 60, "exit_frames": 60, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name()}
	assert(alive == 2 and zone.state == &"active" and gates[0].collision_layer == 0 and gates[1].collision_layer == 0)
	get_tree().paused = true
	_capture.call_deferred()

func _capture() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(12, 62)
	label.add_theme_font_size_override("font_size", 16)
	label.text = "NE-249 actual test exit | x=%.2f < %.2f\n2 living enemies | active encounter | gate collision: 0 / 0" % [snapshot.player_x, snapshot.gate_x - 12.0]
	layer.add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(is_equal_approx(suite.level.player.global_position.x, float(snapshot.player_x)))
	var png := preload("res://tools/viewport_capture.gd").image(get_viewport())
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	assert(png.save_png(output) == OK)
	snapshot["image_size"] = [png.get_width(), png.get_height()]
	snapshot["hdr_2d"] = get_viewport().use_hdr_2d
	var report := FileAccess.open(output + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify(snapshot, "\t") + "\n")
	print("NE249_NATIVE ", JSON.stringify(snapshot))
	captured = true
	get_tree().paused = false
