extends "res://tests/smoke_test.gd"
## Native numerical observation of the actual seven-owner regression, not gameplay.
var _observer: Variant
var _out := ""
var _label := ""
var _rows: Array[Dictionary] = []
const BOUNDARIES := ["RESPAWN SAME POSITION", "STAGE ENTRY", "STAGE CANCEL", "STAGE COMPLETE", "MAP READING ENTRY", "MAP READING EXIT", "REPLAY EXIT"]

class Chart extends Control:
	var rows: Array[Dictionary] = []
	var label_text := ""
	var failed := 0
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(0, 0, 640, 360), Color("101926"))
		draw_string(font, Vector2(12, 22), "SOFTWARE FORWARD+ / LIFECYCLE API FIXTURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_string(font, Vector2(12, 43), "%s | assertions failed: %d | NOT HUMAN PLAY" % [label_text, failed], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e9b86b"))
		draw_string(font, Vector2(12, 63), "Max spring velocity [rad/s] BEFORE / AFTER; common scale 0 to 0.25", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b6c5d7"))
		var maximum := 0.25
		for row in rows:
			assert(maxf(float(row.before.max_velocity_rad_s), float(row.after.max_velocity_rad_s)) <= maximum, "native chart range must cover every measured value")
		for i in rows.size():
			var row := rows[i]
			var y := 92.0 + i * 29.0
			var a := float(row.before.max_velocity_rad_s)
			var c := float(row.after.max_velocity_rad_s)
			draw_string(font, Vector2(12, y + 10), row.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
			draw_rect(Rect2(202, y, 255.0 * a / maximum, 7), Color("e9b86b"))
			if c > 0.0:
				draw_rect(Rect2(202, y + 10, 255.0 * c / maximum, 7), Color("42cfb0"))
			else:
				draw_line(Vector2(202, y + 10), Vector2(202, y + 17), Color("42cfb0"), 1.0)
			draw_string(font, Vector2(472, y + 13), "%.4f / %.4f" % [a, c], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d7e8f0"))
		draw_string(font, Vector2(12, 337), "Real Player/Story APIs; fixed running prime; original rest assertions retained.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("b6c5d7"))
		draw_string(font, Vector2(12, 352), "Radio row must keep motion. All seven presentation boundaries must reset it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("b6c5d7"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="): _label = arg.trim_prefix("--label=")
	_run_observed.call_deferred()

func _check(condition: bool, message: String) -> void:
	super._check(condition, message)
	if message == "ordinary radio keeps the ongoing secondary simulation" and _observer != null:
		_observer.captured_states.append(_observer.snapshot_springs(_observer.last_animator, "radio_after"))

func _run_observed() -> void:
	assert(not _out.is_empty())
	Enemy.activation_culling_enabled = false
	_observer = load("res://work/lifecycle_observer.gd").new(self)
	await _observer._test_secondary_motion_lifecycle()
	var before := {}
	var index := 0
	for state: Dictionary in _observer.captured_states:
		if state.kind == "before":
			before = state
		elif state.kind == "after":
			_rows.append({"name": BOUNDARIES[index], "before": before, "after": state})
			index += 1
		elif state.kind == "radio_after":
			_rows.append({"name": "ORDINARY RADIO: KEEP", "before": before, "after": state})
	assert(index == 7 and _rows.size() == 8)
	var report := {"kind": "arranged native numerical observer, not human gameplay", "label": _label,
		"engine": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "checks": _checks, "failures": _failures,
		"player_visual_sha256": FileAccess.get_file_as_string("res://game/player/player_visual.gd").sha256_text(),
		"test_sha256": FileAccess.get_file_as_string("res://tests/suite/test_protagonist_motion.gd").sha256_text(), "rows": _rows}
	var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	var layer := CanvasLayer.new()
	layer.layer = 1000
	add_child(layer)
	var chart := Chart.new()
	chart.rows = _rows
	chart.label_text = _label
	chart.failed = _failures.size()
	layer.add_child(chart)
	chart.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_out.path_join("frame.png")) == OK)
	print("LIFECYCLE_NATIVE checks=", _checks, " failures=", _failures.size())
	get_tree().quit(_failures.size())
