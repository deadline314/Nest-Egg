class_name Conveyor
extends Node2D
## 輸送帶（NE-401）：站在帶面上的人（玩家與敵人都一樣）每一個物理影格被往帶子的方向推一段（用 move_and_collide，
## 撞到牆就停，不會穿牆）；跳起來就不受影響。右端的馬達被玩家的子彈、近戰或爆炸打中時，帶子反轉。
## 帶面上的箭頭紋路跟著方向移動，只在畫面內才重畫。原點在輸送帶左端的地面上；方向跟著檢查點保存。

signal reversed(conveyor: Conveyor)

const GROUP := &"conveyors"
const BELT_HEIGHT := 4.0
## 帶面上方多高以內的腳底算「站在帶子上」。
const STAND_BAND := 6.0
const CHEVRON_SPACING := 12.0
const BELT_COLOR := Color("22272f")
const BELT_EDGE := Color("566170")
const ARROW_COLOR := Color(0.95, 0.72, 0.25, 0.75)
const MOTOR_SIZE := Vector2(18.0, 16.0)
const MOTOR_COLOR := Color("3a414c")
## 馬達帶動輪的半徑（像素）。
const MOTOR_PULLEY := 5.0
const LAMP_FORWARD := Color(0.35, 0.95, 1.0)
const LAMP_BACK := Color(1.0, 0.55, 0.2)
## 玩家離帶子兩端多遠以內顯示提示（像素）。
const PROMPT_MARGIN := 48.0

var data: ConveyorData
var cell := Vector2i.ZERO
## 目前的速度（像素／秒）；反轉時變號。
var speed := 0.0
var length := 256.0
var health: HealthComponent
var hurtbox: Hurtbox

var _scroll := 0.0
var _cooldown := 0.0
var _flipped := false
var _sensor: Area2D
var _prompt: WorldPrompt
var _on_screen := true
var _half_tile := 0.0
var _player_ref := PlayerRef.new()


func configure(p_data: ConveyorData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	length = float(data.length_tiles * tile_size)
	speed = data.speed
	_half_tile = tile_size * 0.5


func _ready() -> void:
	if data == null:
		push_error("[Conveyor] 未指定 ConveyorData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	add_to_group(WorldState.GROUP)
	position.x -= _half_tile  # 關卡把生成物放在格子中央；帶子從格子左緣開始
	# 只用來找出帶面上方的人；不擋任何東西。
	_sensor = Area2D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = Layers.PLAYER | Layers.ENEMY
	_sensor.monitorable = false
	var band := RectangleShape2D.new()
	band.size = Vector2(length, STAND_BAND * 2.0)
	var band_node := CollisionShape2D.new()
	band_node.shape = band
	band_node.position = Vector2(length * 0.5, -STAND_BAND)
	_sensor.add_child(band_node)
	add_child(_sensor)
	health = HealthComponent.new()
	add_child(health)
	health.setup(1000, 0.0)
	health.damaged.connect(_on_motor_hit)
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, MOTOR_SIZE, motor_center() - global_position)
	hurtbox.hit_material = &"metal"
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.reach_check = _prompt_in_reach
		_prompt.position = Vector2(length, 0.0)
		_prompt.offset = Vector2(0.0, -MOTOR_SIZE.y - 18.0)
		add_child(_prompt)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(Vector2(0.0, -MOTOR_SIZE.y - 4.0), Vector2(length + MOTOR_SIZE.x, MOTOR_SIZE.y + 8.0))
	notifier.screen_entered.connect(func() -> void: _on_screen = true)
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


## 提示在玩家走近或站上帶子時出現（帶子很長，只看離馬達多遠會在最需要的時候看不到）。
func _prompt_in_reach() -> bool:
	var player := _player_ref.get_player(get_tree())
	if player == null:
		return false
	var at := player.global_position - global_position
	return at.x > -PROMPT_MARGIN and at.x < length + PROMPT_MARGIN and absf(at.y) < PROMPT_MARGIN


## 馬達（右端）的世界座標中心。
func motor_center() -> Vector2:
	return global_position + Vector2(length + MOTOR_SIZE.x * 0.5, -MOTOR_SIZE.y * 0.5)


## 帶面在世界座標的範圍。
func belt_rect() -> Rect2:
	return Rect2(global_position + Vector2(0.0, -BELT_HEIGHT), Vector2(length, BELT_HEIGHT))


func is_reversed() -> bool:
	return _flipped


func _on_motor_hit(_info: DamageInfo) -> void:
	health.heal(1000)  # 馬達不會壞，只看有沒有被打到
	reverse()


## 反轉帶子。冷卻中不做事；回傳有沒有反轉。
func reverse() -> bool:
	if _cooldown > 0.0:
		return false
	_cooldown = data.reverse_cooldown
	_flipped = not _flipped
	speed = -data.speed if _flipped else data.speed
	Fx.sparks(motor_center(), Palette.WARNING, 6, 120.0, 0.3)
	Sfx.play(&"switch", -4.0)
	reversed.emit(self)
	queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var push := Vector2(speed * delta, 0.0)
	for body in _sensor.get_overlapping_bodies():
		var mover := body as CharacterBody2D
		if mover == null or not mover.is_on_floor():
			continue
		var feet := mover.global_position
		if feet.x < global_position.x or feet.x > global_position.x + length or feet.y < global_position.y - STAND_BAND:
			continue
		mover.move_and_collide(push)


func _process(delta: float) -> void:
	if not _on_screen:
		return
	if not Settings.get_reduce_ui_motion():
		_scroll = fposmod(_scroll + speed * delta, CHEVRON_SPACING)
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	# 帶面：一條低矮的深色帶子，上緣一條受光的亮邊，兩端是會轉的滾輪。
	draw_rect(Rect2(0.0, -BELT_HEIGHT, length, BELT_HEIGHT), BELT_COLOR)
	draw_line(Vector2(0.0, -BELT_HEIGHT + 0.5), Vector2(length, -BELT_HEIGHT + 0.5), BELT_EDGE, 1.0)
	_draw_pulley(Vector2(0.0, -BELT_HEIGHT * 0.5), BELT_HEIGHT * 0.75)
	# 箭頭紋路：指向目前的方向，跟著帶子移動。
	var direction := signf(speed) if not is_zero_approx(speed) else 1.0
	var x := _scroll
	while x < length:
		var tip := Vector2(x + 2.0 * direction, -BELT_HEIGHT * 0.5)
		draw_line(tip, tip + Vector2(-3.0 * direction, -1.4), ARROW_COLOR, 1.0)
		draw_line(tip, tip + Vector2(-3.0 * direction, 1.4), ARROW_COLOR, 1.0)
		x += CHEVRON_SPACING
	# 馬達：右端切角的機殼（不是方塊），上緣受光、側面散熱槽，帶動輪露在帶子末端；方向燈青色＝原方向、橘色＝反轉中。
	var w := MOTOR_SIZE.x
	var h := MOTOR_SIZE.y
	var c := 4.0
	var shell := PackedVector2Array([
		Vector2(length + 2.0, 0.0), Vector2(length + 2.0, -h + c), Vector2(length + 2.0 + c, -h),
		Vector2(length + w - c, -h), Vector2(length + w, -h + c), Vector2(length + w, 0.0)])
	draw_colored_polygon(shell, MOTOR_COLOR)
	draw_polyline(PackedVector2Array([shell[1], shell[2], shell[3], shell[4]]), BELT_EDGE, 1.0)  # 上緣受光
	for i in 3:
		var y := -h * 0.45 + i * 3.0
		draw_line(Vector2(length + w * 0.45, y), Vector2(length + w - 3.0, y), BELT_COLOR, 1.0)
	draw_rect(Rect2(length + 1.0, -1.5, w, 1.5), BELT_COLOR)  # 底座
	_draw_pulley(Vector2(length + 1.0, -MOTOR_PULLEY), MOTOR_PULLEY)  # 輪子坐在地面上
	var lamp := Vector2(length + w * 0.5 + 1.0, -h + 3.5)
	draw_circle(lamp, 1.6, LightKit.glow(LAMP_BACK if _flipped else LAMP_FORWARD, 1.4))


## 滾輪：圓盤加三根跟著帶子轉的輻條。
func _draw_pulley(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, BELT_COLOR)
	draw_arc(center, radius, 0.0, TAU, 12, BELT_EDGE, 1.0)
	var spin := -_scroll / radius
	for i in 3:
		var angle := spin + i * TAU / 3.0
		draw_line(center, center + Vector2.from_angle(angle) * (radius - 0.5), BELT_EDGE, 1.0)


# 檢查點狀態（WorldState）：方向。
func state_key() -> String:
	return "conveyor@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return _flipped


func restore_state(saved: Variant) -> void:
	if saved is bool and saved != _flipped:
		_flipped = saved
		speed = -data.speed if _flipped else data.speed
		queue_redraw()
