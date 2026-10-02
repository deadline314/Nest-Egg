extends Node
## 無頭冒煙測試：驗證資料完整性，並實際跑過一輪核心遊戲流程。
## 以場景形式執行，與正式遊戲相同（全域單例都已載入）。
## 執行：tools/run_tests.sh（或 godot --headless res://tests/smoke_test.tscn）
## 任何斷言失敗會以非零代碼結束；腳本錯誤由 run_tests.sh 從輸出中偵測。

const LEVEL_PATH := "res://data/levels/level_01.tres"
const ENEMY_DIR := "res://data/enemies"
const WEAPON_DIR := "res://data/weapons"
const HAZARD_SOURCES: Array[StringName] = [&"spikes", &"laser_fence", &"pit"]

var _failures: PackedStringArray = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Nest Egg smoke test ==")
	# 無頭環境沒有畫面，關閉畫面外休眠以便敵人 AI 運作；過場直接結束（劇情另有專門測試）。
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	_test_data()
	_test_level_layout()
	_test_state_machine()
	_test_loadout()
	await _test_rigs()
	await _test_settings_and_bindings()
	await _test_story()
	await _test_gameplay()
	await _test_block_and_parry()
	await _test_dynamic_hud()
	await _test_enemy_behaviours()
	await _test_boss_and_victory()
	await _test_checkpoints_and_difficulties()
	await _test_death_flow()
	print("checks: %d, failures: %d" % [_checks, _failures.size()])
	for failure in _failures:
		printerr("FAIL: " + failure)
	Sfx.stop_all()
	await _frames(2)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# ---------------------------------------------------------------------------

func _test_data() -> void:
	for file in DirAccess.get_files_at(WEAPON_DIR):
		var weapon := load(WEAPON_DIR.path_join(file)) as WeaponData
		_check(weapon != null and weapon.is_valid(), "weapon invalid: %s" % file)
		if weapon != null:
			_check(not weapon.description.is_empty(), "weapon lacks description: %s" % file)
			_check(RigLibrary.weapons().get("weapons", {}).has(weapon.visual_id), "weapon visual missing: %s" % weapon.visual_id)
			_check(Sfx.SOUNDS.has(weapon.fire_sound), "weapon sound missing: %s" % weapon.fire_sound)
			_check(DefeatCodex.has_card(weapon.projectile.source_id) or String(weapon.projectile.source_id).begins_with("player_"),
					"weapon source id not registered: %s" % weapon.projectile.source_id)
	for file in DirAccess.get_files_at(ENEMY_DIR):
		var enemy := load(ENEMY_DIR.path_join(file)) as EnemyData
		_check(enemy != null, "enemy failed to load: %s" % file)
		if enemy == null:
			continue
		_check(enemy.validate().is_empty(), "enemy invalid: %s %s" % [file, enemy.validate()])
		var instance: Object = enemy.behavior.new()
		_check(instance is Enemy, "enemy behaviour is not Enemy: %s" % file)
		if instance is Node:
			(instance as Node).free()
		if enemy.contact_damage > 0:
			_check(DefeatCodex.has_card(enemy.contact_source_id), "codex missing contact card: %s" % enemy.contact_source_id)
		for spec in [enemy.projectile] + enemy.extra_projectiles:
			if spec != null:
				_check(DefeatCodex.has_card(spec.source_id), "codex missing projectile card: %s" % spec.source_id)
	for source in HAZARD_SOURCES:
		_check(DefeatCodex.has_card(source), "codex missing hazard card: %s" % source)
	_check(DefeatCodex.has_card(&"rusher_charge") and DefeatCodex.has_card(&"bomber_blast"), "codex missing ability cards")
	_check(GameState.difficulties.size() == 3, "expected 3 difficulties")
	var tuning := load("res://data/player/player_tuning.tres") as PlayerTuning
	_check(tuning != null, "player tuning failed to load")
	if tuning != null:
		_check(tuning.default_weapon.id == &"pistol", "default weapon is the pistol")
	var ballistic := 0
	var energy := 0
	for file in DirAccess.get_files_at(WEAPON_DIR):
		var weapon := load(WEAPON_DIR.path_join(file)) as WeaponData
		if weapon != null:
			if weapon.is_energy:
				energy += 1
			else:
				ballistic += 1
	_check(ballistic == 6 and energy == 2, "roster is 6 ballistic + 2 energy (got %d + %d)" % [ballistic, energy])


func _test_level_layout() -> void:
	var data := load(LEVEL_PATH) as LevelData
	_check(data != null, "level failed to load")
	var layout := LevelBuilder.parse(data)
	_check(layout.is_valid(), "level layout invalid")
	_check(layout.warnings.is_empty(), "level warnings: %s" % [layout.warnings])
	_check(layout.width == 350 and layout.height == 24, "unexpected level size %dx%d" % [layout.width, layout.height])
	_check(layout.checkpoints.size() >= 4, "level has enough checkpoints")
	_check(not layout.boss_spawn.is_empty() and layout.arena_x > 0.0, "boss arena missing")
	_check(layout.hints.size() == data.hints.size(), "not every hint placed")
	_check(layout.solid_rects.size() < 80, "solid rect merge ineffective: %d" % layout.solid_rects.size())
	var kinds := {}
	for spawn in layout.spawns:
		var res: Resource = spawn["resource"]
		if res is EnemyData:
			kinds[(res as EnemyData).id] = true
	_check(kinds.size() == 6, "expected 6 enemy kinds in level, got %s" % [kinds.keys()])


func _test_state_machine() -> void:
	var log: Array[String] = []
	var fsm := StateMachine.new()
	fsm.add(&"a", func(_d: float) -> void: log.append("tick_a"), func() -> void: log.append("enter_a"), func() -> void: log.append("exit_a"))
	fsm.add(&"b", func(_d: float) -> void: log.append("tick_b"), func() -> void: log.append("enter_b"))
	fsm.start(&"a")
	fsm.tick(0.1)
	fsm.transition(&"b")
	fsm.tick(0.1)
	fsm.transition(&"missing")
	_check(log == ["enter_a", "tick_a", "exit_a", "enter_b", "tick_b"], "state machine order: %s" % [log])
	_check(fsm.is_in(&"b") and is_equal_approx(fsm.time_in_state, 0.1), "state machine time")


func _test_loadout() -> void:
	var rifle := load("res://data/weapons/pistol.tres") as WeaponData
	var spread := load("res://data/weapons/spread.tres") as WeaponData
	var laser := load("res://data/weapons/laser.tres") as WeaponData
	var loadout := Loadout.new()
	loadout.reset(rifle)
	loadout.equip(spread)
	_check(loadout.active_weapon() == spread and loadout.ammo_in(1) == spread.max_ammo, "equip new weapon")
	loadout.equip(laser)
	_check(loadout.slot_count() == 3 and loadout.active_slot == 2, "weapons stack into slots")
	loadout.cycle(1)
	_check(loadout.active_slot == 0, "cycle wraps to primary")
	loadout.cycle(-1)
	_check(loadout.active_slot == 2, "cycle backwards")
	loadout.select(1)
	for i in spread.max_ammo:
		loadout.consume_ammo()
	_check(loadout.active_slot == Loadout.PRIMARY, "auto swap back when empty")
	loadout.cycle(1)
	_check(loadout.active_slot == 2, "cycling skips empty weapons")
	loadout.equip(spread)
	_check(loadout.slot_count() == 3 and loadout.ammo_in(1) == spread.max_ammo, "same weapon refills instead of duplicating")
	var restored := Loadout.new()
	restored.restore(loadout.snapshot(), rifle)
	_check(restored.slot_count() == 3 and restored.weapon_in(2) == laser, "snapshot round trip")
	restored.restore({"weapons": ["res://missing.tres"], "ammo": "bad"}, rifle)
	_check(restored.active_weapon() == rifle, "restore falls back on bad data")


## 骨架角色：定義完整性、零件圖片、IK、裝甲脫落、缺圖容錯。
func _test_rigs() -> void:
	var skeleton := RigLibrary.load_json("res://art/rigs/humanoid.json")
	var bone_names: Dictionary = {}
	for bone: Dictionary in skeleton.get("bones", []):
		bone_names[bone["name"]] = true
	for id in ["rin", "trooper", "grenadier", "enforcer", "warden"]:
		var skin := RigLibrary.character(id)
		_check(not skin.is_empty(), "character definition loads: %s" % id)
		var dir := RigLibrary.character_dir(id)
		for tex_name: String in skin.get("textures", {}).keys():
			var def: Dictionary = skin["textures"][tex_name]
			_check(ResourceLoader.exists(dir.path_join(def["file"])), "part image exists: %s/%s" % [id, def["file"]])
			if def.has("glow"):
				_check(ResourceLoader.exists(dir.path_join(def["glow"])), "glow image exists: %s/%s" % [id, def["glow"]])
		for part: Dictionary in skin.get("parts", []):
			_check(bone_names.has(part["bone"]), "part bone exists: %s.%s" % [id, part["name"]])
	for weapon_id: String in RigLibrary.weapons().get("weapons", {}).keys():
		var wdef := RigLibrary.weapon(weapon_id)
		_check(ResourceLoader.exists("res://art/weapons/".path_join(wdef["file"])), "weapon image exists: %s" % weapon_id)

	var holder := Node2D.new()
	get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	_check(rig.setup("rin"), "rig builds")
	rig.set_weapon("rifle")
	var input := RigInput.new()
	input.aim_dir = Vector2(1, -1).normalized()
	for i in 30:
		rig.animate(1.0 / 60.0, input)
	await _frames(1)
	var hand := rig.bone(&"hand_front").global_position
	var grip := rig.weapon_root().global_position
	_check(hand.distance_to(grip) < 1.5, "front hand IK reaches weapon grip (%.2f)" % hand.distance_to(grip))
	_check(rig.muzzle_global().x > 8.0 and rig.muzzle_global().y < -30.0, "muzzle in front of rig when aiming up-right")
	var armor := rig.armor_count()
	_check(armor >= 4, "rig has breakable armor")
	rig.set_armor_ratio(0.5, false)
	var visible := 0
	for node in rig.find_children("armor_*", "Sprite2D", true, false):
		if (node as Sprite2D).visible:
			visible += 1
	_check(visible == ceili(armor * 0.5), "armor hides by health ratio")
	holder.queue_free()

	_check(RigLibrary.texture("res://art/missing_part.png", Vector2i(8, 8)) != null, "missing part falls back to placeholder")
	var broken := CharacterRig.new()
	_check(not broken.setup("no_such_character"), "unknown character fails gracefully")
	broken.free()


func _test_story() -> void:
	for id: String in Story.speaker_ids():
		var portrait := str(Story.speaker(id).get("portrait", ""))
		_check(ResourceLoader.exists(portrait), "speaker portrait exists: %s" % id)
	for scene_id: String in Story.scene_ids():
		for line: Dictionary in Story.scene_lines(StringName(scene_id)):
			_check(Story.speaker_ids().has(line.get("speaker", "")), "scene %s uses known speaker" % scene_id)
	var data := load(LEVEL_PATH) as LevelData
	for scene_id in [data.intro_scene, data.boss_scene, data.outro_scene]:
		_check(Story.has_scene(scene_id), "level scene exists: %s" % scene_id)
	for scene_id in data.story_triggers:
		_check(Story.has_scene(StringName(scene_id)), "trigger scene exists: %s" % scene_id)
	var layout := LevelBuilder.parse(data)
	_check(layout.story_triggers.size() == data.story_triggers.size(), "every & trigger mapped to a scene")

	# 過場：暫停遊戲、可推進到結束、結束後恢復
	Story.auto_skip = false
	Story.reset_progress()
	var finished := [&""]
	var on_finished := func(id: StringName) -> void: finished[0] = id
	Story.scene_finished.connect(on_finished)
	_check(Story.play(&"prologue"), "cinematic starts")
	await _frames(1)
	_check(get_tree().paused and Story.is_cinematic_active(), "cinematic pauses the game")
	for i in 40:
		Story._layer.advance()
	await _frames(1)
	_check(finished[0] == &"prologue" and not get_tree().paused, "cinematic advances to the end and unpauses")
	_check(not Story.play(&"prologue"), "seen scenes are not replayed")
	Story.reset_progress()
	Story.play(&"boss_intro")
	await _frames(1)
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	_check(not Story.is_cinematic_active() and finished[0] == &"boss_intro", "escape skips the cinematic")
	_check(Story.play(&"radio_start") and not get_tree().paused, "radio plays without pausing")
	Story.scene_finished.disconnect(on_finished)
	Story.auto_skip = true
	Story.reset_progress()

	# 關卡觸發點
	var level := await _start_level()
	var first: Dictionary = layout.story_triggers[0]
	level.player.global_position = Vector2(first["x"] + 20.0, 300.0)
	await _frames(3)
	_check(Story.was_seen(first["scene"]), "map trigger plays its scene")
	_check(Story.was_seen(data.intro_scene), "intro plays when entering the level")
	await _end_level(level)


## 設定與改鍵：改用測試專用設定檔，結束後還原，不影響玩家設定。
func _test_settings_and_bindings() -> void:
	var original_path := Settings.storage_path()
	var test_path := "user://smoke_test_settings.cfg"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	Settings.use_storage(test_path)
	InputBindings.reload_from_settings()

	Settings.set_volume(&"SFX", 0.5)
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_check(sfx_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.5)), "sfx volume applied")
	Settings.set_volume(&"Master", 0.0)
	_check(AudioServer.is_bus_mute(0), "zero volume mutes")

	var swapped := InputBindings.set_code(&"jump", 0, KEY_J)
	_check(swapped == &"shoot" and InputBindings.get_code(&"shoot", 1) == KEY_SPACE, "rebinding swaps conflicting key")
	var probe := InputEventKey.new()
	probe.physical_keycode = KEY_J
	_check(InputMap.event_is_action(probe, &"jump") and not InputMap.event_is_action(probe, &"shoot"), "InputMap updated after rebind")
	_check(InputBindings.set_code(&"jump", 0, KEY_ESCAPE) == &"" and InputBindings.get_code(&"jump", 0) == KEY_J, "reserved key rejected")
	_check(InputBindings.set_code(&"jump", 0, KEY_2) == &"", "weapon number keys reserved")
	_check(InputBindings.format("{jump}跳") == "J跳", "placeholder formatting")
	_check(InputBindings.format("{shoot}") == "左鍵", "mouse button label")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	_check(InputMap.event_is_action(trigger, &"shoot") and InputBindings.joy_label(&"shoot") == "RT", "gamepad trigger shoots")
	var swapped_mouse := InputBindings.set_code(&"melee", 1, -MOUSE_BUTTON_LEFT)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_check(swapped_mouse == &"shoot" and InputMap.event_is_action(click, &"melee"), "mouse buttons bindable and swappable")
	InputBindings.reset_to_defaults()
	InputBindings.set_code(&"jump", 0, KEY_J)
	_check(InputBindings.set_joy_button(&"jump", JOY_BUTTON_X) == &"interact" and InputBindings.get_joy_button(&"interact") == JOY_BUTTON_A, "gamepad swap")
	InputBindings.set_code(&"melee", 0, InputBindings.NONE)
	InputBindings.set_code(&"melee", 1, InputBindings.NONE)
	_check(InputBindings.get_code(&"melee", 0) == KEY_F, "action never left unbound")

	Settings.save_now()
	var config := ConfigFile.new()
	_check(config.load(test_path) == OK and int(config.get_value("input", "jump", {}).get("codes", [0])[0]) == KEY_J, "bindings persisted")
	InputBindings.reload_from_settings()
	_check(InputBindings.get_code(&"jump", 0) == KEY_J, "bindings reload from disk")
	Settings.set_value("input", "dash", "garbage")
	InputBindings.reload_from_settings()
	_check(InputBindings.get_code(&"dash", 0) == KEY_SHIFT, "corrupt binding falls back to default")
	Settings.set_value("input", InputBindings.SCHEMA_KEY, 1)
	InputBindings.reload_from_settings()
	_check(InputBindings.get_code(&"jump", 0) == KEY_SPACE, "old-schema bindings replaced by new defaults")

	var data := load(LEVEL_PATH) as LevelData
	for hint in data.hints:
		_check(not InputBindings.format(hint).contains("{"), "hint placeholder unresolved: %s" % hint)
	_check(not Hud.controls_hint().contains("{"), "controls hint placeholder unresolved")

	# 設定畫面：模擬點擊改鍵與 Esc 取消
	var screen := SettingsScreen.new()
	get_tree().root.add_child(screen)
	await _frames(2)
	screen._begin_capture(&"dash", 1)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	screen._input(key)
	_check(InputBindings.get_code(&"dash", 1) == KEY_G, "settings screen captures key")
	screen._begin_capture(&"melee", 1)
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	screen._input(middle)
	_check(InputBindings.get_code(&"melee", 1) == -MOUSE_BUTTON_MIDDLE, "settings screen captures mouse button")
	screen._begin_capture(&"dash", 1)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	screen._input(esc)
	_check(InputBindings.get_code(&"dash", 1) == KEY_G and not screen._capturing, "escape cancels capture")
	screen.close()
	await _frames(1)

	InputBindings.reset_to_defaults()
	_check(InputBindings.get_code(&"jump", 0) == KEY_SPACE and InputBindings.get_joy_button(&"jump") == JOY_BUTTON_A, "reset to defaults")
	Settings.reset_audio()
	Settings.save_now()
	Settings.use_storage(original_path)
	InputBindings.reload_from_settings()
	DirAccess.remove_absolute(test_path)


# ---------------------------------------------------------------------------

func _start_level() -> Level:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	get_tree().root.add_child(level)
	await _frames(2)
	return level


func _end_level(level: Level) -> void:
	for action in [&"move_right", &"shoot", &"jump", &"aim_right", &"aim_left", &"block"]:
		Input.action_release(action)
	if is_instance_valid(level):
		get_tree().root.remove_child(level)
		level.free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	await _frames(2)


func _test_gameplay() -> void:
	var level := await _start_level()
	var player := level.player
	_check(is_instance_valid(player), "player spawned")
	var start_x := player.global_position.x
	var hits := [0]
	EventBus.hit_confirmed.connect(func(_p: Vector2, _k: bool) -> void: hits[0] += 1)
	# 以右搖桿瞄準向右（無頭環境沒有滑鼠）。
	Input.action_press(&"aim_right")
	Input.action_press(&"move_right")
	Input.action_press(&"shoot")
	await _frames(30)
	_check(ProjectilePool.active_count() > 0, "rifle spawns projectiles")
	_check(player.aim_dir.x > 0.9 and player.facing == 1, "player aims and faces stick direction")
	Input.action_press(&"jump")
	await _frames(10)
	Input.action_release(&"jump")
	await _frames(40)
	Input.action_release(&"move_right")
	Input.action_release(&"shoot")
	_check(player.global_position.x > start_x + 40.0, "player moves right")
	_check(not player.is_dead(), "player alive after short run")
	_check(hits[0] > 0, "hit markers fire when bullets land")
	Input.action_release(&"aim_right")
	Input.action_press(&"aim_left")
	await _frames(3)
	_check(player.facing == -1, "player turns to face aim")
	# 衝刺期間無敵
	Input.action_press(&"dash")
	await _frames(2)
	Input.action_release(&"dash")
	var dash_hp := player.health.current
	player.hurtbox.receive(DamageInfo.create(1, Combat.Team.ENEMY, &"grunt_shot"))
	_check(player.state == Player.State.DASH and player.health.current == dash_hp, "dash grants invulnerability")
	await _frames(20)
	Input.action_release(&"aim_left")
	Input.action_press(&"aim_right")

	# 武器撿取與彈藥
	var spread := load("res://data/weapons/spread.tres") as WeaponData
	player.loadout.equip(spread)
	Input.action_press(&"shoot")
	await _frames(20)
	Input.action_release(&"shoot")
	_check(player.loadout.ammo_in(1) < spread.max_ammo, "special weapon consumes ammo")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await _frames(2)
	_check(player.loadout.active_slot == 0, "mouse wheel cycles weapons")
	var two := InputEventKey.new()
	two.physical_keycode = KEY_2
	two.pressed = true
	Input.parse_input_event(two)
	await _frames(2)
	_check(player.loadout.active_slot == 1, "number keys select weapon")
	var two_up := two.duplicate() as InputEventKey
	two_up.pressed = false
	Input.parse_input_event(two_up)

	# 載具：瞬移到機甲旁搭乘、射擊、下車
	var vehicle: Vehicle = null
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		vehicle = node as Vehicle
	_check(vehicle != null, "vehicle exists")
	if vehicle != null:
		player.global_position = vehicle.global_position + Vector2(-8, -2)
		await _frames(2)
		Input.action_press(&"interact")
		await _frames(1)
		Input.action_release(&"interact")
		await _frames(2)
		_check(player.state == Player.State.MOUNTED and vehicle.driver == player, "player mounts vehicle")
		Input.action_press(&"shoot")
		await _frames(20)
		Input.action_release(&"shoot")
		await _frames(20)
		Input.action_press(&"interact")
		await _frames(1)
		Input.action_release(&"interact")
		await _frames(2)
		_check(player.state != Player.State.MOUNTED and vehicle.driver == null, "player dismounts vehicle")

	# 坑洞：掉落後回到安全位置並扣血
	var hp := player.health.current
	player.global_position = Vector2(player.global_position.x, player.fall_limit_y + 10.0)
	await _frames(2)
	_check(player.health.current < hp and player.global_position.y < player.fall_limit_y, "pit damages and respawns")
	await _frames(2)
	var debris := 0
	for node in level.find_children("*", "RigDebris", true, false):
		debris += 1
	_check(debris > 0, "lost armor flies off as debris")
	await _end_level(level)


func _shoot_at_player(player: Player, from_offset: Vector2) -> Projectile:
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	var origin := player.aim_origin() + from_offset
	return ProjectilePool.spawn(spec, origin, (player.aim_origin() - origin).normalized(), Combat.Team.ENEMY)


func _test_block_and_parry() -> void:
	var level := await _start_level()
	var player := level.player
	player.health.setup(10, 0.0)
	player.global_position = Vector2(300, 320)
	# 清掉關卡原有的敵人，讓格擋測試只受測試子彈影響。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.free()
	Input.action_press(&"aim_right")
	await _frames(5)
	Input.action_press(&"block")
	await _frames(2)
	_check(player.is_blocking and player.is_parry_window(), "block raises shield with parry window")


	var parried := _shoot_at_player(player, Vector2(14, 0))
	await _frames(3)
	_check(parried.team == Combat.Team.PLAYER and parried.velocity.x > 0.0 and player.health.current == 10, "perfect parry reflects bullet toward aim")

	await _frames(15)
	var guard_before := player.guard
	var blocked := _shoot_at_player(player, Vector2(14, 0))
	await _frames(3)
	_check(not blocked.active and player.health.current == 10 and player.guard < guard_before, "block stops bullet and drains guard")

	# 敵人瞄準身體中心（低於肩膀）時也要擋得住。
	await _frames(20)
	var low_hp := player.health.current
	var spec_low := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	ProjectilePool.spawn(spec_low, player.global_position + Vector2(14, -22), Vector2.LEFT, Combat.Team.ENEMY)
	await _frames(3)
	_check(player.health.current == low_hp, "block covers shots aimed at body centre")

	var behind := _shoot_at_player(player, Vector2(-14, 0))
	await _frames(3)
	_check(player.health.current == 9 and not behind.active, "attacks from behind are not blocked")

	Input.action_press(&"shoot")
	var ammo_projectiles := ProjectilePool.active_count()
	await _frames(6)
	_check(ProjectilePool.active_count() <= ammo_projectiles, "cannot shoot while blocking")
	Input.action_release(&"shoot")

	player.guard = 1.0
	_shoot_at_player(player, Vector2(14, 0))
	await _frames(3)
	_check(player.state == Player.State.STAGGERED and not player.is_blocking, "guard break staggers player")
	await _frames(60)
	_check(not player.is_blocking, "guard locked out after break")
	Input.action_release(&"block")

	await _frames(100)
	Input.action_release(&"block")
	await _frames(2)
	Input.action_press(&"block")
	await _frames(2)
	var hp := player.health.current
	Fx.explosion(player.global_position + Vector2(10, -12), 30.0, 1, Combat.Team.ENEMY, &"bomber_blast")
	await _frames(4)
	_check(player.health.current == hp - 1, "explosions ignore the shield")

	# 完美格擋接觸攻擊會讓攻擊者暈眩
	Input.action_release(&"block")
	await _frames(40)
	var grunt_data := load(ENEMY_DIR.path_join("grunt.tres")) as EnemyData
	var grunt := grunt_data.behavior.new() as Enemy
	grunt.configure(grunt_data)
	grunt.position = player.global_position + Vector2(30, 0)
	player.get_parent().add_child(grunt)
	await _frames(2)
	Input.action_press(&"block")
	await _frames(1)
	grunt.global_position = player.global_position + Vector2(6, 0)
	await _frames(3)
	_check(grunt.is_stunned(), "parrying a contact attack stuns the attacker")
	Input.action_release(&"block")
	await _end_level(level)


## 動態 HUD：閒置淡出、變動彈出、危險常駐；彈藥環只跟著有限彈藥武器出現。
func _test_dynamic_hud() -> void:
	var presence := HudPresence.new()
	presence.poke()
	presence.update(0.5, false, true)
	_check(presence.alpha > 0.9, "hud presence pops in after a change")
	for i in 40:
		presence.update(0.1, false, true)
	_check(is_equal_approx(presence.alpha, presence.idle_alpha), "hud presence fades to idle")
	presence.update(0.5, true, true)
	_check(presence.alpha > 0.9, "hud presence holds while in danger")
	presence.update(0.5, false, false)
	_check(presence.alpha > 0.9, "hud presence stays visible when auto hide is off")
	presence.update(0.5, false, true, true)
	_check(presence.alpha < 0.01, "hud presence hides when hidden")

	var level := await _start_level()
	var player := level.player
	var vitals := level.hud.vitals_tag
	var ring := level.hud.ammo_ring
	_check(vitals != null and ring != null, "hud creates dynamic widgets")
	_check(vitals.max_health == player.health.max_health and vitals.health == player.health.current, "vitals tag mirrors health")
	var info := DamageInfo.create(1, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _frames(2)
	_check(vitals.health == player.health.current and vitals.presence.is_lingering(), "damage pops the vitals tag")
	while player.health.current > 1:
		player.health.take_damage(info)
	await _frames(2)
	_check(vitals.is_low_health(), "low health detected for persistent warning")

	_check(not ring.is_showing_ammo(), "ammo ring hidden for infinite primary")
	player.loadout.equip(load(WEAPON_DIR.path_join("spread.tres")) as WeaponData)
	await _frames(1)
	_check(ring.is_showing_ammo() and ring.ammo == ring.max_ammo, "ammo ring shows limited weapon")
	var before := ring.ammo
	player.loadout.consume_ammo()
	_check(ring.ammo < before, "ammo ring follows consumption")
	while player.loadout.active_slot != Loadout.PRIMARY:
		player.loadout.consume_ammo()
	_check(not ring.is_showing_ammo(), "ammo ring hides after weapon runs dry")

	var original := Settings.get_hud_auto_hide()
	Settings.set_hud_auto_hide(false)
	_check(not vitals._auto_hide, "vitals tag follows auto hide setting")
	Settings.set_hud_auto_hide(original)
	await _end_level(level)


## 把每種敵人放在玩家附近跑一段時間，走過各自的 AI 狀態與攻擊。
func _test_enemy_behaviours() -> void:
	var level := await _start_level()
	var player := level.player
	player.health.setup(999, 0.2)
	var arena := Vector2(1200, 320)
	player.global_position = arena
	var entities := player.get_parent()
	var spawned: Array[Enemy] = []
	var offset := -120.0
	for file in DirAccess.get_files_at(ENEMY_DIR):
		var data := load(ENEMY_DIR.path_join(file)) as EnemyData
		if data.is_boss:
			continue
		var enemy := data.behavior.new() as Enemy
		enemy.configure(data)
		enemy.position = arena + Vector2(offset, -40.0 if not data.uses_gravity else 0.0)
		offset += 50.0
		entities.add_child(enemy)
		spawned.append(enemy)
	var states_seen := {}
	for i in 360:
		await get_tree().physics_frame
		for enemy in spawned:
			if is_instance_valid(enemy):
				states_seen["%s:%s" % [enemy.data.id, enemy.fsm.current]] = true
	_check(not player.is_dead(), "player survives enemy test with big health")
	_check(states_seen.size() >= 10, "enemies exercised several states: %s" % [states_seen.keys()])
	# 終結技：把一隻敵人打到破防後終結
	var target: Enemy = null
	for enemy in spawned:
		if is_instance_valid(enemy) and enemy.data.finish_health_ratio > 0.0 and not enemy.health.is_dead:
			target = enemy
			break
	if target != null:
		var info := DamageInfo.create(target.health.current - 1, Combat.Team.PLAYER, &"test")
		info.bypass_guard = true
		target.hurtbox.receive(info)
		_check(target.can_be_finished(), "enemy becomes finishable")
		player.global_position = target.global_position + Vector2(-20, 0)
		var finishers := GameState.finishers
		Input.action_press(&"melee")
		await _frames(1)
		Input.action_release(&"melee")
		await _frames(30)
		_check(GameState.finishers == finishers + 1, "finisher counted")
	# 盾牌：正面打不到
	var rusher_data := load(ENEMY_DIR.path_join("shield_rusher.tres")) as EnemyData
	var rusher := rusher_data.behavior.new() as Enemy
	rusher.configure(rusher_data)
	rusher.position = arena + Vector2(300, 0)
	entities.add_child(rusher)
	await _frames(1)
	rusher.facing = -1
	var front := DamageInfo.create(1, Combat.Team.PLAYER, &"test")
	front.origin = rusher.global_position + Vector2(-30, 0)
	_check(rusher.hurtbox.receive(front) == Hurtbox.Result.BLOCKED, "shield blocks frontal hit")
	var back := DamageInfo.create(1, Combat.Team.PLAYER, &"test")
	back.origin = rusher.global_position + Vector2(30, 0)
	_check(rusher.hurtbox.receive(back) == Hurtbox.Result.DAMAGED, "shield exposes back")
	await _end_level(level)


func _test_boss_and_victory() -> void:
	var level := await _start_level()
	var completed := [false]
	level.completed.connect(func() -> void: completed[0] = true)
	var player := level.player
	player.health.setup(999, 0.5)
	var layout := LevelBuilder.parse(level.data)
	player.global_position = Vector2(layout.arena_x + 80.0, 300.0)
	await _frames(90)
	var boss: Enemy = null
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.is_boss:
			boss = enemy
	_check(boss != null, "boss spawned after entering arena")
	if boss == null:
		await _end_level(level)
		return
	_check(level.camera.limit_left == int(layout.arena_x), "camera locked to arena")
	var attacks := {}
	for i in 600:
		await get_tree().physics_frame
		if is_instance_valid(boss):
			attacks[boss.fsm.current] = true
		if i == 300 and is_instance_valid(boss):
			var half := DamageInfo.create(boss.health.max_health / 2, Combat.Team.PLAYER, &"test")
			boss.hurtbox.receive(half)
	_check(attacks.size() >= 4, "boss used several states: %s" % [attacks.keys()])
	if is_instance_valid(boss):
		var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
		lethal.bypass_guard = true
		lethal.ignore_invulnerability = true
		boss.health.take_damage(lethal)
	# 擊敗後：延遲 → 結尾過場（測試中自動跳過）→ 章節結束卡 → 結算。
	for i in 720:
		await get_tree().physics_frame
		if completed[0]:
			break
	_check(completed[0], "level completes after boss defeat")
	await _end_level(level)


## 每個檢查點都能站穩；三種難度都能打完頭目進入結算。
func _test_checkpoints_and_difficulties() -> void:
	var layout := LevelBuilder.parse(load(LEVEL_PATH))
	var level := await _start_level()
	for checkpoint in layout.checkpoints:
		level.player.global_position = checkpoint + Vector2(0, -2)
		level.player.velocity = Vector2.ZERO
		await _frames(20)
		_check(level.player.is_on_floor() and absf(level.player.global_position.y - checkpoint.y) < 4.0,
				"player stands at checkpoint %s" % checkpoint)
	await _end_level(level)
	for difficulty in GameState.difficulties:
		GameState.start_new_run(difficulty)
		var run := Level.new()
		run.configure(load(LEVEL_PATH))
		get_tree().root.add_child(run)
		await _frames(2)
		var completed := [false]
		run.completed.connect(func() -> void: completed[0] = true)
		run.player.health.setup(999, 0.5)
		run.player.global_position = Vector2(layout.arena_x + 80.0, 300.0)
		var boss: Enemy = null
		for i in 240:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group(&"enemies"):
				if node is Enemy and (node as Enemy).data.is_boss:
					boss = node
			if boss != null:
				break
		if boss != null:
			var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
			lethal.ignore_invulnerability = true
			lethal.bypass_guard = true
			boss.health.take_damage(lethal)
		for i in 720:
			await get_tree().physics_frame
			if completed[0]:
				break
		_check(completed[0], "level completes on %s difficulty" % difficulty.display_name)
		await _end_level(run)


func _test_death_flow() -> void:
	var level := await _start_level()
	var player := level.player
	var info := DamageInfo.create(999, Combat.Team.ENEMY, &"grunt_shot")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	_check(player.is_dead(), "player dies")
	await _frames(120)
	var found := false
	for child in level.get_children():
		if child is DeathScreen:
			found = true
	_check(found, "death screen shown")
	# 暫停選單 → 設定 → 關閉
	var pause_menu: PauseMenu = null
	for child in level.get_children():
		if child is PauseMenu:
			pause_menu = child
	pause_menu.open()
	pause_menu._open_settings()
	await _frames(2)
	_check(is_instance_valid(pause_menu._settings) and get_tree().paused, "settings opens from pause menu")
	pause_menu.close()
	await _frames(2)
	_check(not get_tree().paused and not is_instance_valid(pause_menu._settings), "closing pause also closes settings")
	_check(GameState.deaths == 1, "death registered")
	await _end_level(level)
