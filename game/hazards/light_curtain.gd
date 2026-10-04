class_name LightCurtain
extends Node2D
## 回收燈幕（追逐橋段）：一面貫穿整個關卡高度、向右推進的光幕。
## 待命 → 玩家走過起點 → 光幕從身後 lead_tiles 格出發、以固定速度推進 → 到終點停下並淡出；追上玩家就是死亡。
## 用 ChaseData 描述（速度、起跑距離、長度）；放在地圖 legend 的一個字元上，該格是起點。
## 重來時關卡重建，光幕回到待命；從橋段終點之後的檢查點重生則直接視為已結束。

signal started
signal finished

enum Phase { ARMED, RUNNING, DONE }

const WIDTH := 46.0
const START_WINDOW_TILES := 5
const RUMBLE_INTERVAL := 0.5
const RUMBLE_RANGE := 220.0
const FADE_TIME := 1.2

var data: ChaseData
var phase := Phase.ARMED
## 光幕前緣的 x（世界座標）；玩家在它左邊就會被吞掉。
var front_x := 0.0

var _tile := 16
var _start_x := 0.0
var _end_x := 0.0
var _height := 0.0
var _light: PointLight2D
var _rumble_left := 0.0
var _fade := 1.0
var _time := 0.0
var _player_ref: WeakRef


func configure(p_data: ChaseData, tile_size: int, level_height: float) -> void:
	data = p_data
	_tile = tile_size
	_height = level_height


func _ready() -> void:
	if data == null:
		push_error("[LightCurtain] 未指定 ChaseData，已移除。")
		queue_free()
		return
	for problem in data.validate():
		push_error("[LightCurtain] %s" % problem)
	_start_x = global_position.x
	_end_x = _start_x + float(data.length_tiles * _tile)
	_light = LightKit.create_point_light(data.color, 190.0, 0.0)
	_light.position = Vector2(0.0, _height * 0.5 - global_position.y)
	add_child(_light)
	LightKit.mark_emissive(self)
	set_physics_process(true)


func _player() -> Player:
	var player: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
		_player_ref = weakref(player) if player != null else null
	return player


func _physics_process(delta: float) -> void:
	_time += delta
	var player := _player()
	if player == null:
		return
	match phase:
		Phase.ARMED:
			_tick_armed(player)
		Phase.RUNNING:
			_tick_running(player, delta)
		Phase.DONE:
			_fade = maxf(0.0, _fade - delta / FADE_TIME)
			if _fade <= 0.0:
				_light.energy = 0.0
				visible = false
				set_physics_process(false)
				return
			_light.energy = 1.4 * _fade
	queue_redraw()


func _tick_armed(player: Player) -> void:
	var x := player.global_position.x
	if x > _end_x:
		_finish(true)  # 從橋段之後的檢查點重生：已經過了
	elif x >= _start_x and x <= _start_x + float(START_WINDOW_TILES * _tile):
		phase = Phase.RUNNING
		front_x = _start_x - float(data.lead_tiles * _tile)
		EventBus.toast_requested.emit(data.hint)
		started.emit()


func _tick_running(player: Player, delta: float) -> void:
	front_x += data.speed * delta
	global_position.x = front_x
	_light.energy = 1.4 + 0.3 * sin(_time * 9.0)
	_rumble_left -= delta
	var gap := player.global_position.x - front_x
	if _rumble_left <= 0.0 and gap < RUMBLE_RANGE:
		_rumble_left = RUMBLE_INTERVAL
		Feel.shake_strength(clampf(1.6 - gap / RUMBLE_RANGE, 0.4, 1.6), 0.12)
	if player.global_position.x <= front_x and not player.is_dead():
		player.health.kill(DamageInfo.create(player.health.current, Combat.Team.ENEMY, &"recycle_curtain"))
	if front_x >= _end_x:
		_finish(false)


func _finish(silent: bool) -> void:
	phase = Phase.DONE
	if silent:
		_fade = 0.0
	finished.emit()


## 光幕前緣與玩家的距離（像素，測試與提示用）；還沒出發時回傳 INF。
func gap_to_player() -> float:
	var player := _player()
	return player.global_position.x - front_x if phase == Phase.RUNNING and player != null else INF


func _draw() -> void:
	if phase == Phase.ARMED or data == null:
		return
	var top := -global_position.y
	var color := LightKit.glow(data.color, 1.6)
	# 前緣最亮，往身後逐漸變淡的一排直條。
	var steps := 14
	for i in steps:
		var t := float(i) / float(steps)
		var strip := Color(color.r, color.g, color.b, (1.0 - t) * 0.55 * _fade)
		var x := -WIDTH * t
		draw_rect(Rect2(x - WIDTH / float(steps), top, WIDTH / float(steps) + 0.5, _height), strip)
	draw_rect(Rect2(-1.5, top, 3.0, _height), Color(1.0, 0.85, 0.8, 0.9 * _fade))
	# 掃描線：由上往下緩慢移動的細亮線，看起來像「回收作業」。
	var scan := fposmod(_time * 60.0, _height)
	draw_rect(Rect2(-WIDTH, top + scan, WIDTH, 2.0), Color(1.0, 0.9, 0.85, 0.5 * _fade))
