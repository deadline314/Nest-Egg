extends Node
## 開發工具（NE-145）：量測物理頻率 60／90／120 的成本。場上放一個玩家與一批敵人，各頻率跑幾秒，
## 輸出平均每個物理步驟的處理毫秒、每秒的物理處理毫秒（＝步驟數 × 每步毫秒），以及輸入延遲上限（一個步驟的長度）。
## 用法：godot --headless --path . res://tools/physics_rate_probe.tscn

const RATES: Array[int] = [60, 90, 120]
const SECONDS := 3.0
const ENEMIES := ["grunt", "elite_grunt", "drone", "shock_hound", "turret", "heavy_gunner", "bomber", "mimic"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var data := NewEnemiesSuite.arena_data()
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await get_tree().create_timer(1.0).timeout
	for round in 2:
		for id in ENEMIES:
			var enemy := level._create_enemy(load("res://data/enemies/%s.tres" % id) as EnemyData)
			enemy.position = Vector2((20.0 + float(ENEMIES.find(id)) * 3.0) * 16.0, 20.0 * 16.0)
			level._entities.add_child(enemy)
	level.player.health.setup(999999, 0.0)
	var base_step_ms := 0.0
	print("rate | steps/s | ms/step | physics ms/s | worst input delay (ms)")
	for rate in RATES:
		Engine.physics_ticks_per_second = rate
		await get_tree().create_timer(0.5).timeout
		var total := 0.0
		var samples := 0
		var end := Time.get_ticks_msec() + int(SECONDS * 1000.0)
		while Time.get_ticks_msec() < end:
			await get_tree().physics_frame
			total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			samples += 1
		var ms_per_step := total / float(maxi(1, samples))
		if rate == 60:
			base_step_ms = ms_per_step * 60.0
		print("%d | %d | %.3f | %.1f (%.2fx) | %.1f" % [rate, rate, ms_per_step, ms_per_step * float(rate), ms_per_step * float(rate) / maxf(0.001, base_step_ms), 1000.0 / float(rate)])
	get_tree().quit()
