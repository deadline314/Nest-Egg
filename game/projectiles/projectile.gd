class_name Projectile
extends Area2D
## 子彈：由 ProjectilePool 管理生命週期，請勿自行 queue_free。

signal expired(projectile: Projectile)

const REFLECT_SPEED_SCALE := 1.35
const REFLECT_DAMAGE_SCALE := 2.0
## 反彈子彈的衝擊力（重擊，打得一般敵人硬直）。
const REFLECT_IMPACT := 6.0
## 拖尾最多記錄幾個位置（固定容量，不配置記憶體）、每個影格最多記一次；煙跡的間隔秒數。
const MAX_TRAIL_POINTS := 14
const TRAIL_ALPHA := 0.5
const SMOKE_INTERVAL := 0.045
## 傷害數字只在重擊（衝擊力達此值）或弱點時顯示。
const HEAVY_NUMBER_IMPACT := 6.0
const MAX_SWEEP_CONTACTS := 24
const CONTACT_ADVANCE := 0.05
const ProjectileArt := preload("res://game/projectiles/projectile_art.gd")

var spec: ProjectileSpec
var team: Combat.Team = Combat.Team.PLAYER
var velocity := Vector2.ZERO
var active := false

var _life := 0.0
var _pierce_left := 0
## 反彈後的傷害倍率與顏色（規格資源是共用的，所以覆寫值存在子彈本身）。
var _damage_scale := 1.0
var _color := Color.WHITE
var _hit_ids: Dictionary[int, bool] = {}
var _shape := CircleShape2D.new()
var _sweep := PhysicsShapeQueryParameters2D.new()
var _sweep_exclude: Array[RID] = []
## 拖尾環形緩衝：_trail_head 是最新的一筆，往回數就是越舊；固定容量。
var _trail := PackedVector2Array()
var _trail_len := 0
var _trail_head := 0
var _smoke_left := 0.0


func _init() -> void:
	_trail.resize(MAX_TRAIL_POINTS)
	_sweep.shape = _shape
	_sweep.collide_with_areas = true
	_sweep.collide_with_bodies = true
	_sweep.margin = 0.0
	collision_layer = 0
	monitorable = false
	monitoring = false
	visible = false
	var shape_node := CollisionShape2D.new()
	shape_node.shape = _shape
	add_child(shape_node)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _ready() -> void:
	LightKit.mark_emissive(self)
	set_physics_process(active)


func activate(p_spec: ProjectileSpec, origin: Vector2, direction: Vector2, p_team: Combat.Team, speed_multiplier := 1.0) -> void:
	spec = p_spec
	team = p_team
	global_position = origin
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	velocity = dir * spec.speed * maxf(0.05, speed_multiplier)
	rotation = velocity.angle()
	_life = spec.lifetime
	_pierce_left = spec.pierce
	_hit_ids.clear()
	_trail_len = 0
	_smoke_left = 0.0
	_damage_scale = 1.0
	_color = spec.color
	_shape.radius = maxf(1.0, spec.radius)
	_update_mask()
	active = true
	visible = true
	set_physics_process(true)
	set_deferred(&"monitoring", true)
	queue_redraw()


func deactivate() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)
	set_deferred(&"monitoring", false)
	expired.emit(self)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if spec.gravity != 0.0:
		velocity.y += spec.gravity * delta
		rotation = velocity.angle()
	_move_swept(delta)
	if not active:
		return
	_record_trail(delta)
	_life -= delta
	if _life <= 0.0:
		_finish(false)


## Sweep the same circle used by Area2D. Trails never participate in collision.
## The bounded contact loop also handles penetration and a new team after a parry.
func _move_swept(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var remaining := delta
	_sweep_exclude.clear()
	_sweep_exclude.append(get_rid())
	for contact in MAX_SWEEP_CONTACTS:
		if not active or remaining <= 0.000001:
			return
		_sweep.collision_mask = Combat.hurtbox_mask_against(team) | (0 if spec.passes_walls else Layers.WORLD)
		_sweep.exclude = _sweep_exclude
		_sweep.transform = Transform2D(0.0, global_position)
		_sweep.motion = Vector2.ZERO
		# cast_motion intentionally ignores initial overlaps: resolve these first.
		var hit := space.get_rest_info(_sweep)
		if hit.is_empty():
			var motion := velocity * remaining
			_sweep.motion = motion
			var fractions := space.cast_motion(_sweep)
			if fractions.size() < 2 or fractions[0] >= 1.0:
				global_position += motion
				return
			var fraction := minf(1.0, fractions[1] + CONTACT_ADVANCE / maxf(motion.length(), CONTACT_ADVANCE))
			global_position += motion * fraction
			remaining *= 1.0 - fraction
			_sweep.transform.origin = global_position
			_sweep.motion = Vector2.ZERO
			hit = space.get_rest_info(_sweep)
			if hit.is_empty():
				# Conservatively stop at the safe point if the physics contact disappears.
				global_position -= motion * (fraction - fractions[0])
				return
		var collider := instance_from_id(int(hit["collider_id"])) as Node2D
		_sweep_exclude.append(hit["rid"])
		if collider is Area2D:
			_on_area_entered(collider)
		elif collider != null:
			_on_body_entered(collider)
	# Dense overlap cannot turn into unbounded query work or a head passing through walls.
	deactivate()


## 記下目前位置當作拖尾的一點；火箭另外冒煙。拖尾要重畫，所以有拖尾的子彈每個影格重畫。
func _record_trail(delta: float) -> void:
	if spec.smoke_trail and LightQuality.tier() != LightQuality.Tier.LOW:
		_smoke_left -= delta
		if _smoke_left <= 0.0:
			_smoke_left = SMOKE_INTERVAL
			Fx.smoke(global_position, 1, 3.0, 0.7, 7.0, Color(0.78, 0.72, 0.66, 0.35))
	if spec.trail_points <= 1:
		return
	_trail_head = (_trail_head + 1) % MAX_TRAIL_POINTS
	_trail[_trail_head] = global_position
	_trail_len = mini(_trail_len + 1, MAX_TRAIL_POINTS)
	queue_redraw()


## 第 age 新的拖尾位置（0＝最新）。
func _trail_at(age: int) -> Vector2:
	return _trail[posmod(_trail_head - age, MAX_TRAIL_POINTS)]


func _on_area_entered(area: Area2D) -> void:
	if not active:
		return
	var hurtbox := area as Hurtbox
	if hurtbox == null or hurtbox.team == team or not hurtbox.can_receive():
		return
	_strike(hurtbox)


## 命中受擊框：造成傷害、格擋或反彈；傷害後依貫穿數決定是否繼續飛。
func _strike(hurtbox: Hurtbox) -> void:
	hurtbox = hurtbox.resolve_at(global_position)
	# 同一發子彈對同一個目標只算一次（頭與身體的受擊框重疊時也一樣）。
	var id := hurtbox.health.get_instance_id() if hurtbox.health != null else hurtbox.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true
	var info := _make_damage()
	match hurtbox.receive(info):
		Hurtbox.Result.DAMAGED:
			HitFeedback.play(hurtbox.material_id(), global_position, -velocity.normalized(), spec.color, {"weak": info.weak_hit})
			if team == Combat.Team.PLAYER:
				EventBus.hit_confirmed.emit(global_position, hurtbox.health.is_dead)
				EventBus.hit_marker.emit(&"kill" if hurtbox.health.is_dead else (&"weak" if info.weak_hit else &"hit"))
				if info.weak_hit or info.get_impact() >= HEAVY_NUMBER_IMPACT:
					EventBus.damage_number.emit(global_position, info.amount, &"weak" if info.weak_hit else &"crit", hurtbox.health.get_instance_id())
		Hurtbox.Result.REFLECTED:
			_reflect(hurtbox.reflect_direction)
			return
		Hurtbox.Result.BLOCKED:
			# 被格擋：火花反彈、子彈直接消失（即使可貫穿）。
			HitFeedback.play(hurtbox.material_id(), global_position, -velocity.normalized(), Palette.WHITE, {"ricochet": true})
			Sfx.play(&"block", -4.0)
			if team == Combat.Team.PLAYER:
				EventBus.hit_marker.emit(&"blocked")
				EventBus.damage_number.emit(global_position, 0, &"blocked", hurtbox.health.get_instance_id() if hurtbox.health != null else 0)
			_finish(true)
			return
		_:
			return
	if _pierce_left > 0:
		_pierce_left -= 1
	else:
		_finish(true)


func _make_damage() -> DamageInfo:
	var info := DamageInfo.create(maxi(1, roundi(spec.damage * _damage_scale)), team, spec.source_id, velocity.normalized() * spec.knockback)
	info.stagger = spec.stagger
	info.origin = global_position
	info.is_projectile = true
	if _damage_scale > 1.0:
		info.impact = REFLECT_IMPACT  # 反彈回去的子彈是重擊
	return info


## 撞上實體：一般地形直接消失；可破壞物（有 hit_by_projectile）會受傷，貫穿彈打破後可以繼續飛。
func _on_body_entered(body: Node2D) -> void:
	if not active:
		return
	if body.has_method(&"hit_by_projectile"):
		var id := body.get_instance_id()
		if _hit_ids.has(id):
			return
		_hit_ids[id] = true
		var result: int = body.call(&"hit_by_projectile", _make_damage())
		if result == Hurtbox.Result.DAMAGED:
			var box: Variant = body.get(&"hurtbox")
			HitFeedback.play((box as Hurtbox).material_id() if box is Hurtbox else &"", global_position, -velocity.normalized(), spec.color)
			if team == Combat.Team.PLAYER:
				EventBus.hit_confirmed.emit(global_position, false)
			if _pierce_left > 0:
				_pierce_left -= 1
				return
	HitFeedback.play(&"concrete", global_position, -velocity.normalized(), _color.darkened(0.2))
	_finish(true)


## 被完美格擋：改由對方陣營擁有，朝指定方向加速飛回，傷害加倍。
func _reflect(direction: Vector2) -> void:
	team = Combat.Team.PLAYER if team == Combat.Team.ENEMY else Combat.Team.ENEMY
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else -velocity.normalized()
	velocity = dir * maxf(velocity.length(), spec.speed) * REFLECT_SPEED_SCALE
	rotation = velocity.angle()
	_damage_scale = REFLECT_DAMAGE_SCALE
	_color = Palette.CYAN
	_life = spec.lifetime
	_hit_ids.clear()
	_trail_len = 0
	_smoke_left = 0.0
	_update_mask()
	queue_redraw()


func _update_mask() -> void:
	set_deferred(&"collision_mask", Combat.hurtbox_mask_against(team) | (0 if spec.passes_walls else Layers.WORLD))


func _finish(impact: bool) -> void:
	if spec.explosion_radius > 0.0 and (impact or spec.explode_on_expire):
		Fx.explosion(global_position, spec.explosion_radius, roundi(spec.explosion_damage * _damage_scale), team, spec.source_id, _color)
	deactivate()


func _draw() -> void:
	if spec == null:
		return
	_draw_trail()
	ProjectileArt.paint(self, spec, _color, team, _damage_scale > 1.0)


## 彈道拖尾：沿最近的位置畫漸細漸淡的線段（亮度不超過發光上限，克制不搶眼）；彈道有重力時尾巴會彎。
func _draw_trail() -> void:
	var count := mini(_trail_len, mini(spec.trail_points, MAX_TRAIL_POINTS))
	if count < 2:
		return
	var head_width := spec.radius * 1.5 * spec.trail_width
	var distance_left := clampf(spec.trail_distance, 0.0, 40.0)
	if LightQuality.tier() == LightQuality.Tier.LOW:
		distance_left = minf(distance_left, 6.0)
	for i in range(count - 1):
		var start := _trail_at(i)
		var end := _trail_at(i + 1)
		var length := start.distance_to(end)
		if length <= 0.001:
			continue
		var used := minf(length, distance_left)
		end = start.lerp(end, used / length)
		var k := float(i) / float(count - 1)
		var color := Color(_color, TRAIL_ALPHA * 0.5 * (1.0 - k))
		draw_line(to_local(start), to_local(end), color, maxf(0.6, lerpf(head_width * 0.65, 0.6, k)))
		distance_left -= used
		if distance_left <= 0.001:
			break
