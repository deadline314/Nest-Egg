class_name WeaponLight
extends Node2D
## 槍燈（NE-258）：掛在槍上的常亮照明，從槍口朝瞄準方向照出一道光錐；每把槍的光寫在 WeaponData（Light 群組）。
## 不需要電量、不和射擊互斥。光錐會被地形擋住；被它照到的潛行者會現形（LightKit.light_level_at）。
## 有細瞄準光的武器（light_sight）另外畫一條發光的細線。開火後要等一下才能再開火的武器（light_dims_until_ready）
## 開火時變暗、可以再開火時恢復全亮。

## 開火後光錐輕微抖動多久（秒），以及最大抖動角度（度，乘上武器的 light_jitter）。
const JITTER_TIME := 0.12
const JITTER_DEGREES := 2.2
## 開火後變暗的武器，暗到全亮的幾成。
const UNREADY_LEVEL := 0.35
## 開關與換槍時亮度變化的速度（每秒）。
const FADE_SPEED := 6.0
const SIGHT_WIDTH := 1.0
const SIGHT_ALPHA := 0.55

## 強制關掉（對照量測與測試用）：和「這把武器沒有槍燈」的表現相同。
var suppressed := false

var _light: PointLight2D
var _weapon: WeaponData
var _active := false
var _level := 0.0
var _ready_ratio := 1.0
var _jitter_left := 0.0
var _sight_length := 0.0
## 細瞄準光用來找牆：線只畫到第一道實心地形。
var _sight_ray: RayCast2D


func _ready() -> void:
	_light = LightKit.create_point_light(Color.WHITE, 64.0, 0.0, true, false)
	_light.enabled = false
	add_child(_light)
	_sight_ray = RayCast2D.new()
	_sight_ray.collision_mask = Layers.WORLD
	_sight_ray.enabled = false
	add_child(_sight_ray)
	LightKit.mark_emissive(self)


## 換成這把武器的光。沒有槍燈的武器（近戰、載具武器、light_range 為 0）會把光關掉。
func configure(weapon: WeaponData) -> void:
	_weapon = weapon if weapon != null and weapon.has_light() else null
	_jitter_left = 0.0
	_ready_ratio = 1.0
	if _weapon == null:
		_sight_length = 0.0
		_sight_ray.enabled = false
		queue_redraw()
		return
	_light.texture = LightKit.cone_texture(_weapon.light_cone_degrees)
	_light.texture_scale = _weapon.light_range * 2.0 / float(LightKit.CONE_TEXTURE_SIZE)
	_light.color = _weapon.light_color
	LightKit.mark_aimed(_light, _weapon.light_range, _weapon.light_cone_degrees)
	_sight_length = _weapon.light_range if _weapon.light_sight else 0.0
	_sight_ray.enabled = _sight_length > 0.0
	_sight_ray.target_position = Vector2(_sight_length, 0.0)
	queue_redraw()


## 事先建立這些武器會用到的光錐貼圖，換槍的那一格就不用現做。
static func warm(weapons: Array) -> void:
	for item: Variant in weapons:
		var weapon := item as WeaponData
		if weapon != null and weapon.has_light():
			LightKit.cone_texture(weapon.light_cone_degrees)


## 這一格要不要亮（死亡、搭載具、講電話時關掉）。
func set_active(active: bool) -> void:
	_active = active


## 立刻熄掉（主角死亡時）：不等淡出。
func extinguish() -> void:
	_active = false
	_level = 0.0
	_light.enabled = false
	queue_redraw()


func is_lit() -> bool:
	return _weapon != null and not suppressed and _level > 0.01


## 光的照射距離與張角（沒有槍燈時是 0）。
func reach() -> float:
	return _weapon.light_range if _weapon != null else 0.0


## 開火的那一刻：會抖的武器開始抖，開火後變暗的武器先變暗。
func fired() -> void:
	if _weapon == null:
		return
	if _weapon.light_jitter > 0.0:
		_jitter_left = JITTER_TIME
	if _weapon.light_dims_until_ready:
		_ready_ratio = 0.0


## 每一格更新：origin 是槍口附近（世界座標）、direction 是瞄準方向、ready 是「離可以再開火還差多少」（0 剛開火、1 可以開火）。
func aim(origin: Vector2, direction: Vector2, ready: float, delta: float) -> void:
	var wanted := 1.0 if _active and _weapon != null and not suppressed else 0.0
	_level = move_toward(_level, wanted, FADE_SPEED * delta)
	if _weapon == null or _level <= 0.0:
		_light.enabled = false
		if _sight_length > 0.0:
			queue_redraw()
		return
	global_position = origin
	var angle := direction.angle()
	if _jitter_left > 0.0:
		_jitter_left -= delta
		angle += deg_to_rad(JITTER_DEGREES) * _weapon.light_jitter * Settings.flash_scale() * sin(_jitter_left * 140.0)
	rotation = angle
	if _weapon.light_dims_until_ready:
		_ready_ratio = clampf(ready, 0.0, 1.0)
	var brightness := lerpf(UNREADY_LEVEL, 1.0, _ready_ratio) if _weapon.light_dims_until_ready else 1.0
	_light.enabled = true
	_light.energy = _weapon.light_energy * _level * brightness
	if _sight_length > 0.0:
		queue_redraw()


func _draw() -> void:
	if _sight_length <= 0.0 or _weapon == null or _level <= 0.01:
		return
	var color := LightKit.glow(_weapon.light_color, 1.6)
	var length := to_local(_sight_ray.get_collision_point()).x if _sight_ray.is_colliding() else _sight_length
	draw_line(Vector2(6.0, 0.0), Vector2(maxf(6.0, length), 0.0), Color(color.r, color.g, color.b, SIGHT_ALPHA * _level), SIGHT_WIDTH)
