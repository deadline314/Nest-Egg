@abstract
class_name EnemySuiteBase
extends TestSuite
## 第二批敵人（NE-46～48）測試的共用基底：有掩體牆與平台的測試場地（tests/fixtures/cover_map.json）、
## 生成敵人、擺放玩家、等狀態、致命傷害與預兆／冷卻的公平性檢查。
##
## 場地（格）：地面在第 20 列；掩體牆在欄 30～31（高 7 格）；單向平台在欄 50～56（第 16 列，離地 4 格）；
## 高處平台在欄 62～65（第 12 列）。玩家預設起點欄 3。

const MAP_PATH := "res://tests/fixtures/cover_map.json"
const FLOOR_Y := 20 * 16.0
const MIN_TELEGRAPH := 0.3
const MIN_COOLDOWN := 0.6
const GRUNT_PATH := "res://data/enemies/grunt.tres"
const RIFLE_SHOT_PATH := "res://data/projectiles/rifle_shot.tres"

var level: Level


static func map_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"cover_test"
	data.layout_path = MAP_PATH
	return data


## 開一輪新遊戲與測試場地；玩家站在 player_tile，生命很多（死亡測試自己改）。
func open_level(player_tile := 10.0, difficulty_index := 1) -> Level:
	level = await start_level(map_data(), difficulty_index)
	level.player.health.setup(999, 0.0)
	place_player(player_tile)
	return level


func spawn(path: String, x_tile: float, y := FLOOR_Y) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(x_tile * 16.0, y)
	level._entities.add_child(enemy)
	return enemy


func place_player(x_tile: float, y := FLOOR_Y) -> void:
	level.player.global_position = Vector2(x_tile * 16.0, y)
	level.player.velocity = Vector2.ZERO


func wait_state(enemy: Enemy, state: StringName, frames_max: int) -> bool:
	for i in frames_max:
		if enemy.fsm.is_in(state):
			return true
		await physics_frames(1)
	return enemy.fsm.is_in(state)


## 一發玩家子彈（預設步槍彈）從 origin 朝 direction 飛。
func shoot_from(origin: Vector2, direction: Vector2, spec_path := RIFLE_SHOT_PATH) -> void:
	ProjectilePool.spawn(load(spec_path) as ProjectileSpec, origin, direction, Combat.Team.PLAYER)


func lethal() -> DamageInfo:
	var info := DamageInfo.create(999, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info


func hit(amount := 1, bypass := false, origin := Vector2.ZERO) -> DamageInfo:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	info.bypass_guard = bypass
	info.origin = origin
	return info


## 資料檢查：能載入、通過驗證、接觸與子彈都有圖鑑卡片、卡片有攻略；任何難度預兆不少於 0.3 秒、攻擊間隔不少於 0.6 秒。
func check_enemy_data(paths: Array, extra_card_ids: Array) -> void:
	for path: String in paths:
		var data := load(path) as EnemyData
		check(data != null and data.validate().is_empty(), "enemy data valid: %s" % path)
		if data == null:
			continue
		check(data.contact_damage > 0 and DefeatCodex.has_card(data.contact_source_id), "%s has a contact codex card" % data.id)
		if data.projectile != null and data.projectile.damage > 0:
			check(DefeatCodex.has_card(data.projectile.source_id), "%s projectile has a codex card: %s" % [data.id, data.projectile.source_id])
		for difficulty in GameState.difficulties:
			check(data.telegraph_time >= MIN_TELEGRAPH, "%s telegraph is readable on %s" % [data.id, difficulty.id])
			check(data.attack_cooldown * difficulty.enemy_cooldown_multiplier >= MIN_COOLDOWN, "%s cooldown is fair on %s" % [data.id, difficulty.id])
	for id: StringName in extra_card_ids:
		var found := false
		for card in DefeatCodex.get_all_cards():
			if card["id"] == id:
				found = true
				check(not str(card.get("hint", "")).is_empty(), "codex card gives a strategy hint: %s" % id)
		check(found, "codex card exists: %s" % id)


## 關卡配置檢查：expected 是 { 關卡路徑: [敵人 id, 欄起點, 欄終點] 清單 }，每筆至少有一個配置落在欄範圍內，
## 而且第一次遭遇的左邊有安全空間。
func check_level_placement(expected: Dictionary) -> void:
	for path: String in expected.keys():
		var layout := LevelBuilder.parse(load(path) as LevelData)
		for entry: Array in expected[path]:
			var found := false
			for cell in PlacementChecks.cells_of(layout, StringName(entry[0])):
				if cell.x >= int(entry[1]) and cell.x < int(entry[2]):
					found = true
					check(PlacementChecks.first_encounter_clear(layout, cell), "%s at column %d has a safe space on its left in %s" % [entry[0], cell.x, path])
			check(found, "%s is placed within columns %d..%d of %s" % [entry[0], entry[1], entry[2], path])


## 三種難度下都能擊敗：生成後打到生命歸零並進入死亡流程。
func check_defeatable_on_every_difficulty(paths: Array) -> void:
	for index in GameState.difficulties.size():
		await open_level(10.0, index)
		for path: String in paths:
			var enemy := spawn(path, 60.0, FLOOR_Y - (60.0 if not (load(path) as EnemyData).uses_gravity else 0.0))
			for i in enemy.data.max_health + 1:
				enemy.hurtbox.receive(lethal())
			check(enemy.is_dying(), "%s can be defeated on %s" % [enemy.data.id, GameState.difficulties[index].id])
		await physics_frames(90)
		await end_level(level)


## 被敵人擊敗：把玩家生命設成 1，跑 run_until 回呼等到死亡，確認死因對應的圖鑑卡片解鎖。
func expect_codex_unlock(cause: StringName, label: String, wait_frames: int) -> void:
	var unlocked: Array[StringName] = []
	var listener := func(id: StringName, _is_new: bool) -> void: unlocked.append(id)
	EventBus.codex_card_unlocked.connect(listener)
	for i in wait_frames:
		await physics_frames(1)
		if level.player.is_dead():
			break
	check(level.player.is_dead() and unlocked.has(cause), "dying to %s unlocks its codex card (%s)" % [label, cause])
	EventBus.codex_card_unlocked.disconnect(listener)
