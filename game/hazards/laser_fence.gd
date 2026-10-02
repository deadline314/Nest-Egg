class_name LaserFence
extends Node2D
## 雷射柵欄：週期性開關，開啟前會閃爍警示。
## 應對：抓準關閉的時機通過；同一關卡的柵欄可用 phase 錯開節奏。

const ON_TIME := 1.6
const OFF_TIME := 1.4
const WARN_TIME := 0.45
const DAMAGE := 2
const BEAM_WIDTH := 4.0

var rect := Rect2()
var phase := 0.0

var _time := 0.0
## 所在區域是否有電（電力開關切斷後柵欄停擺）。
var _powered := true
var _hitbox: ContactHitbox
var _light: PointLight2D


func setup(p_rect: Rect2, p_phase := 0.0) -> void:
	rect = p_rect
	phase = p_phase


func _ready() -> void:
	LightKit.mark_emissive(self)
	position = rect.position
	_time = phase
	_hitbox = ContactHitbox.new()
	add_child(_hitbox)
	_hitbox.setup(Combat.Team.ENEMY, DAMAGE, &"laser_fence", Vector2(BEAM_WIDTH + 2.0, rect.size.y),
			Vector2(rect.size.x * 0.5, rect.size.y * 0.5))
	_hitbox.knockback_force = 200.0
	_light = LightKit.create_point_light(Palette.DANGER, rect.size.y * 0.6, 0.0)
	_light.position = Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	add_child(_light)


func is_on() -> bool:
	return _powered and fmod(_time, ON_TIME + OFF_TIME) < ON_TIME


func _is_warning() -> bool:
	if not _powered:
		return false
	var t := fmod(_time, ON_TIME + OFF_TIME)
	return t >= ON_TIME + OFF_TIME - WARN_TIME


func _physics_process(delta: float) -> void:
	_time += delta
	_powered = PowerGrid.is_powered(self)
	var on := is_on()
	_hitbox.active = on
	_light.energy = 1.2 if on else (0.3 if _is_warning() else 0.0)
	queue_redraw()


func _draw() -> void:
	var x := rect.size.x * 0.5
	# 上下發射器
	draw_rect(Rect2(x - 4, 0, 8, 4), Palette.TERRAIN_TOP)
	draw_rect(Rect2(x - 4, rect.size.y - 4, 8, 4), Palette.TERRAIN_TOP)
	if is_on():
		var flicker := 2.5 + 0.5 * sin(_time * 50.0)
		draw_line(Vector2(x, 4), Vector2(x, rect.size.y - 4), Color(LightKit.glow(Palette.DANGER, 1.2), 0.35), BEAM_WIDTH * 2.0)
		draw_line(Vector2(x, 4), Vector2(x, rect.size.y - 4), LightKit.glow(Palette.DANGER, flicker), BEAM_WIDTH * 0.5)
	elif _is_warning() and int(_time * 16.0) % 2 == 0:
		draw_line(Vector2(x, 4), Vector2(x, rect.size.y - 4), Color(Palette.DANGER, 0.35), 1.0)
