class_name StageLibrary
extends RefCounted
## 過場場景（舞台）庫：讀取 data/cutscene/stages/<id>.json 並快取。
## 檔案內容：{"layers": [圖層定義…], "camera": {"pos": [x, y], "zoom": 1.0}, "ambient": "#hex"（可選）}

const DIR := "res://data/cutscene/stages"

static var _cache: Dictionary[StringName, Dictionary] = {}


static func path_of(id: StringName) -> String:
	return "%s/%s.json" % [DIR, id]


static func exists(id: StringName) -> bool:
	return ResourceLoader.exists(path_of(id))


## 所有舞台 id（檢查工具與測試用）。
static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".json") or file.ends_with(".json.remap"):
			result.append(StringName(file.get_basename().get_basename() if file.ends_with(".remap") else file.get_basename()))
	return result


## 讀取舞台定義；缺檔或格式錯誤回傳空字典並記錄。
static func definition(id: StringName) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var result: Dictionary = {}
	var path := path_of(id)
	var json: JSON = load(path) as JSON if ResourceLoader.exists(path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[Stage] 無法讀取過場場景：%s" % path)
	else:
		result = json.data
	_cache[id] = result
	return result


## 回傳檢查問題（空代表通過）：圖層種類、必填欄位。
static func validate(id: StringName) -> PackedStringArray:
	var problems := PackedStringArray()
	var def := definition(id)
	if def.is_empty():
		problems.append("過場場景 %s 讀不到" % id)
		return problems
	var layers: Variant = def.get("layers", [])
	if typeof(layers) != TYPE_ARRAY or (layers as Array).is_empty():
		problems.append("過場場景 %s 沒有任何圖層" % id)
		return problems
	var index := 0
	for layer: Variant in layers:
		index += 1
		if typeof(layer) != TYPE_DICTIONARY:
			problems.append("過場場景 %s 第 %d 層不是物件" % [id, index])
			continue
		var kind := str(layer.get("kind", ""))
		if not StageLayers.KINDS.has(kind):
			problems.append("過場場景 %s 第 %d 層種類「%s」不存在" % [id, index, kind])
			continue
		for key in StageLayers.KINDS[kind]:
			if not (layer as Dictionary).has(key):
				problems.append("過場場景 %s 第 %d 層（%s）缺少「%s」" % [id, index, kind, key])
		if kind == "sprite" and RigLibrary.optional_texture(str(layer.get("path", ""))) == null:
			problems.append("過場場景 %s 第 %d 層圖片不存在：%s" % [id, index, layer.get("path", "")])
	return problems


## 建立舞台節點：back／actors／front 三組，由底到頂。
static func build(id: StringName) -> Stage:
	var def := definition(id)
	var stage := Stage.new()
	stage.stage_id = id
	var layers: Variant = def.get("layers", [])
	if typeof(layers) == TYPE_ARRAY:
		var index := 0
		for layer_def: Variant in layers:
			index += 1
			if typeof(layer_def) != TYPE_DICTIONARY:
				continue
			var node := StageLayers.create(layer_def, "場景 %s 第 %d 層" % [id, index])
			if node != null:
				stage.add_layer(node)
	var cam: Dictionary = def.get("camera", {})
	stage.default_camera_pos = StageLayers.vec2_of(cam.get("pos"), Stage.CENTER)
	stage.default_camera_zoom = float(cam.get("zoom", 1.0))
	return stage


## 舞台節點：由後往前 back → actors → front。
class Stage:
	extends Node2D

	const CENTER := Vector2(320, 180)

	var stage_id: StringName = &""
	var default_camera_pos := CENTER
	var default_camera_zoom := 1.0
	var back := Node2D.new()
	var actors := Node2D.new()
	var front := Node2D.new()

	func _init() -> void:
		# 背景各層排在所有演員零件之下、前景各層排在其上；演員零件的 z 從 -9 到 +7（後側的手腳零件比背景預設的 0 還低）。
		back.z_index = WorldLayers.STAGE_BACK
		front.z_index = WorldLayers.STAGE_FRONT
		add_child(back)
		add_child(actors)
		add_child(front)
		actors.y_sort_enabled = true

	func add_layer(node: Node2D) -> void:
		(front if str(node.get_meta(&"depth", "back")) == "front" else back).add_child(node)

	## 依鏡頭位置更新各層視差：parallax 1 = 隨舞台、0 = 固定在畫面。
	func apply_parallax(camera_pos: Vector2) -> void:
		var offset := camera_pos - CENTER
		for group: Node2D in [back, front]:
			for layer in group.get_children():
				var node := layer as Node2D
				var p := float(node.get_meta(&"parallax", 1.0))
				if p != 1.0:
					node.position = _home(node) + offset * (1.0 - p)

	func _home(node: Node2D) -> Vector2:
		if not node.has_meta(&"home"):
			node.set_meta(&"home", node.position)
		return node.get_meta(&"home")
