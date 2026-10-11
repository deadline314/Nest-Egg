class_name Portal
extends Area2D
## 出入口節點（PortalData 的實體）：互動或走進去就請求切換區域。原點在底邊中點。
## 玩家從這裡出現時（entry）暫時不觸發，等他離開一次再啟用，避免來回彈跳。
## 缺旗標或沒有目標的門只顯示提示文字，不會切換。

signal used(portal: Portal)

const PROMPT_LOCKED_RADIUS := 56.0
const LOCKED_TOAST_COOLDOWN := 1.2
## 門貼圖上狀態燈燈座的位置與大小（占門寬、門高的比例）：對應 cel_fixtures.py 的 door()。
const DOOR_LAMP := Rect2(0.0, 0.5 / 48.0, 4.0 / 28.0, 2.0 / 48.0)
## 梯子貼圖上扶手外緣的位置（占梯寬的比例）：對應 cel_fixtures.py 的 ladder()。
const LADDER_RAIL_EDGE := 2.5 / 20.0

var data: PortalData
var cell := Vector2i.ZERO

var _player_in_range := false
## false＝剛從這裡出現，玩家離開前不觸發。
var _armed := true
var _time := 0.0
var _toast_left := 0.0
var _prompt: WorldPrompt
var _cinematic_notice: WorldPrompt
var _preview_valid := false
## 門或梯子的貼圖（墊在後面的子節點）；讀不到貼圖時是 null，改用簡單畫法。
var _art: Sprite2D


func configure(p_data: PortalData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[Portal] 未指定 PortalData，已移除。")
		queue_free()
		return
	for problem in data.validate():
		push_error("[Portal] %s" % problem)
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(data.width, data.height)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -data.height * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = WorldPrompt.new()
	_prompt.text = data.default_prompt()
	_prompt.radius = maxf(PROMPT_LOCKED_RADIUS, data.width * 0.5 + 24.0)
	_prompt.reach_check = func() -> bool: return _player_in_range and _armed and data.mode == PortalData.Mode.INTERACT
	_prompt.offset = Vector2(0, -data.height - 10.0)
	add_child(_prompt)
	if data.cinematic_preview_scene != &"":
		var target := load(data.target_level) as LevelData if ResourceLoader.exists(data.target_level) else null
		_preview_valid = target != null and target.intro_scene == data.cinematic_preview_scene \
			and Story.has_scene(data.cinematic_preview_scene) \
			and Story.scene_mode(data.cinematic_preview_scene) in [Story.MODE_CINEMATIC, Story.MODE_ANIMATED] \
			and Story.uses_cinematic_framing(data.cinematic_preview_scene)
		if not _preview_valid:
			push_error("[Portal] %s 的電影預告 %s 必須對應目標區域的正式intro：%s" % [data.id, data.cinematic_preview_scene, data.target_level])
		else:
			Story.framing.register_target(self)
			_cinematic_notice = WorldPrompt.new()
			_cinematic_notice.text = "前方將播放劇情。"
			_cinematic_notice.offset = Vector2(-20, -data.height - 10)
			_cinematic_notice.reach_check = func() -> bool:
				return preview_available() and not _player_in_range and Story.framing.selected_target() == self
			add_child(_cinematic_notice)
	var frame_top_left := Vector2(-data.width * 0.5, -float(data.height))
	if data.style == "ladder":
		_art = FixtureArt.attach(self, &"ladder_segment", frame_top_left, Vector2(data.width, data.height), true)
	elif data.style != "road" and data.style != "hidden":
		_art = FixtureArt.attach(self, &"door_steel", frame_top_left, Vector2(data.width, data.height))
	if data.style != "road" and data.style != "hidden":
		var light := LightKit.create_point_light(_accent(), 70.0, 0.5, false)
		light.position = Vector2(0, -data.height * 0.5)
		add_child(light)


## 玩家從這個出入口出現：離開一次之前不觸發。
func disarm() -> void:
	_armed = false


func is_armed() -> bool:
	return _armed


## 現在能不能通行（旗標滿足、有目標）。
func is_open() -> bool:
	if data == null or data.is_locked_door():
		return false
	return data.requires_flag == &"" or GameState.has_flag(data.requires_flag)


func preview_available() -> bool:
	return _preview_valid and _armed and is_open() and not Story.was_seen(data.cinematic_preview_scene)


func interaction_available() -> bool:
	return _armed and _player_in_range and data.mode == PortalData.Mode.INTERACT


## 嘗試使用：可通行就發出 used，否則顯示鎖住的提示。回傳是否通行。
func try_use() -> bool:
	if not is_open():
		if _toast_left <= 0.0 and not data.locked_text.is_empty():
			_toast_left = LOCKED_TOAST_COOLDOWN
			EventBus.toast_requested.emit(data.locked_text)
		return false
	if _preview_valid:
		Story.framing.interaction_started(self)
	used.emit(self)
	return true


func _physics_process(delta: float) -> void:
	_time += delta
	_toast_left = maxf(0.0, _toast_left - delta)
	if _player_in_range and _armed and data.mode == PortalData.Mode.INTERACT \
			and Input.is_action_just_pressed(&"interact") and not get_tree().paused \
			and (not _preview_valid or Story.framing.is_interaction_target(self)):
		var player := get_tree().get_first_node_in_group(&"player") as Player
		if player != null and not player.is_dead():
			try_use()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) == null:
		return
	_player_in_range = true
	if _armed and data.mode == PortalData.Mode.WALK:
		try_use()


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) == null:
		return
	_player_in_range = false
	_armed = true


func _accent() -> Color:
	if data.is_locked_door() or (data.requires_flag != &"" and not GameState.has_flag(data.requires_flag)):
		return Palette.DANGER.darkened(0.2)
	return Palette.NEON_YELLOW if data.style == "door" else Palette.CYAN


func _draw() -> void:
	if data == null:
		return
	var half := data.width * 0.5
	var top := -float(data.height)
	var accent := _accent()
	match data.style:
		"ladder":
			if _art != null:
				# 梯子本體是貼圖；扶手外側留一條淡淡的亮線，暗處也看得出這裡可以爬。
				var edge := Color(accent, 0.55)
				var rail_x := data.width * LADDER_RAIL_EDGE
				draw_line(Vector2(-half + rail_x, 0.0), Vector2(-half + rail_x, top), edge, 1.0)
				draw_line(Vector2(half - rail_x, 0.0), Vector2(half - rail_x, top), edge, 1.0)
				return
			var rail := Color(accent, 0.9)
			draw_line(Vector2(-half + 3.0, 0.0), Vector2(-half + 3.0, top), rail, 1.5)
			draw_line(Vector2(half - 3.0, 0.0), Vector2(half - 3.0, top), rail, 1.5)
			var y := -4.0
			while y > top:
				draw_line(Vector2(-half + 3.0, y), Vector2(half - 3.0, y), Color(accent, 0.7), 1.0)
				y -= 8.0
		"hidden":
			pass  # 門就是擺設本身，只留互動範圍與提示
		"road":
			# 街口：地面上兩個淡淡的箭頭，沒有門框。
			var pulse := 0.5 + 0.5 * sin(_time * 3.0)
			var color := Color(accent, 0.25 + 0.2 * pulse)
			for i in 2:
				var x := -4.0 + float(i) * 8.0
				draw_polyline(PackedVector2Array([Vector2(x, -10.0), Vector2(x + 4.0, -6.0), Vector2(x, -2.0)]), color, 1.2)
		_:
			if _art != null:
				# 門框頂端的狀態燈：上鎖是紅色，可以進去是黃色。
				var lamp := Vector2(data.width * DOOR_LAMP.size.x, data.height * DOOR_LAMP.size.y)
				draw_rect(Rect2(Vector2(-lamp.x * 0.5, top + data.height * DOOR_LAMP.position.y), lamp), LightKit.glow(accent, 1.8))
				return
			var frame := Rect2(-half, top, data.width, data.height)
			draw_rect(frame, Color(0.03, 0.04, 0.06, 0.55))
			draw_rect(frame, LightKit.glow(accent, 1.2), false, 1.5)
			draw_line(Vector2(0.0, top + 3.0), Vector2(0.0, -3.0), Color(accent, 0.25), 1.0)
