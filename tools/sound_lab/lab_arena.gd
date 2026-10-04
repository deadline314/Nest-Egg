class_name LabArena
extends Node
## 實驗室的場地：用遊戲真正的關卡、玩家、敵人、HUD 與特效搭一個空曠的場地，情境動作（tools/sound_lab/stage_actions.gd）在這裡做真實動作。
## 放在 SubViewport 底下，所以有自己的畫面與物理世界。不播背景音樂與環境音（避免蓋過正在調的聲音）。
## 玩家永遠不死、不受傷害累積；reset() 把場地還原成乾淨的起點。

const MAP_PATH := "res://tests/fixtures/arena_map.json"
const LIGHTING_PATH := "res://data/lighting/neutral.tres"
const ENEMY_DIR := "res://data/enemies/"
const WEAPON_DIR := "res://data/weapons/"
const TILE := 16.0
const FLOOR_Y := 20.0 * TILE
const PLAYER_TILE := 14.0
const SETTLE_FRAMES := 20

var level: Level
var player: Player
var _environment: Node
var _held: Dictionary = {}


## 建立場地；完成後 player 可用。可以重複呼叫（會先拆掉舊的）。
func build() -> void:
	teardown()
	_environment = LightKit.create_environment()
	add_child(_environment)
	var data := LevelData.new()
	data.id = &"lab_arena"
	data.layout_path = MAP_PATH
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load(LIGHTING_PATH)
	data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	player = level.player
	player.health.setup(999999, 0.0)
	place_player()
	level.hud.visible = true
	# 關卡一進來就會開背景音樂與環境音，場地不要。
	Music.leave_level()
	Music.stop(0.0)
	Ambience.stop_all(0.0)


func teardown() -> void:
	release_all()
	for node in [level, _environment]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	level = null
	player = null
	_environment = null


func is_ready() -> bool:
	return level != null and is_instance_valid(level) and player != null and is_instance_valid(player)


## 還原成乾淨的起點：清掉敵人與靶、玩家回到起點、彈藥補滿、放開按住的按鍵。玩家狀態不對（例如死掉）就整個重建。
func reset() -> void:
	release_all()
	if not is_ready() or player.state == Player.State.DEAD:
		await build()
		return
	clear_targets()
	player.velocity = Vector2.ZERO
	place_player()
	player.health.setup(999999, 0.0)
	player.loadout.refill_all()
	Input.action_release(&"shoot")


func place_player(x_tile := PLAYER_TILE) -> void:
	if player == null:
		return
	player.global_position = Vector2(x_tile * TILE, FLOOR_Y)
	player.velocity = Vector2.ZERO
	player.facing = 1


func enemy_ids() -> PackedStringArray:
	return _resource_ids(ENEMY_DIR)


func weapon_ids() -> PackedStringArray:
	return _resource_ids(WEAPON_DIR)


func _resource_ids(dir: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			ids.append(file.trim_suffix(".tres"))
	ids.sort()
	return ids


## 讀武器資料；找不到時記錄具體位置並回傳 null。
func load_weapon(id: String) -> WeaponData:
	var path := WEAPON_DIR + id + ".tres"
	var weapon := load(path) as WeaponData if ResourceLoader.exists(path) else null
	if weapon == null:
		push_error("[LabArena] 沒有這把武器：%s" % path)
	return weapon


## 把這把武器換成手上唯一的武器（主武器）；不觸發換槍聲。
func use_weapon(id: String) -> WeaponData:
	var weapon := load_weapon(id)
	if weapon != null and player != null:
		player.loadout.reset(weapon)
		player.loadout.refill_all()
	return weapon


## 撿到這把武器並換過去（觸發換槍聲）。
func pick_up_weapon(id: String) -> WeaponData:
	var weapon := load_weapon(id)
	if weapon != null and player != null:
		player.loadout.equip(weapon)
	return weapon


## 在玩家前方（離玩家幾格；負的在後方）生一隻敵人；找不到資料回傳 null。
func spawn_enemy(id: String, tiles_from_player := 6.0) -> Enemy:
	var path := ENEMY_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("[LabArena] 沒有這個敵人：%s" % path)
		return null
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(player.global_position.x + tiles_from_player * TILE, FLOOR_Y)
	level._entities.add_child(enemy)
	return enemy


## 材質靶（打不死，受擊閃白）；tiles_from_player 同上。
func spawn_target(material: StringName, tiles_from_player := 8.0) -> MaterialDummy:
	var dummy := MaterialDummy.new()
	dummy.setup(material)
	dummy.position = Vector2(player.global_position.x + tiles_from_player * TILE, FLOOR_Y)
	level._entities.add_child(dummy)
	return dummy


## 對敵人造成指定傷害（走真實的受擊框，所以受擊聲、特效、反應都照真實規則）。
func damage_enemy(enemy: Enemy, amount: int, weak := false) -> void:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"lab")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	info.weak_hit = weak
	info.origin = player.global_position
	enemy.hurtbox.receive(info)


## 把敵人打到剛好進入可終結的血量（會暈眩）。
func damage_enemy_to_finishable(enemy: Enemy) -> void:
	var threshold := ceili(enemy.health.max_health * enemy.data.finish_health_ratio)
	damage_enemy(enemy, maxi(1, enemy.health.current - threshold))


func clear_targets() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if level != null and level.is_ancestor_of(node):
			node.queue_free()
	for node in get_tree().get_nodes_in_group(&"feel_lab_targets"):
		if level != null and level.is_ancestor_of(node):
			node.queue_free()


# ---------------------------------------------------------------------------
# 模擬按鍵：用遊戲自己的輸入動作，所以走的是真實的玩家程式路徑
# ---------------------------------------------------------------------------

## 按住某個動作；release 才放開。瞄準固定朝右（手把式輸入，不受滑鼠位置影響）。
func hold(action: StringName, strength := 1.0) -> void:
	Input.action_press(action, strength)
	_held[action] = true


func release(action: StringName) -> void:
	Input.action_release(action)
	_held.erase(action)


func release_all() -> void:
	for action: StringName in _held.keys():
		Input.action_release(action)
	_held.clear()
	Input.action_release(&"aim_right")


func aim_right() -> void:
	hold(&"aim_right")


## 按一下（按下、等一個物理影格、放開）。
func tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


## 等指定秒數（受慢動作影響，所以動作與聲音一起放慢）。
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
