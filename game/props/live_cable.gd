class_name LiveCable
extends Node2D
## 斷電纜（NE-400）：天花板垂下一條冒火花的電纜，下面是一灘積水。
## 玩家的子彈、近戰或爆炸打中電纜，電纜就斷掉掉進水裡；水面先閃一下預警，接著通電 live_seconds 秒：
## 站在水裡的人（敵人與玩家都一樣）會觸電，跳起來就不會；格擋擋不住電流。用過一次就只剩一灘普通的水。
## 原點在積水中央的地面上。外觀、寬度、時間與傷害來自 LiveCableData；用過了沒跟著檢查點保存。

signal electrified(cable: LiveCable)

enum State { HANGING, WARNING, LIVE, SPENT }

const GROUP := &"live_cables"
## 電纜最長畫多長（世界像素）；吊點更高時上面接一段固定的導管。
const CABLE_MAX := 72.0
const CABLE_COLOR := Color("2b323d")
const CABLE_EDGE := Color("7d8a9c")
## 吊著時偶爾冒火花的間隔（秒）。
const SPARK_EVERY := Vector2(0.6, 1.6)
## 通電時沿水面放電弧的間隔（秒），以及水面的高度（觸電範圍只在腳底附近，跳起來就碰不到）。
const ARC_EVERY := 0.07
const WATER_HEIGHT := 3.0
const SHOCK_HEIGHT := 7.0
const WATER_COLOR := Color(0.32, 0.5, 0.62, 0.7)
const LIVE_COLOR := Color(0.55, 0.9, 1.0)
const HURTBOX_SIZE := Vector2(10.0, 22.0)
const PROMPT_REACH := 150.0

var data: LiveCableData
var cell := Vector2i.ZERO
var state: State = State.HANGING
var health: HealthComponent
var hurtbox: Hurtbox

var _anchor_height := 96.0
var _left := 0.0
var _spark_in := 1.0
var _arc_in := 0.0
var _time := 0.0
var _drop := 0.0  # 斷掉後電纜下端掉到哪裡（0＝還吊著，1＝落在水面）
var _hit_players: ContactHitbox
var _hit_enemies: ContactHitbox
var _prompt: WorldPrompt
var _player_ref := PlayerRef.new()


## anchor_height：吊點（天花板底面）離水面多高（像素）。
func configure(p_data: LiveCableData, p_cell: Vector2i, anchor_height: float) -> void:
	data = p_data
	cell = p_cell
	_anchor_height = clampf(anchor_height, 32.0, 400.0) if is_finite(anchor_height) else 96.0


func _ready() -> void:
	if data == null:
		push_error("[LiveCable] 未指定 LiveCableData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	health = HealthComponent.new()
	add_child(health)
	health.setup(1, 0.0)
	health.died.connect(func(_info: DamageInfo) -> void: cut())
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, HURTBOX_SIZE, Vector2(0.0, -_cable_bottom() - HURTBOX_SIZE.y * 0.5 + 6.0))
	hurtbox.hit_material = &"metal"
	# 兩個陣營各一個觸電範圍：一個打玩家、一個打敵人。只在通電時啟用。
	var shock := Vector2(data.water_width, SHOCK_HEIGHT)
	var offset := Vector2(0.0, -SHOCK_HEIGHT * 0.5)
	_hit_players = _make_shock(Combat.Team.ENEMY, shock, offset)
	_hit_enemies = _make_shock(Combat.Team.PLAYER, shock, offset)
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.offset = Vector2(0.0, -_cable_bottom() - 20.0)
		_prompt.reach_check = _prompt_in_reach
		add_child(_prompt)
	_spark_in = randf_range(SPARK_EVERY.x, SPARK_EVERY.y)


func _make_shock(team: Combat.Team, size: Vector2, offset: Vector2) -> ContactHitbox:
	var box := ContactHitbox.new()
	add_child(box)
	box.setup(team, data.damage, data.source_id, size, offset)
	box.knockback_override = Vector2(40.0, -160.0)
	box.bypass_guard = true  # 水裡的電流擋不住
	box.environmental = true
	box.active = false
	return box


func _prompt_in_reach() -> bool:
	if state != State.HANGING:
		return false
	var player := _player_ref.get_player(get_tree())
	return player != null and player.global_position.distance_to(global_position) <= PROMPT_REACH


## 電纜下端離水面多高（吊著時）。
func _cable_bottom() -> float:
	return maxf(_anchor_height - CABLE_MAX, 18.0)


func is_live() -> bool:
	return state == State.LIVE


## 觸電範圍在世界座標的矩形（測試與量測用）。
func shock_rect() -> Rect2:
	return Rect2(global_position + Vector2(-data.water_width * 0.5, -SHOCK_HEIGHT), Vector2(data.water_width, SHOCK_HEIGHT))


## 剪斷電纜：開始掉進水裡。已經斷了就不做事；回傳有沒有剪斷。
func cut() -> bool:
	if state != State.HANGING:
		return false
	state = State.WARNING
	_left = data.warning_seconds
	hurtbox.enabled = false
	if _prompt != null:
		_prompt.enabled = false
	Fx.sparks(global_position + Vector2(0.0, -_anchor_height + 4.0), LIVE_COLOR, 8, 160.0, 0.35)
	Sfx.play(&"zap", -6.0)
	EventBus.world_noise.emit(global_position, 0.6)
	# 預警一開始就讓敵人知道別踩進來（NE-408）；腳底剛好在水面上，所以範圍往下多留一點。
	HazardZones.register(self, shock_rect().grow_individual(0.0, 0.0, 0.0, 2.0))
	return true


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.HANGING:
			_spark_in -= delta
			if _spark_in <= 0.0:
				_spark_in = randf_range(SPARK_EVERY.x, SPARK_EVERY.y)
				if not Settings.get_reduce_flashes():
					Fx.sparks(global_position + Vector2(0.0, -_cable_bottom()), LIVE_COLOR, 3, 90.0, 0.25)
		State.WARNING:
			_drop = minf(1.0, _drop + delta / maxf(data.warning_seconds * 0.6, 0.05))
			_left -= delta
			if _left <= 0.0:
				_go_live()
		State.LIVE:
			_left -= delta
			_arc_in -= delta
			if _arc_in <= 0.0:
				_arc_in = ARC_EVERY * (2.5 if Settings.get_reduce_flashes() else 1.0)
				var half := data.water_width * 0.5
				var x := randf_range(-half, half - 16.0)
				Fx.arc(global_position + Vector2(x, -1.0), global_position + Vector2(x + randf_range(10.0, 26.0), -1.0), LIVE_COLOR, 0.12, 1.2, 0.3, 0)
			if _left <= 0.0:
				_spend()
		State.SPENT:
			set_process(false)
	queue_redraw()


func _go_live() -> void:
	state = State.LIVE
	_left = data.live_seconds
	_drop = 1.0
	_hit_players.active = true
	_hit_enemies.active = true
	Fx.flash_light(global_position + Vector2(0.0, -8.0), LIVE_COLOR, data.water_width * 0.8, 1.2, data.live_seconds, data.live_seconds * 0.6)
	Sfx.play(&"zap", -1.0)
	electrified.emit(self)


func _spend() -> void:
	state = State.SPENT
	_hit_players.active = false
	_hit_enemies.active = false
	HazardZones.unregister(self)


func _exit_tree() -> void:
	HazardZones.unregister(self)


func _draw() -> void:
	if data == null:
		return
	var half := data.water_width * 0.5
	# 積水：一條低矮的水面，通電時發亮並抖動。
	var water := WATER_COLOR
	if state == State.LIVE:
		var pulse := 0.5 if Settings.get_reduce_flashes() else 0.5 + 0.5 * sin(_time * 40.0)
		water = WATER_COLOR.lerp(Color(LIVE_COLOR, 0.8), 0.35 + 0.35 * pulse)
	elif state == State.WARNING:
		water = WATER_COLOR.lerp(Color(LIVE_COLOR, 0.7), 0.25 + 0.25 * sin(_time * 25.0))
	draw_texture_rect(LightKit.soft_texture(), Rect2(-half * 1.08, -WATER_HEIGHT * 1.4, half * 2.16, WATER_HEIGHT * 2.8), false, water)
	draw_line(Vector2(-half * 0.85, -WATER_HEIGHT * 0.6), Vector2(half * 0.85, -WATER_HEIGHT * 0.6), Color(0.8, 0.95, 1.0, 0.3), 1.0)  # 水面反光
	# 電纜：吊點固定，下端在吊著時輕輕晃，斷了之後落到水面並蜷在水裡。
	var top := Vector2(0.0, -_anchor_height)
	var conduit := _anchor_height - CABLE_MAX
	if conduit > 0.0:
		draw_line(top, top + Vector2(0.0, conduit), CABLE_EDGE, 2.0)
	var start := top + Vector2(0.0, maxf(conduit, 0.0))
	var sway := 0.0 if Settings.get_reduce_ui_motion() else sin(_time * 1.7) * 2.0
	var hanging_end := Vector2(sway, -_cable_bottom())
	var fallen_end := Vector2(10.0, -1.0)
	var end := hanging_end.lerp(fallen_end, _drop) if state != State.HANGING else hanging_end
	var mid := start.lerp(end, 0.5) + Vector2(4.0 * _drop, 0.0)
	draw_polyline(PackedVector2Array([start, mid, end]), CABLE_COLOR, 2.5)
	draw_polyline(PackedVector2Array([start + Vector2(-0.8, 0.0), mid + Vector2(-0.8, 0.0), end + Vector2(-0.8, 0.0)]), CABLE_EDGE, 0.8)  # 受光的一側
	draw_circle(end, 1.6, LightKit.glow(LIVE_COLOR, 1.3) if state != State.SPENT else CABLE_EDGE)
