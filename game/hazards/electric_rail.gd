class_name ElectricRail
extends Node2D
## 電軌：貼在地面的一段通電區域。先閃黃燈預警，接著通電一段時間，通電時接觸會受傷。
## 由頭目或機關呼叫 arm()；平時完全隱形、不佔碰撞。rect 是世界座標的像素範圍。

const DAMAGE := 2
const SOURCE_ID := &"reclaimer_rail"
const HEIGHT := 10.0

enum State { IDLE, WARNING, LIVE }

var rect := Rect2()
var state := State.IDLE

var _hitbox: ContactHitbox
var _light: PointLight2D
var _warn_left := 0.0
var _live_left := 0.0
var _time := 0.0


func setup(p_rect: Rect2) -> void:
	rect = p_rect


func _ready() -> void:
	LightKit.mark_emissive(self)
	position = Vector2(rect.position.x, rect.end.y - HEIGHT)
	z_index = 3
	_hitbox = ContactHitbox.new()
	add_child(_hitbox)
	_hitbox.setup(Combat.Team.ENEMY, DAMAGE, SOURCE_ID, Vector2(rect.size.x, HEIGHT + 6.0), Vector2(rect.size.x * 0.5, HEIGHT * 0.5 - 3.0))
	_hitbox.knockback_override = Vector2(60, -220)
	_hitbox.active = false
	_light = LightKit.create_point_light(Palette.WARNING, rect.size.x * 0.8, 0.0, false)
	_light.position = Vector2(rect.size.x * 0.5, -6)
	add_child(_light)
	set_physics_process(false)


## 開始預警：warn 秒後通電，持續 live 秒。已經在預警或通電時重新計時。
func arm(warn: float, live: float) -> void:
	_warn_left = maxf(0.0, warn)
	_live_left = maxf(0.0, live)
	state = State.WARNING
	_hitbox.active = false
	set_physics_process(true)
	Sfx.play(&"telegraph", -12.0)


func is_live() -> bool:
	return state == State.LIVE


func disarm() -> void:
	state = State.IDLE
	_hitbox.active = false
	_light.energy = 0.0
	set_physics_process(false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time += delta
	match state:
		State.WARNING:
			_warn_left -= delta
			_light.energy = 0.5 + 0.3 * sin(_time * 30.0)
			if _warn_left <= 0.0:
				state = State.LIVE
				_hitbox.active = true
				Sfx.play(&"hit", -4.0)
		State.LIVE:
			_live_left -= delta
			_light.energy = 1.4 + 0.5 * sin(_time * 50.0)
			if _live_left <= 0.0:
				disarm()
				return
	queue_redraw()


func _draw() -> void:
	match state:
		State.WARNING:
			# 預警：黃色閃爍的底色與虛線，越接近通電越亮；在暗處也一眼看得出是哪一段。
			var t := clampf(1.0 - _warn_left / 1.0, 0.0, 1.0)
			var blink := int(_time * 14.0) % 2 == 0
			draw_rect(Rect2(0, 0, rect.size.x, HEIGHT), Color(Palette.WARNING, (0.18 + 0.3 * t) if blink else 0.08))
			var color := LightKit.glow(Palette.WARNING, 1.6 + 1.2 * t)
			color.a = 0.9 if blink else 0.45
			var x := 0.0
			while x < rect.size.x:
				draw_line(Vector2(x, HEIGHT - 1.0), Vector2(minf(x + 6.0, rect.size.x), HEIGHT - 1.0), color, 2.0)
				x += 10.0
			draw_line(Vector2(1, 0), Vector2(1, HEIGHT), color, 1.0)
			draw_line(Vector2(rect.size.x - 1, 0), Vector2(rect.size.x - 1, HEIGHT), color, 1.0)
		State.LIVE:
			draw_rect(Rect2(0, 0, rect.size.x, HEIGHT), Color(LightKit.glow(Palette.WARNING, 1.6), 0.35))
			draw_line(Vector2(0, HEIGHT - 1.0), Vector2(rect.size.x, HEIGHT - 1.0), LightKit.glow(Palette.CYAN, 2.5), 2.0)
			# 電弧：沿軌道亂數跳動的鋸齒線。
			var points := PackedVector2Array()
			var steps := maxi(4, int(rect.size.x / 8.0))
			for i in steps + 1:
				var y := HEIGHT * 0.5 + sin(_time * 40.0 + i * 1.7) * HEIGHT * 0.45
				points.append(Vector2(rect.size.x * i / steps, y))
			draw_polyline(points, LightKit.glow(Palette.WHITE, 2.4), 1.5)
