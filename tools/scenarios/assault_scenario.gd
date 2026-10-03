extends ScenarioBase
## NE-48 情境：電擊犬（成群低吼蓄力、撲咬、站上平台就安全）與偽裝箱（和貨箱一模一樣、
## 子彈試探現形、靠近震動預兆、彈起咬人）。用有平台的測試場地、貨運站光影。

const HOUND := "res://data/enemies/shock_hound.tres"
const MIMIC := "res://data/enemies/mimic.tres"
const CRATE := "res://data/props/crate.tres"
const LIGHTING := "res://data/lighting/freight.tres"
const PLATFORM_Y := 16 * 16.0


func run() -> void:
	await open_arena(LIGHTING, 40.0, EnemySuiteBase.map_data())
	await _hounds()
	await clear_enemies()
	await _mimic()
	await finish()


func _hounds() -> void:
	place_player(40.0)
	var hounds: Array[ShockHound] = []
	for x in [54.0, 55.0, 56.5]:
		hounds.append(spawn_enemy(HOUND, x) as ShockHound)
	while not hounds.any(func(h: ShockHound) -> bool: return h.fsm.is_in(&"growl")):
		await wait(0.03)
	await wait(0.35)
	capture("NE-48-hound-growl")
	while not hounds.any(func(h: ShockHound) -> bool: return h.fsm.is_in(&"pounce")):
		await wait(0.02)
	await wait(0.12)
	capture("NE-48-hound-pounce")
	# 站上平台：牠們只能在底下打轉。
	await clear_enemies()
	player.global_position = Vector2(53 * 16.0, PLATFORM_Y - 1.0)
	snap_camera()
	for x in [46.0, 47.5, 49.0]:
		spawn_enemy(HOUND, x)
	await wait(3.0)
	capture("NE-48-hound-platform-safe")


func _mimic() -> void:
	place_player(50.0)
	# 左邊一個偽裝箱、右邊一個真的貨箱：長得一模一樣。
	var crate := Breakable.new()
	crate.configure(load(CRATE) as BreakableData, Vector2i(62, 19), 16)
	crate.position = Vector2(62 * 16.0, FLOOR_Y)
	level._entities.add_child(crate)
	var probed := spawn_enemy(MIMIC, 58.0) as Mimic
	await wait(1.0)
	capture("NE-48-mimic-disguised")
	# 子彈試探：震動、牙齒亮起，但外殼擋下傷害。
	ProjectilePool.spawn(load("res://data/projectiles/rifle_shot.tres") as ProjectileSpec, Vector2(53 * 16.0, FLOOR_Y - 15.0), Vector2.RIGHT, Combat.Team.PLAYER)
	await wait(0.22)
	capture("NE-48-mimic-probed")
	await wait(1.0)
	probed.queue_free()
	crate.queue_free()
	# 另一個沒被試探過的箱子：靠近時震動預兆，接著彈起咬人。
	var ambusher := spawn_enemy(MIMIC, 58.0) as Mimic
	place_player(55.5)
	while not ambusher.fsm.is_in(&"shake"):
		await wait(0.02)
	await wait(0.25)
	capture("NE-48-mimic-warning")
	while not ambusher.fsm.is_in(&"lunge"):
		await wait(0.02)
	await wait(0.1)
	capture("NE-48-mimic-lunge")
