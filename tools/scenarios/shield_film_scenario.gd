class_name ShieldFilmScenario
extends ScenarioBase
## 舉盾連續畫面（NE-239）：用真正的按鍵與真的敵方子彈，依序拍舉起、維持、普通格擋、收起、完美反彈與破防，
## 每個動作連拍幾格（遊戲時間），用來看連續動作與三種結果的回饋是否分得開。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=shield_film

const LIGHTING := "res://data/lighting/neutral.tres"
const SHOT := "res://data/projectiles/grunt_shot.tres"


func run() -> void:
	await open_arena(LIGHTING, 30.0)
	await clear_enemies()
	AimInput.set_virtual_gamepad(player, true)
	_aim(Vector2.RIGHT)
	await wait(0.4)
	Sfx.sound_played.connect(_on_sound)
	# 軟體繪圖很慢：放慢遊戲時間，指定的遊戲時刻真的畫出來再拍。
	Engine.time_scale = 0.1
	capture("shield-00-idle")
	Input.action_press(&"block")
	await _shoot_at([0.02, 0.05, 0.09], "shield-01-raise")
	await _game_time(0.3)
	capture("shield-02-hold")
	# 普通格擋：完美窗口過後才被打。
	var spec := load(SHOT) as ProjectileSpec
	ProjectilePool.spawn(spec, _chest() + Vector2(24, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _until_sound()
	await _shoot_at([0.0, 0.04, 0.1], "shield-03-block")
	Input.action_release(&"block")
	await _shoot_at([0.03, 0.07, 0.12], "shield-04-lower")
	await _game_time(0.6)
	# 完美反彈：剛舉盾的一瞬間被打到。
	Input.action_press(&"block")
	ProjectilePool.spawn(spec, _chest() + Vector2(12, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _until_sound()
	await _shoot_at([0.0, 0.05, 0.12], "shield-05-parry")
	Input.action_release(&"block")
	await _game_time(0.6)
	# 破防：最後一點盾量被打掉。
	Input.action_press(&"block")
	await _game_time(0.3)
	player.guard = 0.5
	ProjectilePool.spawn(spec, _chest() + Vector2(24, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _until_sound()
	await _shoot_at([0.0, 0.06, 0.18], "shield-06-break")
	Input.action_release(&"block")
	Engine.time_scale = 1.0
	Sfx.sound_played.disconnect(_on_sound)
	_aim(Vector2.ZERO)
	AimInput.set_virtual_gamepad(player, false)
	await finish()


var _heard := false


func _on_sound(id: StringName) -> void:
	if id in [&"block", &"parry", &"guard_break"]:
		_heard = true


## 等到盾發出格擋、反彈或破防的聲音（子彈真的打到盾）。
func _until_sound() -> void:
	_heard = false
	for i in 600:
		if _heard:
			return
		await get_tree().physics_frame


func _chest() -> Vector2:
	return player.global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5)


## 等過 seconds 秒的遊戲時間（放慢時間時，一個物理影格只前進 1/60 × 倍率秒）。
func _game_time(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += Engine.time_scale / float(Engine.physics_ticks_per_second)


## 從現在起，在指定的遊戲時刻各拍一張（等畫面畫出來再拍）。
func _shoot_at(times: Array, prefix: String) -> void:
	var done := 0.0
	for index in times.size():
		await _game_time(float(times[index]) - done)
		done = float(times[index])
		await settle(1)
		capture("%s-%d" % [prefix, index + 1])


func _aim(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
