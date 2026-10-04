class_name Checkpoint
extends Area2D
## 檢查點＝老式公共電話亭（NE-121）：世界裡的「錨點」。玩家走近、按互動鍵拿起話筒、撥給帳房，把現在的自己轉存一份；
## 死亡後在最近的亭子醒來。話筒裡永遠是那句標語「再來一次，沒關係」。
## 啟動後再按一次可以補滿彈藥、重新備份；只是路過不會啟動。亭子的外觀自己畫（玻璃、雨痕、發光招牌、話筒），
## 有待機、通話中、已啟動三種光色；從這個亭子重生時直接顯示為已啟動，並有一小段來電鈴聲與招牌閃動。

## 互動範圍（玩家腳底往上），與提示文字出現的範圍一致。
const REACH := Vector2(52.0, 48.0)
const PROMPT_FIRST := "{interact} 撥號備份"
const PROMPT_AGAIN := "{interact} 再撥一次（補滿彈藥）"
const SLOGAN := "再來一次，沒關係。"
## 通話過程中各個時間點（占動作進度 0~1 的比例）：拿起話筒、三聲撥號音、話筒裡的錄音、掛上、備份完成。
const T_PICKUP := 0.26
const T_DIAL: Array[float] = [0.42, 0.5, 0.58]
const DIAL_SOUNDS: Array[StringName] = [&"phone_dial", &"phone_dial2", &"phone_dial3"]
const T_VOICE := 0.66
const T_HANGUP := 0.9
const T_DONE := 0.97
## 亭子的外形（原點在腳底正中央）。
const WIDTH := 28.0
const HEIGHT := 66.0
const GLASS_TOP := -55.0
## 電話機掛在亭子外牆（玩家站的那一側）的高度：機身頂到底、掛鉤。與撥號動作的肩膀高度對得上。
const UNIT_TOP := -50.0
const UNIT_HEIGHT := 15.0
## 撥號時玩家站在亭子外牆旁，離亭子中心的水平距離。
const STAND_DISTANCE := 23.0
const RAIN_STREAKS := 7

var activated := false

var _time := 0.0
var _light: PointLight2D
var _prompt: WorldPrompt
var _player_in_range := false
var _player_ref: WeakRef
## 通話中的已過秒數（負值＝沒在通話）與已經播過的事件。
var _call_t := -1.0
var _picked := false
var _dialed := 0
var _voiced := false
var _hung := false
## 話筒是不是離開了掛鉤（拿在玩家手上）、玩家站在哪一側（話筒裝在那一側的牆上）。
var _handset_out := false
var _side := -1
## 重生演出：剩餘秒數與是否已播過來電鈴聲。
var _rebirth := 0.0
var _rang := false


func _ready() -> void:
	LightKit.mark_emissive(self)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = REACH
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -REACH.y * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_light = LightKit.create_point_light(Palette.CYAN, 90.0, 0.0, true)
	_light.position = Vector2(0, -30)
	add_child(_light)
	_prompt = WorldPrompt.new()
	_prompt.text = PROMPT_FIRST
	_prompt.radius = REACH.x * 0.5 + 6.0
	_prompt.reach_check = func() -> bool: return _player_in_range
	_prompt.offset = Vector2(0, -HEIGHT - 8.0)
	add_child(_prompt)
	# 從這個亭子重生時直接顯示為已啟動，並有一段來電鈴聲與招牌閃動。
	if GameState.has_checkpoint and GameState.checkpoint_position.distance_to(global_position) < 1.0:
		_set_active(false)
		_rebirth = 1.4
	_apply_state()


func _on_body_entered(body: Node2D) -> void:
	var player := Pickup.resolve_player(body)
	if player != null:
		_player_in_range = true
		_player_ref = weakref(player)
		Music.set_safe(self, true)


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = false
		Music.set_safe(self, false)


## 現在能不能撥號：玩家在範圍內、沒在通話、遊戲沒暫停。
func can_dial() -> bool:
	return _player_in_range and _call_t < 0.0 and not get_tree().paused


## 開始通話（按互動鍵時呼叫；測試也直接呼叫）。成功回傳 true。
func start_call(player: Player) -> bool:
	if player == null or _call_t >= 0.0:
		return false
	var face := 1 if global_position.x >= player.global_position.x else -1
	if not player.begin_phone_call(face):
		return false
	_player_ref = weakref(player)
	_side = -face
	_snap_beside(player, face)
	_call_t = 0.0
	_picked = false
	_dialed = 0
	_voiced = false
	_hung = false
	_prompt.enabled = false
	return true


## 玩家站到亭子外牆旁（電話機在那一側），讓手剛好夠到話筒；被牆擋住就留在原地。
func _snap_beside(player: Player, face: int) -> void:
	var target := Vector2(global_position.x - float(face) * STAND_DISTANCE, player.global_position.y)
	if absf(target.x - player.global_position.x) < 1.0:
		return
	if not player.test_move(player.global_transform, target - player.global_position):
		player.global_position = target


func is_calling() -> bool:
	return _call_t >= 0.0


func _process(delta: float) -> void:
	_time += delta
	if can_dial() and Input.is_action_just_pressed(&"interact"):
		start_call(_player_ref.get_ref() as Player if _player_ref != null else null)
	if _call_t >= 0.0:
		_tick_call(delta)
	if _rebirth > 0.0:
		_rebirth = maxf(0.0, _rebirth - delta)
		if not _rang and _rebirth < 1.1:
			_rang = true
			Sfx.play(&"phone_ring", -6.0)
	_update_light()
	queue_redraw()


## 通話時間線：玩家的撥號動作與這裡的聲音、話筒、備份是同一條進度。
func _tick_call(delta: float) -> void:
	_call_t += delta
	var player := _player_ref.get_ref() as Player if _player_ref != null else null
	if player == null or not is_instance_valid(player) or player.is_dead():
		_abort_call()
		return
	var p := player.phone_progress()
	if not _picked and p >= T_PICKUP:
		_picked = true
		_handset_out = true
		Sfx.play(&"phone_pickup", -3.0)
	while _dialed < T_DIAL.size() and p >= T_DIAL[_dialed]:
		Sfx.play(DIAL_SOUNDS[_dialed], -6.0)
		_dialed += 1
	if not _voiced and p >= T_VOICE:
		_voiced = true
		Sfx.play(&"phone_voice", -4.0)
		EventBus.toast_requested.emit(SLOGAN)
	if not _hung and p >= T_HANGUP:
		_hung = true
		_handset_out = false
		Sfx.play(&"phone_hangup", -3.0)
	if p >= T_DONE or not player.is_on_phone():
		_complete_call(player)


## 通話被打斷（玩家死亡或離開狀態）：話筒放回、不備份。
func _abort_call() -> void:
	_call_t = -1.0
	_handset_out = false
	_prompt.enabled = true


func _complete_call(player: Player) -> void:
	_call_t = -1.0
	_handset_out = false
	_prompt.enabled = true
	var first := not activated
	if first:
		_set_active(true)
		if GameState.difficulty.checkpoint_heals:
			player.health.heal(player.health.max_health)
	player.loadout.refill_all()
	GameState.set_checkpoint(global_position, player.checkpoint_snapshot(), WorldState.capture(get_tree()), Progression.snapshot())
	EventBus.toast_requested.emit("已備份" if first else "已備份，彈藥補滿")


func _set_active(with_effects: bool) -> void:
	activated = true
	_prompt.text = PROMPT_AGAIN
	_apply_state()
	if with_effects:
		Fx.burst(global_position + Vector2(0, -30), Palette.CYAN, 14, 130.0)
		Fx.flash_light(global_position + Vector2(0, -30), Palette.CYAN, 140.0, 2.0, 0.5)
		Sfx.play(&"ui_confirm", -4.0)


func _apply_state() -> void:
	if _light != null:
		_light.energy = 0.9 if activated else 0.3


## 光色與亮度：待機時微弱不穩定地閃，通話中呼吸，已啟動穩定偏亮，重生時招牌閃動。
func _update_light() -> void:
	if _light == null:
		return
	var energy := 0.9 if activated else 0.28 + 0.06 * sin(_time * 3.1) + (0.06 if fmod(_time, 3.7) < 0.08 else 0.0)
	if _call_t >= 0.0:
		energy = 1.2 + 0.25 * sin(_time * 14.0)
	if _rebirth > 0.0:
		energy += 0.6 * absf(sin(_time * 18.0)) * minf(1.0, _rebirth)
	_light.energy = energy


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw() -> void:
	var half := WIDTH * 0.5
	var lit := activated or _call_t >= 0.0
	var accent := Palette.CYAN if lit else Palette.CYAN_DIM
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	# 內部的光：從上往下漸淡的青色，已啟動較亮。
	var inner_alpha := (0.5 + 0.12 * pulse) if lit else 0.2 + 0.04 * sin(_time * 3.1)
	var inner_top := Color(accent.r, accent.g, accent.b, inner_alpha)
	var inner_bottom := Color(accent.r, accent.g, accent.b, inner_alpha * 0.25)
	var glass := _rounded(Rect2(-half + 3.0, GLASS_TOP, WIDTH - 6.0, -GLASS_TOP - 5.0), 3.0)
	draw_polygon(glass, _gradient(glass, GLASS_TOP, -5.0, inner_top, inner_bottom))
	# 牆上的電話機（裝在玩家站的那一側）：機身、撥號盤、掛鉤上的話筒（拿起來時只剩電線）。
	var unit_x := _side * (half + 3.0)
	var unit_y := UNIT_TOP + 6.0
	draw_polygon(_rounded(Rect2(unit_x - 4.5, UNIT_TOP + 4.0, 9.0, UNIT_HEIGHT), 2.0), PackedColorArray([Color("1a1e28")]))
	draw_polyline(_close(_rounded(Rect2(unit_x - 4.5, UNIT_TOP + 4.0, 9.0, UNIT_HEIGHT), 2.0)), frame_edge_color(), 0.7)
	draw_circle(Vector2(unit_x, unit_y + 6.0), 2.4, Color("0c0e14"))
	draw_arc(Vector2(unit_x, unit_y + 6.0), 2.4, 0.0, TAU, 12, LightKit.glow(accent, 1.4) if lit else accent.darkened(0.2), 0.8)
	if _handset_out:
		var sway := sin(_time * 5.0) * 1.5
		draw_polyline(PackedVector2Array([Vector2(unit_x, unit_y + 12.0), Vector2(unit_x + _side * 1.5 + sway, unit_y + 17.0), Vector2(unit_x + _side * 3.0, unit_y + 21.0 + sway)]), Color("2a2f3c"), 1.0)
	else:
		draw_polygon(_rounded(Rect2(unit_x - 5.5, UNIT_TOP - 1.0, 11.0, 4.0), 2.0), PackedColorArray([Color("262b38")]))
		draw_circle(Vector2(unit_x - 4.5, UNIT_TOP + 1.0), 2.2, Color("303644"))
		draw_circle(Vector2(unit_x + 4.5, UNIT_TOP + 1.0), 2.2, Color("303644"))
	# 玻璃的反光與雨痕。
	draw_polygon(PackedVector2Array([Vector2(-half + 4.0, -9.0), Vector2(-half + 8.0, -9.0), Vector2(-half + 16.0, GLASS_TOP + 2.0), Vector2(-half + 12.0, GLASS_TOP + 2.0)]), PackedColorArray([Color(1, 1, 1, 0.07)]))
	draw_polygon(PackedVector2Array([Vector2(half - 10.0, -9.0), Vector2(half - 8.0, -9.0), Vector2(half - 4.0, GLASS_TOP + 2.0), Vector2(half - 6.0, GLASS_TOP + 2.0)]), PackedColorArray([Color(1, 1, 1, 0.05)]))
	for i in RAIN_STREAKS:
		var x := -half + 5.0 + float(i) * (WIDTH - 10.0) / float(RAIN_STREAKS - 1) + sin(float(i) * 2.7) * 1.2
		var travel := fmod(_time * (9.0 + float(i % 3) * 4.0) + float(i) * 11.0, -GLASS_TOP - 8.0)
		var y := GLASS_TOP + 3.0 + travel
		draw_line(Vector2(x, y), Vector2(x - 0.4, minf(-6.0, y + 4.0 + float(i % 2) * 3.0)), Color(0.75, 0.9, 1.0, 0.28), 0.8)
	# 框：左右立柱、底座、頂蓋（切角，不是方塊）。
	var frame := Color("20242f")
	var frame_edge := Color("3a4152")
	draw_polygon(PackedVector2Array([Vector2(-half, 0.0), Vector2(half, 0.0), Vector2(half - 1.5, -5.0), Vector2(-half + 1.5, -5.0)]), PackedColorArray([frame]))
	draw_polygon(PackedVector2Array([Vector2(-half, -5.0), Vector2(-half + 3.0, -5.0), Vector2(-half + 3.0, GLASS_TOP), Vector2(-half + 1.0, GLASS_TOP)]), PackedColorArray([frame]))
	draw_polygon(PackedVector2Array([Vector2(half, -5.0), Vector2(half - 3.0, -5.0), Vector2(half - 3.0, GLASS_TOP), Vector2(half - 1.0, GLASS_TOP)]), PackedColorArray([frame]))
	draw_line(Vector2(-half + 3.0, -28.0), Vector2(half - 3.0, -28.0), frame_edge, 1.0)  # 玻璃中間的橫框
	var roof := PackedVector2Array([Vector2(-half - 1.5, GLASS_TOP), Vector2(half + 1.5, GLASS_TOP), Vector2(half - 1.0, GLASS_TOP - 3.0), Vector2(half - 4.0, -HEIGHT + 1.0), Vector2(-half + 4.0, -HEIGHT + 1.0), Vector2(-half + 1.0, GLASS_TOP - 3.0)])
	draw_polygon(roof, PackedColorArray([frame]))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[4], roof[5], roof[0]]), frame_edge, 0.8)
	# 招牌：發光的小方窗，裡面一支話筒的剪影；重生時閃動。
	var sign_color := LightKit.glow(accent, 1.6 + 0.3 * pulse) if lit else Color(accent.r, accent.g, accent.b, 0.55 + 0.2 * sin(_time * 3.1))
	if _rebirth > 0.0 and int(_time * 10.0) % 2 == 0:
		sign_color = LightKit.glow(Palette.WHITE, 1.8)
	var sign_box := _rounded(Rect2(-9.0, -HEIGHT + 4.0, 18.0, 7.0), 2.0)
	draw_polygon(sign_box, PackedColorArray([Color(0.04, 0.06, 0.1, 0.95)]))
	draw_polyline(_close(sign_box), sign_color, 0.9)
	draw_polyline(PackedVector2Array([Vector2(-5.0, -HEIGHT + 9.0), Vector2(-3.4, -HEIGHT + 6.6), Vector2(3.4, -HEIGHT + 6.6), Vector2(5.0, -HEIGHT + 9.0)]), sign_color, 1.1)


static func frame_edge_color() -> Color:
	return Color("3a4152")


## 圓角矩形的頂點（y 往上為負，所以 size.y 為負時由下往上）。
static func _rounded(rect: Rect2, radius: float, steps := 4) -> PackedVector2Array:
	var r := rect.abs()
	var out := PackedVector2Array()
	var corners := [
		[Vector2(r.position.x + r.size.x - radius, r.position.y + radius), -PI * 0.5],
		[Vector2(r.position.x + r.size.x - radius, r.position.y + r.size.y - radius), 0.0],
		[Vector2(r.position.x + radius, r.position.y + r.size.y - radius), PI * 0.5],
		[Vector2(r.position.x + radius, r.position.y + radius), PI],
	]
	for corner: Array in corners:
		for i in steps + 1:
			var a: float = float(corner[1]) + (PI * 0.5) * float(i) / float(steps)
			out.append((corner[0] as Vector2) + Vector2.RIGHT.rotated(a) * radius)
	return out


static func _close(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed


## 依每個頂點的 y 在上下兩色之間內插的頂點色。
static func _gradient(points: PackedVector2Array, y_top: float, y_bottom: float, top: Color, bottom: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for point in points:
		colors.append(top.lerp(bottom, clampf((point.y - y_top) / (y_bottom - y_top), 0.0, 1.0)))
	return colors
