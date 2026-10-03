class_name ScenePackScenario
extends ScenarioBase
## 開發工具（BG-15）：預覽場景包。每個場景一張截圖：場景背景圖（art/environment/scenes/<id>.webp）上，
## 該場景的所有專屬物件（data/environment/scene_props/<id>/*.tres）依遊戲內的比例並排站在地板線上，
## 套用光影預設的環境光；物件的法線、自發光、閃爍、蒸汽照遊戲內的方式運作（直接用 PropNode）。
## 沒有指定場景時依序輸出全部有背景或有物件的場景，並印出每個場景的物件數與缺圖清單。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=scene_packs [--scene=<id>] [--lighting=neutral] [--floor=292]
## 缺背景圖、缺貼圖或資料錯誤時指出具體路徑並繼續下一個場景。

const VIEW := Vector2(640, 360)
const BACKGROUND_DIR := "res://art/environment/scenes"
const PACK_DIR := "res://data/environment/scene_props"
const PAD := 14.0

var _only := ""
var _lighting := "neutral"
var _floor_y := 292.0


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_only = arg.trim_prefix("--scene=")
		elif arg.begins_with("--lighting="):
			_lighting = arg.trim_prefix("--lighting=")
		elif arg.begins_with("--floor="):
			_floor_y = float(arg.trim_prefix("--floor="))
	var ids := _scene_ids()
	print("== scene packs: %d scene(s)" % ids.size())
	var total_props := 0
	for id in ids:
		total_props += await _preview(id)
	print("== %d props in %d scene(s)" % [total_props, ids.size()])


## 有背景圖或有物件資料夾的場景 id（排序）。
func _scene_ids() -> PackedStringArray:
	var found: Dictionary[String, bool] = {}
	for file in DirAccess.get_files_at(BACKGROUND_DIR):
		if file.ends_with(".webp") and not file.ends_with("_glow.webp"):
			found[file.get_basename()] = true
	for dir in DirAccess.get_directories_at(PACK_DIR):
		found[dir] = true
	var ids := PackedStringArray(found.keys())
	ids.sort()
	if _only != "":
		return PackedStringArray([_only]) if ids.has(_only) else PackedStringArray()
	return ids


func _preview(id: String) -> int:
	var root := Node2D.new()
	add_child(root)
	var modulate := CanvasModulate.new()
	modulate.color = _profile_color("ambient_color", Color(0.5, 0.5, 0.55))
	root.add_child(modulate)
	# 背景圖本身已經畫好光影：放在另一個畫布層，只乘光影預設的背景色調，不再乘環境光（否則夜景會暗兩次）。
	var backdrop := CanvasLayer.new()
	backdrop.layer = -10
	root.add_child(backdrop)
	root.add_child(LightKit.create_environment())
	var problems: PackedStringArray = []
	var bg_path := "%s/%s.webp" % [BACKGROUND_DIR, id]
	if ResourceLoader.exists(bg_path):
		var sprite := Sprite2D.new()
		sprite.texture = load(bg_path) as Texture2D
		sprite.centered = false
		sprite.scale = VIEW / Vector2(sprite.texture.get_size())
		sprite.modulate = _profile_color("background_tint", Color.WHITE)
		backdrop.add_child(sprite)
		var glow_path := "%s/%s_glow.webp" % [BACKGROUND_DIR, id]
		if ResourceLoader.exists(glow_path):
			var glow := Sprite2D.new()
			glow.texture = load(glow_path) as Texture2D
			glow.centered = false
			glow.scale = sprite.scale
			glow.material = LightKit.additive_emissive_material()
			backdrop.add_child(glow)
	else:
		problems.append("缺場景背景：" + bg_path)
	var count := 0
	var x := PAD
	var dir := "%s/%s" % [PACK_DIR, id]
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var data := load("%s/%s" % [dir, file]) as PropData
		if data == null:
			problems.append("無法讀取物件資料：%s/%s" % [dir, file])
			continue
		var issues := data.validate()
		if not issues.is_empty():
			problems.append_array(issues)
			problems.append("（新生成的圖要先 godot --headless --import 才找得到）")
			continue
		var node := PropNode.new()
		node.setup(data, Vector2(x, _floor_y - data.size.y))
		root.add_child(node)
		x += data.size.x + PAD
		count += 1
		if x > VIEW.x:  # 一排放不下就換到更靠左的第二層（畫面左半的牆邊）
			x = PAD
	print("%-28s props %2d  %s" % [id, count, "OK" if problems.is_empty() else "；".join(problems)])
	await settle(8)
	await wait(0.4)
	capture("scene_" + id)
	root.queue_free()
	await settle(2)
	return count


func _profile_color(property: String, fallback: Color) -> Color:
	var path := "res://data/lighting/%s.tres" % _lighting
	if ResourceLoader.exists(path):
		var profile = load(path)
		if profile != null and property in profile:
			return profile.get(property)
	push_error("[ScenePack] 找不到光影預設或欄位：%s（%s）" % [path, property])
	return fallback
