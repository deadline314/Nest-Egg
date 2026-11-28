class_name CrumblingWalkway
extends Node2D
## 會塌的走道：架在落差上的舊鐵走道，分成幾片單向平台（可以從底下跳上去，也可以按下加跳穿下去）。
## 有人（玩家或敵人）站上某一片，那一片先抖並裂開，warn_seconds 之後掉下去；空出來 respawn_seconds 之後，
## 那一片的位置沒有人時再補回來。站著不動就會跟著掉，所以要一路走過去。
## 原點在走道最左那一格的底邊中點（關卡的放法）；走道面是那一格的上緣，往右延伸 length_tiles 格。
## 不存進檢查點：重來時關卡重建，走道一律是完整的。「減少介面動態」時不抖，只靠裂痕與變色預警。

signal segment_warned(index: int)
signal segment_fell(index: int)

enum Piece { INTACT, WARNING, FALLEN, RETURNING }

const GROUP := &"crumbling_walkways"
## 碰撞厚度與地圖單向平台一樣（格子上緣的薄片）。
const DECK_THICKNESS := 6.0
## 腳底離走道面多近算站在上面。
const STAND_BAND := 4.0
## 補回前檢查這一片上方多高的範圍裡有沒有人（像素）。
const CLEAR_HEIGHT := 48.0
const FALL_GRAVITY := 900.0
const FALL_SECONDS := 0.8
const RETURN_SECONDS := 0.35
const SHAKE_PIXELS := 1.0
const SHAKE_RATE := 70.0
## 玩家離走道兩端多遠以內顯示提示（像素）。
const PROMPT_MARGIN := 56.0
const PROMPT_HEIGHT := 80.0

const DECK_COLOR := Color("2c333d")
const DECK_EDGE := Color("71859a")
const STRINGER_COLOR := Color("4a3b33")
const TRUSS_COLOR := Color("262b33")
const RUST_COLOR := Color(0.55, 0.3, 0.16, 0.6)
const HOLE_COLOR := Color("161a20")
const CRACK_COLOR := Color(1.0, 0.62, 0.25)

var data: CrumblingWalkwayData
var cell := Vector2i.ZERO
var length := 192.0

var _tile := 16.0
var _top := -16.0
var _starts := PackedFloat32Array()
var _widths := PackedFloat32Array()
var _state := PackedInt32Array()
## 預警剩幾秒／掉下去後過了幾秒／補回的進度（看狀態）。
var _timer := PackedFloat32Array()
var _drop := PackedFloat32Array()
var _drop_speed := PackedFloat32Array()
var _shapes: Array[CollisionShape2D] = []
var _sensor: Area2D
var _prompt: WorldPrompt
var _on_screen := true
var _animating := false
var _time := 0.0
var _player_ref := PlayerRef.new()


func configure(p_data: CrumblingWalkwayData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_tile = float(tile_size)
	_top = -_tile
	length = float(maxi(data.length_tiles, 1)) * _tile
	var step := float(maxi(data.segment_tiles, 1)) * _tile
	var x := 0.0
	while x < length - 0.5:
		_starts.append(x)
		_widths.append(minf(step, length - x))
		x += step
	_state.resize(_starts.size())
	_state.fill(Piece.INTACT)
	_timer.resize(_starts.size())
	_timer.fill(0.0)
	_drop.resize(_starts.size())
	_drop.fill(0.0)
	_drop_speed.resize(_starts.size())
	_drop_speed.fill(0.0)


func _ready() -> void:
	if data == null or _starts.is_empty():
		push_error("[CrumblingWalkway] 未指定 CrumblingWalkwayData 或長度為 0（格 %s），已移除。" % cell)
		queue_free()
		return
	add_to_group(GROUP)
	position.x -= _tile * 0.5  # 關卡把生成物放在格子中央；走道從格子左緣開始
	var body := StaticBody2D.new()
	body.name = "Deck"
	body.collision_layer = Layers.PLATFORM
	body.collision_mask = 0
	add_child(body)
	for i in _starts.size():
		var shape := RectangleShape2D.new()
		shape.size = Vector2(_widths[i], DECK_THICKNESS)
		var node := CollisionShape2D.new()
		node.shape = shape
		node.one_way_collision = true
		node.position = Vector2(_starts[i] + _widths[i] * 0.5, _top + DECK_THICKNESS * 0.5)
		body.add_child(node)
		_shapes.append(node)
	# 只用來找出走道上方的人；不擋任何東西。
	_sensor = Area2D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = Layers.PLAYER | Layers.ENEMY
	_sensor.monitorable = false
	var band := RectangleShape2D.new()
	band.size = Vector2(length, CLEAR_HEIGHT + STAND_BAND)
	var band_node := CollisionShape2D.new()
	band_node.shape = band
	band_node.position = Vector2(length * 0.5, _top - (CLEAR_HEIGHT - STAND_BAND) * 0.5)
	_sensor.add_child(band_node)
	add_child(_sensor)
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.reach_check = _prompt_in_reach
		_prompt.position = Vector2(minf(48.0, length * 0.5), _top)
		_prompt.offset = Vector2(0.0, -34.0)
		add_child(_prompt)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(Vector2(-8.0, _top - 8.0), Vector2(length + 16.0, 40.0))
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


func _on_screen_entered() -> void:
	_on_screen = true
	queue_redraw()


func _prompt_in_reach() -> bool:
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return false
	var at := player.global_position - global_position
	return at.x > -PROMPT_MARGIN and at.x < length + 8.0 and absf(at.y - _top) < PROMPT_HEIGHT


# ---------------------------------------------------------------------------
# 查詢（測試、截圖與其他系統用）
# ---------------------------------------------------------------------------

func segment_count() -> int:
	return _starts.size()


func segment_state(index: int) -> int:
	return _state[index] if index >= 0 and index < _state.size() else Piece.INTACT


func is_solid(index: int) -> bool:
	return index >= 0 and index < _state.size() and (_state[index] == Piece.INTACT or _state[index] == Piece.WARNING or _state[index] == Piece.RETURNING)


## 走道面的世界座標 y。
func deck_top() -> float:
	return global_position.y + _top


## 第 index 片走道面在世界座標的範圍（高度是碰撞的厚度）。
func segment_rect(index: int) -> Rect2:
	return Rect2(global_position + Vector2(_starts[index], _top), Vector2(_widths[index], DECK_THICKNESS))


## 世界座標 x 落在第幾片；不在走道範圍內回傳 -1。
func segment_at(world_x: float) -> int:
	var local := world_x - global_position.x
	if local < 0.0 or local >= length:
		return -1
	return clampi(int(local / (float(data.segment_tiles) * _tile)), 0, _starts.size() - 1)


# ---------------------------------------------------------------------------
# 每影格
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	var occupied := _occupied_segments()
	var crowded := -1  # 要補回時才查一次
	var any_moving := false
	for i in _state.size():
		match _state[i]:
			Piece.INTACT:
				if occupied & (1 << i):
					_warn(i)
					any_moving = true
			Piece.WARNING:
				_timer[i] -= delta
				if _timer[i] <= 0.0:
					_fall(i)
				any_moving = true
			Piece.FALLEN:
				_timer[i] += delta
				if _timer[i] < FALL_SECONDS:
					_drop_speed[i] += FALL_GRAVITY * delta
					_drop[i] += _drop_speed[i] * delta
					any_moving = true
				elif _timer[i] >= data.respawn_seconds:
					if crowded < 0:
						crowded = _crowded_segments()
					if not (crowded & (1 << i)):
						_state[i] = Piece.RETURNING
						_timer[i] = 0.0
						_drop[i] = 0.0
						_shapes[i].set_deferred(&"disabled", false)
						any_moving = true
			Piece.RETURNING:
				_timer[i] += delta / RETURN_SECONDS
				if _timer[i] >= 1.0:
					_state[i] = Piece.INTACT
					_timer[i] = 0.0
				any_moving = true
	if any_moving or _animating:
		_animating = any_moving
		if _on_screen:
			queue_redraw()


## 腳底踩在走道面上的人（玩家與敵人）各在哪一片：回傳位元遮罩。
func _occupied_segments() -> int:
	if not _sensor.has_overlapping_bodies():
		return 0
	var mask := 0
	var top := deck_top()
	for body in _sensor.get_overlapping_bodies():
		var mover := body as CharacterBody2D
		if mover == null or not mover.is_on_floor() or absf(mover.global_position.y - top) > STAND_BAND:
			continue
		var index := segment_at(mover.global_position.x)
		if index >= 0 and is_solid(index):
			mask |= 1 << index
	return mask


## 走道上方 CLEAR_HEIGHT 以內有人的那幾片：有人就先不補回，免得把人卡在平台裡。
func _crowded_segments() -> int:
	if not _sensor.has_overlapping_bodies():
		return 0
	var mask := 0
	for body in _sensor.get_overlapping_bodies():
		var node := body as Node2D
		if node == null:
			continue
		var index := segment_at(node.global_position.x)
		if index >= 0:
			mask |= 1 << index
	return mask


func _warn(index: int) -> void:
	_state[index] = Piece.WARNING
	_timer[index] = data.warn_seconds
	var rect := segment_rect(index)
	Fx.dust(Vector2(rect.get_center().x, rect.end.y), 3, rect.size.x * 0.8)
	Sfx.play(&"rattle", -9.0, 0.12)
	segment_warned.emit(index)


func _fall(index: int) -> void:
	_state[index] = Piece.FALLEN
	_timer[index] = 0.0
	_drop[index] = 0.0
	_drop_speed[index] = 0.0
	_shapes[index].set_deferred(&"disabled", true)
	var rect := segment_rect(index)
	Fx.dust(Vector2(rect.get_center().x, rect.position.y), 5, rect.size.x)
	Sfx.play(&"mat_metal", -5.0, 0.1)
	segment_fell.emit(index)


# ---------------------------------------------------------------------------
# 外觀：鋼格柵走道面、生鏽的側樑、底下的三角桁架；兩端有斜撐。不是一塊平板。
# ---------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return
	_draw_strut(Vector2(0.0, _top + 5.0), -1.0)
	_draw_strut(Vector2(length, _top + 5.0), 1.0)
	for i in _starts.size():
		var alpha := 1.0
		var offset := Vector2(shake_offset(i), 0.0)
		var angle := 0.0
		match _state[i]:
			Piece.FALLEN:
				if _timer[i] >= FALL_SECONDS:
					continue
				alpha = 1.0 - _timer[i] / FALL_SECONDS
				offset.y = _drop[i]
				angle = (0.35 if i % 2 == 0 else -0.3) * _timer[i] / FALL_SECONDS
			Piece.RETURNING:
				alpha = clampf(_timer[i], 0.0, 1.0)
		var pivot := Vector2(_starts[i] + _widths[i] * 0.5, _top)
		draw_set_transform(pivot + offset, angle)
		_draw_segment(i, -_widths[i] * 0.5, _widths[i], alpha)
	draw_set_transform(Vector2.ZERO)


## 預警中那一片左右抖動的距離（像素）；「減少介面動態」時不抖，只靠裂痕與變色。
func shake_offset(index: int) -> float:
	if segment_state(index) != Piece.WARNING or Settings.get_reduce_ui_motion():
		return 0.0
	return sin(_time * SHAKE_RATE + float(index) * 1.7) * SHAKE_PIXELS


## 一片走道，以走道面中點為原點：x0 是左緣，w 是寬度。
func _draw_segment(index: int, x0: float, w: float, alpha: float) -> void:
	var warned := _state[index] == Piece.WARNING
	var x1 := x0 + w - 1.0  # 片與片之間留 1 像素的縫
	# 桁架：上下弦加 V 字腹桿。
	draw_line(Vector2(x0 + 1.0, 11.0), Vector2(x1 - 1.0, 11.0), Color(TRUSS_COLOR, alpha), 1.0)
	var x := x0 + 1.0
	var up := true
	while x < x1 - 1.0:
		var nx := minf(x + 4.0, x1 - 1.0)
		draw_line(Vector2(x, 5.0 if up else 11.0), Vector2(nx, 11.0 if up else 5.0), Color(TRUSS_COLOR, alpha), 1.0)
		x = nx
		up = not up
	# 側樑（生鏽的槽鋼）與走道面。
	draw_rect(Rect2(x0, 3.0, x1 - x0, 2.0), Color(STRINGER_COLOR, alpha))
	draw_rect(Rect2(x0, 0.0, x1 - x0, 3.0), Color(DECK_COLOR, alpha))
	var hole := x0 + 2.0
	while hole < x1 - 1.0:
		draw_rect(Rect2(hole, 1.0, 1.0, 1.0), Color(HOLE_COLOR, alpha))
		hole += 3.0
	# 鏽斑位置跟著片號固定，每片不一樣。
	var seed := (index * 37 + cell.x * 11) % 17
	draw_rect(Rect2(x0 + 2.0 + float(seed % 7) * w / 9.0, 2.0, 4.0, 3.0), Color(RUST_COLOR, RUST_COLOR.a * alpha))
	draw_line(Vector2(x0, 0.5), Vector2(x1, 0.5), LightKit.glow(CRACK_COLOR, 0.9 * alpha) if warned else Color(DECK_EDGE, alpha), 1.0)
	# 接縫處的連接板。
	draw_rect(Rect2(x1 - 2.0, 1.0, 2.0, 4.0), Color(TRUSS_COLOR, alpha))
	if warned:
		# 裂痕：從片的中段往兩側裂開，越接近掉落越長。
		var grow := 1.0 - clampf(_timer[index] / maxf(data.warn_seconds, 0.01), 0.0, 1.0)
		var mid := x0 + w * (0.35 + float(seed % 5) * 0.06)
		var reach := w * 0.45 * (0.4 + 0.6 * grow)
		var crack := PackedVector2Array([
			Vector2(mid - reach, 2.0), Vector2(mid - reach * 0.5, 0.6), Vector2(mid - reach * 0.15, 2.4),
			Vector2(mid + reach * 0.2, 0.8), Vector2(mid + reach * 0.6, 2.2), Vector2(mid + reach, 1.0)])
		draw_polyline(crack, LightKit.glow(CRACK_COLOR, 1.2 * alpha), 1.5)
		# 側樑也裂開一道往下的縫，從底下看也看得出這一片要掉了。
		draw_line(Vector2(mid, 3.0), Vector2(mid + 1.5, 5.0), LightKit.glow(CRACK_COLOR, 0.8 * alpha), 1.0)


## 走道端點的斜撐：從走道底下斜斜插進兩側的牆或平台。
func _draw_strut(anchor: Vector2, side: float) -> void:
	draw_line(anchor, anchor + Vector2(7.0 * side, 9.0), TRUSS_COLOR, 2.0)
	draw_line(anchor + Vector2(0.0, -1.0), anchor + Vector2(3.0 * side, -1.0), STRINGER_COLOR, 2.0)
