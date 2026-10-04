@abstract
class_name ChainEnemy
extends Enemy
## 觸手生物敵人的共用基底（打撈臂、纏絲、浮標蟲）：外觀是 ChainCreature（art/creatures/<creature_skin>.json）。
## 基底負責：
##   - 外觀組裝與每影格驅動（面向、速度、瞄準點、受擊身體反應）
##   - 每條觸手一個簡單的受擊框（尖端與中段的外框，跟著骨頭移動），打到觸手就扣那條觸手的生命，打斷後整條飛出
##   - 觸手還在時本體有裝甲（傷害 × armor_scale）；全部斷光後核心露出，傷害 × exposed_scale、出現弱點標記並硬直
##   - 出招用的傷害判定：_strike_begin(觸手編號) 之後判定圓每影格跟著那幾條觸手的骨頭，_strike_end() 收起
##   - 死亡：觸手失去張力軟下去、本體下沉
## 子類別寫狀態機與招式；觸手斷得越多移動越慢（_move_speed）。

const TENTACLE_PREFIX := "tentacle_"
const STRIKE_STRIDE := 3
const MAX_STRIKE_POINTS := 32
const PART_PAD := 3.0
const GROUND_PROBE_UP := 28.0
const GROUND_PROBE_DOWN := 72.0
const DEATH_SINK := 9.0
const DEATH_TIME := 1.0
const CORE_PART_MULT := 1.6

var chain: ChainCreature

var _strike: BoneHitbox
var _strike_tentacles := PackedInt32Array()
var _strike_points := PackedVector2Array()
var _scratch := PackedVector2Array()
var _tentacle_parts: Array[Hurtbox] = []
var _part_enabled: Array[bool] = []
var _ground := GroundProbe.new()
var _armor_scale := 1.0
var _exposed_scale := 1.0


func _build_creature() -> void:
	chain = ChainCreature.new()
	chain.name = "Chain"
	add_child(chain)
	if not chain.setup(data.creature_skin):
		push_error("[ChainEnemy] %s 的觸手外觀載入失敗：%s，改用程式繪製。" % [data.id, data.creature_skin])
		chain.queue_free()
		chain = null
		return
	chain.show_behind_parent = true
	chain.body_scale = data.creature_scale
	chain.ground_probe = _probe_ground
	chain.tentacle_severed.connect(_on_tentacle_severed)
	chain.core_exposed.connect(_on_core_exposed)
	chain.foot_planted.connect(_on_foot_planted)
	_armor_scale = chain.combat_value("armor_scale", 1.0)
	_exposed_scale = chain.combat_value("exposed_scale", 2.0)
	hurtbox.damage_scale = _armor_scale
	_strike = BoneHitbox.new()
	_strike.name = "Strike"
	add_child(_strike)
	_strike.setup_bones(Combat.Team.ENEMY, maxi(1, data.contact_damage), data.contact_source_id, MAX_STRIKE_POINTS)
	_strike.active = false
	_strike_points.resize(0)


func _build_hurt_parts() -> void:
	super()
	if chain == null:
		return
	for i in chain.tentacle_count():
		var part := hurtbox.add_part(StringName(TENTACLE_PREFIX + str(i)), Vector2(8, 8), Vector2.ZERO, 1.0)
		_tentacle_parts.append(part)
		_part_enabled.append(true)


# ---------------------------------------------------------------------------
# 驅動
# ---------------------------------------------------------------------------

func _creature_state() -> StringName:
	return &"dead" if _dying else super()


func _physics_process(delta: float) -> void:
	if _dying and chain != null:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		if data.uses_gravity and not is_on_floor():
			velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL_SPEED)
		move_and_slide()
		_drive_creature(delta)
		return
	super(delta)


func _drive_creature(delta: float) -> void:
	if chain == null:
		return
	var params := _body_kick_params()
	chain.position = params[0]
	chain.rotation = params[1]
	chain.facing = facing
	chain.set_aim_point(_target_point())
	chain.animate(delta, _creature_state(), velocity)
	_drive_strike()


func _move_speed() -> float:
	return data.move_speed * (chain.speed_scale() if chain != null else 1.0)


## 地面高度（世界座標 y）：從腳邊上方往下射一條線，找不到就用敵人自己的高度。
func _probe_ground(world_x: float) -> float:
	return _ground.ground_y(get_world_2d().direct_space_state, world_x, global_position.y - GROUND_PROBE_UP, global_position.y, GROUND_PROBE_UP + GROUND_PROBE_DOWN)


# ---------------------------------------------------------------------------
# 受擊框跟著觸手
# ---------------------------------------------------------------------------

## 子類別覆寫：目前觸手能不能被打到（例如纏絲縮回時不行）。
func _tentacles_hittable() -> bool:
	return true


func _update_hurt_parts() -> void:
	super()
	if chain == null:
		return
	var hittable := _tentacles_hittable()
	for i in _tentacle_parts.size():
		var part := _tentacle_parts[i]
		var on := hittable and chain.is_alive(i)
		if on != _part_enabled[i]:
			_part_enabled[i] = on
			part.enabled = on
		if not on:
			continue
		chain.fill_hit_points(i, maxi(1, chain.bone_count() / 2), _scratch)
		if _scratch.size() < 2:
			continue
		var a := _scratch[0]
		var b := _scratch[_scratch.size() - 1]
		var pad := chain.hit_radius(i) * 2.0 + PART_PAD
		hurtbox.move_part(part, (a + b) * 0.5 - global_position)
		part.resize(Vector2(absf(a.x - b.x) + pad, absf(a.y - b.y) + pad), (a + b) * 0.5 - global_position)


func _on_hit(info: DamageInfo) -> void:
	if chain == null:
		return
	var id := String(info.part)
	if id.begins_with(TENTACLE_PREFIX):
		var index := int(id.substr(TENTACLE_PREFIX.length()))
		var tip := chain.tip_of(index)
		if tip != Vector2.INF:
			chain.hit_wave(tip, clampf(float(info.amount) * 0.4, 0.3, 1.2))
		chain.damage_tentacle(index, info.amount, info.knockback)


func _on_tentacle_severed(index: int) -> void:
	var at := global_position + Vector2(0.0, -data.body_size.y * 0.4)
	Fx.sparks(at, data.color, 8, 170.0, 0.3)
	Fx.smoke(at, 2, 5.0, 0.7, 8.0)
	Feel.play(&"enemy_flinch", {"targets": [self]})
	_on_tentacle_lost(index)


## （可選）失去一條觸手時子類別要做的事（改變招式、換步態…）。
func _on_tentacle_lost(_index: int) -> void:
	pass


func _on_core_exposed() -> void:
	hurtbox.damage_scale = _exposed_scale
	var size := Vector2(10, 10)
	var offset := Vector2(0.0, -data.body_size.y * 0.55)
	var part := hurtbox.add_part(&"core", size, offset, CORE_PART_MULT)
	_parts.append({"box": part, "bone": &"", "offset": offset, "size": size, "mult": CORE_PART_MULT})
	Fx.burst(_center(), Palette.WARNING, 12, 140.0)
	stun(data.stagger_duration)


func _on_foot_planted(_index: int, at: Vector2) -> void:
	Fx.dust(at, 1, 6.0)


# ---------------------------------------------------------------------------
# 出招判定
# ---------------------------------------------------------------------------

## 讓這幾條觸手變成傷害判定（判定圓跟著骨頭）；已斷的忽略。
func _strike_begin(indices: PackedInt32Array) -> void:
	_strike_tentacles = indices
	if _strike != null:
		_strike.active = true


func _strike_end() -> void:
	_strike_tentacles = PackedInt32Array()
	if _strike != null:
		_strike.active = false
		_strike.clear_points()


func _drive_strike() -> void:
	if _strike == null or _strike_tentacles.is_empty():
		return
	_strike_points.clear()
	var radius := 3.0
	for index in _strike_tentacles:
		chain.fill_hit_points(index, STRIKE_STRIDE, _scratch)
		_strike_points.append_array(_scratch)
		radius = maxf(radius, chain.hit_radius(index))
	_strike.set_points(_strike_points, radius)


## 活著的觸手編號中，尖端最靠近 world_point 的前 count 條（出招挑觸手用）。
func _nearest_tentacles(world_point: Vector2, count: int) -> PackedInt32Array:
	var order: Array[Vector2] = []
	for i in chain.tentacle_count():
		if chain.is_alive(i):
			order.append(Vector2(i, chain.tip_of(i).distance_squared_to(world_point)))
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var out := PackedInt32Array()
	for k in mini(count, order.size()):
		out.append(int(order[k].x))
	return out


# ---------------------------------------------------------------------------
# 死亡與繪製
# ---------------------------------------------------------------------------

func _play_death() -> void:
	if chain == null:
		super()
		return
	_strike_end()
	chain.go_limp()
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	_death_tween.tween_property(chain, "position:y", DEATH_SINK, DEATH_TIME).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(DEATH_TIME)
	_death_tween.chain().tween_callback(queue_free)
	_register_corpse()


func _draw_body(color: Color) -> void:
	if chain != null:
		return
	# 外觀載入失敗時的保險：畫一個色塊，至少看得到位置。
	draw_rect(Rect2(Vector2(-data.body_size.x * 0.5, -data.body_size.y), data.body_size), color)
