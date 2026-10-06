class_name Flamer
extends Enemy
## 火焰兵（重裝近距離）
## 行為：逼近玩家到火焰的射程內，停下點火——噴口亮起、火舌逐漸變長（預兆，頭上有驚嘆號）——
##       然後朝面向方向噴射一段時間，噴射時緩慢前進；噴完收火，有一段空檔。
##       背後掛著燃料罐：打中夠多次會爆炸，傷到附近所有人（包含牠自己）。
## 應對：保持距離（火舌只有固定的長度）；繞到背後或在背後遠距離射擊燃料罐，爆炸傷害很高；
##       用格擋擋火焰（完美格擋會讓牠暈眩）；收火的空檔是輸出的機會。
## 數值：attack_range = 火焰長度（從槍口算起；點火距離再加上槍口到身體的距離），telegraph_time = 點火預熱，ability_time = 噴射秒數，
##       ability_speed = 噴射時前進速度，contact_damage = 火焰每次命中的傷害，ability_damage = 燃料罐能承受的攻擊次數，
##       projectile = 燃料罐爆炸規格（explosion_radius、explosion_damage 對敵人、damage 對玩家、source_id 死因）。

const FLAME_HEIGHT := 24.0
## 火焰碰撞盒的最短長度，避免貼牆時縮成零。
const MIN_FLAME_LENGTH := 8.0
const RECOVER_TIME := 0.8
const APPROACH_RATIO := 0.85
const IGNITE_RANGE_RATIO := 1.0
## 燃料罐的位置（背後）：和身體的受擊框留 3 像素空隙，子彈從背後來會先打中罐子而不是身體。
const TANK_OFFSET := Vector2(16.0, -28.0)
## 槍口離身體的大約距離：火焰長度從槍口算起，點火與逼近的距離要把它算進去。
const MUZZLE_OFFSET := 30.0
const FLAME_COLOR := Color(1.0, 0.5, 0.12)
const SOUND_INTERVAL := 0.22

var tank: FuelTank
var flame_length := 0.0

var _cooldown := 0.6
var _flame_box: ContactHitbox
var _flame_light: PointLight2D
var _sound_left := 0.0
var _burn_progress := 0.0


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"ignite", _ignite_tick, _ignite_enter)
	fsm.add(&"burn", _burn_tick, _burn_enter, _burn_exit)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"patrol")


func _ready() -> void:
	super._ready()
	if data == null:
		return
	_flame_box = ContactHitbox.new()
	add_child(_flame_box)
	_flame_box.setup(Combat.Team.ENEMY, maxi(1, data.contact_damage), &"flamer_burn", Vector2(data.attack_range, FLAME_HEIGHT))
	_flame_box.active = false
	_flame_light = LightKit.create_point_light(FLAME_COLOR, 90.0, 0.0, false, false)
	_flame_light.enabled = false
	add_child(_flame_light)
	tank = FuelTank.new()
	add_child(tank)
	tank.setup(maxi(1, data.ability_damage), data.projectile)
	tank.follow(facing, TANK_OFFSET)
	tank.exploded.connect(_on_tank_exploded)


func has_tank() -> bool:
	return tank != null and is_instance_valid(tank) and not tank.is_exploded


func is_burning() -> bool:
	return fsm.is_in(&"burn")


func _on_stunned() -> void:
	if fsm.is_in(&"ignite") or fsm.is_in(&"burn"):
		fsm.transition(&"recover")


func _on_defeated(_info: DamageInfo) -> void:
	_stop_flame()
	if tank != null and is_instance_valid(tank) and not tank.is_exploded:
		tank.hurtbox.enabled = false
		tank.visible = false


## 燃料罐爆炸：牠被炸得暈眩（爆炸傷害已由爆炸本身造成）。
func _on_tank_exploded(_tank: FuelTank) -> void:
	if is_dying():
		return
	_stop_flame()
	stun(data.stagger_duration)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if tank != null and is_instance_valid(tank):
		tank.follow(facing, TANK_OFFSET)


# ---------------------------------------------------------------------------
# 狀態
# ---------------------------------------------------------------------------

func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not _can_see_target(data.detect_range, 70.0):
		_patrol(data.move_speed)
		return
	_face_target()
	var distance := _distance_to_target()
	var reach := data.attack_range + MUZZLE_OFFSET
	if distance > reach * APPROACH_RATIO and not (is_on_floor() and _is_ledge_ahead()):
		velocity.x = facing * data.move_speed
	else:
		velocity.x = 0.0
	if _cooldown <= 0.0 and _token_free() and distance <= reach * IGNITE_RANGE_RATIO:
		fsm.transition(&"ignite")


func _ignite_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_start_telegraph(data.telegraph_time)
	Sfx.play(&"ignite", -4.0)
	_flame_light.enabled = true


func _ignite_tick(_delta: float) -> void:
	velocity.x = 0.0
	var t := clampf(fsm.time_in_state / maxf(0.05, data.telegraph_time), 0.0, 1.0)
	flame_length = lerpf(6.0, data.attack_range * 0.3, t)
	_flame_light.global_position = _muzzle() + Vector2(facing * 10.0, 0)
	_flame_light.energy = 0.4 + 0.5 * t + 0.15 * sin(_anim_time * 30.0)
	if not is_telegraphing():
		fsm.transition(&"burn")


func _burn_enter() -> void:
	_burn_progress = 0.0
	_sound_left = 0.0
	_flame_box.active = true


func _burn_exit() -> void:
	_stop_flame()


func _burn_tick(delta: float) -> void:
	_burn_progress = clampf(fsm.time_in_state / maxf(0.1, data.ability_time), 0.0, 1.0)
	var blocked := is_on_wall() or (is_on_floor() and _is_ledge_ahead())
	velocity.x = 0.0 if blocked else facing * data.ability_speed
	# 火舌先衝出去，再維持；被牆擋住就截短。
	var reach := data.attack_range * clampf(fsm.time_in_state / 0.18, 0.3, 1.0)
	flame_length = _clip_to_wall(reach)
	var length := maxf(MIN_FLAME_LENGTH, flame_length)
	var origin := to_local(_muzzle())
	_flame_box.resize(Vector2(length, FLAME_HEIGHT), origin + Vector2(facing * (length * 0.5), 0.0))
	_flame_light.global_position = _muzzle() + Vector2(facing * length * 0.5, 0)
	_flame_light.energy = 1.5 + 0.4 * sin(_anim_time * 40.0)
	_sound_left -= delta
	if _sound_left <= 0.0:
		_sound_left = SOUND_INTERVAL
		Sfx.play(&"flame", -9.0, 0.1)
		Fx.burst(_muzzle() + Vector2(facing * length * randf(), randf_range(-6.0, 6.0)), FLAME_COLOR, 2, 40.0, 0.3)
	if fsm.time_in_state >= data.ability_time:
		fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if fsm.time_in_state >= RECOVER_TIME:
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


func _stop_flame() -> void:
	flame_length = 0.0
	if _flame_box != null:
		_flame_box.active = false
	if _flame_light != null:
		_flame_light.enabled = false


## 火焰沿面向方向的實際長度：碰到牆就截斷。
func _clip_to_wall(reach: float) -> float:
	var from := _muzzle()
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(facing * reach, 0.0), Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return reach if hit.is_empty() else from.distance_to(hit["position"])


func _rig_aim() -> Vector2:
	return Vector2(facing, 0.04).normalized()


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

func _draw_overlay() -> void:
	if flame_length <= 1.0 or not (fsm.is_in(&"ignite") or fsm.is_in(&"burn")):
		return
	var origin := to_local(_muzzle())
	var f := float(facing)
	var burning := fsm.is_in(&"burn")
	var length := flame_length
	var flicker := 1.0 + 0.12 * sin(_anim_time * 55.0) + 0.08 * sin(_anim_time * 31.0)
	# 三層火舌：外層紅橘、中層橘、核心黃白。
	var layers := [[1.0, Color(1.0, 0.25, 0.08, 0.55), 2.2], [0.72, Color(1.0, 0.55, 0.12, 0.8), 2.8], [0.42, Color(1.0, 0.93, 0.6, 0.95), 3.4]]
	for layer: Array in layers:
		var len_scale: float = layer[0]
		var color: Color = layer[1]
		var spread := FLAME_HEIGHT * 0.5 * (0.45 if not burning else 1.0) * len_scale
		var tip := origin + Vector2(f * length * len_scale * flicker, 0.0)
		var wobble := sin(_anim_time * 24.0 + len_scale * 3.0) * 2.0
		var points := PackedVector2Array([origin + Vector2(0, -2), origin + Vector2(f * length * 0.45 * len_scale, -spread + wobble),
				tip, origin + Vector2(f * length * 0.45 * len_scale, spread - wobble), origin + Vector2(0, 2)])
		draw_colored_polygon(points, LightKit.glow(color, layer[2]))
	# 噴口的光點。
	draw_circle(origin, 3.0 if not burning else 4.5, LightKit.glow(Color(1.0, 0.9, 0.5), 3.0))


func _draw_body(color: Color) -> void:
	# 骨架載入失敗時的備用外觀：圓厚的身形與橘色護目鏡。
	var f := float(facing)
	var h := data.body_size.y
	draw_line(Vector2(-4, -h * 0.4), Vector2(-4, 0), color.darkened(0.45), 4.0)
	draw_line(Vector2(4, -h * 0.4), Vector2(4, 0), color.darkened(0.45), 4.0)
	draw_rect(Rect2(-8, -h * 0.82, 16, h * 0.46), color.darkened(0.2))
	draw_circle(Vector2(0, -h * 0.9), 6.0, color.darkened(0.3))
	draw_circle(Vector2(f * 3.0, -h * 0.9), 2.0, LightKit.glow(FLAME_COLOR, 2.0))
