extends Node
## 打擊感與特效服務（全域單例）：
##   - hitstop：頓幀，強化命中重量感
##   - shake / kick：鏡頭震動（trauma 模型）與方向性後座
##   - impact / burst / casing / dust：粒子（單節點粒子場，零節點生成）
##   - flash_light：短暫光源（固定數量光源池，循環使用）
##   - explosion：範圍傷害 + 視覺
## 所有效果在沒有綁定關卡時都會安全地不做事。

const HITSTOP_TIME_SCALE := 0.05
const LIGHT_POOL_SIZE := 10

var _container: Node2D
var _particles: ParticleField
var _lights: Array[PointLight2D] = []
var _light_tweens: Array[Tween] = []
var _next_light := 0
var _hitstop_until_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


## 由關卡呼叫：特效要放在哪個節點下。
func bind_container(container: Node2D) -> void:
	_container = container
	_particles = ParticleField.new()
	_particles.z_index = 5
	container.add_child(_particles)
	_lights.clear()
	_light_tweens.clear()
	for i in LIGHT_POOL_SIZE:
		var light := LightKit.create_point_light(Palette.WARNING, 64.0, 0.0, false, false)
		light.enabled = false
		container.add_child(light)
		_lights.append(light)
		_light_tweens.append(null)
	container.tree_exiting.connect(_on_container_exiting.bind(container), CONNECT_ONE_SHOT)


func _on_container_exiting(container: Node2D) -> void:
	if container != _container:
		return
	_container = null
	_particles = null
	_lights.clear()
	_light_tweens.clear()
	reset_time()


func _process(_delta: float) -> void:
	if _hitstop_until_msec > 0 and Time.get_ticks_msec() >= _hitstop_until_msec:
		reset_time()


# ---------------------------------------------------------------------------
# 時間與鏡頭
# ---------------------------------------------------------------------------

## 短暫凍結時間。重疊呼叫取最長者；暫停中不作用。
func hitstop(seconds: float) -> void:
	if seconds <= 0.0 or get_tree().paused:
		return
	_hitstop_until_msec = maxi(_hitstop_until_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = HITSTOP_TIME_SCALE


func reset_time() -> void:
	_hitstop_until_msec = 0
	Engine.time_scale = 1.0


## 震動強度約 1（輕微）~ 8（巨大爆炸）。
func shake(strength: float, duration: float) -> void:
	if strength > 0.0 and duration > 0.0:
		EventBus.screen_shake.emit(strength, duration)


## 方向性鏡頭後座（射擊時往反方向微推）。
func kick(direction: Vector2, amount: float) -> void:
	if amount > 0.0:
		EventBus.camera_kick.emit(direction.normalized() * amount)


# ---------------------------------------------------------------------------
# 粒子
# ---------------------------------------------------------------------------

## 命中火花：沿 normal 方向噴出的錐形火花（HDR 發光）。
func impact(position: Vector2, normal: Vector2, color: Color, amount := 6) -> void:
	if _particles == null:
		return
	var base := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	var hot := LightKit.glow(color, 2.2)
	for i in amount:
		var dir := base.rotated(randf_range(-0.7, 0.7))
		_particles.emit(position, dir * randf_range(90.0, 260.0), hot, randf_range(0.12, 0.28), 1.5, 200.0, 4.0)
	_particles.emit(position, Vector2.ZERO, LightKit.glow(color.lerp(Palette.WHITE, 0.6), 1.8), 0.05, 2.0, 0.0, 0.0, ParticleField.Shape.SQUARE)


## 全方向爆散（擊殺、受傷、裝甲剝落）。
func burst(position: Vector2, color: Color, amount := 8, speed := 120.0, lifetime := 0.35) -> void:
	if _particles == null:
		return
	var hot := LightKit.glow(color, 1.3)
	for i in clampi(amount, 1, 64):
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var shape := ParticleField.Shape.SQUARE if i % 3 == 0 else ParticleField.Shape.SPARK
		_particles.emit(position, dir * randf_range(speed * 0.35, speed), hot, lifetime * randf_range(0.6, 1.2),
				randf_range(1.5, 3.0), 320.0, 1.5, shape)


## 彈殼拋出（往射擊反方向上方）。
func casing(position: Vector2, facing: int) -> void:
	if _particles == null:
		return
	var velocity := Vector2(-facing * randf_range(40.0, 80.0), randf_range(-140.0, -90.0))
	_particles.emit(position, velocity, Color("e0b45a"), 0.5, 1.2, 600.0, 0.5, ParticleField.Shape.CASING)


## 揚塵（起跳、落地、衝刺、急停）。
func dust(position: Vector2, amount := 5, spread_x := 50.0) -> void:
	if _particles == null:
		return
	for i in amount:
		var velocity := Vector2(randf_range(-spread_x, spread_x), randf_range(-30.0, -5.0))
		_particles.emit(position + Vector2(randf_range(-3.0, 3.0), 0), velocity, Color(0.75, 0.82, 0.88, 0.45),
				randf_range(0.25, 0.45), randf_range(1.5, 2.5), -20.0, 3.0, ParticleField.Shape.DUST)


## 把一個短生命週期的節點（例如脫落的裝甲片）放進世界特效層。沒有綁定關卡時直接釋放。
func add_world_node(node: Node2D) -> bool:
	if _container == null:
		node.queue_free()
		return false
	_container.add_child.call_deferred(node)
	return true


## 雨滴落地的小水花。
func splash(position: Vector2) -> void:
	if _particles == null:
		return
	for i in 2:
		var velocity := Vector2(randf_range(-40.0, 40.0), randf_range(-70.0, -35.0))
		_particles.emit(position, velocity, Color(0.7, 0.8, 1.0, 0.55), randf_range(0.12, 0.22), 1.0, 500.0, 1.0, ParticleField.Shape.SPARK)


## 緩慢上升的蒸汽。
func steam(position: Vector2) -> void:
	if _particles == null:
		return
	var velocity := Vector2(randf_range(-6.0, 6.0), randf_range(-38.0, -22.0))
	_particles.emit(position, velocity, Color(0.75, 0.78, 0.9, 0.12), randf_range(1.2, 2.0), randf_range(4.0, 7.0), -6.0, 0.4, ParticleField.Shape.DUST)


# ---------------------------------------------------------------------------
# 光源與爆炸
# ---------------------------------------------------------------------------

## 短暫閃光（槍口、爆炸、終結技）。光源池循環使用，不會無限增加。
func flash_light(position: Vector2, color: Color, radius: float, energy: float, duration: float) -> void:
	if _lights.is_empty():
		return
	var index := _next_light
	_next_light = (_next_light + 1) % _lights.size()
	var light := _lights[index]
	if not is_instance_valid(light):
		return
	var previous := _light_tweens[index]
	if previous != null and previous.is_valid():
		previous.kill()
	light.global_position = position
	light.color = color
	light.texture_scale = maxf(0.05, radius * 2.0 / LightKit.TEXTURE_SIZE)
	light.energy = energy
	light.enabled = true
	var tween := light.create_tween()
	tween.tween_property(light, "energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.set.bind("enabled", false))
	_light_tweens[index] = tween


## 命中與擊殺的短暫點光：命中是小而冷的白青光，擊殺更大更暖。
func _on_hit_confirmed(world_position: Vector2, killed: bool) -> void:
	if killed:
		flash_light(world_position, Palette.WARNING, 90.0, 1.8, 0.22)
	else:
		flash_light(world_position, Palette.CYAN.lerp(Palette.WHITE, 0.5), 48.0, 0.9, 0.1)


## 範圍爆炸（延後一影格生效，避免在物理回呼中查詢空間）。damage = 0 時只有視覺。
func explosion(position: Vector2, radius: float, damage: int, team: Combat.Team, source_id: StringName, color := Palette.WARNING) -> void:
	if _container == null:
		return
	var blast := Explosion.new()
	blast.radius = radius
	blast.damage = damage
	blast.team = team
	blast.source_id = source_id
	blast.color = color
	blast.position = position
	_container.add_child.call_deferred(blast)
	burst(position, color, 18, radius * 7.0, 0.45)
	flash_light(position, color, radius * 4.0, 2.2, 0.35)
	# 整個環境光被閃亮一下：爆炸越大越亮。
	EventBus.ambient_flash_requested.emit(color.lerp(Palette.WHITE, 0.5), clampf(0.12 + radius / 160.0, 0.2, 0.5), 0.3)
	shake(clampf(radius / 6.0, 2.0, 8.0), 0.25)
	Sfx.play(&"explosion", -2.0, 0.1)
