extends Node2D
## 燈具一覽（BG-36）：把每一款場景燈具排成一列，各用它自己的安裝方式（吊在天花板、裝在牆上、立桿、站在地上），
## 能掛在桿子上的款式再多排一格掛在桿子上的樣子（標籤後面加 @pole）；拍亮著與熄滅各一張。新增或重畫燈具後用它看大小、支撐、發光部位與光的顏色。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/lamp_gallery.tscn -- --out=<絕對資料夾> [--tag=<標籤>] [--ambient=0.25]
## 輸出 <標籤>-lit.png、<標籤>-unlit.png 與 <標籤>-index.json（每一款的安裝方式、大小、有沒有支撐）。

const Capture := preload("res://tools/viewport_capture.gd")
const SPACING := 76.0
const COLUMNS := 8
const ROW_HEIGHT := 184.0
const CEILING_DROP := 34.0
const FLOOR_DROP := 112.0
const WALL_COLOR := Color(0.36, 0.33, 0.4)
const SOLID_COLOR := Color(0.09, 0.09, 0.12)
const FIGURE_HEIGHT := 58.0

var _out := ""
var _tag := "lamps"
var _ambient := 0.25
var _lamps: Array[Lamp] = []


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--ambient="):
			_ambient = clampf(float(argument.trim_prefix("--ambient=")), 0.02, 1.0)
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[LampGallery] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[LampGallery] 無法建立輸出資料夾：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	var ambient := CanvasModulate.new()
	ambient.color = Color(_ambient, _ambient, _ambient * 1.15)
	add_child(ambient)
	var ids := LampFixtures.ids()
	var failures := LampFixtures.problems().size()
	for problem: String in LampFixtures.problems():
		push_error("[LampGallery] " + problem)
	# 每一款一格；能掛在桿子上的款式再加一格。
	var bays: Array[Array] = []
	for id: StringName in ids:
		bays.append([id, false])
	for id: StringName in ids:
		if LampFixtures.fixture(id).get("pole", &"") != &"":
			bays.append([id, true])
	var rows := ceili(float(bays.size()) / float(COLUMNS))
	var view := get_viewport().get_visible_rect().size
	var camera := Camera2D.new()
	camera.position = Vector2(float(COLUMNS) * SPACING * 0.5, float(rows) * ROW_HEIGHT * 0.5)
	camera.zoom = Vector2.ONE * minf(view.x / (float(COLUMNS) * SPACING + 24.0), view.y / (float(rows) * ROW_HEIGHT + 12.0))
	add_child(camera)
	camera.make_current()
	var records: Array[Dictionary] = []
	for index in bays.size():
		var origin := Vector2(float(index % COLUMNS) * SPACING, float(index / COLUMNS) * ROW_HEIGHT)
		records.append(_add_bay(bays[index][0], origin, bays[index][1]))
	LightKit.lamp_power = 1.0
	await _settle(30)
	Capture.image(get_viewport()).save_png(_out.path_join(_tag + "-lit.png"))
	LightKit.lamp_power = 0.0
	await _settle(20)
	Capture.image(get_viewport()).save_png(_out.path_join(_tag + "-unlit.png"))
	LightKit.lamp_power = 1.0
	for index in _lamps.size():
		records[index]["supported"] = _lamps[index].is_supported()
		if not _lamps[index].is_supported():
			failures += 1
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[LampGallery] 無法寫入索引：%s" % _out)
		failures += 1
	else:
		writer.store_string(JSON.stringify({"tag": _tag, "ambient": _ambient, "fixtures": records}, "\t"))
		writer.close()
	print("LAMP_GALLERY_RESULT:", ids.size(), " fixtures / ", bays.size(), " bays / ", failures, " failures")
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures == 0 else 1)


## 一格：背牆、天花板、地板、一個主角身高的比例尺，以及一盞用這款燈具的燈。
func _add_bay(id: StringName, origin: Vector2, on_pole := false) -> Dictionary:
	var entry := LampFixtures.fixture(id)
	var bay := Node2D.new()
	bay.position = origin
	add_child(bay)
	var wall := Polygon2D.new()
	wall.polygon = PackedVector2Array([Vector2(2, 0), Vector2(SPACING - 2, 0), Vector2(SPACING - 2, ROW_HEIGHT), Vector2(2, ROW_HEIGHT)])
	wall.color = WALL_COLOR
	wall.z_index = WorldLayers.BACK_WALL
	bay.add_child(wall)
	var ceiling_y := 14.0
	var floor_y := ceiling_y + CEILING_DROP + FLOOR_DROP
	for band: Rect2 in [Rect2(2, 0, SPACING - 4, ceiling_y), Rect2(2, floor_y, SPACING - 4, ROW_HEIGHT - floor_y)]:
		var solid := Polygon2D.new()
		solid.polygon = PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
		solid.color = SOLID_COLOR
		solid.z_index = WorldLayers.TERRAIN
		bay.add_child(solid)
	# 比例尺：主角站立的高度。
	var figure := Polygon2D.new()
	figure.polygon = PackedVector2Array([Vector2(8, floor_y - FIGURE_HEIGHT), Vector2(11, floor_y - FIGURE_HEIGHT), Vector2(11, floor_y), Vector2(8, floor_y)])
	figure.color = Color(0.75, 0.78, 0.85)
	bay.add_child(figure)
	var lamp := Lamp.new()
	lamp.position = origin + Vector2(SPACING * 0.5 + 6.0, ceiling_y + CEILING_DROP)
	var mount: StringName = &"pole" if on_pole else StringName(str(entry.get("mount", "")))
	lamp.floor_y = origin.y + floor_y
	lamp.ceiling_y = origin.y + ceiling_y if mount == &"ceiling" else INF
	lamp.radius = 120.0
	lamp.energy = 1.4
	lamp.flicker_chance = 0.0
	lamp.zone_tint = 0.0
	lamp.wall_behind = not on_pole
	lamp.use_fixture(id, {&"pole": true} if on_pole else {})
	add_child(lamp)
	_lamps.append(lamp)
	var label := Label.new()
	label.text = String(id) + ("@pole" if on_pole else "")
	label.position = origin + Vector2(3, ROW_HEIGHT - 12)
	label.add_theme_font_size_override("font_size", 6)
	label.material = LightKit.emissive_material()
	add_child(label)
	var prop := LampFixtures.prop(id)
	return {"id": String(id), "mount": String(mount), "size": [prop.size.x, prop.size.y] if prop != null else [0, 0]}


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
