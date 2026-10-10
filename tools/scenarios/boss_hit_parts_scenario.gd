class_name BossHitPartsScenario
extends ScenarioBase
## 截圖情境（NE-252、NE-248）：看門狗與監管者並排，畫出受擊框（黃＝部位）；監管者核心外露。
## 再用真實子彈瞄準看門狗畫面上的頭、監管者藏在身體框裡的核心，各拍一張命中瞬間（應出現弱點回饋）。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=boss_hit_parts

const LIGHTING := "res://data/lighting/neutral.tres"
const CAMERA_TILE := 24.0
const SHOT := "res://data/projectiles/pistol_shot.tres"


func run() -> void:
	await open_arena(LIGHTING, CAMERA_TILE)
	player.visible = false
	await clear_enemies()
	var dog := _still("res://data/enemies/watchdog.tres", 22.0)
	var warden := _still("res://data/enemies/warden.tres", 28.0)
	await wait(0.6)
	for enemy in [dog, warden]:
		enemy.set_physics_process(false)
	warden.call(&"_set_core_exposed", true)
	Enemy.debug_hurtboxes = true
	for enemy in [dog, warden]:
		enemy.queue_redraw()
	await wait(0.2)
	capture("NE-252-boss-parts-debug")
	var spec := load(SHOT) as ProjectileSpec
	var head := _part_center(dog, &"head")
	var core := _part_center(warden, &"core")
	ProjectilePool.spawn(spec, head + Vector2(-70.0, 0.0), Vector2.RIGHT, Combat.Team.PLAYER)
	ProjectilePool.spawn(spec, core + Vector2(70.0, 0.0), Vector2.LEFT, Combat.Team.PLAYER)
	for i in 4:
		await wait(0.03)
		for enemy in [dog, warden]:
			enemy.queue_redraw()
		capture("NE-252-boss-parts-shot-%d" % i)
	print("HIT dog %d/%d warden %d/%d" % [dog.health.current, dog.health.max_health, warden.health.current, warden.health.max_health])
	Enemy.debug_hurtboxes = false
	await finish()


func _still(path: String, tile: float) -> Enemy:
	var enemy := spawn_enemy(path, tile)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.facing = -1
	return enemy


func _part_center(enemy: Enemy, id: StringName) -> Vector2:
	for part in enemy.hurtbox.parts:
		if part.part_id == id:
			return part.center()
	return enemy.hurtbox.center()
