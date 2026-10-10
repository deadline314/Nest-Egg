class_name VitalsTag
extends Control
## 動態 HUD：浮在凜頭部背側的全像標籤，上排生命格、下排護盾能量。
## 閒置淡出、數值變動時彈出；低血量、格擋、護盾回復與破防時常駐。
## 數值走 EventBus，位置與面向只讀玩家的公開屬性，玩家不存在時自動隱藏。

## 頭頂相對於玩家腳底的位置（世界座標）。
const HEAD_OFFSET := Vector2(0, -56)
## 標籤與頭部的水平間距（畫面像素）。
const SIDE_GAP := 10.0
const PIP_W := 6.0
const PIP_H := 6.0
const PIP_SKEW := 2.0
const PIP_STEP := 7.0
const PAD := 4.0
const GUARD_H := 2.0
## 生命上限超過此數改畫連續長條。
const MAX_PIPS := 12
const BAR_WIDTH := 60.0
const LOST_FLASH := 0.14
const LOST_TIME := 0.55
const GAIN_TIME := 0.3
const SHAKE_TIME := 0.28
const PARRY_TIME := 0.3
const FOLLOW_SHARPNESS := 16.0
## 跟隨距離超過此值直接瞬移（重生、傳送），不要從畫面另一頭飛過來。
const SNAP_DISTANCE := 120.0

var presence := HudPresence.new()
var health := -1
var max_health := 0
var guard_ratio := 1.0
var guard_broken := false

var _player_ref := PlayerRef.new()
var _auto_hide := true
var _pos := Vector2.ZERO
var _has_pos := false
var _side := -1.0
var _time := 0.0
var _shake_left := 0.0
var _parry_left := 0.0
var _guard_shown := 1.0
var _guard_ghost := 1.0
var _guard_rising := false
## 每格的動畫計時：<0 代表沒有動畫。
var _lost_time := PackedFloat32Array()
var _gain_time := PackedFloat32Array()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 過場會暫停遊戲；仍要處理才能淡出隱藏。
	process_mode = Node.PROCESS_MODE_ALWAYS
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	_auto_hide = Settings.get_hud_auto_hide()
	Settings.display_changed.connect(func() -> void: _auto_hide = Settings.get_hud_auto_hide())
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_guard_changed.connect(_on_guard_changed)
	EventBus.player_parried.connect(_on_parried)
	EventBus.player_spawned.connect(func(_p: Node2D) -> void:
		_has_pos = false
		presence.poke())


func is_low_health() -> bool:
	return health > 0 and max_health > 0 and health <= maxi(1, ceili(max_health / 3.0))


func _process(delta: float) -> void:
	var cinematic := Story.is_cinematic_active()
	if get_tree().paused and not cinematic:
		return
	_time += delta
	var player := _player_ref.get_player(get_tree())
	var hidden := cinematic or player == null or player.is_dead() or player.mounted_vehicle != null
	var hold := is_low_health() or guard_broken or guard_ratio < 0.995 or (player != null and player.is_blocking)
	presence.update(delta, hold, _auto_hide, hidden)
	_tick_effects(delta)
	if player != null:
		_follow(player, delta)
	queue_redraw()


func _tick_effects(delta: float) -> void:
	_shake_left = maxf(0.0, _shake_left - delta)
	_parry_left = maxf(0.0, _parry_left - delta)
	for i in _lost_time.size():
		if _lost_time[i] >= 0.0:
			_lost_time[i] = _lost_time[i] + delta if _lost_time[i] + delta < LOST_TIME else -1.0
		if _gain_time[i] >= 0.0:
			_gain_time[i] = _gain_time[i] + delta if _gain_time[i] + delta < GAIN_TIME else -1.0
	_guard_rising = guard_ratio > _guard_shown + 0.001
	_guard_shown = move_toward(_guard_shown, guard_ratio, delta * 4.0)
	# 殘影條：先停一下再慢慢追上，看得出剛剛扣了多少。
	if _guard_ghost < _guard_shown:
		_guard_ghost = _guard_shown
	else:
		_guard_ghost = move_toward(_guard_ghost, _guard_shown, delta * 0.8)


func _follow(player: Player, delta: float) -> void:
	_side = move_toward(_side, -float(player.facing), delta * 6.0)
	var head := get_viewport().get_canvas_transform() * (player.global_position + HEAD_OFFSET)
	var width := _content_width() + PAD * 2.0
	var target := head + Vector2(_side * (SIDE_GAP + width * 0.5) - width * 0.5, -10.0)
	if not _has_pos or _pos.distance_to(target) > SNAP_DISTANCE:
		_pos = target
		_has_pos = true
	else:
		_pos = _pos.lerp(target, 1.0 - exp(-delta * FOLLOW_SHARPNESS))


func _content_width() -> float:
	if max_health > MAX_PIPS:
		return BAR_WIDTH
	return maxf(PIP_STEP, max_health * PIP_STEP - (PIP_STEP - PIP_W) + PIP_SKEW)


## Actual screen-space tag becomes a world-space reading obstacle. Include
## pop, shake and leader; invisible tags reserve no space. No rig/HUD relocation.
func prompt_obstacle_rect() -> Rect2:
	if not is_visible_in_tree() or presence.alpha <= 0.01 or max_health <= 0 or not _has_pos:
		return Rect2()
	var canvas := get_viewport().get_canvas_transform()
	if not is_finite(canvas.determinant()) or is_zero_approx(canvas.determinant()):
		return Rect2()
	var extent := Vector2(_content_width() + PAD * 2.0, PAD + PIP_H + 3.0 + GUARD_H + PAD)
	var pop_scale := 1.0 + 0.18 * ease(presence.pop, 0.5)
	var rect := Rect2(_pos + extent * (1.0 - pop_scale) * 0.5, extent * pop_scale)
	# The tag's leader, BREAK caption and damage fragments extend outside its plate.
	var margin := 10.0
	for age in _lost_time:
		if age >= 0.0:
			margin = 20.0
			break
	return canvas.affine_inverse() * (get_global_transform() * rect.grow(margin * pop_scale))


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	var first := health < 0
	if maximum != max_health:
		max_health = maxi(0, maximum)
		_lost_time.resize(max_health)
		_gain_time.resize(max_health)
		_lost_time.fill(-1.0)
		_gain_time.fill(-1.0)
	var previous := health
	health = clampi(current, 0, max_health)
	if first:
		return
	if health < previous:
		for i in range(health, mini(previous, max_health)):
			_lost_time[i] = 0.0
			_gain_time[i] = -1.0
		_shake_left = SHAKE_TIME
		presence.poke()
	elif health > previous:
		for i in range(maxi(previous, 0), health):
			_gain_time[i] = 0.0
			_lost_time[i] = -1.0
		presence.poke()


func _on_guard_changed(current: float, maximum: float, broken: bool) -> void:
	var ratio := clampf(current / maxf(1.0, maximum), 0.0, 1.0)
	if ratio < guard_ratio - 0.001 or broken != guard_broken:
		presence.poke()
	guard_ratio = ratio
	guard_broken = broken


func _on_parried(_at: Vector2) -> void:
	_parry_left = PARRY_TIME
	presence.poke()


# ---------------------------------------------------------------------------
# 繪製
# ---------------------------------------------------------------------------

func _draw() -> void:
	var alpha := presence.alpha
	if alpha <= 0.01 or max_health <= 0:
		return
	var shake := Vector2.ZERO
	if _shake_left > 0.0:
		var k := _shake_left / SHAKE_TIME
		shake = Vector2(sin(_time * 90.0), cos(_time * 70.0)) * 2.5 * k
	var width := _content_width() + PAD * 2.0
	var height := PAD + PIP_H + 3.0 + GUARD_H + PAD
	var pivot := _pos + Vector2(width, height) * 0.5
	var s := 1.0 + 0.18 * ease(presence.pop, 0.5)
	draw_set_transform(pivot + shake + (Vector2(-width, -height) * 0.5) * s, 0.0, Vector2.ONE * s)

	_draw_plate(width, height, alpha)
	if max_health > MAX_PIPS:
		_draw_health_bar(alpha)
	else:
		for i in max_health:
			_draw_pip(i, alpha)
	_draw_guard(alpha)
	draw_set_transform(Vector2.ZERO)


func _draw_plate(width: float, height: float, alpha: float) -> void:
	var plate := PackedVector2Array([Vector2(3, 0), Vector2(width, 0), Vector2(width - 3, height), Vector2(0, height)])
	var damage_k := _shake_left / SHAKE_TIME
	var fill := Color(0.03, 0.05, 0.09, 0.62 * alpha).lerp(Color(0.35, 0.02, 0.06, 0.7 * alpha), damage_k * 0.7)
	draw_colored_polygon(plate, fill)
	var edge := Color(Palette.CYAN_DIM, 0.9 * alpha)
	if is_low_health():
		edge = Color(Palette.DANGER, (0.5 + 0.5 * _heartbeat()) * alpha)
	# 斷開的角框：只畫左上與右下兩個角，像全像投影的取景框。
	draw_polyline(PackedVector2Array([Vector2(1, 5), Vector2(3, 0), Vector2(10, 0)]), edge, 1.0)
	draw_polyline(PackedVector2Array([Vector2(width - 10, height), Vector2(width - 3, height), Vector2(width - 1, height - 5)]), edge, 1.0)
	# 連到頭部的細線（從靠近角色的那一側拉出）。
	var near_x := width if _side < 0.0 else 0.0
	draw_line(Vector2(near_x, height * 0.5), Vector2(near_x - _side * SIDE_GAP * 0.8, height * 0.5 + 6.0), Color(Palette.CYAN_DIM, 0.6 * alpha), 1.0)


func _pip_points(i: int) -> PackedVector2Array:
	var x := PAD + i * PIP_STEP
	var y := PAD
	return PackedVector2Array([Vector2(x + PIP_SKEW, y), Vector2(x + PIP_W + PIP_SKEW, y), Vector2(x + PIP_W, y + PIP_H), Vector2(x, y + PIP_H)])


func _health_color(alpha: float) -> Color:
	if is_low_health():
		return Color(LightKit.glow(Palette.DANGER, 1.2 + 0.9 * _heartbeat()), alpha)
	return Color(LightKit.glow(Palette.CYAN, 1.5), alpha)


func _draw_pip(i: int, alpha: float) -> void:
	var points := _pip_points(i)
	var outline := points.duplicate()
	outline.append(points[0])
	if i < health:
		var color := _health_color(alpha)
		var gain := _gain_time[i]
		if gain >= 0.0:
			var t := gain / GAIN_TIME
			var center := (points[0] + points[2]) * 0.5
			for j in points.size():
				points[j] = center + (points[j] - center) * ease(t, 0.4)
			color = color.lerp(Color(LightKit.glow(Palette.WHITE, 2.2), alpha), 1.0 - t)
		draw_colored_polygon(points, color)
		return
	draw_colored_polygon(points, Color(0.1, 0.16, 0.22, 0.75 * alpha))
	draw_polyline(outline, Color(Palette.CYAN_DIM.lightened(0.25), 0.9 * alpha), 1.0)
	var lost := _lost_time[i]
	if lost < 0.0:
		return
	if lost < LOST_FLASH:
		# 殘影：剛損失的格子先亮白。
		draw_colored_polygon(points, Color(LightKit.glow(Palette.WHITE, 2.4), alpha))
		return
	# 碎裂：三塊碎片往外下方飛散並淡出。
	var t := (lost - LOST_FLASH) / (LOST_TIME - LOST_FLASH)
	var center := (points[0] + points[2]) * 0.5
	var shard_color := Color(LightKit.glow(Palette.DANGER, 1.8), (1.0 - t) * alpha)
	for k in 3:
		var dir := Vector2(-1.0 + k, -1.2 + 0.4 * k).normalized()
		var p := center + dir * 9.0 * t + Vector2(0, 14.0 * t * t)
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), shard_color)


func _draw_health_bar(alpha: float) -> void:
	var rect := Rect2(PAD, PAD, BAR_WIDTH, PIP_H)
	draw_rect(rect, Color(0.02, 0.03, 0.05, 0.6 * alpha))
	var ratio := float(health) / float(maxi(1, max_health))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), _health_color(alpha))
	draw_rect(rect, Color(Palette.CYAN_DIM, 0.8 * alpha), false, 1.0)


func _draw_guard(alpha: float) -> void:
	var width := _content_width() - PIP_SKEW
	var rect := Rect2(PAD, PAD + PIP_H + 3.0, width, GUARD_H)
	draw_rect(rect, Color(0.02, 0.03, 0.05, 0.75 * alpha))
	if guard_broken:
		var flicker := 0.55 + 0.45 * signf(sin(_time * 28.0))
		draw_rect(Rect2(rect.position, Vector2(width * maxf(_guard_shown, 0.04), GUARD_H)), Color(LightKit.glow(Palette.DANGER, 1.6), flicker * alpha))
		draw_string(UiKit.font(), Vector2(rect.end.x - 26.0, rect.end.y + 9.0), "BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(LightKit.glow(Palette.DANGER, 1.4), flicker * alpha))
		return
	if _guard_ghost > _guard_shown:
		draw_rect(Rect2(rect.position, Vector2(width * _guard_ghost, GUARD_H)), Color(Palette.WHITE, 0.55 * alpha))
	var fill := Color(LightKit.glow(Palette.ARMOR, 1.3), alpha)
	draw_rect(Rect2(rect.position, Vector2(width * _guard_shown, GUARD_H)), fill)
	if _guard_rising:
		# 回復中：一道亮光沿著能量條掃過。
		var x := fmod(_time * 50.0, maxf(1.0, width * _guard_shown))
		draw_rect(Rect2(rect.position + Vector2(x, -0.5), Vector2(3, GUARD_H + 1.0)), Color(LightKit.glow(Palette.WHITE, 2.0), alpha))
	if _parry_left > 0.0:
		var k := _parry_left / PARRY_TIME
		draw_rect(rect.grow(1.5 * k), Color(LightKit.glow(Palette.CYAN, 2.5), k * alpha))


## 低血量的心跳節奏（0~1，一下強一下弱）。
func _heartbeat() -> float:
	var t := fmod(_time, 0.9)
	return maxf(exp(-pow((t - 0.08) * 22.0, 2.0)), 0.6 * exp(-pow((t - 0.3) * 22.0, 2.0)))
