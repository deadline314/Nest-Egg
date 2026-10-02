class_name Projectile
extends Area2D
## 子彈：由 ProjectilePool 管理生命週期，請勿自行 queue_free。

signal expired(projectile: Projectile)

var spec: ProjectileSpec
var team: Combat.Team = Combat.Team.PLAYER
var velocity := Vector2.ZERO
var active := false

var _life := 0.0
var _pierce_left := 0
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
	_shape.radius = maxf(1.0, spec.radius)
	collision_mask = Combat.hurtbox_mask_against(team)
	if not spec.passes_walls:
		collision_mask |= Layers.WORLD
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
	var id := hurtbox.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true
	var info := DamageInfo.create(spec.damage, team, spec.source_id, velocity.normalized() * spec.knockback)
	info.stagger = spec.stagger
	info.origin = global_position
	match hurtbox.receive(info):
		Hurtbox.Result.DAMAGED:
			Fx.impact(global_position, -velocity.normalized(), spec.color, 6)
			Sfx.play(&"hit", -6.0)
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


func _on_body_entered(_body: Node2D) -> void:
	if not active:
		return
	Fx.impact(global_position, -velocity.normalized(), spec.color.darkened(0.2), 4)
	_finish(true)


func _finish(impact: bool) -> void:
	if spec.explosion_radius > 0.0 and (impact or spec.explode_on_expire):
		Fx.explosion(global_position, spec.explosion_radius, spec.explosion_damage, team, spec.source_id, spec.color)
	deactivate()


func _draw() -> void:
	if spec == null:
		return
	# HDR 發光核心 + 外暈 + 速度拖尾，在泛光下呈現霓虹子彈。
	var half := maxf(spec.length, spec.radius * 2.0) * 0.5
	var tail := clampf(spec.speed * 0.02, 0.0, 14.0)
	var glow := LightKit.glow(spec.color, 2.0)
	draw_line(Vector2(-half - tail, 0), Vector2(-half, 0), Color(spec.color, 0.35), spec.radius)
	draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), glow, spec.radius * 2.0)
	draw_circle(Vector2(-half + spec.radius, 0), spec.radius, glow)
	draw_circle(Vector2(half - spec.radius, 0), spec.radius, glow)
	draw_line(Vector2(-half + spec.radius, 0), Vector2(half - spec.radius, 0), LightKit.glow(Palette.WHITE, 2.5), maxf(1.0, spec.radius * 0.8))
