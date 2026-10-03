class_name Projectile
extends Area2D
## 子彈：由 ProjectilePool 管理生命週期，請勿自行 queue_free。

signal expired(projectile: Projectile)

const REFLECT_SPEED_SCALE := 1.35
const REFLECT_DAMAGE_SCALE := 2.0
## 反彈子彈的衝擊力（重擊，打得一般敵人硬直）。
const REFLECT_IMPACT := 6.0

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


func _init() -> void:
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
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		_finish(false)


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
			Fx.impact(global_position, -velocity.normalized(), spec.color, 6)
			Sfx.play(&"hit", -6.0)
			if team == Combat.Team.PLAYER:
				EventBus.hit_confirmed.emit(global_position, hurtbox.health.is_dead)
		Hurtbox.Result.REFLECTED:
			_reflect(hurtbox.reflect_direction)
			return
		Hurtbox.Result.BLOCKED:
			# 被格擋：火花反彈、子彈直接消失（即使可貫穿）。
			Fx.impact(global_position, -velocity.normalized(), Palette.WHITE, 8)
			Sfx.play(&"block", -4.0)
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
		if not _hit_ids.has(id):
			_hit_ids[id] = true
			var result: int = body.call(&"hit_by_projectile", _make_damage())
			if result == Hurtbox.Result.DAMAGED:
				Fx.impact(global_position, -velocity.normalized(), spec.color, 6)
				if team == Combat.Team.PLAYER:
					EventBus.hit_confirmed.emit(global_position, false)
				if _pierce_left > 0:
					_pierce_left -= 1
					return
	Fx.impact(global_position, -velocity.normalized(), _color.darkened(0.2), 4)
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
	# HDR 發光核心 + 外暈 + 速度拖尾，在泛光下呈現霓虹子彈。
	var half := maxf(spec.length, spec.radius * 2.0) * 0.5
	var tail := clampf(spec.speed * 0.02, 0.0, 14.0)
	var glow := LightKit.glow(_color, 2.0)
	draw_line(Vector2(-half - tail, 0), Vector2(-half, 0), Color(_color, 0.35), spec.radius)
	draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), glow, spec.radius * 2.0)
	draw_circle(Vector2(-half + spec.radius, 0), spec.radius, glow)
	draw_circle(Vector2(half - spec.radius, 0), spec.radius, glow)
	draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), LightKit.glow(Palette.WHITE, 2.5), maxf(1.0, spec.radius * 0.8))
