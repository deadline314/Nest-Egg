class_name Gate
extends StaticBody2D
## 閘門：擋路。同頻道的開關啟動時打開（滑進天花板），關閉時放下。原點在底邊中點。
## 門閂門（MechanismData.latch_side，NE-430）：站在門閂那一側按互動鍵拉開，之後一直開著（回頭的捷徑）；另一側只看到一句提示。

const SLIDE_SPEED := 3.0
## 門閂門：離門多近（水平，從門邊算起；垂直，從門底算起）可以拉門閂。
const LATCH_REACH := Vector2(30.0, 48.0)
const LATCH_PROMPT_RANGE := Vector2(64.0, 64.0)
const LATCH_STEEL := Color("8796a6")
const LATCH_DARK := Color("2a3038")

var data: MechanismData
var cell := Vector2i.ZERO
var is_open := false

var _size := Vector2(16, 64)
## 0 = 關閉、1 = 完全打開（動畫用）。
var _openness := 0.0
var _shape_node: CollisionShape2D
var _prompt: WorldPrompt
var _time := 0.0
## 捲門板的貼圖（依閘門大小平鋪，開門時高度跟著縮）；讀不到時是 null，改用簡單畫法。
var _art: Sprite2D
var _player_ref := PlayerRef.new()
var _on_latch_side := true


func configure(p_data: MechanismData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_size = Vector2(data.size_tiles) * tile_size


func _ready() -> void:
	if data == null:
		push_error("[Gate] 未指定 MechanismData，已移除。")
		queue_free()
		return
	if data.is_retired_arena_gate():
		# 舊的一般遭遇門沒有封路用途：不建立碰撞、遮光或門板，也不加入持久世界。
		is_open = true
		collision_layer = 0
		hide()
		set_process(false)
		return
	LightKit.mark_emissive(self)
	_art = FixtureArt.attach(self, &"gate_shutter", Vector2(-_size.x * 0.5, -_size.y), _size, true)
	collision_layer = Layers.WORLD
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = _size
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = shape
	_shape_node.position = Vector2(0, -_size.y * 0.5)
	add_child(_shape_node)
	var occluder := LightOccluder2D.new()
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(-_size.x * 0.5, -_size.y), Vector2(_size.x * 0.5, -_size.y), Vector2(_size.x * 0.5, 0), Vector2(-_size.x * 0.5, 0)])
	occluder.occluder = polygon
	LightKit.mark_shadow_occluder(occluder)
	add_child(occluder)
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.radius = 64.0
		_prompt.offset = Vector2(0, -_size.y - 10.0)
		add_child(_prompt)
	EventBus.mechanism_toggled.connect(_on_channel_toggled)
	if data.is_latch_door():
		if _prompt == null:
			_prompt = WorldPrompt.new()
			_prompt.radius = 64.0
			_prompt.offset = Vector2(0, -_size.y - 10.0)
			add_child(_prompt)
		_prompt.reach_check = _latch_prompt_in_reach
		_prompt.interaction_owner = self
		Story.framing.register_target(self)
	set_physics_process(data.is_latch_door())
	if data.arena_gate:
		# 競技場閘門：重生與重新進場時一定是打開的，不存進世界狀態。
		_set_open(true, true)
	else:
		add_to_group(WorldState.GROUP)


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if is_open else 0.0
	if not is_equal_approx(_openness, target) or not is_open:
		_openness = move_toward(_openness, target, SLIDE_SPEED * delta)
		queue_redraw()


# ---------------------------------------------------------------------------
# 門閂門（NE-430）
# ---------------------------------------------------------------------------

func preview_available() -> bool:
	return false


## 站在門閂那一側、離門夠近、門還關著：按互動鍵就拉得開。
func interaction_available() -> bool:
	if not data.is_latch_door() or is_open:
		return false
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return false
	var at := player.global_position - global_position
	return at.x * data.latch_side > 0.0 and absf(at.x) <= _size.x * 0.5 + LATCH_REACH.x and absf(at.y) <= LATCH_REACH.y


func _latch_prompt_in_reach() -> bool:
	if is_open:
		return false
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return false
	var at := player.global_position - global_position
	return absf(at.x) <= LATCH_PROMPT_RANGE.x and absf(at.y) <= LATCH_PROMPT_RANGE.y


func _physics_process(_delta: float) -> void:
	if is_open or data == null or not data.is_latch_door() or _prompt == null:
		set_physics_process(false)
		return
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return
	var latch_side := (player.global_position.x - global_position.x) * data.latch_side > 0.0
	if latch_side != _on_latch_side or _prompt.text.is_empty():
		_on_latch_side = latch_side
		_prompt.text = data.hint_for(Story.language) if latch_side else data.latch_blocked_text_for(Story.language)
		# 門閂那一側是互動提示（被選中才顯示）；另一側只是說明，走近就顯示。
		_prompt.interaction_owner = self if latch_side else null
	if Input.is_action_just_pressed(&"interact") and interaction_available() and Story.framing.is_interaction_target(self):
		open_latch()


## 拉開門閂：門打開並一直開著。已經開了就不做事；回傳有沒有拉開。
func open_latch() -> bool:
	if not data.is_latch_door() or is_open:
		return false
	_set_open(true, false)
	Sfx.play(&"switch", -3.0)
	Fx.burst(global_position + Vector2(data.latch_side * _size.x * 0.5, -_size.y * 0.5), LATCH_STEEL, 6, 70.0, 0.25)
	return true


func _on_channel_toggled(channel: StringName, active: bool) -> void:
	if channel == &"":
		return
	if channel == data.channel:
		# 競技場閘門與一般閘門相反：頻道啟動（遭遇開始）時關上，結束時打開。
		_set_open(not active if data.arena_gate else active, false)


func _set_open(open: bool, silent: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_shape_node.set_deferred(&"disabled", open)
	# 說明講的是「為什麼關著」，打開後就收起。
	if _prompt != null:
		_prompt.enabled = not open
	if silent:
		_openness = 1.0 if open else 0.0
		queue_redraw()
	else:
		Sfx.play(&"gate", -3.0)
		Feel.play(&"gate_open")


func state_key() -> String:
	return "gate@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return is_open


func restore_state(state: Variant) -> void:
	if data != null and data.is_retired_arena_gate():
		is_open = true
		return
	_set_open(state == true, true)


func _draw() -> void:
	# 閘板往上收：打開時只剩頂端一小段。
	var visible_height := lerpf(_size.y, 6.0, _openness)
	var rect := Rect2(Vector2(-_size.x * 0.5, -_size.y), Vector2(_size.x, visible_height))
	if _art != null:
		FixtureArt.resize(_art, rect.size, true)
		# 捲門底緣的橫桿。
		draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), Palette.TERRAIN_TOP)
	else:
		draw_rect(rect, Palette.TERRAIN_FILL)
		var y := rect.position.y + 4.0
		while y < rect.end.y:
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y + 6.0), Palette.TERRAIN_EDGE, 2.0)
			y += 12.0
		draw_rect(rect, Palette.TERRAIN_TOP, false, 1.0)
	# 閘板中央的狀態燈：關閉時發紅（頻道顏色），打開時熄滅。
	var closed := 1.0 - _openness
	if data.is_latch_door() and closed > 0.05:
		_draw_latch(closed)
	if closed > 0.05:
		var glow := LightKit.glow(data.color, (1.2 + 0.4 * sin(_time * 3.0)) * closed)
		draw_line(Vector2(0, rect.position.y + 4), Vector2(0, rect.end.y - 4), glow, 2.0)


## 門閂：門閂那一側門板中段的一支橫插栓加兩個托架；打開時跟著收起。
func _draw_latch(closed: float) -> void:
	var side := float(data.latch_side)
	var edge := side * _size.x * 0.5
	var y := -_size.y * 0.5
	var bolt := Color(LATCH_STEEL, closed)
	var dark := Color(LATCH_DARK, closed)
	var reach := 9.0 * closed
	# 托架：門板上一個、門框上一個。
	draw_rect(Rect2(edge - side * 4.0 - 1.5, y - 4.0, 3.0, 8.0), dark)
	draw_rect(Rect2(edge + side * 6.0 - 1.5, y - 4.0, 3.0, 8.0), dark)
	# 插栓本體與把手。
	var start := edge - side * 6.0
	draw_line(Vector2(start, y), Vector2(start + side * (6.0 + reach), y), bolt, 2.0)
	draw_line(Vector2(start + side * 2.0, y), Vector2(start + side * 2.0, y + 4.0), bolt, 2.0)
