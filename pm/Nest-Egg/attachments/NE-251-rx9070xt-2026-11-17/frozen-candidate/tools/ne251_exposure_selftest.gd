extends Node
## CPU-only contract checks for the native NE251 exposure gate. Negative cases naturally exit 1.

class Probe extends "res://tools/ne251_wake_probe.gd":
	func _ready() -> void:
		pass

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var probe := Probe.new()
	var selected := "all"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			selected = arg.trim_prefix("--case=")
	var failures := 0
	var checks := 0
	for name: String in ["valid", "blank", "tiny", "white", "washed", "non-hdr", "drift", "clipped-geometry", "missing-file", "black-bar"]:
		if selected != "all" and selected != name:
			continue
		var shown := Image.create(32, 32, false, Image.FORMAT_RGBH)
		var hidden := Image.create(32, 32, false, Image.FORMAT_RGBH)
		var mask := Image.create(32, 32, false, Image.FORMAT_RGBAH)
		shown.fill(Color(0.3, 0.3, 0.3))
		hidden.fill(Color(0.1, 0.1, 0.1))
		mask.fill(Color(1, 1, 1, 1))
		match name:
			"blank": mask.fill(Color.TRANSPARENT)
			"tiny":
				mask.fill(Color.TRANSPARENT)
				mask.set_pixel(1, 1, Color.WHITE)
			"white": shown.fill(Color(1.1, 1.1, 1.1))
			"washed":
				shown.fill(Color(0.85, 0.85, 0.85))
				hidden.fill(Color(0.82, 0.82, 0.82))
			"non-hdr": shown.convert(Image.FORMAT_RGB8)
		var stats: Dictionary = probe._head_stats(hidden, shown, mask, Rect2i(0, 0, 32, 32))
		stats.merge({"source_held": true, "probe_state_restored": true, "geometry_fits": true, "head_inside_content": true, "shown_stable": true, "hidden_stable": true, "files_ok": true})
		if name == "drift": stats["hidden_stable"] = false
		if name == "clipped-geometry": stats["geometry_fits"] = false
		if name == "missing-file": stats["files_ok"] = false
		if name == "black-bar": stats["head_inside_content"] = probe._inside_content(Rect2i(100, 40, 30, 60), CinematicFraming.rect_for(Vector2(1280, 720)))
		var passed: bool = probe._exposure_passes(stats)
		var expected := name == "valid"
		var correct := passed == expected if selected == "all" else passed
		checks += 1
		failures += int(not correct)
		print("NE251_CPU:", name, ":", "PASS" if correct else "FAIL", ":", JSON.stringify(stats))
	if selected == "all":
		var layer := CanvasLayer.new()
		layer.transform = Transform2D(0.0, Vector2(80, 50))
		get_tree().root.add_child(layer)
		var polygon := Polygon2D.new()
		polygon.polygon = PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 20), Vector2(0, 20)])
		polygon.position = Vector2(10, 15)
		layer.add_child(polygon)
		get_tree().root.add_child(probe)
		# Do not let the real native probe _ready run: only use its geometry method.
		var rect: Rect2i = probe._screen_rect([polygon])
		checks += 1
		var final := get_viewport().get_final_transform()
		var start := final * Vector2(90, 65)
		var end := final * Vector2(102, 85)
		var expected := Rect2i(Vector2i(floori(start.x), floori(start.y)), Vector2i(ceili(end.x) - floori(start.x), ceili(end.y) - floori(start.y)))
		var correct := rect == expected and rect.has_area()
		failures += int(not correct)
		print("NE251_CPU:Polygon2D stage canvas:", "PASS" if correct else "FAIL", ":", rect)
		var stage_parent := Node2D.new()
		stage_parent.scale = Vector2(1.2, 1.2)
		stage_parent.rotation = 0.1
		layer.add_child(stage_parent)
		var actor := Node2D.new()
		actor.scale = Vector2(2.95, 2.95)
		actor.position = Vector2(300, 300)
		stage_parent.add_child(actor)
		var viewport := get_viewport()
		var world_before := viewport.canvas_transform
		viewport.canvas_transform = Transform2D(0.0, Vector2(200, -43)).scaled(Vector2(0.3, 0.3))
		var image_before := viewport.get_final_transform() * actor.get_global_transform_with_canvas() * Vector2.ZERO
		probe._shift_actor_in_image(actor, Vector2(0, 22.7142868))
		var image_after := viewport.get_final_transform() * actor.get_global_transform_with_canvas() * Vector2.ZERO
		viewport.canvas_transform = world_before
		checks += 1
		var shift_correct := (image_after - image_before).distance_to(Vector2(0, 22.7142868)) < 0.001
		failures += int(not shift_correct)
		print("NE251_CPU:stage image shift ignores world camera and actor scale:", "PASS" if shift_correct else "FAIL", ":", image_after - image_before)
		layer.free()
		checks += 1
		var content := CinematicFraming.rect_for(Vector2(1280, 720))
		var fits: bool = probe._inside_content(Rect2i(100, 90, 30, 60), content) and not probe._inside_content(Rect2i(100, 40, 30, 60), content)
		failures += int(not fits)
		print("NE251_CPU:actual 21:9 top bar reject and visible head accept:", "PASS" if fits else "FAIL")
	probe.free()
	if checks == 0:
		failures += 1
	print("NE251_CPU_RESULT:", checks, "/", failures)
	get_tree().quit(0 if failures == 0 else 1)
