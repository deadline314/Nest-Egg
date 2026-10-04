class_name LabArena
extends Node
## 實驗室的場地：用遊戲真正的關卡、玩家、敵人、HUD 與特效搭一個空曠的場地，情境動作（tools/sound_lab/stage_actions.gd）在這裡做真實動作。
## 放在 SubViewport 底下，所以有自己的畫面與物理世界。不播背景音樂與環境音（避免蓋過正在調的聲音）。
## 玩家永遠不死、不受傷害累積；reset() 把場地還原成乾淨的起點。

const MAP_PATH := "res://tests/fixtures/arena_map.json"
const LIGHTING_DIR := "res://data/lighting/"
const DEFAULT_LIGHTING := &"neutral"
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
## 目前場地的光影設定 id 與背景音樂／環境音有沒有開（環境音與音樂情境才會開）。
var lighting_id: StringName = DEFAULT_LIGHTING
var audio_on := false
## 情境放進場地的東西（敵人、靶、道具）：還原場地時一併清掉，不會擋住下一個情境。
var _spawned: Array[Node] = []
var _codex_before: Array = []
var _codex_guarded := false
var _culling_before := true


## 建立場地；完成後 player 可用。可以重複呼叫（會先拆掉舊的）。
## p_lighting 是光影設定 id（data/lighting/<id>.tres，也就是環境音與音樂對應表用的區段 id）；
## with_audio 為 true 時像進遊戲一樣自己播背景音樂與環境音，預設關掉避免蓋過正在調的聲音。
func build(p_lighting: StringName = DEFAULT_LIGHTING, with_audio := false) -> void:
	teardown()
	lighting_id = p_lighting
	audio_on = with_audio
	_guard_codex()
	# 敵人只在畫面內才動（省效能），場地小，一律讓它們動，不依賴有沒有繪圖。
	_culling_before = Enemy.activation_culling_enabled
	Enemy.activation_culling_enabled = false
	_environment = LightKit.create_environment()
	add_child(_environment)
	var data := LevelData.new()
	data.id = &"lab_arena"
	data.layout_path = MAP_PATH
	var zone := LightingZone.new()
	zone.start_tile = 0
	var profile_path := LIGHTING_DIR + String(lighting_id) + ".tres"
	if not ResourceLoader.exists(profile_path):
		push_error("[LabArena] 沒有這個光影設定：%s，改用 %s" % [profile_path, DEFAULT_LIGHTING])
		lighting_id = DEFAULT_LIGHTING
		profile_path = LIGHTING_DIR + String(DEFAULT_LIGHTING) + ".tres"
	zone.profile = load(profile_path)
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
	player._since_block_release = 10.0
	# 關卡一進來就會開背景音樂與環境音；只有音樂與環境音的情境要，其他一律關掉。
	if not audio_on:
		Music.leave_level()
		Music.stop(0.0)
		Ambience.stop_all(0.0)
	# 關卡會把滑鼠游標藏起來換成準星；實驗室要看得到游標。
	UiKit.set_cursor_visible(true)


func _exit_tree() -> void:
	_release_codex()
	Enemy.activation_culling_enabled = _culling_before


## 玩家在場地裡死掉會解鎖敗北圖鑑：場地存在期間不寫進存檔，離開時還原記憶體裡的進度。
func _guard_codex() -> void:
	if _codex_guarded:
		return
	_codex_guarded = true
	_codex_before = DefeatCodex.unlocked_ids()
	DefeatCodex.persist = false


func _release_codex() -> void:
	if not _codex_guarded:
		return
	_codex_guarded = false
	DefeatCodex.restore_unlocked(_codex_before)
	DefeatCodex.persist = true


func teardown() -> void:
	release_all()
	# 舊關卡要先從樹上拿掉：它離開時會通知背景音樂「離開關卡」，要在新關卡進來之前發生，不然會把新關卡的音樂關掉。
	for node in [level, _environment]:
		if node != null and is_instance_valid(node):
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	level = null
	player = null
	_environment = null


func is_ready() -> bool:
	return level != null and is_instance_valid(level) and player != null and is_instance_valid(player)


## 還原成乾淨的起點：清掉敵人與靶、玩家回到起點、彈藥補滿、放開按住的按鍵。玩家狀態不對（例如死掉）就整個重建。
func reset() -> void:
	release_all()
	# 上一個情境用了別的光影或開了音樂，或玩家死了：整個重建回預設場地。
	if not is_ready() or player.state == Player.State.DEAD or audio_on or lighting_id != DEFAULT_LIGHTING:
		await build()
		return
	UiKit.set_cursor_visible(true)
	clear_targets()
	player.cyber.debug_set_ability(null)
	player.velocity = Vector2.ZERO
	place_player()
	player.health.setup(999999, 0.0)
	player.loadout.refill_all()
	# 完美格擋的窗口在「剛放開盾又舉盾」時會縮短，場地還原時當作很久沒舉過盾。
	player._since_block_release = 10.0
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


## 在玩家前方（離玩家幾格；負的在後方）生一隻敵人；lift 是離地高度（飛行敵人用）；找不到資料回傳 null。
func spawn_enemy(id: String, tiles_from_player := 6.0, lift := 0.0) -> Enemy:
	var path := ENEMY_DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("[LabArena] 沒有這個敵人：%s" % path)
		return null
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(player.global_position.x + tiles_from_player * TILE, FLOOR_Y - lift)
	level._entities.add_child(enemy)
	return adopt(enemy) as Enemy


## 在玩家前方生一個場景道具（data/props 或機關資料的路徑，例如 res://data/props/crate.tres）；用關卡自己的生成函式，所以行為和進遊戲一樣。
func spawn_prop(path: String, tiles_from_player := 6.0) -> Node2D:
	if not ResourceLoader.exists(path):
		push_error("[LabArena] 沒有這個道具：%s" % path)
		return null
	var cell := Vector2i(roundi(player.global_position.x / TILE + tiles_from_player), roundi(FLOOR_Y / TILE))
	var prop: Node2D = level._create_prop({"resource": load(path), "cell": cell})
	if prop == null:
		push_error("[LabArena] 關卡不支援這個道具：%s" % path)
		return null
	prop.position = Vector2((float(cell.x) + 0.5) * TILE, FLOOR_Y)
	level._entities.add_child(prop)
	return adopt(prop) as Node2D


## 材質靶（打不死，受擊閃白）；tiles_from_player 同上。
func spawn_target(material: StringName, tiles_from_player := 8.0) -> MaterialDummy:
	var dummy := MaterialDummy.new()
	dummy.setup(material)
	dummy.position = Vector2(player.global_position.x + tiles_from_player * TILE, FLOOR_Y)
	level._entities.add_child(dummy)
	return adopt(dummy) as MaterialDummy


## 對敵人造成指定傷害（走真實的受擊框，所以受擊聲、特效、反應都照真實規則）。
func damage_enemy(enemy: Enemy, amount: int, weak := false) -> void:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"lab")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	info.origin = player.global_position
	var target: Hurtbox = enemy.hurtbox
	if weak:
		# 弱點是另一個受擊框（傷害倍率大於 1 的部位）；沒有弱點部位的敵人就打本體。
		for entry: Dictionary in enemy._parts:
			if (entry["box"] as Hurtbox).damage_scale > 1.0:
				target = entry["box"]
				break
	target.receive(info)


## 把敵人打到剛好進入可終結的血量（會暈眩）。
func damage_enemy_to_finishable(enemy: Enemy) -> void:
	var threshold := ceili(enemy.health.max_health * enemy.data.finish_health_ratio)
	damage_enemy(enemy, maxi(1, enemy.health.current - threshold))


## 一發敵人的子彈從右側打到玩家（走真實的受擊框與格擋判定，所以受傷聲、格擋聲都照真實規則）。
func enemy_bullet_hits_player(amount := 1) -> void:
	var info := DamageInfo.create(amount, Combat.Team.ENEMY, &"lab", Vector2(-120.0, 0.0))
	info.is_projectile = true
	info.origin = player.global_position + Vector2(48.0, -22.0)
	player.hurtbox.receive(info)


## 把情境自己加進場地的節點登記起來，還原場地時會清掉。回傳同一個節點。
func adopt(node: Node) -> Node:
	_spawned.append(node)
	return node


func clear_targets() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
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


## 瞄準某個世界座標（用瞄準動作的強度組出方向，所以走的是和手把一樣的真實瞄準路徑）。
func aim_at(point: Vector2) -> void:
	for action in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		release(action)
	var direction := (point - player.aim_origin()).normalized()
	if absf(direction.x) > 0.01:
		hold(&"aim_right" if direction.x > 0.0 else &"aim_left", absf(direction.x))
	if absf(direction.y) > 0.01:
		hold(&"aim_down" if direction.y > 0.0 else &"aim_up", absf(direction.y))


## 按一下（按下、等一個物理影格、放開）。
func tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


## 等指定秒數（受慢動作影響，所以動作與聲音一起放慢）。
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
