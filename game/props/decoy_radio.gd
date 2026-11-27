class_name DecoyRadio
extends Node2D
## 誘餌收音機（NE-404）：放在地上的手提收音機。玩家的子彈、近戰或爆炸打中就大聲播放 play_seconds 秒，
## 期間每隔一下叫範圍內還沒發現玩家的敵人走過來盯著看（Enemy.lure_to）；盯著看的敵人看不到背後的人。
## 播完就壞，只剩一台冒煙的空殼。敵人打不開。原點在地面上；用過了沒跟著檢查點保存。

signal started(radio: DecoyRadio)

enum State { IDLE, PLAYING, SPENT }

const GROUP := &"decoy_radios"
const BODY_SIZE := Vector2(18.0, 11.0)
## 播放中多久叫一次附近的敵人、多久響一聲雜訊（秒）。
const CALL_EVERY := 0.4
const STATIC_EVERY := 0.9
## 機身用和場景裡的機械一樣偏亮的米褐色：暗場只靠主角的自發光照到，太深的顏色會整台消失。
const BODY_COLOR := Color("a28b6c")
const EDGE_COLOR := Color("dcc7a3")
const GRILLE_COLOR := Color("2c2723")
const DIAL_COLOR := Color(1.0, 0.78, 0.4)
## 待機燈：暗處也找得到它（播完就熄）。
const STANDBY_COLOR := Color(0.45, 1.0, 0.6)
const WAVE_COLOR := Color(1.0, 0.82, 0.5, 0.55)
const PROMPT_REACH := 240.0

var data: DecoyRadioData
var cell := Vector2i.ZERO
var state: State = State.IDLE
var health: HealthComponent
var hurtbox: Hurtbox

var _left := 0.0
var _call_in := 0.0
var _static_in := 0.0
var _time := 0.0
var _prompt: WorldPrompt
var _player_ref := PlayerRef.new()
var _glow: _Glow


func configure(p_data: DecoyRadioData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[DecoyRadio] 未指定 DecoyRadioData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	_glow = _Glow.new()
	_glow.radio = self
	LightKit.mark_emissive(_glow)
	add_child(_glow)
	health = HealthComponent.new()
	add_child(health)
	health.setup(1, 0.0)
	health.died.connect(func(_info: DamageInfo) -> void: play())
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, BODY_SIZE + Vector2(4.0, 6.0), Vector2(0.0, -BODY_SIZE.y * 0.5 - 2.0))
	hurtbox.hit_material = &"metal"
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.offset = Vector2(0.0, -BODY_SIZE.y - 22.0)
		_prompt.reach_check = _prompt_in_reach
		add_child(_prompt)
	set_process(false)


func _prompt_in_reach() -> bool:
	if state != State.IDLE:
		return false
	var player := _player_ref.get_player(get_tree())
	return player != null and player.global_position.distance_to(global_position) <= PROMPT_REACH


func is_playing() -> bool:
	return state == State.PLAYING


## 開始播放。已經播過就不做事；回傳有沒有開始。
func play() -> bool:
	if state != State.IDLE:
		return false
	state = State.PLAYING
	_left = data.play_seconds
	_call_in = CALL_EVERY
	_static_in = 0.0
	hurtbox.enabled = false
	if _prompt != null:
		_prompt.enabled = false
	Sfx.play(&"beep", -4.0)
	_call_enemies()  # 立刻叫一次：命中的頓格（hitstop）期間 _process 的 delta 是 0
	started.emit(self)
	set_process(true)
	return true


func _process(delta: float) -> void:
	_time += delta
	if state != State.PLAYING:
		return
	_left -= delta
	_call_in -= delta
	_static_in -= delta
	if _call_in <= 0.0:
		_call_in = CALL_EVERY
		_call_enemies()
	if _static_in <= 0.0:
		_static_in = STATIC_EVERY
		Sfx.play(&"ch2_radio_static", -6.0)
	if _left <= 0.0:
		_spend()
	queue_redraw()
	_glow.queue_redraw()


## 叫範圍內的敵人過來；盯著的時間算到播完再多 linger_seconds 秒。
func _call_enemies() -> void:
	var seconds := maxf(_left, 0.0) + data.linger_seconds
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var offset := enemy.global_position - global_position
		if absf(offset.x) <= data.lure_radius and absf(offset.y) <= data.lure_height:
			enemy.lure_to(global_position, seconds)


func _spend() -> void:
	state = State.SPENT
	Fx.sparks(global_position + Vector2(0.0, -BODY_SIZE.y), DIAL_COLOR, 4, 80.0, 0.3)
	set_process(false)
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	if data == null:
		return
	var w := BODY_SIZE.x
	var h := BODY_SIZE.y
	var playing := state == State.PLAYING
	# 播放中機身隨低音輕輕震（減少介面動態時不震）。
	var shake := 0.0
	if playing and not Settings.get_reduce_ui_motion():
		shake = sin(_time * 38.0) * 0.4
	var o := Vector2(-w * 0.5 + shake, -h)
	# 提把：機身上方的弧形把手。
	draw_arc(o + Vector2(w * 0.5, 1.0), w * 0.32, PI, TAU, 10, EDGE_COLOR, 1.2)
	# 機身：切角的箱體，上緣受光。
	var c := 2.5
	var body := PackedVector2Array([o + Vector2(0.0, c), o + Vector2(c, 0.0), o + Vector2(w - c, 0.0), o + Vector2(w, c),
			o + Vector2(w, h), o + Vector2(0.0, h)])
	draw_colored_polygon(body, BODY_COLOR if state != State.SPENT else BODY_COLOR.darkened(0.4))
	draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3]]), EDGE_COLOR, 1.0)
	# 兩個喇叭與中間的刻度窗：播放中喇叭隨節奏鼓動、刻度窗亮起。
	var pulse := 0.0
	if playing:
		pulse = 0.5 + 0.5 * sin(_time * 12.0) if not Settings.get_reduce_ui_motion() else 0.5
	for side: float in [0.27, 0.73]:
		var center := o + Vector2(w * side, h * 0.58)
		draw_circle(center, 3.2 + pulse * 0.5, GRILLE_COLOR)
		draw_arc(center, 3.2 + pulse * 0.5, 0.0, TAU, 12, EDGE_COLOR, 0.8)
	if state != State.PLAYING:
		draw_rect(Rect2(o + Vector2(w * 0.42, h * 0.3), Vector2(w * 0.16, 2.0)), GRILLE_COLOR)


## 會發光的部分（待機燈、刻度窗、聲波）畫在自發光的子節點上：暗場裡也看得見，不被場景光影壓暗。
func _draw_glow(canvas: CanvasItem) -> void:
	if data == null:
		return
	var w := BODY_SIZE.x
	var h := BODY_SIZE.y
	var o := Vector2(-w * 0.5, -h)
	if state == State.IDLE:
		var led := o + Vector2(w - 3.0, 2.8)
		canvas.draw_texture_rect(LightKit.soft_texture(), Rect2(led - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), false, Color(STANDBY_COLOR, 0.35))
		canvas.draw_circle(led, 1.2, LightKit.glow(STANDBY_COLOR, 1.6))
	elif state == State.PLAYING:
		canvas.draw_rect(Rect2(o + Vector2(w * 0.42, h * 0.3), Vector2(w * 0.16, 2.0)), LightKit.glow(DIAL_COLOR, 1.3))
		# 聲波：兩側各兩道往外擴、逐漸淡掉的弧線（少量、克制）。
		var mid := o + Vector2(w * 0.5, h * 0.5)
		for i in 2:
			var t := fposmod(_time * 1.6 + i * 0.5, 1.0)
			var r := 8.0 + t * 14.0
			var color := Color(WAVE_COLOR, WAVE_COLOR.a * (1.0 - t))
			canvas.draw_arc(mid, r, -0.5, 0.5, 6, color, 1.0)
			canvas.draw_arc(mid, r, PI - 0.5, PI + 0.5, 6, color, 1.0)


class _Glow:
	extends Node2D
	var radio: DecoyRadio

	func _draw() -> void:
		radio._draw_glow(self)
