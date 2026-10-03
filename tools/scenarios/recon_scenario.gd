extends ScenarioBase
## NE-46 情境：探照無人機（巡邏的光束、鎖定時圓環填滿、警報與被引來的敵人、切電墜落）
## 與狙擊手（掃描的細線、鎖定後閃爍的雷射）。在偏暗的設施光影下拍，確認預兆自帶光。

const DRONE := "res://data/enemies/searchlight_drone.tres"
const SNIPER := "res://data/enemies/sniper.tres"
const GRUNT := "res://data/enemies/grunt.tres"
const LIGHTING := "res://data/lighting/facility.tres"


func run() -> void:
	await open_arena(LIGHTING, 20.0)
	await _drone()
	await clear_enemies()
	await _sniper()
	await finish()


func _drone() -> void:
	var drone := spawn_enemy(DRONE, 26.0, FLOOR_Y - 110.0) as SearchlightDrone
	place_player(18.0)
	# 巡邏：光束掃過地面。
	await wait(2.2)
	capture("NE-46-drone-patrol")
	# 鎖定：玩家站進光束，圓環逐漸填滿，光束變黃。
	place_player(26.0)
	drone.fsm.transition(&"spot")
	while drone.charge() < 0.55:
		await wait(0.05)
	capture("NE-46-drone-spot")
	# 警報：光束變紅，附近的敵人被引來（頭上出現黃色三角）。
	var grunts: Array[Enemy] = [spawn_enemy(GRUNT, 33.0), spawn_enemy(GRUNT, 36.0)]
	while not drone.fsm.is_in(&"alarm"):
		await wait(0.05)
	await wait(0.35)
	capture("NE-46-drone-alarm")
	for grunt in grunts:
		grunt.queue_free()
	# 切電：失去動力墜落，光束熄滅。
	await wait(1.6)
	level._power_grid.register_zone(&"scenario", 0, 80)
	level._power_grid.set_zone_powered(&"scenario", false)
	await wait(2.2)
	capture("NE-46-drone-unpowered")
	level._power_grid.set_zone_powered(&"scenario", true)
	await wait(2.0)


func _sniper() -> void:
	place_player(18.0)
	var sniper := spawn_enemy(SNIPER, 31.0) as Sniper
	while not sniper.fsm.is_in(&"sweep"):
		await wait(0.05)
	await wait(0.45)
	capture("NE-46-sniper-sweep")
	while not sniper.is_locked():
		await wait(0.02)
	# 鎖定後閃三下：軟體渲染的畫面更新很慢，放慢時間才抓得到亮、暗兩張。
	Engine.time_scale = 0.15
	while sniper.laser_phase() < 0.9:
		await wait(0.01)
	await wait(0.04)
	capture("NE-46-sniper-lock-on")
	while sniper.laser_phase() > 0.2:
		await wait(0.01)
	await settle(2)
	capture("NE-46-sniper-lock-off")
	Engine.time_scale = 1.0
