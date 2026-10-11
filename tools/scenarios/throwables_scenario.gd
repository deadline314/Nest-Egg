class_name ThrowablesScenario
extends ScenarioBase
## 截圖情境（NE-254）：在有掩體牆與平台的測試場地，用真正的按鍵撿起木箱、舉著（拋物線瞄向高處平台）、丟中敵人；
## 再射油桶：引信燒著時地上的爆炸範圍、爆炸與連鎖。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=throwables

const LIGHTING := "res://data/lighting/neutral.tres"


func run() -> void:
	await open_arena(LIGHTING, 44.0, EnemySuiteBase.map_data())
	await clear_enemies()
	level.hud.visible = true
	AimInput.set_virtual_gamepad(player, true)
	var crate := _place("res://data/throwables/crate_small.tres", 45.0)
	var grunt := spawn_enemy("res://data/enemies/grunt.tres", 58.0)
	grunt.data = grunt.data.duplicate()
	grunt.data.detect_range = 0.0
	grunt.data.attack_range = 0.0
	_place("res://data/throwables/pipe.tres", 47.0)
	await wait(0.4)
	# 軟體繪圖很慢，一個畫面會跑好幾個物理影格：拍動作瞬間時先放慢遊戲時間，等畫面真的畫出來再拍。
	Engine.time_scale = 0.15
	await _press(&"interact")
	await settle(2)
	capture("NE-254-lift")
	Engine.time_scale = 1.0
	await wait(0.4)
	_aim(Vector2(0.75, -0.66).normalized())
	await wait(0.3)
	capture("NE-254-hold-arc-up")
	_aim(Vector2(1.0, -0.12).normalized())
	await wait(0.3)
	capture("NE-254-hold-arc-enemy")
	Engine.time_scale = 0.15
	await _press(&"shoot")
	await settle(2)
	capture("NE-254-throw")
	Engine.time_scale = 1.0
	for i in 30:
		if not is_instance_valid(crate):
			break
		await get_tree().physics_frame
	capture("NE-254-hit")
	_release()
	# 油桶：射一槍點燃引信 → 地上的爆炸範圍 → 爆炸與連鎖。
	await clear_enemies()
	var barrel := _place("res://data/throwables/fuel_barrel.tres", 52.0)
	_place("res://data/throwables/fuel_barrel.tres", 54.5)
	var target := spawn_enemy("res://data/enemies/grunt.tres", 53.5)
	target.data = target.data.duplicate()
	target.data.detect_range = 0.0
	target.data.attack_range = 0.0
	await wait(0.4)
	for i in 2:
		ProjectilePool.spawn(load("res://data/projectiles/rifle_shot.tres") as ProjectileSpec, barrel.world_center() + Vector2(-50, 0), Vector2.RIGHT, Combat.Team.PLAYER)
		await wait(0.08)
	await wait(0.25)
	capture("NE-254-barrel-fuse")
	for i in 60:
		if not is_instance_valid(barrel):
			break
		await get_tree().physics_frame
	await wait(0.05)
	capture("NE-254-barrel-blast")
	await wait(0.5)
	capture("NE-254-barrel-chain")
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _place(path: String, x_tile: float) -> Throwable:
	var item := Throwable.new()
	item.configure(load(path) as ThrowableData)
	item.position = Vector2(x_tile * 16.0, FLOOR_Y)
	level._entities.add_child(item)
	return item


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _aim(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])


func _release() -> void:
	for action: StringName in [&"aim_left", &"aim_right", &"aim_up", &"aim_down", &"shoot", &"interact"]:
		Input.action_release(action)
