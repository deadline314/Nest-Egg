class_name StageLibrary
extends RefCounted
## 過場場景（舞台）庫：讀取 data/cutscene/stages/<id>.json 並快取。
## 檔案內容：{"layers": [圖層定義…], "camera": {"pos": [x, y], "zoom": 1.0}, "floor": 地面線 y, "floors": [其他地面線 y…]（可選，例如玻璃牆後的室內地面）, "ambient": "#hex"（可選）}

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
	var prop_ids := {}
	for layer: Variant in layers:
		index += 1
		if typeof(layer) != TYPE_DICTIONARY:
			problems.append("過場場景 %s 第 %d 層不是物件" % [id, index])
			continue
		var kind := str(layer.get("kind", ""))
		var state_issue := StageLayers.prop_state_problem(layer)
		if not state_issue.is_empty():
			problems.append("過場場景 %s 第 %d 層: %s" % [id, index, state_issue])
		if layer.has("id"):
			var prop_id := str(layer["id"])
			if prop_ids.has(prop_id):
				problems.append("過場場景 %s 有重複物件: %s" % [id, prop_id])
			prop_ids[prop_id] = true
		if not StageLayers.KINDS.has(kind):
			problems.append("過場場景 %s 第 %d 層種類「%s」不存在" % [id, index, kind])
			continue
		for key in StageLayers.KINDS[kind]:
			if not (layer as Dictionary).has(key):
				problems.append("過場場景 %s 第 %d 層（%s）缺少「%s」" % [id, index, kind, key])
		if kind == "sprite" and RigLibrary.texture_size(str(layer.get("path", ""))) == Vector2.ZERO:
			problems.append("過場場景 %s 第 %d 層圖片不存在：%s" % [id, index, layer.get("path", "")])
		if kind == "grain" and str(layer.get("reason", "")).strip_edges().is_empty():
			problems.append("過場場景 %s 第 %d 層是顆粒卻沒寫 reason：一般舞台不加顆粒，回憶或非現實的舞台要寫明理由" % [id, index])
		if kind == "sprite" and life_covers_stage(layer):
			problems.append("過場場景 %s 第 %d 層是整張背景卻開了 life：窗光閃爍會把整張圖切成一格一格忽明忽暗的方塊，life 只能用在窗光等小面積的層" % [id, index])
		var anchor_issue := ScenerySupport.stage_anchor_issue(layer, def)
		if not anchor_issue.is_empty():
			problems.append("過場場景 %s 第 %d 層支撐無效：%s" % [id, index, anchor_issue])
	problems.append_array(_parent_problems(id, layers))
	return problems


static func _parent_problems(id: StringName, layers: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	var named := {}
	var edges := {}
	for layer: Variant in layers:
		if layer is Dictionary and layer.get("id") is String:
			named[layer["id"]] = layer
	for layer: Variant in layers:
		if not layer is Dictionary or not layer.has("parent_prop") or not StageSpriteGeometry.problem(layer).is_empty():
			continue
		if edges.size() >= 8:
			problems.append("stage %s exceeds eight parent-prop links" % id)
			break
		var parent: Dictionary = named.get(layer["parent_prop"], {})
		var point := StageLayers.vec2_of(layer["anchor"])
		var frame := StageSpriteGeometry.source_frame(parent)
		var inside := frame.has_area() and point.x >= frame.position.x and point.y >= frame.position.y and point.x <= frame.end.x and point.y <= frame.end.y
		if parent.get("kind") != "sprite" or not inside:
			problems.append("stage %s prop %s has a missing parent or an anchor outside its source region" % [id, layer["id"]])
		edges[layer["id"]] = layer["parent_prop"]
	for child: String in edges:
		var current := child
		var seen := {}
		while edges.has(current):
			if seen.has(current):
				problems.append("stage %s has a cyclic prop anchor at %s" % [id, child])
				break
			seen[current] = true
			current = edges[current]
	return problems


## 舞台的大小（邏輯像素）。
const STAGE_SIZE := Vector2(640, 360)
## 開了 life 的圖層蓋住舞台面積的比例達到這個值，就是整張背景。
const LIFE_MAX_COVER := 0.9


## 這一層開了 life（窗光閃爍：每 16 像素一格、約兩成的格子忽明忽暗），而且大到蓋住整個舞台：
## 整張背景都會出現一格一格的深色方塊（像破圖）。life 只能用在窗光、信標這類小面積或只在窗戶處有亮度的層。
static func life_covers_stage(layer: Dictionary) -> bool:
	if not bool(layer.get("life", false)):
		return false
	var native := RigLibrary.texture_size(str(layer.get("path", "")))
	if native == Vector2.ZERO:
		return false
	var size := native * StageLayers.sprite_scale_for_width(layer, native.x)
	return size.x * size.y >= STAGE_SIZE.x * STAGE_SIZE.y * LIFE_MAX_COVER


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
			var anchor_issue := ScenerySupport.stage_anchor_issue(layer_def, def)
			if not anchor_issue.is_empty():
				push_warning("[Stage] %s 第 %d 層支撐無效（%s），已略過" % [id, index, anchor_issue])
				continue
			var node := StageLayers.create(layer_def, "場景 %s 第 %d 層" % [id, index])
			if node != null:
				stage.add_layer(node)
	stage.resolve_prop_parents()
	var cam: Dictionary = def.get("camera", {})
	stage.default_camera_pos = StageLayers.vec2_of(cam.get("pos"), Stage.CENTER)
	stage.default_camera_zoom = float(cam.get("zoom", 1.0))
	stage.floor_y = float(def.get("floor", NAN))
	return stage


## 舞台節點：由後往前 back → actors → front。
class Stage:
	extends Node2D

	const CENTER := Vector2(320, 180)

	var stage_id: StringName = &""
	var default_camera_pos := CENTER
	var default_camera_zoom := 1.0
	## 地面線（演員腳底的舞台 y）；舞台資料的 floor 欄位，沒有登記就是 NAN。坐著的演員站起來時腳要落回這條線。
	var floor_y := NAN
	var back := Node2D.new()
	var actors := Node2D.new()
	var front := Node2D.new()
	var _props: Dictionary = {}
	var _held: Array[StagePropHold] = []

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 10  # 演員（0）完成 IK 後才跟隨掌心。
		set_process(false)
		# 背景各層排在所有演員零件之下、前景各層排在其上；演員零件的 z 從 -9 到 +7（後側的手腳零件比背景預設的 0 還低）。
		back.z_index = WorldLayers.STAGE_BACK
		front.z_index = WorldLayers.STAGE_FRONT
		add_child(back)
		add_child(actors)
		add_child(front)
		actors.y_sort_enabled = true

	func add_layer(node: Node2D) -> void:
		if node.has_meta(&"prop_id"):
			var id := str(node.get_meta(&"prop_id"))
			if _props.has(id):
				push_error("[Stage] %s duplicate prop: %s" % [stage_id, id])
				node.free()
				return
			_props[id] = node
		(front if str(node.get_meta(&"depth", "back")) == "front" else back).add_child(node)

	func set_prop_state(id: String, state: String) -> bool:
		return _props.has(id) and _props[id] is StageLayers._Sprite and _props[id].set_prop_state(state)

	func prop_state(id: String) -> String:
		return _props[id].prop_state() if _props.has(id) and _props[id] is StageLayers._Sprite else ""

	func prop_node(id: String) -> Node2D:
		var node: Node2D = _props.get(id)
		return node if is_instance_valid(node) else null

	func set_prop_visible(id: String, value: bool) -> bool:
		var node := prop_node(id)
		if node == null:
			return false
		if not node.has_meta(&"visible_process_mode"):
			node.set_meta(&"visible_process_mode", node.process_mode)
		node.visible = value
		node.process_mode = node.get_meta(&"visible_process_mode") if value else Node.PROCESS_MODE_DISABLED
		return true

	func initial_props(props: Variant) -> String:
		var issue := CutscenePropAction.initial_problem(props)
		if not issue.is_empty():
			return issue
		# 先驗整批，避免壞掉的最後一筆只留下半套爐火／水壺狀態。
		for id: String in props:
			var node := prop_node(id)
			if node == null:
				return "initial prop is not registered: " + id
			var record: Dictionary = props[id]
			if record.has("pos") and node is StageLayers._Sprite and node.anchored():
				return "initial prop cannot move an anchored child: " + id
			if record.has("state") and (not node is StageLayers._Sprite or not node.supports_prop_state(record["state"])):
				return "initial prop state is unavailable: " + id
		for id: String in props:
			var node := prop_node(id)
			var record: Dictionary = props[id]
			if record.has("state"):
				set_prop_state(id, record["state"])
			if record.has("pos"):
				node.position = StageLayers.vec2_of(record["pos"])
			if record.has("angle"):
				node.rotation = float(record["angle"])
			if record.has("visible"):
				set_prop_visible(id, record["visible"])
		return ""

	func prop_held(id: String) -> bool:
		for hold: StagePropHold in _held:
			if hold.prop_id == id:
				return true
		return false

	func resolve_prop_parents() -> void:
		var count := 0
		for id: String in _props:
			var child := prop_node(id) as StageLayers._Sprite
			if child == null or not child.has_meta(&"parent_prop"):
				continue
			var parent := prop_node(str(child.get_meta(&"parent_prop"))) as StageLayers._Sprite
			count += 1
			var issue := child.anchor_to(parent, child.get_meta(&"anchor")) if count <= 8 else "stage exceeds eight parent-prop links"
			if not issue.is_empty():
				child.hide()
				child.process_mode = Node.PROCESS_MODE_DISABLED
				push_error("[Stage] %s/%s: %s" % [stage_id, id, issue])

	func hold_prop(id: String, actor: CutsceneActor, hand: StringName, source_point: Vector2) -> String:
		if _held.size() >= 8 or prop_held(id):
			return "prop is already held or the eight-prop hold limit was reached"
		for existing: StagePropHold in _held:
			if existing.owns_hand(actor, hand):
				return "hand is already holding another stage prop"
		var sprite := prop_node(id) as StageLayers._Sprite
		if sprite == null:
			return "held prop must be a named stage sprite"
		if sprite.anchored():
			return "anchored child cannot be independently held"
		var hold := StagePropHold.new()
		var issue := hold.setup(id, sprite, actor, hand, source_point, self)
		if not issue.is_empty():
			return issue
		_held.append(hold)
		hold.update(self)
		set_process(true)
		return ""

	func release_prop(id: String) -> bool:
		for index in _held.size():
			if _held[index].prop_id == id:
				_held[index].release()
				_held.remove_at(index)
				set_process(not _held.is_empty())
				return true
		return false

	func release_actor_props(actor: CutsceneActor) -> void:
		var index := _held.size() - 1
		while index >= 0:
			if _held[index].owns_actor(actor):
				_held[index].release()
				_held.remove_at(index)
			index -= 1
		set_process(not _held.is_empty())

	func _process(_delta: float) -> void:
		var index := _held.size() - 1
		while index >= 0:
			if not _held[index].update(self):
				_held.remove_at(index)
			index -= 1
		set_process(not _held.is_empty())

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
