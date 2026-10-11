extends ScenarioBase
## NE-224：監管者在正式場地的實機戰鬥擷取（Forward+）。讓它用自己的 AI 對主角出招，同時用真實的傷害事件把血量逐段打低，
## 每 1.5 秒拍一張並記錄：狀態、階段、血量比例、槍口到武器節點的距離、場上敵方子彈離槍口最近的距離（子彈是不是從槍口出來）。
## 不改數值、不指定招式。用法：godot --path . res://pm/Nest-Egg/attachments/NE-224-warden-combat/capture.tscn -- --out=<絕對目錄>

const SECONDS := 24.0
var rows: Array[Dictionary] = []
var boss: Enemy
var nearest_spawn := INF
var seen_projectiles := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await run()
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "adapter": RenderingServer.get_video_adapter_name(),
		"projectiles_seen": seen_projectiles.size(), "nearest_projectile_spawn_to_muzzle": nearest_spawn, "rows": rows}, "\t"))
	file.close()
	await finish()
	get_tree().quit()


func run() -> void:
	seed(22481)
	await open_arena("res://data/lighting/neutral.tres", 10.0)
	player.set_physics_process(false)  # 主角站著當目標，不輸入
	boss = spawn_enemy("res://data/enemies/warden.tres", 22.0)
	level.camera.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	level.camera.limit_left = -100000
	level.camera.limit_right = 100000
	level.camera.zoom = Vector2.ONE * 1.6
	level.camera.global_position = Vector2(16.0 * 16.0, FLOOR_Y - 60.0)
	var elapsed := 0.0
	var shot := 0
	while elapsed < SECONDS and is_instance_valid(boss):
		await wait(0.1)
		elapsed += 0.1
		_track_projectiles()
		if int(elapsed * 10.0) % 15 == 0:
			if elapsed > 3.0 and boss.health.current > 1:  # 每 1.5 秒打掉一成血，裝甲跟著脫落、進入第二階段
				var info := DamageInfo.create(maxi(1, int(boss.health.max_health * 0.1)), Combat.Team.PLAYER, &"ne224_probe")
				info.origin = player.global_position
				boss.health.take_damage(info)
			capture("warden_%02d" % shot)
			rows.append({"t": elapsed, "image": "warden_%02d.png" % shot, "state": str(boss.fsm.current) if "fsm" in boss else "", "phase": int(boss.get("_phase")) if boss.get("_phase") != null else 0,
				"health_ratio": boss.health.ratio(), "x": boss.global_position.x, "player_hp": player.health.current,
				"muzzle_to_weapon": boss._muzzle().distance_to(boss.rig.weapon_root().global_position) if boss.rig != null and boss.rig.weapon_root() != null else -1.0})
			shot += 1


func _track_projectiles() -> void:
	if not is_instance_valid(boss):
		return
	for node in level.find_children("*", "Projectile", true, false):
		if not (node as Node2D).visible or seen_projectiles.has(node.get_instance_id()):
			continue
		seen_projectiles[node.get_instance_id()] = true
		nearest_spawn = minf(nearest_spawn, (node as Node2D).global_position.distance_to(boss._muzzle()))
