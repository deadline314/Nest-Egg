class_name SteamValve
extends Node2D
## 蒸汽閥（NE-398）：玩家的子彈、近戰或爆炸打到閥門，旁邊的管口就噴出一道蒸汽牆。
## 蒸汽牆在 screen_seconds 秒內擋住雙方的子彈（角色可以穿過去），最後一秒逐漸變淡提醒快散了；散去後冷卻才能再用。
## 閥門上的指示燈：青色＝可以用，暗紅＝冷卻中。外觀與時間來自 SteamValveData。原點在閥門腳底那一格的底邊中點。
## 不存進檢查點：蒸汽是暫時的，重生後一律回到可以用。

signal screen_opened(valve: SteamValve)
signal screen_closed(valve: SteamValve)

enum State { READY, VENTING, COOLING }

const GROUP := &"steam_valves"
## 噴蒸汽的頻率（每秒幾團）：管口的強噴與牆面上的慢慢上升。
const JET_INTERVAL := 0.05
const DRIFT_INTERVAL := 0.06
## 最後幾秒開始變淡（只改外觀，擋子彈到最後一刻為止）。
const FADE_SECONDS := 1.0
const SCREEN_ALPHA := 0.7
const LAMP_READY := Color(0.35, 0.95, 1.0)
const LAMP_COOLING := Color(0.75, 0.18, 0.16)
const HURTBOX_PADDING := 2.0
const PROMPT_OFFSET := Vector2(0, -46)

var data: SteamValveData
var cell := Vector2i.ZERO
## true＝蒸汽牆在閥門左邊（地圖上鏡像擺放）。
var flip := false
var state: State = State.READY
var health: HealthComponent
var hurtbox: Hurtbox

var _left := 0.0
var _jet_timer := 0.0
var _drift_timer := 0.0
var _time := 0.0
var _screen: _Screen
var _lamp: _Lamp
var _prompt: WorldPrompt


func configure(p_data: SteamValveData, p_cell: Vector2i, p_flip := false) -> void:
	data = p_data
	cell = p_cell
	flip = p_flip


func _ready() -> void:
	if data == null:
		push_error("[SteamValve] 未指定 SteamValveData，已移除。")
		queue_free()
		return
	add_to_group(GROUP)
	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = LitTextures.load_texture(data.texture, Vector2i(data.size))
	body.centered = false
	var tex_size := Vector2(body.texture.get_size())
	body.scale = Vector2(data.size.x / maxf(tex_size.x, 1.0), data.size.y / maxf(tex_size.y, 1.0))
	body.position = Vector2(-data.size.x * 0.5, -data.size.y)
	body.flip_h = flip
	add_child(body)
	_lamp = _Lamp.new()
	_lamp.valve = self
	_lamp.position = Vector2(0.0, -data.size.y * 0.62)
	LightKit.mark_emissive(_lamp)
	add_child(_lamp)

	health = HealthComponent.new()
	add_child(health)
	health.setup(1000, 0.0)
	health.damaged.connect(_on_hit)
	hurtbox = Hurtbox.new()
	add_child(hurtbox)
	hurtbox.setup(Combat.Team.ENEMY, health, data.size + Vector2.ONE * HURTBOX_PADDING, Vector2(0, -data.size.y * 0.5))
	hurtbox.hit_material = &"metal"

	_screen = _Screen.new()
	_screen.valve = self
	_screen.position = Vector2(screen_x(), 0.0)
	add_child(_screen)

	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.radius = 110.0
		_prompt.offset = PROMPT_OFFSET
		add_child(_prompt)
	set_process(false)


## 蒸汽牆中心離閥門的橫向距離（已套用鏡像）。
func screen_x() -> float:
	return -data.screen_offset if flip else data.screen_offset


func is_ready_to_vent() -> bool:
	return state == State.READY


func is_venting() -> bool:
	return state == State.VENTING


## 蒸汽牆在世界座標的範圍（測試與量測用）。
func screen_rect() -> Rect2:
	return Rect2(global_position + Vector2(screen_x() - data.screen_width * 0.5, -data.screen_height), Vector2(data.screen_width, data.screen_height))


func _on_hit(_info: DamageInfo) -> void:
	# 閥門不會壞：每一下都補回去，只看「有沒有被打到」。
	health.heal(1000)
	vent()


## 打開閥門。冷卻中或已經在噴時不做事；回傳有沒有打開。
func vent() -> bool:
	if state != State.READY:
		return false
	state = State.VENTING
	_left = data.screen_seconds
	_screen.set_blocking(true)
	_lamp.queue_redraw()
	if _prompt != null:
		_prompt.enabled = false
	Sfx.play(&"vent", -2.0)
	EventBus.world_noise.emit(global_position, 0.7)
	set_process(true)
	screen_opened.emit(self)
	return true


func _process(delta: float) -> void:
	_time += delta
	_left -= delta
	match state:
		State.VENTING:
			_emit_steam(delta)
			_screen.queue_redraw()
			if _left <= 0.0:
				state = State.COOLING
				_left = data.cooldown_seconds
				_screen.set_blocking(false)
				_screen.queue_redraw()
				_lamp.queue_redraw()
				screen_closed.emit(self)
		State.COOLING:
			if _left <= 0.0:
				state = State.READY
				_lamp.queue_redraw()
				if _prompt != null:
					_prompt.enabled = true
				set_process(false)


## 管口強噴＋牆面上的蒸汽慢慢上升。最後一秒噴得越來越少（看得出快散了）。
func _emit_steam(delta: float) -> void:
	var strength := clampf(_left / FADE_SECONDS, 0.0, 1.0)
	_jet_timer -= delta
	if _jet_timer <= 0.0:
		_jet_timer = JET_INTERVAL / maxf(strength, 0.25)
		Fx.steam_jet(global_position + Vector2(screen_x() + randf_range(-3.0, 3.0), -2.0))
	_drift_timer -= delta
	if _drift_timer <= 0.0:
		_drift_timer = DRIFT_INTERVAL / maxf(strength, 0.25)
		var rect := screen_rect()
		Fx.steam(Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y + rect.size.y * 0.3, rect.end.y)))


## 目前蒸汽牆的不透明度（0～1；最後一秒逐漸變淡）。
func screen_opacity() -> float:
	if state != State.VENTING:
		return 0.0
	return clampf(_left / FADE_SECONDS, 0.0, 1.0) if _left < FADE_SECONDS else 1.0


## 蒸汽牆：只有子彈會撞到（自己的碰撞層），角色穿得過去。子彈撞上時化成一小團蒸汽。
class _Screen:
	extends StaticBody2D

	var valve: SteamValve
	var _shape: CollisionShape2D

	func _ready() -> void:
		collision_layer = Layers.SCREEN
		collision_mask = 0
		var box := RectangleShape2D.new()
		box.size = Vector2(valve.data.screen_width, valve.data.screen_height)
		_shape = CollisionShape2D.new()
		_shape.shape = box
		_shape.position = Vector2(0.0, -valve.data.screen_height * 0.5)
		_shape.disabled = true
		add_child(_shape)
		z_as_relative = false
		z_index = WorldLayers.ENTITY_BEHIND + 30  # 畫在角色前面一點：子彈從蒸汽裡消失要看得到

	func set_blocking(on: bool) -> void:
		_shape.set_deferred(&"disabled", not on)

	func is_blocking() -> bool:
		return not _shape.disabled

	## Projectile 撞到這個身體時呼叫：子彈被蒸汽吃掉，不算命中、不冒火花。
	func absorbs_projectile(at: Vector2) -> void:
		Fx.steam(at)

	func _draw() -> void:
		var alpha := valve.screen_opacity()
		if alpha <= 0.0:
			return
		var size := Vector2(valve.data.screen_width, valve.data.screen_height)
		var breathe := 0.0 if Settings.get_reduce_ui_motion() else sin(valve._time * 2.3) * 0.06
		var color := Color(0.8, 0.84, 0.92, SteamValve.SCREEN_ALPHA * alpha * (1.0 + breathe))
		var soft := LightKit.soft_texture()
		# 底部最濃、往上散開：兩層柔邊疊成一道柱子，不是一塊方形。
		draw_texture_rect(soft, Rect2(-size.x * 0.9, -size.y * 0.55, size.x * 1.8, size.y * 0.7), false, color)
		draw_texture_rect(soft, Rect2(-size.x * 0.7, -size.y * 1.05, size.x * 1.4, size.y * 0.8), false, Color(color, color.a * 0.7))


## 閥門上的指示燈：可以用時是青色，冷卻中是暗紅，噴蒸汽時熄掉。
class _Lamp:
	extends Node2D

	var valve: SteamValve

	func _draw() -> void:
		match valve.state:
			SteamValve.State.READY:
				draw_circle(Vector2.ZERO, 1.6, LightKit.glow(SteamValve.LAMP_READY, 1.4))
			SteamValve.State.COOLING:
				draw_circle(Vector2.ZERO, 1.4, SteamValve.LAMP_COOLING)
			_:
				pass
