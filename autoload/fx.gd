extends Node
## 打擊感與特效服務（全域單例）：
##   - hitstop：頓幀，強化命中重量感
##   - shake / kick：鏡頭震動（trauma 模型）與方向性後座
##   - impact / burst / casing / dust：粒子（單節點粒子場，零節點生成）
##   - flash_light：短暫光源（固定數量光源池，循環使用）
##   - explosion：範圍傷害 + 視覺
## 所有效果在沒有綁定關卡時都會安全地不做事。

## 全域頓幀的預算：單次上限、以及任一 1 秒內累計上限（秒），避免連續命中變成卡頓。
const HITSTOP_MAX := 0.2
const HITSTOP_WINDOW := 1.0
const HITSTOP_WINDOW_BUDGET := 0.4
## 凍結中參與者的微抖幅度（像素），避免看起來像當機。
const FREEZE_JITTER := 0.6
## 慢動作只允許這些情境；同一種慢動作之間有冷卻（秒）。
const SLOWMO_WHITELIST: PackedStringArray = ["boss_death", "finisher", "clear_out"]
const SLOWMO_COOLDOWN := 6.0
const LIGHT_POOL_SIZE := 10
const RING_POOL_SIZE := 5
## 特效克制係數：粒子數量、閃光與衝擊波的整體強度。想整體加強或減弱特效，只動這幾個數字（1.0＝原本設計的量）。
const PARTICLE_SCALE := 0.5
const FLARE_SCALE := 0.7
const SHOCK_SCALE := 0.55

var _container: Node2D
var _glow: ParticleField  # 疊加（發光）層
var _soft: ParticleField  # 一般混合層（煙、灰塵、碎片）
var _arcs: ArcField
var _rings: Array[ShockRing] = []
var _next_ring := 0
var _last_blast_msec := -1000
var _last_blast_position := Vector2.INF
var _lights: Array[PointLight2D] = []
var _light_tweens: Array[Tween] = []
var _next_light := 0
var _hitstop_log: Array[Vector2] = []  # [發生時間（毫秒）, 秒數]
var _slowmo_until_msec := 0
var _slowmo_ready_msec := 0
## 局部頓幀中的節點 → [結束時間（毫秒）, 原本的 process_mode]。
var _frozen: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


## 由關卡呼叫：特效要放在哪個節點下。
func bind_container(container: Node2D) -> void:
	_container = container
	_soft = ParticleField.new()
	_soft.additive = false
	_soft.z_index = 4
	container.add_child(_soft)
	_glow = ParticleField.new()
	_glow.additive = true
	_glow.z_index = 6
	container.add_child(_glow)
	_arcs = ArcField.new()
	_arcs.z_index = 6
	container.add_child(_arcs)
	_rings.clear()
	_next_ring = 0
	for i in RING_POOL_SIZE:
		var ring := ShockRing.new()
		container.add_child(ring)
		_rings.append(ring)
	_lights.clear()
	_light_tweens.clear()
	for i in LIGHT_POOL_SIZE:
		var light := LightKit.create_point_light(Palette.WARNING, 64.0, 0.0, false, false)
		light.enabled = false
		container.add_child(light)
		_lights.append(light)
		_light_tweens.append(null)
	container.tree_exiting.connect(_on_container_exiting.bind(container), CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	RigDebris.clear_pool()


func _on_container_exiting(container: Node2D) -> void:
	if container != _container:
		return
	_container = null
	_glow = null
	_soft = null
	_arcs = null
	_rings.clear()
	_lights.clear()
	_light_tweens.clear()
	reset_time()
	_clear_frozen()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _slowmo_until_msec > 0 and now >= _slowmo_until_msec:
		reset_time()
	if not _frozen.is_empty():
		_release_frozen(now)
		_jitter_frozen()


# ---------------------------------------------------------------------------
# 時間與鏡頭
# ---------------------------------------------------------------------------

## 全域頓幀：凍結玩家、敵人、載具與子彈，粒子與介面照常動。重疊取最長者；單次與 1 秒內累計都有上限；暫停中不作用。
func hitstop(seconds: float) -> void:
	if seconds <= 0.0 or get_tree().paused:
		return
	var granted := minf(minf(seconds, HITSTOP_MAX), hitstop_budget_left())
	if granted <= 0.0:
		return
	var now := Time.get_ticks_msec()
	_hitstop_log.append(Vector2(now, granted))
	var nodes: Array = []
	for group in [&"player", &"enemies", &"vehicles"]:
		nodes.append_array(get_tree().get_nodes_in_group(group))
	if ProjectilePool.container() != null:
		nodes.append(ProjectilePool.container())
	freeze.call_deferred(nodes, granted)  # 常在物理回呼（命中）裡觸發，停用碰撞節點要延後


## 這一秒內還能用的全域頓幀秒數。
func hitstop_budget_left() -> float:
	var now := Time.get_ticks_msec()
	var used := 0.0
	for i in range(_hitstop_log.size() - 1, -1, -1):
		if float(now) - _hitstop_log[i].x > HITSTOP_WINDOW * 1000.0:
			_hitstop_log.remove_at(i)
		else:
			used += _hitstop_log[i].y
	return maxf(0.0, HITSTOP_WINDOW_BUDGET - used)


## 慢動作：只有白名單情境、且過了冷卻才會播；回傳是否真的播放。
func slowmo(reason: String, scale: float, seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	if not SLOWMO_WHITELIST.has(reason) or seconds <= 0.0 or now < _slowmo_ready_msec or get_tree().paused:
		return false
	_slowmo_until_msec = now + int(seconds * 1000.0)  # seconds 是實際時間
	_slowmo_ready_msec = now + int(SLOWMO_COOLDOWN * 1000.0)
	Engine.time_scale = clampf(scale, 0.1, 1.0)
	return true


func is_slowmo() -> bool:
	return _slowmo_until_msec > 0


## 診斷：目前存活的粒子數（兩層粒子場加總）。
func particle_count() -> int:
	return (_glow.alive_count() if _glow != null else 0) + (_soft.alive_count() if _soft != null else 0)


## 診斷：目前被凍結的節點數。
func frozen_count() -> int:
	return _frozen.size()


func reset_time() -> void:
	_slowmo_until_msec = 0
	Engine.time_scale = 1.0


## 局部頓幀：只凍結指定的節點（攻擊方與被打方），其他敵人、粒子與介面照常動。重疊時取較長者，不相加。
func freeze(nodes: Array, seconds: float) -> void:
	if seconds <= 0.0 or get_tree().paused:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	for target: Variant in nodes:
		if target == null or not is_instance_valid(target):
			continue
		var node: Node = target
		var entry: Variant = _frozen.get(node)
		if entry == null:
			_frozen[node] = [until, node.process_mode]
			node.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			entry[0] = maxi(int(entry[0]), until)


func _release_frozen(now: int) -> void:
	for key: Variant in _frozen.keys():
		var entry: Array = _frozen[key]
		if is_instance_valid(key):
			if now < int(entry[0]):
				continue
			(key as Node).process_mode = entry[1]
			if entry.size() > 2 and key is Node2D:
				(key as Node2D).position = entry[2]
		_frozen.erase(key)


## 凍結中的 2D 節點每影格在原位附近微抖（只在有畫面的情況下；放開時回到原位）。
func _jitter_frozen() -> void:
	var side := 1.0 if Engine.get_process_frames() % 2 == 0 else -1.0
	for key: Variant in _frozen.keys():
		if not is_instance_valid(key):
			continue
		var node := key as Node2D
		if node == null or node is Camera2D:
			continue
		var entry: Array = _frozen[key]
		if entry.size() < 3:
			entry.append(node.position)
		node.position = (entry[2] as Vector2) + Vector2(side * FREEZE_JITTER, 0.0)


func _clear_frozen() -> void:
	_release_frozen(1 << 60)


## 鏡頭震動的底層：峰值像素與秒數。其他程式一律走 Feel。
func shake(px: float, duration: float, direction := Vector2.ZERO, origin := Vector2.INF) -> void:
	if px > 0.0 and duration > 0.0:
		EventBus.screen_shake.emit(px, duration, direction, origin)


## 方向性鏡頭後座（射擊時往反方向微推）。
## 鏡頭後座：畫面震動調到 0 時仍保留約一半。
func kick(direction: Vector2, amount: float) -> void:
	if amount > 0.0:
		EventBus.camera_kick.emit(direction.normalized() * amount * (0.5 + 0.5 * Settings.get_feel_scale("shake")))


# ---------------------------------------------------------------------------
# 粒子（VFX 2.0）：兩層粒子場（疊加發光層、一般混合層）、衝擊波環池、電弧；全部固定容量，零節點生成。
# 高階特效（sparks / embers / smoke / fire / shards / flare / shock / arc / lightning）可以單獨呼叫，也由 burst、impact、explosion 與敵人專屬特效組合使用。
# ---------------------------------------------------------------------------

## 粒子數量：基準倍率乘上設定的粒子強度；設定為 0 時完全不產生，其他情況至少 1 顆。
func _particle_count(amount: int) -> int:
	var scale := Settings.get_feel_scale("particles")
	return 0 if scale <= 0.0 else maxi(1, roundi(float(amount) * PARTICLE_SCALE * scale))


## 火花：沿速度拉長的亮線，頭是近乎白熱的亮色、尾巴漸成顏色再淡出；有阻力與重力。dir＝主要方向（ZERO＝四面八方），spread＝散開角度（弧度）。
func sparks(position: Vector2, color: Color, amount := 10, speed := 220.0, life := 0.4, dir := Vector2.ZERO, spread := TAU, gravity := 520.0) -> void:
	amount = _particle_count(amount)
	if amount <= 0:
		return
	if _glow == null:
		return
	var base := dir.angle() if dir != Vector2.ZERO else 0.0
	var half := spread * 0.5 if dir != Vector2.ZERO else PI
	for i in clampi(amount, 1, 80):
		var angle := base + randf_range(-half, half)
		var v := Vector2.RIGHT.rotated(angle) * speed * randf_range(0.3, 1.0)
		var l := life * randf_range(0.55, 1.2)
		var hot := Color(minf(2.0, color.r * 1.3 + 0.35), minf(2.0, color.g * 1.3 + 0.3), minf(2.0, color.b * 1.3 + 0.25), 1.0)
		_glow.emit_ex(position, v, l, VfxAtlas.Cell.STREAK, randf_range(2.2, 4.2), 1.0, hot, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 0.0),
				gravity, 2.2, 0.0, 0.0, 0.045 + randf() * 0.02)


## 餘燼：小亮點，慢慢往上飄並閃爍，顏色由亮橘漸成暗紅。
func embers(position: Vector2, color: Color, amount := 8, speed := 70.0, life := 1.0, spread := 18.0) -> void:
	amount = _particle_count(amount)
	if amount <= 0:
		return
	if _glow == null:
		return
	for i in clampi(amount, 1, 60):
		var v := Vector2(randf_range(-speed, speed) * 0.6, randf_range(-speed, -speed * 0.2))
		var l := life * randf_range(0.6, 1.3)
		_glow.emit_ex(position + Vector2(randf_range(-spread, spread), randf_range(-spread, spread * 0.5)), v, l, VfxAtlas.Cell.EMBER,
				randf_range(4.0, 8.0), 1.5, Color(color.r * 2.0, color.g * 1.6, color.b * 1.2, 1.0), Color(color.r * 0.9, color.g * 0.25, color.b * 0.1, 0.0),
				-14.0, 0.9, 0.0, 0.0, 0.0, 0.6)


## 煙：柔邊的一團團，由深灰漸漸變大、變淡，緩緩上升。tint＝煙的基本色（預設暗灰藍）。
func smoke(position: Vector2, amount := 6, spread := 14.0, life := 1.1, size := 18.0, tint := Color(0.2, 0.22, 0.28, 0.55)) -> void:
	amount = maxi(1, roundi(float(amount) * PARTICLE_SCALE))
	if _soft == null:
		return
	for i in clampi(amount, 1, 40):
		var v := Vector2(randf_range(-18.0, 18.0), randf_range(-46.0, -14.0))
		_soft.emit_ex(position + Vector2(randf_range(-spread, spread), randf_range(-spread * 0.4, spread * 0.4)), v, life * randf_range(0.7, 1.3),
				VfxAtlas.Cell.PUFF_A if randf() < 0.5 else VfxAtlas.Cell.PUFF_B, size * 0.5, size * randf_range(1.6, 2.4),
				tint, Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.75, 0.0), -10.0, 1.1, randf() * TAU, randf_range(-0.8, 0.8))


## 火球：發光的團塊向外膨脹，顏色由近白的亮黃漸成橘、深紅再消失；（再疊上 smoke 就是爆炸的雲）。
func fire(position: Vector2, radius: float, color: Color, amount := 8, life := 0.55) -> void:
	amount = maxi(1, roundi(float(amount) * PARTICLE_SCALE))
	if _glow == null:
		return
	for i in clampi(amount, 1, 30):
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var v := dir * radius * randf_range(0.8, 3.2)
		var l := life * randf_range(0.65, 1.2)
		_glow.emit_ex(position + dir * radius * randf() * 0.3, v, l, VfxAtlas.Cell.PUFF_A if randf() < 0.5 else VfxAtlas.Cell.PUFF_B,
				radius * 0.8, radius * randf_range(1.5, 2.3),
				Color(minf(1.9, color.r * 1.2 + 0.6), minf(1.7, color.g * 1.2 + 0.4), minf(1.5, color.b * 1.2 + 0.2), 0.55),
				Color(color.r * 0.7, color.g * 0.2, color.b * 0.1, 0.0), -30.0, 3.0, randf() * TAU, randf_range(-2.0, 2.0))


## 碎片：不規則的金屬碎塊，帶重力與自轉，落下時漸漸變暗。
func shards(position: Vector2, color: Color, amount := 6, speed := 200.0, life := 0.9, size := 7.0) -> void:
	amount = maxi(1, roundi(float(amount) * PARTICLE_SCALE))
	if _soft == null:
		return
	for i in clampi(amount, 1, 30):
		var v := Vector2.RIGHT.rotated(randf() * TAU) * speed * randf_range(0.3, 1.0) + Vector2(0, -speed * 0.3)
		var c := Color(color.r * 0.55 + 0.1, color.g * 0.55 + 0.1, color.b * 0.55 + 0.12, 1.0)
		_soft.emit_ex(position, v, life * randf_range(0.7, 1.3), VfxAtlas.Cell.SHARD, size * randf_range(0.6, 1.3), size * 0.5, c,
				Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 0.0), 620.0, 0.9, randf() * TAU, randf_range(-14.0, 14.0))


## 星芒與光暈的閃光：一瞬間的十字星芒加一圈光暈（槍口、擊殺、鎖定）。
func flare(position: Vector2, color: Color, size := 40.0, life := 0.14) -> void:
	size *= FLARE_SCALE
	if _glow == null:
		return
	_glow.emit_ex(position, Vector2.ZERO, life, VfxAtlas.Cell.FLARE, size * 0.6, size, Color(minf(1.9, color.r * 1.3 + 0.4), minf(1.9, color.g * 1.3 + 0.35), minf(1.9, color.b * 1.3 + 0.3), 0.85),
			Color(color.r, color.g, color.b, 0.0), 0.0, 0.0, randf() * 0.4)
	_glow.emit_ex(position, Vector2.ZERO, life * 1.4, VfxAtlas.Cell.GLOW, size * 0.7, size * 1.6, Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.45),
			Color(color.r, color.g, color.b, 0.0), 0.0, 0.0)


## 衝擊波：環形折射加亮邊（需要畫面可渲染；沒有綁定關卡時不做事）。
func shock(position: Vector2, radius := 60.0, strength := 0.04, color := Palette.WARNING, time := 0.5) -> void:
	strength *= SHOCK_SCALE
	radius *= 0.85
	if _rings.is_empty():
		return
	var ring := _rings[_next_ring]
	_next_ring = (_next_ring + 1) % _rings.size()
	if is_instance_valid(ring):
		ring.play(position, radius, strength, color, time)


## 電弧：從一點到另一點的閃電（可帶分支）。
func arc(from: Vector2, to: Vector2, color := Palette.CYAN, life := 0.18, width := 1.6, jag := 0.14, branches := 1) -> void:
	if _arcs != null:
		_arcs.emit_arc(from, to, color, life, width, jag, branches)


## 電弧簇：從一點向四周打出 count 道短閃電（敵人被電、機械爆炸）。
func lightning(position: Vector2, color := Palette.CYAN, count := 5, reach := 36.0, life := 0.2) -> void:
	count = maxi(1, roundi(float(count) * PARTICLE_SCALE))
	for i in count:
		var angle := randf() * TAU
		arc(position, position + Vector2.RIGHT.rotated(angle) * reach * randf_range(0.5, 1.2), color, life * randf_range(0.7, 1.2), 1.4, 0.2, 1)


## 命中火花：沿 normal 方向噴出的錐形火花（HDR 發光），加一個小星芒與光暈。
func impact(position: Vector2, normal: Vector2, color: Color, amount := 6) -> void:
	if _glow == null:
		return
	var base := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	sparks(position, color, amount + 2, 300.0, 0.3, base, 1.5, 420.0)
	flare(position, color, 12.0 + float(amount), 0.07)


## 全方向爆散（擊殺、受傷、裝甲剝落）：火花、一圈光暈，量大時加星芒。
func burst(position: Vector2, color: Color, amount := 8, speed := 120.0, lifetime := 0.35) -> void:
	if _glow == null:
		return
	sparks(position, color, amount, speed * 1.4, lifetime * 1.2)
	_glow.emit_ex(position, Vector2.ZERO, lifetime * 0.5, VfxAtlas.Cell.GLOW, 6.0, 12.0 + float(amount) * 1.1, Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.3),
			Color(color.r, color.g, color.b, 0.0), 0.0, 0.0)
	if amount >= 12:
		flare(position, color, 20.0 + float(amount), 0.1)


## 彈殼拋出（往射擊反方向上方）。
func casing(position: Vector2, facing: int) -> void:
	if _soft == null:
		return
	var velocity := Vector2(-facing * randf_range(40.0, 80.0), randf_range(-140.0, -90.0))
	_soft.emit_ex(position, velocity, 0.55, VfxAtlas.Cell.SHARD, 4.5, 4.5, Color("e8c060"), Color(0.9, 0.7, 0.3, 0.0), 600.0, 0.5, randf() * TAU, randf_range(-18.0, 18.0))


## 揚塵（起跳、落地、衝刺、急停）：柔邊的灰塵團，往兩側擴散。
func dust(position: Vector2, amount := 5, spread_x := 50.0) -> void:
	if _soft == null:
		return
	for i in amount:
		var velocity := Vector2(randf_range(-spread_x, spread_x), randf_range(-26.0, -4.0))
		_soft.emit_ex(position + Vector2(randf_range(-3.0, 3.0), 0), velocity, randf_range(0.35, 0.6),
				VfxAtlas.Cell.PUFF_A if randf() < 0.5 else VfxAtlas.Cell.PUFF_B, randf_range(5.0, 8.0), randf_range(14.0, 22.0),
				Color(0.62, 0.68, 0.76, 0.34), Color(0.5, 0.56, 0.64, 0.0), -8.0, 3.2, randf() * TAU, randf_range(-1.5, 1.5))


## 把一個短生命週期的節點（例如脫落的裝甲片）放進世界特效層。沒有綁定關卡時直接釋放。
func add_world_node(node: Node2D) -> bool:
	if _container == null:
		node.queue_free()
		return false
	_container.add_child.call_deferred(node)
	return true


## 雨滴落地的小水花。
func splash(position: Vector2) -> void:
	if _glow == null:
		return
	for i in 2:
		var velocity := Vector2(randf_range(-40.0, 40.0), randf_range(-70.0, -35.0))
		_glow.emit_ex(position, velocity, randf_range(0.14, 0.24), VfxAtlas.Cell.STREAK, 3.0, 1.0, Color(0.8, 0.9, 1.3, 0.55), Color(0.7, 0.8, 1.0, 0.0), 500.0, 1.0, 0.0, 0.0, 0.05)


## 緩慢上升的蒸汽。
func steam(position: Vector2) -> void:
	if _soft == null:
		return
	var velocity := Vector2(randf_range(-6.0, 6.0), randf_range(-38.0, -22.0))
	_soft.emit_ex(position, velocity, randf_range(1.2, 2.0), VfxAtlas.Cell.PUFF_B, randf_range(8.0, 12.0), randf_range(22.0, 34.0),
			Color(0.78, 0.82, 0.92, 0.2), Color(0.75, 0.78, 0.9, 0.0), -6.0, 0.4, randf() * TAU, randf_range(-0.4, 0.4))


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
		flash_light(world_position, Palette.WARNING, 80.0, 1.1, 0.2)
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
	_explosion_visual(position, radius, color)
	flash_light(position, color, radius * 4.0, 2.2, 0.35)
	# 整個環境光被閃亮一下：爆炸越大越亮。
	EventBus.ambient_flash_requested.emit(color.lerp(Palette.WHITE, 0.5), clampf(0.12 + radius / 160.0, 0.2, 0.5), 0.3)
	Feel.shake_strength(clampf(radius / 6.0, 2.0, 8.0), 0.25)
	Sfx.play(&"explosion", -2.0, 0.1)


## 爆炸的視覺：核心閃光、火球、煙、火花、餘燼、碎片、衝擊波（半徑越大越誇張）。
func _explosion_visual(position: Vector2, radius: float, color: Color) -> void:
	if _glow == null:
		return
	# 同一處同時間的第二次爆炸（玩家陣營與敵人陣營各炸一次）只畫一次。
	var now := Time.get_ticks_msec()
	if now - _last_blast_msec < 60 and position.distance_to(_last_blast_position) < 4.0:
		return
	_last_blast_msec = now
	_last_blast_position = position
	var r := maxf(8.0, radius)
	_glow.emit_ex(position, Vector2.ZERO, 0.12, VfxAtlas.Cell.GLOW, r * 1.2, r * 2.4, Color(1.8, 1.5, 1.1, 0.6), Color(color.r * 1.4, color.g * 1.1, color.b, 0.0))
	flare(position, color, r * 2.2, 0.14)
	fire(position, r * 0.45, color, 7, 0.45)
	smoke(position + Vector2(0, -r * 0.2), 6, r * 0.5, 1.2, r * 0.7)
	sparks(position, color, 14, r * 8.0, 0.4)
	embers(position, color, 6, r * 1.0, 0.9, r * 0.4)
	shards(position, color, 5, r * 4.5, 0.9, maxf(5.0, r * 0.16))
	shock(position, r * 3.2, 0.05, color.lerp(Palette.WHITE, 0.3), 0.55)

