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
## 半徑小於這個值的爆炸用小爆炸音效（頭目死亡時連環的小爆、油桶以外的小型爆炸）。
const SMALL_EXPLOSION_RADIUS := 40.0
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
## 爆炸的時間（秒）：白熱核心一瞬、火球撐住再退場、濃煙留到最後；照亮四周的光跟火球一樣久。
const BLAST_CORE_TIME := 0.1
const BLAST_FIRE_TIME := 0.46
## 爆炸中心離地面不到「半徑 × 這個倍率」就算貼地。
const BLAST_GROUND_REACH := 0.75
const BLAST_SMOKE_TIME := 1.1
const BLAST_SMOKE := Color(0.17, 0.14, 0.15, 0.88)
## 爆炸的光：照到半徑的幾倍遠、顏色往紅偏多少。
const BLAST_LIGHT_REACH := 5.0
const BLAST_LIGHT_WARMTH := 0.3
const BLAST_LIGHT_ENERGY := 2.0
const CLOTH_TEAR_COLOR := Color(0.24, 0.27, 0.32, 0.9)
## 特效的 HDR 亮度上限（同 LightKit.HDR_PEAK_MAX，LightKit.glow 本身就會夾住）：測試（FxUpgradesSuite）會掃描程式裡寫死的倍率，
## 並對每個光影設定檢查泛光超出量在預算內。Fx.hdr() 只是讓呼叫端更明白「這裡有上限」。
const HDR_PEAK_MAX := LightKit.HDR_PEAK_MAX

var _container: Node2D
var _glow: ParticleField  # 疊加（發光）層
var _soft: ParticleField  # 一般混合層（煙、灰塵、碎片）
var _arcs: ArcField
var _numbers: DamageNumbers
var _rings: Array[ShockRing] = []
var _next_ring := 0
var _last_blast_msec := -1000
var _last_blast_position := Vector2.INF
var _lights: Array[PointLight2D] = []
var _light_tweens: Array[Tween] = []
var _next_light := 0
var _floor_query := PhysicsRayQueryParameters2D.new()
var _hitstop_log: Array[Vector2] = []  # [發生時間（毫秒）, 秒數]
var _slowmo_until_msec := 0
var _slowmo_ready_msec := 0
## 局部頓幀中的節點 → [結束時間（毫秒）, 原本的 process_mode]。
var _frozen: Dictionary = {}


## 夾在上限內的 HDR 發光色（intensity 超過 HDR_PEAK_MAX 時以上限計）。
func hdr(color: Color, intensity: float) -> Color:
	return LightKit.glow(color, minf(intensity, HDR_PEAK_MAX))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_floor_query.collision_mask = Layers.SOLID
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


## 由關卡呼叫：特效要放在哪個節點下。
func bind_container(container: Node2D) -> void:
	_container = container
	_numbers = DamageNumbers.new()
	container.add_child(_numbers)
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
	_numbers = null
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


## 立刻解除所有頓幀，被凍結的節點恢復（測試與切換場景時用；一般戰鬥讓頓幀自己到期）。
func thaw_all() -> void:
	_clear_frozen()


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


## 布料脫落：少量暗色碎布沿角色面向外散開，不使用發光層或整件身體碎片。
func cloth_tear(position: Vector2, facing: int) -> void:
	if _soft == null or _container == null or not position.is_finite():
		return
	var amount := _particle_count(6)
	if amount <= 0:
		return
	var direction := -1.0 if facing < 0 else 1.0
	for i in mini(amount, 3):
		var side := direction * (1.0 if i != 1 else -1.0)
		var velocity := Vector2(side * randf_range(24.0, 52.0), randf_range(-62.0, -28.0))
		var life := randf_range(0.32, 0.48)
		_soft.emit_ex(position, velocity, life, VfxAtlas.Cell.SHARD, randf_range(2.6, 4.2), 1.0,
				CLOTH_TEAR_COLOR, Color(CLOTH_TEAR_COLOR.r, CLOTH_TEAR_COLOR.g, CLOTH_TEAR_COLOR.b, 0.0), 110.0, 2.8,
				randf() * TAU, randf_range(-4.5, 4.5))


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


## 排氣孔噴發：比一般蒸汽更猛、更高、更大團。
func steam_jet(position: Vector2) -> void:
	if _soft == null:
		return
	var velocity := Vector2(randf_range(-16.0, 16.0), randf_range(-78.0, -50.0))
	_soft.emit_ex(position, velocity, randf_range(0.9, 1.5), VfxAtlas.Cell.PUFF_B, randf_range(8.0, 12.0), randf_range(26.0, 40.0),
			Color(0.82, 0.86, 0.95, 0.26), Color(0.75, 0.78, 0.9, 0.0), -10.0, 0.5, randf() * TAU, randf_range(-0.5, 0.5))


# ---------------------------------------------------------------------------
# 光源與爆炸
# ---------------------------------------------------------------------------

## 短暫閃光（槍口、爆炸、終結技）。光源池循環使用，不會無限增加。
func flash_light(position: Vector2, color: Color, radius: float, energy: float, duration: float, hold := 0.0) -> void:
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
	# 貼近玩家的閃光不能把白色頭髮照成一團白（NE-213）。
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	var near := player != null and player.global_position.distance_to(position) < radius * 0.6
	energy = LightKit.capped_flash_energy(energy, near)
	light.energy = energy
	light.enabled = true
	var tween := light.create_tween()
	if hold > 0.0:
		tween.tween_interval(hold)
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
	if not _explosion_visual(position, radius, color):
		return  # keep both damage teams, but emit their visual/audio/flash only once
	# 爆炸照亮四周：整個環境光被帶亮（爆炸越大越亮），再加一盞以爆炸為中心的暖光照近處的地面與角色；
	# 兩者都跟火球一樣久，火球還亮著的時候四周不會先暗掉。
	flash_light(position, color.lerp(Palette.DANGER, BLAST_LIGHT_WARMTH), radius * BLAST_LIGHT_REACH, BLAST_LIGHT_ENERGY, BLAST_FIRE_TIME * 0.6, BLAST_FIRE_TIME * 0.5)
	EventBus.ambient_flash_requested.emit(color.lerp(Palette.WHITE, 0.3), clampf(0.08 + radius / 260.0, 0.12, 0.32), BLAST_FIRE_TIME)
	Feel.shake_strength(clampf(radius / 6.0, 2.0, 8.0), 0.25)
	Sfx.play(&"explosion_small" if radius < SMALL_EXPLOSION_RADIUS else &"explosion", -2.0, 0.1)


## 爆炸的視覺：一瞬的白熱核心、平塗分層的火球（亮黃心、橘色團），火球退場後露出後面的濃煙，
## 加上火花、餘燼、碎片與衝擊波；貼地的爆炸只往上炸開，並在地面留一道暖色反光（半徑越大越誇張）。
func _explosion_visual(position: Vector2, radius: float, color: Color) -> bool:
	if _glow == null:
		return false
	# 同一處同時間的第二次爆炸（玩家陣營與敵人陣營各炸一次）只畫一次。
	var now := Time.get_ticks_msec()
	if now - _last_blast_msec < 60 and position.distance_to(_last_blast_position) < 4.0:
		return false
	_last_blast_msec = now
	_last_blast_position = position
	var r := maxf(8.0, radius)
	var floor_y := _floor_below(position, r * BLAST_GROUND_REACH)
	var grounded := not is_nan(floor_y)
	fireball(position, r, color, grounded)
	# 貼地時白熱核心往上抬，光暈才不會溢到地板底下。
	var core := Vector2(position.x, minf(position.y, floor_y - r * 0.55)) if grounded else position
	_glow.emit_ex(core, Vector2.ZERO, BLAST_CORE_TIME, VfxAtlas.Cell.GLOW, r * 0.8, r * 1.4, Color(1.2, 0.95, 0.6, 0.4), Color(color.r, color.g * 0.8, color.b * 0.6, 0.0))
	flare(core, color, r * 1.3, 0.1)
	if grounded:
		# 地面反光：一道壓扁的暖光貼在地上，跟火球一起退。
		var reach := r * 3.2
		_glow.emit_ex(Vector2(position.x + reach * 0.5, floor_y), Vector2(1.0, 0.0), BLAST_FIRE_TIME, VfxAtlas.Cell.GLOW, r * 0.22, r * 0.1,
				Color(color.r * 1.2, color.g * 0.9, color.b * 0.6, 0.55), Color(color.r, color.g * 0.5, color.b * 0.3, 0.0), 0.0, 0.0, 0.0, 0.0, reach, 0.0, 0.3)
	sparks(position, color, 14, r * 8.0, 0.4)
	embers(position, color, 6, r * 1.0, 0.9, r * 0.4)
	shards(position, color, 5, r * 4.5, 0.9, maxf(5.0, r * 0.16))
	shock(position, r * 3.2, 0.05, color.lerp(Palette.WHITE, 0.3), 0.55)
	return true


## 平塗分層的火球：最後面是濃煙，外圈的橘色團先撐開、停一下再轉暗退場，中間疊亮黃的團，最裡面是一瞬的白熱心。
## 每一層都是硬邊色塊，顏色不相加，所以中心不會糊成一片白。grounded＝貼地，只往上半邊炸開。
func fireball(position: Vector2, radius: float, color: Color, grounded := false) -> void:
	if _soft == null:
		return
	var outer := _particle_count(8)
	if outer <= 0:
		return
	var warm := color.h < 0.2 or color.h > 0.92
	var hue := color.h - (0.035 if warm else 0.0)
	var body := Color.from_hsv(fposmod(hue, 1.0), minf(1.0, color.s * 1.25 + 0.1), color.v * (0.95 if warm else 0.78))
	var soot := Color.from_hsv(body.h, body.s * 0.8, 0.2, 0.0)
	# 三層的明度要拉開（白熱心最亮、中層次之、外圈最暗）：彩度被調色壓低的場景裡，層次靠明暗分辨。
	var hot := Color(color.r * 1.05, color.g * 1.05, color.b * 1.05, 1.0)
	var white := color.lerp(Palette.WHITE, 0.75)
	white = Color(white.r * 1.6, white.g * 1.6, white.b * 1.6, 1.0)
	var centre := position + Vector2(0.0, -radius * 0.18) if grounded else position
	var arc_from := PI if grounded else 0.0
	var arc_span := PI if grounded else TAU
	outer = clampi(outer, 3, 12)
	# 濃煙先放（畫在火球後面），火球退掉才露出來，慢慢往上飄散。
	var clouds := maxi(2, outer / 2 + 1)
	for i in clouds:
		var dir := Vector2.RIGHT.rotated(arc_from + arc_span * (float(i) + randf_range(0.2, 0.8)) / float(clouds))
		_soft.emit_ex(centre + dir * radius * 0.3, dir * radius * randf_range(0.5, 0.9) + Vector2(0.0, -radius * 0.5), BLAST_SMOKE_TIME * randf_range(0.8, 1.15),
				VfxAtlas.Cell.BLOB_B if i % 2 == 0 else VfxAtlas.Cell.BLOB_A, radius * 0.7, radius * randf_range(1.0, 1.25),
				BLAST_SMOKE, Color(BLAST_SMOKE.r, BLAST_SMOKE.g, BLAST_SMOKE.b, 0.0), -18.0, 2.2, randf() * TAU, randf_range(-0.5, 0.5), 0.0, 0.0, 0.35)
	for i in outer:
		var dir := Vector2.RIGHT.rotated(arc_from + arc_span * (float(i) + randf_range(0.15, 0.85)) / float(outer))
		_soft.emit_ex(centre + dir * radius * 0.26, dir * radius * randf_range(1.2, 2.0), BLAST_FIRE_TIME * randf_range(0.85, 1.15),
				VfxAtlas.Cell.BLOB_A if i % 2 == 0 else VfxAtlas.Cell.BLOB_B, radius * 0.7, radius * randf_range(1.05, 1.25),
				body, soot, -24.0, 5.0, randf() * TAU, randf_range(-0.9, 0.9), 0.0, 0.0, 0.62)
	var inner := maxi(2, outer / 2)
	for i in inner:
		var dir := Vector2.RIGHT.rotated(arc_from + arc_span * (float(i) + randf_range(0.2, 0.8)) / float(inner))
		_soft.emit_ex(centre + dir * radius * 0.1, dir * radius * randf_range(0.5, 1.0), BLAST_FIRE_TIME * randf_range(0.55, 0.7),
				VfxAtlas.Cell.BLOB_B if i % 2 == 0 else VfxAtlas.Cell.BLOB_A, radius * 0.5, radius * randf_range(0.72, 0.86),
				hot, Color(body.r, body.g, body.b, 0.0), -24.0, 5.0, randf() * TAU, randf_range(-1.2, 1.2), 0.0, 0.0, 0.5)
	_soft.emit_ex(centre, Vector2.ZERO, BLAST_CORE_TIME * 1.6, VfxAtlas.Cell.BLOB_A, radius * 0.36, radius * 0.5,
			white, Color(hot.r, hot.g, hot.b, 0.0), 0.0, 0.0, randf() * TAU, 0.0, 0.0, 0.0, 0.6)


## position 正下方 reach 像素內的地面高度（世界座標）；沒有地面回傳 NAN。
func _floor_below(position: Vector2, reach: float) -> float:
	if _container == null or not _container.is_inside_tree():
		return NAN
	_floor_query.from = position + Vector2(0.0, -2.0)
	_floor_query.to = position + Vector2(0.0, reach)
	var hit := _container.get_world_2d().direct_space_state.intersect_ray(_floor_query)
	return (hit["position"] as Vector2).y if not hit.is_empty() else NAN
