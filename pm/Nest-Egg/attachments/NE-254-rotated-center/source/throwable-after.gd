class_name Throwable
extends CharacterBody2D
## 可撿起來丟的場景物件（NE-254）：靜置 → 被拿著 → 飛行 → 落地（或碎掉、爆炸）。外觀、重量、傷害與爆炸都來自 ThrowableData。
## 飛行時每個物理影格先沿路徑掃一次敵人的受擊框，再用 move_and_collide 撞地形（兩者都是掃掠，不會穿牆或卡進地形）；
## 單向平台只在往下掉時接住。油桶：丟出後撞到東西就爆；放在地上被打壞時先燒 fuse 秒（閃紅光、地上畫出爆炸範圍）再爆。
## 不擋玩家與敵人的路；玩家的子彈、近戰與爆炸打得到它（受擊框屬於敵方陣營，所以敵人的子彈不會誤觸）。原點在底邊中點。

signal finished(throwable: Throwable)

enum State { REST, HELD, FLYING, GONE }

const GROUP := &"throwables"
## 落地時速度低於這個就停下來躺著；碎掉需要的撞擊速度。
const SETTLE_SPEED := 60.0
const BREAK_SPEED := 160.0
const GROUND_FRICTION := 900.0
const MAX_FALL_SPEED := 700.0
const MAX_FLIGHT_TIME := 4.0
const PROMPT_RADIUS := 26.0

var data: ThrowableData
var state: State = State.REST
## 誰丟的（陣營決定打得到誰）；靜置時是 ENEMY 陣營的受擊框，讓玩家打得到。
var team: Combat.Team = Combat.Team.PLAYER
var health: HealthComponent
var hurtbox: Hurtbox

var _fuse_left := -1.0
var _flight_time := 0.0
var _spin := 0.0
var _hit_ids: Dictionary[int, bool] = {}
var _sweep := PhysicsShapeQueryParameters2D.new()
var _sweep_shape := RectangleShape2D.new()
var _terrain_collision := KinematicCollision2D.new()
var _prompt: WorldPrompt
var _flash := 0.0
var _body_art: Sprite2D
var _body_id: StringName


func configure(p_data: ThrowableData) -> void:
	data = p_data


func _ready() -> void:
	if data == null:
		push_error("[Throwable] 未指定 ThrowableData，已移除。")
		queue_free()
		return
	for problem in data.validate():
		push_error("[Throwable] %s" % problem)
	collision_layer = 0
	collision_mask = Layers.SOLID
	var shape := RectangleShape2D.new()
	shape.size = data.size
	var node := CollisionShape2D.new()
	node.shape = shape
	node.position = Vector2(0, -data.size.y * 0.5)
	add_child(node)
	_sweep_shape.size = data.size
	_sweep.shape = _sweep_shape
	_sweep.collide_with_areas = true
	_sweep.collide_with_bodies = false
	if data.max_health > 0:
		health = HealthComponent.new()
		add_child(health)
		health.setup(data.max_health, 0.0)
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_destroyed)
		hurtbox = Hurtbox.new()
		add_child(hurtbox)
		hurtbox.setup(Combat.Team.ENEMY, health, data.size + Vector2(4, 4), Vector2(0, -data.size.y * 0.5))
		hurtbox.hit_material = &"metal" if data.look in [ThrowableData.Look.BARREL, ThrowableData.Look.PIPE] else &"wood"
	if not data.hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = data.hint
		_prompt.radius = PROMPT_RADIUS
		_prompt.offset = Vector2(0, -data.size.y - 10.0)
		_prompt.reach_check = _pickup_prompt_reachable
		add_child(_prompt)
	add_to_group(GROUP)
	LightKit.mark_emissive(self)
	_body_id = FixtureArt.throwable_body(data.look)
	if _body_id != &"":
		_body_art = FixtureArt.attach(self, _body_id, Vector2(-data.size.x * 0.5, -data.size.y), data.size)


func can_pick_up() -> bool:
	return state == State.REST and _fuse_left < 0.0 and is_on_floor()


## Offer exactly the object that the real interact handler would pick.
func _pickup_prompt_reachable() -> bool:
	if not can_pick_up():
		return false
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.state != Player.State.NORMAL or player.carry == null or player.carry.phase not in [PlayerCarry.Phase.NONE, PlayerCarry.Phase.THROWING]:
		return false
	var offset := global_position - player.global_position
	if absf(offset.x) > PlayerCarry.PICK_RANGE_X + data.size.x * 0.5 or absf(offset.y) > PlayerCarry.PICK_RANGE_Y:
		return false
	return player.carry.nearest_pickable() == self


func world_center() -> Vector2:
	return center_at(global_transform)


## The collision rectangle is centered above the bottom-origin in local space.
func center_at(pose: Transform2D) -> Vector2:
	return pose * Vector2(0, -data.size.y * 0.5)


# ---------------------------------------------------------------------------
# 拿著與丟出（由 PlayerCarry 呼叫）
# ---------------------------------------------------------------------------

func pick_up() -> void:
	state = State.HELD
	velocity = Vector2.ZERO
	_set_targetable(false)
	if _prompt != null:
		_prompt.visible = false


## 拿著時跟著玩家的手（世界座標，底邊中點）。
func hold_at(point: Vector2) -> void:
	global_position = point


## 放下：輕輕落在 point（玩家腳前），回到靜置。
func put_down(point: Vector2) -> void:
	# Reuse the full body and terrain rules instead of teleporting into nearby walls.
	move_and_collide(point - global_position)
	velocity = Vector2.ZERO
	_to_rest()


## 丟出：從 origin 以 launch_velocity 飛出，陣營決定打得到誰。
func launch(origin: Vector2, launch_velocity: Vector2, p_team: Combat.Team) -> void:
	global_position = origin
	velocity = launch_velocity
	team = p_team
	state = State.FLYING
	_flight_time = 0.0
	_spin = signf(launch_velocity.x) * (6.0 if data.look != ThrowableData.Look.BARREL else 3.0)
	_hit_ids.clear()
	_set_targetable(false)
	Sfx.play(&"melee_swing_heavy" if data.throw_speed < 360.0 else &"melee_swing", -6.0)


# ---------------------------------------------------------------------------
# 物理
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.GONE or state == State.HELD:
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if _fuse_left >= 0.0:
		_tick_fuse(delta)
		if state == State.GONE:
			return
	if state == State.FLYING:
		_fly(delta)
	else:
		_rest(delta)
	queue_redraw()


func _rest(delta: float) -> void:
	velocity.y = minf(velocity.y + data.gravity * delta, MAX_FALL_SPEED)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
	move_and_slide()


func _fly(delta: float) -> void:
	_flight_time += delta
	velocity.y = minf(velocity.y + data.gravity * delta, MAX_FALL_SPEED)
	rotation += _spin * delta
	var motion := velocity * delta
	# A hurtbox beyond the first wall is outside this frame's reachable path.
	# Reuse the body's actual terrain test so one-way platforms keep their rules.
	var reachable := _terrain_collision.get_travel() if test_move(global_transform, motion, _terrain_collision) else motion
	var target := _sweep_targets(reachable)
	if not target.is_empty():
		global_position += reachable * float(target["fraction"])
		_strike(target["hurtbox"])
		return
	var collision := move_and_collide(motion)
	if collision != null:
		_bounce(collision)
	elif _flight_time > MAX_FLIGHT_TIME:
		_to_rest()


## 沿這一步的路徑找第一個打得到的受擊框（掃掠，不會穿過）。回傳 {fraction, hurtbox} 或空字典。
func _sweep_targets(motion: Vector2) -> Dictionary:
	_sweep.collision_mask = Combat.hurtbox_mask_against(team)
	var pose := global_transform
	pose.origin = center_at(pose)
	_sweep.transform = pose
	_sweep.motion = motion
	var space := get_world_2d().direct_space_state
	var fractions := space.cast_motion(_sweep)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return {}
	pose.origin += motion * fractions[1]
	_sweep.transform = pose
	_sweep.motion = Vector2.ZERO
	for hit in space.intersect_shape(_sweep, 4):
		var box := hit["collider"] as Hurtbox
		if box == null or box.team == team or not box.can_receive():
			continue
		var id := box.health.get_instance_id() if box.health != null else box.get_instance_id()
		if _hit_ids.has(id) or (hurtbox != null and box.root() == hurtbox):
			continue
		return {"fraction": fractions[1], "hurtbox": box}
	return {}


## 打中敵人（或丟回來時打中玩家）：傷害、擊退、衝擊；之後彈開往下掉。油桶直接爆炸。
func _strike(box: Hurtbox) -> void:
	var root := box.root()
	_hit_ids[root.health.get_instance_id() if root.health != null else root.get_instance_id()] = true
	if data.is_explosive():
		_explode()
		return
	var direction := velocity.normalized()
	var info := DamageInfo.create(data.damage, team, data.source_id, Vector2(signf(direction.x) * data.knockback, -data.knockback * 0.35))
	info.impact = data.impact
	info.origin = world_center()
	var part := root.resolve_along(world_center(), velocity)
	var result := part.receive(info)
	var material := part.material_id()
	HitFeedback.play(material, world_center(), -direction, data.color, {"weak": info.weak_hit, "ricochet": result == Hurtbox.Result.BLOCKED})
	if result == Hurtbox.Result.DAMAGED and team == Combat.Team.PLAYER:
		EventBus.hit_confirmed.emit(world_center(), part.health.is_dead)
		EventBus.hit_marker.emit(&"kill" if part.health.is_dead else (&"weak" if info.weak_hit else &"hit"))
	Feel.shake_strength(2.0 + data.impact * 0.3, 0.12)
	if data.breaks_on_impact:
		_break()
		return
	velocity = Vector2(-velocity.x * 0.25, -60.0)
	_spin *= -0.5


func _bounce(collision: KinematicCollision2D) -> void:
	var normal := collision.get_normal()
	var speed := velocity.length()
	if data.is_explosive():
		_explode()
		return
	if data.breaks_on_impact and speed > BREAK_SPEED:
		_break()
		return
	HitFeedback.play(&"concrete", world_center(), normal, data.color.darkened(0.2))
	Sfx.play(&"mat_metal" if data.look in [ThrowableData.Look.BARREL, ThrowableData.Look.PIPE] else &"mat_wood", -10.0)
	velocity = velocity.bounce(normal) * data.bounce
	if normal.y < -0.6 and velocity.length() < SETTLE_SPEED:
		_to_rest()


func _to_rest() -> void:
	state = State.REST
	rotation = 0.0  # 平躺落地（判定框左右對稱，轉正不會穿地；鐵管不會斜插在地上）
	team = Combat.Team.PLAYER
	velocity.y = maxf(velocity.y, 0.0)
	_spin = 0.0
	_set_targetable(true)
	if _prompt != null:
		_prompt.visible = true


func _set_targetable(on: bool) -> void:
	if hurtbox != null:
		hurtbox.enabled = on


# ---------------------------------------------------------------------------
# 受損、碎掉、爆炸
# ---------------------------------------------------------------------------

func _on_damaged(_info: DamageInfo) -> void:
	_flash = 0.12
	FixtureArt.damage(_body_art, _body_id, health.ratio(), data.size)
	Fx.impact(world_center(), Vector2.UP, data.color.lightened(0.3), 4)
	queue_redraw()


## 被打壞：會爆炸的先點燃引信（預兆），其他直接碎掉。
func _on_destroyed(_info: DamageInfo) -> void:
	if state == State.GONE:
		return
	if data.is_explosive():
		if _fuse_left < 0.0:
			_fuse_left = data.fuse
			Sfx.play(&"ignite", -4.0)
	else:
		_break.call_deferred()


func _tick_fuse(delta: float) -> void:
	_fuse_left -= delta
	if int(_fuse_left * 20.0) % 2 == 0:
		Fx.sparks(global_position + Vector2(0, -data.size.y), Palette.WARNING, 1, 80.0, 0.2, Vector2.UP, 0.8, 0.0)
	if _fuse_left <= 0.0:
		_explode()


func is_fuse_lit() -> bool:
	return _fuse_left >= 0.0


func _break() -> void:
	if state == State.GONE:
		return
	Fx.burst(world_center(), data.color, 10, 160.0, 0.4)
	Fx.dust(global_position, 4, 50.0)
	Sfx.play(&"crate_break", -6.0)
	FixtureArt.rubble(self, _body_id, data.size)
	_finish()


## 爆炸：同時傷害敵人與玩家（油桶不認人），也會引爆旁邊的油桶（打壞它們，各自燒引信）。
func _explode() -> void:
	if state == State.GONE:
		return
	var center := world_center()
	FixtureArt.rubble(self, _body_id, data.size)
	Fx.explosion(center, data.explosion_radius, data.explosion_damage, Combat.Team.PLAYER, data.source_id, Palette.WARNING)
	Fx.explosion(center, data.explosion_radius, data.explosion_damage, Combat.Team.ENEMY, data.source_id, Palette.WARNING)
	_finish()


func _finish() -> void:
	state = State.GONE
	_fuse_left = -1.0
	_set_targetable(false)
	set_physics_process(false)
	visible = false
	collision_mask = 0
	finished.emit(self)
	queue_free()


# ---------------------------------------------------------------------------
# 外觀（程式繪製；暗處也看得出「可以撿」與「會爆」）
# ---------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return
	var rect := Rect2(Vector2(-data.size.x * 0.5, -data.size.y), data.size)
	match data.look:
		ThrowableData.Look.CRATE:
			if _body_art == null:
				draw_rect(rect, data.color.darkened(0.35))
				draw_rect(rect.grow(-2.0), data.color)
				draw_line(rect.position + Vector2(2, 2), rect.end - Vector2(2, 2), data.color.darkened(0.5), 1.5)
		ThrowableData.Look.BARREL:
			if _body_art == null:
				var body := data.color
				draw_rect(rect, body.darkened(0.3))
				draw_rect(Rect2(rect.position + Vector2(1, 0), Vector2(rect.size.x * 0.35, rect.size.y)), body)
				for fraction in [0.22, 0.78]:
					var y: float = rect.position.y + rect.size.y * fraction
					draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), body.darkened(0.55), 1.5)
				var c := rect.get_center()
				var s := minf(rect.size.x, rect.size.y) * 0.24
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.8), c + Vector2(-s, s * 0.8)]), Palette.WARNING.darkened(0.1))
			# 頂端警示燈：平常微亮，點燃引信後快速閃。
			draw_rect(Rect2(Vector2(-1.5, rect.position.y - 2.0), Vector2(3, 2)), LightKit.glow(Palette.DANGER, fuse_light_energy()))
		ThrowableData.Look.PIPE:
			draw_rect(rect, data.color.darkened(0.25))
			draw_line(Vector2(rect.position.x, rect.position.y + 1.0), Vector2(rect.end.x, rect.position.y + 1.0), data.color.lightened(0.35), 1.0)
		ThrowableData.Look.CHUNK:
			draw_colored_polygon(PackedVector2Array([rect.position + Vector2(1, 2), Vector2(rect.end.x - 2, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), data.color)
	# 可撿的提示：上緣一條細亮線（與可破壞物的語言一致）。
	if state == State.REST:
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(Palette.TERRAIN_TOP, 0.8), 1.0)
	if _flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.5))
	# 引信燒著：地上畫出爆炸範圍（紅圈越縮越緊），看得到會炸到哪。
	if _fuse_left >= 0.0:
		var t := 1.0 - clampf(_fuse_left / maxf(0.01, data.fuse), 0.0, 1.0)
		var at := Vector2(0, -data.size.y * 0.5)
		draw_arc(at, data.explosion_radius, 0.0, TAU, 40, Color(LightKit.glow(Palette.DANGER, 1.6), 0.35 + 0.5 * t), 1.5)
		draw_arc(at, data.explosion_radius * (1.0 - t), 0.0, TAU, 32, Color(LightKit.glow(Palette.DANGER, 2.2), 0.6), 1.0)


## Two smooth pulses per second; reduced flashes retains a steady warning.
func fuse_light_energy() -> float:
	if _fuse_left < 0.0:
		return 1.4
	if Settings.get_reduce_flashes():
		return 2.0
	return 2.0 + 0.6 * sin((data.fuse - _fuse_left) * TAU * 2.0)
