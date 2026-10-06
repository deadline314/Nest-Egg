extends Node
## 無頭冒煙測試：驗證資料完整性，並實際跑過一輪核心遊戲流程。
## 以場景形式執行，與正式遊戲相同（全域單例都已載入）。
## 執行：tools/run_tests.sh（或 godot --headless res://tests/smoke_test.tscn）
## 任何斷言失敗會以非零代碼結束；腳本錯誤由 run_tests.sh 從輸出中偵測。

const LEVEL_PATH := "res://data/levels/level_01.tres"
const ENEMY_DIR := "res://data/enemies"
const WEAPON_DIR := "res://data/weapons"
const HAZARD_SOURCES: Array[StringName] = [&"spikes", &"laser_fence", &"pit", &"explosive_barrel", &"flood"]

var _failures: PackedStringArray = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Nest Egg smoke test ==")
	# 無頭環境沒有畫面，關閉畫面外休眠以便敵人 AI 運作；過場直接結束（劇情另有專門測試）。
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	var only := _only_suite()
	if only == "list":  # 列出所有套件名稱給平行執行器分組（-- --only=list）
		print("SUITES: %s" % ",".join(PackedStringArray(_suites().map(func(suite: TestSuite) -> String: return str(suite.get_script().get_global_name())))))
		get_tree().quit(0)
		return
	if only == "block":  # 只跑格擋與反彈的檢查（-- --only=block）
		await _test_block_and_parry()
		await _finish()
		return
	if only != "":
		# 逗號分隔：套件類別名稱，加上 main（開頭那一大段不屬於任何套件的流程測試）。
		if only.split(",", false).has("main"):
			await _run_main()
		await _run_suites(only)
		await _finish()
		return
	await _run_main()
	await _run_suites("")
	await _finish()


## 不屬於任何套件的流程測試（資料、關卡、狀態機、武器欄、角色、設定、劇情、核心玩法、機關、死亡流程…）。
func _run_main() -> void:
	var started := Time.get_ticks_msec()
	_test_data()
	_test_level_layout()
	_test_state_machine()
	_test_loadout()
	await _test_rigs()
	await _test_settings_and_bindings()
	await _test_story()
	await _test_story_items()
	await _test_gameplay()
	await _test_block_and_parry()
	await _test_dynamic_hud()
	await _test_consumables()
	await _test_inventory()
	await _test_lighting()
	await _test_enemy_behaviours()
	await _test_boss_and_victory()
	await _test_checkpoints_and_difficulties()
	await _test_death_flow()
	print("SUITE_TIME main %.1f" % (float(Time.get_ticks_msec() - started) / 1000.0))


func _finish() -> void:
	print("checks: %d, failures: %d" % [_checks, _failures.size()])
	for failure in _failures:
		printerr("FAIL: " + failure)
	# 無頭模式的影格很快：延遲出聲的聲音層（命中尾音等）可能在停止之後才開始播，音訊執行緒也來不及放掉剛停掉的播放實例，
	# 結束時就會報資源還在使用。先等延遲的聲音層出完、停掉全部、再等一小段實際時間讓播放實例釋放。
	await get_tree().create_timer(0.2, true, false, true).timeout
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)


## 功能套件（tests/suite/）。開發時可用 `-- --only=套件類別名` 只跑其中一份（逗號分隔可以跑多份），例如 UiKitSuite。
func _suites() -> Array[TestSuite]:
	return [
		PropsSuite.new(self), NewEnemiesSuite.new(self), CollectiblesSuite.new(self),
		ProgressionSuite.new(self), SupplySuite.new(self), ReclaimerSuite.new(self),
		Chapter2Suite.new(self), UiKitSuite.new(self), TransitionSuite.new(self), UiScreensSuite.new(self), CutsceneSuite.new(self), EnvironmentSuite.new(self), AmmoIconsSuite.new(self), AmmoTraySuite.new(self), CombatHudSuite.new(self), ChapterCutscenesSuite.new(self),
		NpcSuite.new(self), NpcAnimationSuite.new(self), RigActionsSuite.new(self), EnemyVfxSuite.new(self), StoryLintSuite.new(self), StoryContentSuite.new(self), DeathReactionSuite.new(self), DeathFlowSuite.new(self), ContinuitySuite.new(self), MapBubblesSuite.new(self), AttackTokensSuite.new(self), EncounterSuite.new(self), HitReactionSuite.new(self), PostureSuite.new(self), AnimAuditSuite.new(self), ProtagonistMotionSuite.new(self), LocomotionSuite.new(self), PhoneBoothSuite.new(self), PartCreatureSuite.new(self), ChainCreatureSuite.new(self), ExoticEnemiesSuite.new(self), Chapter2ExpansionSuite.new(self), Chapter2ArtSuite.new(self), FeelSuite.new(self), MeleeSuite.new(self), MeleeWeaponsSuite.new(self), StrikeEnemiesSuite.new(self), FxUpgradesSuite.new(self), FxMeleePickupsSuite.new(self), FeelLabSuite.new(self), InputFeelSuite.new(self), FeelToolsSuite.new(self), AudioSuite.new(self), MusicSuite.new(self), ReloadCuesSuite.new(self), SoundLabSuite.new(self), ClipEditorSuite.new(self), ApplyPanelSuite.new(self), LayerOrderSuite.new(self), SoundStageSuite.new(self), StageCoverageWeaponsSuite.new(self), StageCoverageCharactersSuite.new(self), StageCoverageWorldSuite.new(self), DevMenuSuite.new(self),
		CharactersSuite.new(self), ReconEnemiesSuite.new(self), HeavyEnemiesSuite.new(self), AssaultEnemiesSuite.new(self),
		WorldPromptSuite.new(self), AreasSuite.new(self), Chapter1EnemiesSuite.new(self), FloodPitSuite.new(self), Chapter1MapSuite.new(self),
	]


func _only_suite() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.trim_prefix("--only=")
	return ""


func _run_suites(only: String) -> void:
	var wanted := only.split(",", false)
	for suite in _suites():
		var suite_name := str(suite.get_script().get_global_name())
		if only == "" or wanted.has(suite_name):
			var started := Time.get_ticks_msec()
			await suite.run()
			# 平行執行器用這行時間把套件平均分給各個程序。
			print("SUITE_TIME %s %.1f" % [suite_name, float(Time.get_ticks_msec() - started) / 1000.0])


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
	for original: StringName in [&"grunt", &"shield_rusher", &"drone", &"turret", &"bomber", &"mortar"]:
		_check(kinds.has(original), "level has the original enemy kind %s (got %s)" % [original, kinds.keys()])


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
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	var spread := load("res://data/weapons/spread.tres") as WeaponData
	var laser := load("res://data/weapons/laser.tres") as WeaponData
	var loadout := Loadout.new()
	loadout.reset(pistol)
	_check(loadout.mag_in(0) == 12 and loadout.reserve_in(0) < 0, "pistol starts with 12-round magazine and infinite reserve")
	var fired := 0
	for i in 12:
		if loadout.consume_ammo():
			fired += 1
	_check(fired == 12, "pistol fires 12 shots per magazine")
	_check(loadout.mag_in(0) == 0 and loadout.is_reloading(), "empty magazine starts reload automatically")
	_check(not loadout.consume_ammo(), "cannot fire while reloading")
	for i in 120:
		loadout.tick(1.0 / 60.0)
	_check(not loadout.is_reloading() and loadout.mag_in(0) == 12, "reload refills magazine")

	loadout.equip(spread)
	_check(loadout.active_weapon() == spread and loadout.mag_in(1) == spread.magazine_size and loadout.reserve_in(1) == spread.max_reserve, "equip new weapon")
	loadout.consume_ammo()
	_check(loadout.start_reload() and loadout.is_reloading(), "manual reload with partial magazine")
	loadout.select(0)
	_check(not loadout.is_reloading(), "switching weapons cancels reload")
	loadout.select(1)
	loadout.start_reload()
	for i in 200:
		loadout.tick(1.0 / 60.0)
	_check(loadout.mag_in(1) == spread.magazine_size and loadout.reserve_in(1) == spread.max_reserve - 1, "reload takes rounds from reserve")
	_check(not loadout.start_reload(), "full magazine does not reload")
	loadout.equip(laser)
	_check(loadout.slot_count() == 3 and loadout.active_slot == 2, "weapons stack into slots")
	loadout.cycle(1)
	_check(loadout.active_slot == 0, "cycle wraps to primary")
	loadout.cycle(-1)
	_check(loadout.active_slot == 2, "cycle backwards")
	loadout.select(1)
	var guard := 0
	while loadout.active_slot == 1 and guard < 500:
		guard += 1
		if not loadout.consume_ammo():
			loadout.tick(5.0)
	_check(loadout.active_slot == Loadout.PRIMARY and loadout.mag_in(1) == 0 and loadout.reserve_in(1) == 0, "auto swap back when magazine and reserve run dry")
	loadout.cycle(1)
	_check(loadout.active_slot == 2, "cycling skips empty weapons")
	loadout.equip(spread)
	_check(loadout.slot_count() == 3 and loadout.reserve_in(1) == spread.max_reserve, "same weapon refills reserve instead of duplicating")
	loadout.refill_ratio(0.5)
	var restored := Loadout.new()
	restored.restore(loadout.snapshot(), pistol)
	_check(restored.slot_count() == 3 and restored.weapon_in(2) == laser and restored.mag_in(1) == loadout.mag_in(1)
			and restored.reserve_in(1) == loadout.reserve_in(1), "snapshot round trip keeps magazine and reserve")
	restored.restore({"weapons": ["res://data/weapons/pistol.tres", "res://data/weapons/spread.tres"], "ammo": [-1, 10], "active": 1}, pistol)
	_check(restored.mag_in(1) == spread.magazine_size and restored.reserve_in(1) == 10 - spread.magazine_size, "legacy snapshot converts total ammo")
	restored.restore({"weapons": ["res://missing.tres"], "mag": "bad"}, pistol)
	_check(restored.active_weapon() == pistol, "restore falls back on bad data")


func _test_rigs() -> void:
	for id in ["rin", "trooper", "grenadier", "enforcer", "warden"]:
		var skin := RigLibrary.character(id)
		_check(not skin.is_empty(), "character definition loads: %s" % id)
		# 角色可以有自己的骨架（監管者的肩甲骨頭）；沒寫就用共用的人形骨架。
		var skeleton := RigLibrary.load_json(str(skin.get("rig", "res://art/rigs/humanoid.json")))
		var bone_names: Dictionary = {}
		for bone: Dictionary in skeleton.get("bones", []):
			bone_names[bone["name"]] = true
		var dir := RigLibrary.character_dir(id)
		for tex_name: String in skin.get("textures", {}).keys():
			var def: Dictionary = skin["textures"][tex_name]
			_check(ResourceLoader.exists(dir.path_join(def["file"])), "part image exists: %s/%s" % [id, def["file"]])
			if def.has("glow"):
				_check(ResourceLoader.exists(dir.path_join(def["glow"])), "glow image exists: %s/%s" % [id, def["glow"]])
		# 零件掛的骨頭以角色自己的骨架為準（含專屬骨頭，NE-89）；骨架家族的名稱也都要在。
		var own_bones: Dictionary = {}
		for bone: Dictionary in RigLibrary.load_json(str(skin.get("rig", ""))).get("bones", []):
			own_bones[bone["name"]] = true
		for part: Dictionary in skin.get("parts", []):
			_check(own_bones.has(part["bone"]), "part bone exists: %s.%s" % [id, part["name"]])
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
	var armor_total := 0
	for node in rig.find_children("armor_*", "Sprite2D", true, false):
		armor_total += 1
	rig.set_armor_ratio(0.5, false)
	var visible := 0
	for node in rig.find_children("armor_*", "Sprite2D", true, false):
		if (node as Sprite2D).visible:
			visible += 1
	_check(visible > 0 and visible < armor_total, "armor hides by health ratio (%d of %d pieces left at half health)" % [visible, armor_total])
	holder.queue_free()

	_check(RigLibrary.texture("res://art/missing_part.png", Vector2i(8, 8)) != null, "missing part falls back to placeholder")
	var broken := CharacterRig.new()
	_check(not broken.setup("no_such_character"), "unknown character fails gracefully")
	broken.free()


func _filler_lines(count: int) -> Array:
	var lines: Array = []
	for i in count:
		lines.append({"speaker": "rin", "text": "測試 %d" % i})
	return lines


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

	# 多章節：章節資訊分開、講者與場景合併、劇本守則（句數、講者、頭像）全部通過。
	_check(Story.validate().is_empty(), "story passes validation %s" % Story.validate())
	_check(Story.chapter_ids().has(&"chapter_01") and Story.chapter_ids().has(&"chapter_02"), "both chapters are loaded")
	for chapter_id in Story.chapter_ids():
		var info := Story.chapter_info(chapter_id)
		for key in ["title", "subtitle", "end_title", "teaser"]:
			_check(not str(info.get(key, "")).is_empty(), "chapter %s has %s" % [chapter_id, key])
	_check(Story.chapter_info(&"chapter_02").get("title") != Story.chapter_info(&"chapter_01").get("title"), "chapters have their own titles")
	_check(Story.has_scene(&"prologue") and Story.has_scene(&"c2_prologue"), "scenes of both chapters are available")
	for scene_id in [&"c2_prologue", &"c2_boss_intro", &"c2_epilogue"]:
		_check(str(Story._scenes[String(scene_id)].get("mode")) == "cinematic", "chapter 2 scene is a cinematic: %s" % scene_id)
	for speaker_id in ["wataru", "reclaimer"]:
		_check(Story.speaker_ids().has(speaker_id), "chapter 2 speaker defined: %s" % speaker_id)
	# 守則檢查真的會抓到違規：過場太長、通訊太長、講者未定義。
	Story._scenes["test_long_cinematic"] = {"mode": "cinematic", "lines": _filler_lines(7)}
	Story._scenes["test_long_radio"] = {"mode": "radio", "lines": _filler_lines(3)}
	Story._scenes["test_bad_speaker"] = {"mode": "radio", "lines": [{"speaker": "nobody", "text": "x"}]}
	var problems := Story.validate()
	_check(problems.size() == 3, "story validation catches 3 violations (got %d)" % problems.size())
	for scene_id in ["test_long_cinematic", "test_long_radio", "test_bad_speaker"]:
		Story._scenes.erase(scene_id)
	_check(Story.validate().is_empty(), "story validation clean again")
	_check(Story.chapter_info(&"no_such_chapter").is_empty(), "unknown chapter returns empty info")

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
func _test_story_items() -> void:
	var catalog := StoryItems.catalog()
	_check(catalog.size() == 26, "story item catalog loads 26 items (got %d)" % catalog.size())
	var ids: Dictionary[StringName, bool] = {}
	var last_order := -INF
	for item in catalog:
		_check(item.validate().is_empty(), "story item valid: %s %s" % [item.id, item.validate()])
		_check(not ids.has(item.id), "story item id unique: %s" % item.id)
		ids[item.id] = true
		_check(item.order >= last_order, "story items sorted by order: %s" % item.id)
		last_order = item.order
		_check(ResourceLoader.exists(ItemIcons.ICON_DIR.path_join(item.icon + ".png")), "story item icon exists: %s" % item.id)
		if item.trigger == StoryItemData.Trigger.SCENE_FINISHED:
			_check(Story.has_scene(item.trigger_scene), "story item scene exists: %s -> %s" % [item.id, item.trigger_scene])

	# 開局只持有「開場就有」的道具，且不跳提示。
	var toasts: Array[String] = []
	var on_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	GameState.start_new_run(GameState.difficulties[1])
	_check(StoryItems.owns(&"wataru_photo") and StoryItems.owns(&"nest_egg_chip"), "run start grants the starting items")
	_check(not StoryItems.owns(&"old_k_order") and not StoryItems.owns(&"nest07_shard"), "later items not owned at run start")
	_check(toasts.is_empty(), "starting items grant silently")
	_check(StoryItems.owned_items().size() == 2, "owned items listed")

	# 取得：未知與重複都安全回傳 false；提示只跳一次。
	_check(not StoryItems.acquire(&"no_such_item"), "unknown story item is rejected")
	_check(not StoryItems.acquire(&"wataru_photo"), "owned story item is not granted twice")
	_check(StoryItems.acquire(&"old_k_order") and toasts.size() == 1 and toasts[0].contains("老K的委託單"), "acquire announces the item")
	_check(not StoryItems.acquire(&"old_k_order") and toasts.size() == 1, "repeat acquire does not announce again")
	GameState.start_new_run(GameState.difficulties[1])
	_check(not StoryItems.owns(&"old_k_order"), "new run resets story items")

	# 劇情場景播完才取得委託單。
	Story.reset_progress()
	_check(not StoryItems.owns(&"old_k_order"), "order not owned before the opening scene")
	Story.play(&"cut_c1_shop")
	await _frames(3)
	_check(StoryItems.owns(&"old_k_order"), "opening scene finishing grants the order")
	_check(toasts.filter(func(t: String) -> bool: return t.contains("老K的委託單")).size() >= 1, "scene grant announces the item")
	EventBus.toast_requested.disconnect(on_toast)

	# 進關卡後持有開場道具；重開關卡（不重置一輪）保留已取得的道具。
	var level := await _start_level()
	await _frames(4)
	_check(StoryItems.owns(&"wataru_photo") and StoryItems.owns(&"nest_egg_chip") and StoryItems.owns(&"old_k_order"), "level start holds photo, chip and order")
	_check(not StoryItems.owns(&"nest07_shard"), "shard not owned before the boss")
	await _end_level(level)
	var retry := Level.new()
	retry.configure(load(LEVEL_PATH))
	get_tree().root.add_child(retry)
	await _frames(4)
	_check(StoryItems.owned_items().size() == 3, "reloading the level keeps acquired items")
	await _end_level(retry)

	# 資料目錄載入器：壞檔、型別不符、重複 id 都略過且不影響其他資料。
	var dir := "user://test_catalog"
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	var good := StoryItemData.new()
	good.id = &"fixture_a"
	good.display_name = "A"
	good.description = "a"
	good.order = 2
	ResourceSaver.save(good, dir.path_join("a.tres"))
	var early := StoryItemData.new()
	early.id = &"fixture_b"
	early.display_name = "B"
	early.description = "b"
	early.order = 1
	ResourceSaver.save(early, dir.path_join("b.tres"))
	var duplicate := StoryItemData.new()
	duplicate.id = &"fixture_a"
	ResourceSaver.save(duplicate, dir.path_join("c_duplicate.tres"))
	ResourceSaver.save(ConsumableData.new(), dir.path_join("d_wrong_type.tres"))
	var loaded := ResourceCatalog.load_dir(dir, StoryItemData, "test_catalog")
	_check(loaded.size() == 2 and loaded[0].get(&"id") == &"fixture_b" and loaded[1].get(&"id") == &"fixture_a", "catalog sorts by order and skips duplicate and wrong-type files")
	_check(ResourceCatalog.load_dir("user://no_such_catalog_dir", StoryItemData, "test_catalog").is_empty(), "missing catalog folder yields an empty list")
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))


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
	_check(player.loadout.mag_in(1) < spread.magazine_size or player.loadout.reserve_in(1) < spread.max_reserve, "special weapon consumes ammo")
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
	Fx.thaw_all()
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
	# 瞄準身體中心（受擊框的中央）：瞄準起點會隨外觀高度改變，可能高過受擊框。
	var center := player.global_position + Vector2(0, -Player.BODY_SIZE.y * 0.5)
	var origin := center + from_offset
	return ProjectilePool.spawn(spec, origin, (center - origin).normalized(), Combat.Team.ENEMY)


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

	await _frames(8)  # 格擋有短暫頓幀，等它過去
	var behind := _shoot_at_player(player, Vector2(-14, 0))
	await _frames(8)
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

	_check(ring.is_showing_ammo() and ring.max_ammo == 12 and ring.reserve < 0, "ammo ring shows pistol magazine")
	player.loadout.equip(load(WEAPON_DIR.path_join("spread.tres")) as WeaponData)
	await _frames(1)
	_check(ring.is_showing_ammo() and ring.ammo == ring.max_ammo, "ammo ring shows new weapon magazine")
	var before := ring.ammo
	player.loadout.consume_ammo()
	_check(ring.ammo < before, "ammo ring follows consumption")
	var safety := 0
	while player.loadout.active_slot != Loadout.PRIMARY and safety < 500:
		safety += 1
		if not player.loadout.consume_ammo():
			player.loadout.tick(5.0)
	_check(ring.max_ammo == 12, "ammo ring returns to pistol after weapon runs dry")
	Fx.thaw_all()  # 前面的命中可能還在頓幀，玩家被凍結時收不到輸入
	Input.action_press(&"reload")
	player.loadout.consume_ammo()
	var reload_event := InputEventAction.new()
	reload_event.action = &"reload"
	reload_event.pressed = true
	Input.parse_input_event(reload_event)
	for i in 4:
		await get_tree().process_frame
	Input.action_release(&"reload")
	_check(player.is_reloading(), "reload key starts reload")
	await _frames(70)
	_check(not player.is_reloading() and player.loadout.mag_in(0) == 12, "reload finishes in game time")

	var original := Settings.get_hud_auto_hide()
	Settings.set_hud_auto_hide(false)
	_check(not vitals._auto_hide, "vitals tag follows auto hide setting")
	Settings.set_hud_auto_hide(original)
	await _end_level(level)


## 消耗品：攜帶上限、快速使用、滿血不浪費、護盾電池、檢查點保存。
func _test_consumables() -> void:
	var catalog := ConsumableBag.catalog()
	_check(catalog.size() >= 2, "consumable catalog loads")
	for item in catalog:
		_check(item.validate().is_empty(), "consumable invalid: %s" % item.id)
	var med := ConsumableBag.find(&"med_injector")
	var cell := ConsumableBag.find(&"shield_cell")
	_check(med != null and cell != null and med.quick_use, "med injector and shield cell defined")
	var bag := ConsumableBag.new()
	for i in med.max_carry:
		bag.add(med)
	_check(not bag.add(med) and bag.count(med.id) == med.max_carry, "carry limit enforced")
	var copy := ConsumableBag.new()
	copy.restore(bag.snapshot())
	_check(copy.count(med.id) == med.max_carry, "consumable snapshot round trip")
	copy.restore({"med_injector": 99, "unknown": 3})
	_check(copy.count(med.id) == med.max_carry, "restore clamps and ignores unknown items")

	var level := await _start_level()
	var player := level.player
	# 等開場演出結束（演出期間遊戲暫停，不接受操作）。
	while get_tree().paused:
		await get_tree().process_frame
	await _frames(2)
	player.consumables.add(med)
	player.consumables.add(cell)
	_check(not player.use_consumable(med.id) and player.consumables.count(med.id) == 1, "med injector not wasted at full health")
	var info := DamageInfo.create(2, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	var hurt_hp := player.health.current
	var use_event := InputEventAction.new()
	use_event.action = &"use_item"
	use_event.pressed = true
	await _frames(2)  # 受傷的頓幀在傷害之後才套上，等它出現再解除
	Fx.reset_time()
	Fx.thaw_all()
	Input.parse_input_event(use_event)
	# 輸入事件在 idle 影格處理；只等物理影格可能還沒輪到。
	for i in 4:
		await get_tree().process_frame
	_check(player.health.current == hurt_hp + med.heal_amount and player.consumables.count(med.id) == 0, "quick-use key heals with med injector")
	player.guard = 0.0
	player._guard_lockout_left = 1.0
	_check(player.use_consumable(cell.id) and is_equal_approx(player.guard, player.tuning.guard_max) and player._guard_lockout_left == 0.0, "shield cell restores guard and clears break")
	player.consumables.add(med)
	var snapshot := player.checkpoint_snapshot()
	_check(snapshot.has("consumables") and int(snapshot["consumables"].get("med_injector", 0)) == 1, "checkpoint saves consumables")
	await _end_level(level)


## 模擬按下／放開一個動作（輸入事件在 idle 影格處理，所以等幾個 process 影格）。
func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		for i in 3:
			await get_tree().process_frame


func _test_inventory() -> void:
	# 資料：每個圖示、武器圖與立繪分層都存在，按鍵有預設值。
	for item in ConsumableBag.catalog():
		_check(ResourceLoader.exists(ItemIcons.ICON_DIR.path_join(item.icon + ".png")), "consumable icon exists: %s" % item.id)
	for file in DirAccess.get_files_at(WEAPON_DIR):
		var weapon := load(WEAPON_DIR.path_join(file)) as WeaponData
		if weapon != null:
			_check(ResourceLoader.exists(ItemIcons.WEAPON_DIR.path_join(weapon.visual_id + ".png")), "weapon icon exists: %s" % weapon.visual_id)
	for layer in ItemIcons.PORTRAIT_LAYERS:
		_check(ResourceLoader.exists(ItemIcons.PORTRAIT_DIR.path_join("rin_%s.png" % layer)), "portrait layer exists: %s" % layer)
		_check(ItemIcons.portrait_layer("rin", layer).get_size() == Vector2(ItemIcons.PORTRAIT_SIZE), "portrait layer size: %s" % layer)
	_check(ItemIcons.item("no_such_icon").get_size() == Vector2(ItemIcons.ICON_SIZE), "missing icon falls back to a placeholder of the same size")
	_check(InputBindings.get_code(&"inventory", 0) == KEY_TAB and InputBindings.get_code(&"inventory", 1) == KEY_I, "inventory key defaults to Tab and I")
	_check(InputMap.has_action(&"inventory_prev_tab") and InputMap.has_action(&"inventory_next_tab"), "inventory tab actions registered")

	var level := await _start_level()
	while get_tree().paused:
		await get_tree().process_frame
	await _frames(2)
	var player := level.player
	var inventory: InventoryScreen = level._inventory
	var smg := load("res://data/weapons/smg.tres") as WeaponData
	var spread := load("res://data/weapons/spread.tres") as WeaponData
	player.loadout.equip(smg)
	player.loadout.equip(spread)
	_check(inventory != null and not inventory.is_open() and not get_tree().paused, "inventory starts closed")

	# 開關：Tab 開啟並暫停，再按一次關閉並繼續。
	await _press_action(&"inventory")
	_check(inventory.is_open() and get_tree().paused, "inventory key opens the bag and pauses the game")
	await _press_action(&"inventory")
	_check(not inventory.is_open() and not get_tree().paused, "inventory key closes the bag and resumes")
	await _press_action(&"inventory")
	await _press_action(&"pause")
	_check(not inventory.is_open() and not get_tree().paused and not level._pause_menu._root.visible, "escape closes the bag without opening the pause menu")

	# 分頁：Q／E 切換並循環，每頁都有標題與提示。
	await _press_action(&"inventory")
	var tab_count: int = inventory._pages.size()
	_check(tab_count >= 5, "bag has its tabs (%d)" % tab_count)
	for page in inventory._pages:
		_check(not page.tab_title().is_empty() and not page.tab_tooltip().is_empty(), "tab has a title and tooltip")
	_check(inventory._current == 0, "bag opens on the weapons tab")
	await _press_action(&"inventory_next_tab")
	_check(inventory._current == 1, "next-tab key moves to the second tab")
	await _press_action(&"inventory_prev_tab")
	await _press_action(&"inventory_prev_tab")
	_check(inventory._current == tab_count - 1, "previous-tab key wraps around from the first tab")
	inventory.select_tab(0)

	# 武器分頁：四個欄位、手上武器標記、選另一把並確認後換成手上武器。
	var weapons: WeaponsPage = inventory._pages[0]
	_check(weapons._entries.size() == Loadout.MAX_SLOTS, "weapons tab lists every slot")
	_check(weapons._entries[player.loadout.active_slot].badge == "手上", "active weapon is marked")
	_check(weapons._entries[3].dimmed and weapons._entries[3].action_label.is_empty(), "empty slot is dimmed and has no action")
	weapons._select(0)
	_check(weapons._entries[0].action_enabled or player.loadout.active_slot == 0, "other weapons can be equipped")
	await _press_action(&"ui_accept")
	_check(player.loadout.active_slot == 0 and player.loadout.active_weapon().id == &"pistol", "confirming a weapon equips it")
	weapons._select(1)
	await _press_action(&"ui_accept")
	_check(player.loadout.active_weapon() == smg, "bag swaps the held weapon")
	weapons._select(3)
	var held := player.loadout.active_slot
	weapons.activate()
	_check(player.loadout.active_slot == held, "empty slot cannot be equipped")

	# 消耗品分頁：滿血不會用掉；受傷後使用回血、數量減少。
	inventory.select_tab(inventory.page_index(ConsumablesPage))
	var med := ConsumableBag.find(&"med_injector")
	player.consumables.add(med)
	var consumables: ConsumablesPage = inventory._pages[inventory.page_index(ConsumablesPage)]
	consumables.refresh()
	consumables._select(0)
	consumables.activate()
	_check(player.consumables.count(med.id) == 1, "bag does not waste a med injector at full health")
	var hurt := DamageInfo.create(3, Combat.Team.ENEMY, &"test")
	hurt.ignore_invulnerability = true
	player.health.take_damage(hurt)
	var hp := player.health.current
	consumables.activate()
	_check(player.health.current == hp + med.heal_amount and player.consumables.count(med.id) == 0, "using a med injector in the bag heals")
	consumables.activate()
	_check(consumables._entries[0].dimmed and not consumables._entries[0].action_enabled, "empty consumable is dimmed and cannot be used")

	# 劇情道具分頁：新取得的標 NEW，看過後取消。
	inventory.select_tab(inventory.page_index(StoryItemsPage))
	var story_page: StoryItemsPage = inventory._pages[inventory.page_index(StoryItemsPage)]
	_check(story_page._entries.size() == StoryItems.owned_items().size() and story_page._entries.size() >= 2, "story tab lists owned items")
	_check(story_page._entries[0].badge == "NEW" and StoryItems.new_count() > 0, "new story items are flagged")
	var first_id := story_page._entries[0].id
	story_page.navigate(Vector2i(0, 1))
	_check(not StoryItems.is_new(first_id) and story_page._entries[0].badge.is_empty(), "viewing a story item clears its NEW flag")
	_check(story_page._entries[1].action_label.is_empty(), "story items have no action")

	# 角色狀態分頁：數字取自這一輪的紀錄。
	inventory.select_tab(inventory.page_index(StatusPage))
	var status: StatusPage = inventory._pages[inventory.page_index(StatusPage)]
	GameState.kills = 7
	status.refresh()
	await get_tree().create_timer(0.1, true).timeout
	_check(status._values[&"kills"].text.begins_with("7"), "status tab shows kills")
	_check(status._values[&"health"].text == "%d / %d" % [player.health.current, player.health.max_health], "status tab shows health")
	_check(status._values[&"difficulty"].text == GameState.difficulty.display_name, "status tab shows difficulty")
	await _press_action(&"inventory")
	_check(not inventory.is_open() and not get_tree().paused, "bag closes from any tab")

	# 倒下時背包關閉並鎖住。
	await _press_action(&"inventory")
	_check(inventory.is_open(), "bag reopens")
	var lethal := DamageInfo.create(999, Combat.Team.ENEMY, &"test")
	lethal.ignore_invulnerability = true
	player.health.take_damage(lethal)
	await _frames(3)
	_check(not inventory.is_open() and not inventory.allowed, "death closes and locks the bag")
	await _press_action(&"inventory")
	_check(not inventory.is_open(), "bag cannot open after death")
	await _end_level(level)


## 場景光源群組中目前啟用的光源數與開著陰影的光源數。
func _count_scene_lights() -> Array[int]:
	var lights := 0
	var shadows := 0
	for light: PointLight2D in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
		if light.visible and light.enabled and light.is_visible_in_tree():
			lights += 1
			shadows += 1 if light.shadow_enabled else 0
	return [lights, shadows]


## 圓形的法線貼圖測試圖（16×16，中間一個實心圓，邊緣有透明）。
func _make_blob_normal() -> Image:
	var source := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8)) < 6.0:
				source.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))
	return NormalMapMaker.make(source, 2, 3.0, 0.0)


func _test_lighting() -> void:
	# 資料：所有光影設定與第一關的區段都有效。
	var profile_count := 0
	for file in DirAccess.get_files_at("res://data/lighting"):
		var profile := load("res://data/lighting/".path_join(file.trim_suffix(".remap"))) as LightingProfile
		_check(profile != null and profile.validate().is_empty(), "lighting profile valid: %s" % file)
		profile_count += 1
	_check(profile_count >= 8, "lighting profiles present (got %d)" % profile_count)
	# 光影預設 → 場景背景的對應表（BG-14）：每個預設存在，且至少列一個場景。
	var preview_problems := LightingSceneScenario.validate()
	_check(preview_problems.is_empty(), "lighting preview scenes map is valid: %s" % [preview_problems])
	_check(not LightingSceneScenario.entries().is_empty(), "lighting preview scenes map lists scenes")
	var data := load(LEVEL_PATH) as LevelData
	_check(data.lighting_zones.size() == 5, "level 1 has five lighting zones")
	_check(data.validate_lighting().is_empty(), "level lighting zones valid: %s" % [data.validate_lighting()])
	var bad := LightingProfile.new()
	bad.ambient_color = Color(-1, 0, 0)
	bad.glow_threshold = 0.0
	_check(bad.validate().size() >= 2, "invalid lighting profile is reported")
	var unsorted := LevelData.new()
	var late := LightingZone.new()
	late.start_tile = 50
	late.profile = LightingProfile.new()
	var early := LightingZone.new()
	early.start_tile = 10
	early.profile = LightingProfile.new()
	unsorted.lighting_zones = [late, early]
	_check(not unsorted.validate_lighting().is_empty(), "unsorted lighting zones are reported")

	# 控制器遇到壞區段不崩潰，退回預設（全亮）。
	var broken := LightingController.new()
	get_tree().root.add_child(broken)
	var empty_zone := LightingZone.new()
	empty_zone.start_tile = 987654
	broken.setup([empty_zone], 16, null, null, null, null, Color.WHITE)
	var probe := LightingProfile.new()
	broken.zone_state_at(0.0, probe)
	_check(probe.ambient_color == Color.WHITE, "broken lighting zone falls back to neutral lighting")
	get_tree().root.remove_child(broken)
	broken.free()

	var level := await _start_level()
	while get_tree().paused:
		await get_tree().process_frame
	await _frames(2)
	var lighting: LightingController = level._lighting
	var ambient := level.get_node("Ambient") as CanvasModulate
	var tile := float(level._layout.tile_size)
	var zones := data.lighting_zones
	_check(lighting != null and ambient != null, "level builds the lighting controller and ambient light")

	# 每個區段中段是該區段的設定；邊界上是兩者的中點；跨越邊界沒有跳變。
	for i in zones.size():
		var from_x := float(zones[i].start_tile) * tile + float(zones[i].blend_tiles) * tile
		var to_x := float(zones[i + 1].start_tile) * tile - float(zones[i + 1].blend_tiles) * tile if i + 1 < zones.size() else from_x + 400.0
		lighting.zone_state_at((from_x + to_x) * 0.5, probe)
		_check(probe.ambient_color.is_equal_approx(zones[i].profile.ambient_color) and is_equal_approx(probe.fog_density, zones[i].profile.fog_density),
				"zone %d settings apply in the middle of the zone" % i)
	var boundary := float(zones[1].start_tile) * tile
	lighting.zone_state_at(boundary, probe)
	_check(probe.ambient_color.is_equal_approx(zones[0].profile.ambient_color.lerp(zones[1].profile.ambient_color, 0.5)), "zone boundary blends halfway")
	var previous := Color.BLACK
	var largest_step := 0.0
	var x := boundary - 300.0
	while x < boundary + 300.0:
		lighting.zone_state_at(x, probe)
		if x > boundary - 300.0:
			largest_step = maxf(largest_step, absf(probe.ambient_color.r - previous.r) + absf(probe.ambient_color.g - previous.g) + absf(probe.ambient_color.b - previous.b))
		previous = probe.ambient_color
		x += 4.0
	_check(largest_step < 0.03, "crossing a zone boundary changes lighting smoothly (largest step %.3f)" % largest_step)

	# 環境光與背景、霧、泛光跟著玩家所在區段。
	_check(ambient.color.is_equal_approx(zones[0].profile.ambient_color), "ambient light starts with the first zone")
	# 設施入口停電走廊之前的一段（頭目機庫會觸發警報覆蓋，另外測）。
	var follow := 3
	level.player.global_position = Vector2(252.0 * tile, level.player.global_position.y)
	# 光影以平滑過渡追上玩家所在區段；最多等 2 秒，避免依賴幀率造成偶發失敗。
	for i in 120:
		await get_tree().process_frame
		if ambient.color.is_equal_approx(zones[follow].profile.ambient_color):
			break
	_check(ambient.color.is_equal_approx(zones[follow].profile.ambient_color), "ambient light follows the player into the facility zone")
	_check(level._background.modulate.is_equal_approx(zones[follow].profile.background_tint), "background tint follows the zone")
	_check(is_equal_approx(level._fog.density, zones[follow].profile.fog_density) and level._fog.color.is_equal_approx(zones[follow].profile.fog_color), "fog follows the zone")
	_check(is_equal_approx(LightKit.environment().glow_hdr_threshold, zones[follow].profile.glow_threshold), "glow follows the zone")

	# 後製：調色、暗角、顆粒與色差跟著區段；畫在場景之上、介面之下。
	var post: PostProcess = level._post
	_check(post != null and post.is_active(), "post-processing is active")
	var grade: LightingProfile = zones[follow].profile
	# 顆粒與色差依光影品質縮放（中、低檔關閉），預期值要乘上目前品質的倍率，不能假設這台機器的設定是高檔。
	var effects := LightQuality.post_effects()
	_check(is_equal_approx(post.parameter(&"vignette"), grade.vignette) and is_equal_approx(post.parameter(&"saturation"), grade.saturation)
			and is_equal_approx(post.parameter(&"contrast"), grade.contrast) and is_equal_approx(post.parameter(&"grain"), grade.grain * effects)
			and is_equal_approx(post.parameter(&"aberration"), grade.aberration * effects), "grade, vignette, grain and aberration follow the zone")
	var shadow: Vector3 = post.parameter(&"shadow_tint")
	_check(is_equal_approx(shadow.x, grade.shadow_tint.r) and is_equal_approx(shadow.z, grade.shadow_tint.b), "shadow tint follows the zone")
	_check(post.layer < level.hud.layer and level.hud.layer < level._inventory.layer and level._inventory.layer < level._pause_menu.layer, "post-processing sits under the HUD and menus")
	var shader_code := (post._material.shader as Shader).code
	_check(shader_code.contains("hint_screen_texture") and shader_code.contains("uniform float vignette") and shader_code.contains("uniform float grain"), "post shader reads the screen and exposes grade parameters")
	var bad_grade := LightingProfile.new()
	bad_grade.grain = -0.1
	bad_grade.contrast = 0.0
	_check(bad_grade.validate().size() >= 2, "invalid grade values are reported")
	var scratch := LightingProfile.new()
	LightingProfile.blend_into(scratch, zones[0].profile, zones[1].profile, 0.5)
	_check(is_equal_approx(scratch.vignette, lerpf(zones[0].profile.vignette, zones[1].profile.vignette, 0.5)), "grade values blend between zones")

	# 事件覆蓋：淡入、取代同 id、淡出後回到區段光影。
	var blackout := load("res://data/lighting/blackout.tres") as LightingProfile
	EventBus.lighting_override_requested.emit(&"blackout", blackout, 0.2)
	await get_tree().create_timer(0.5, true).timeout
	_check(ambient.color.is_equal_approx(blackout.ambient_color) and lighting.has_override(&"blackout"), "lighting override fades in")
	_check(LightKit.character_fill > 2.0, "characters are lit up in the blackout (fill %.2f)" % LightKit.character_fill)
	var working_lamps := 0
	var lit_lamps := 0
	for node in level._world.get_children():
		var lamp := node as Lamp
		if lamp != null and not lamp.dead:
			working_lamps += 1
			lit_lamps += 1 if lamp._light.enabled else 0
	_check(working_lamps > 0 and lit_lamps == 0, "a blackout switches every working lamp off (%d of %d lit)" % [lit_lamps, working_lamps])
	var alarm := load("res://data/lighting/alarm.tres") as LightingProfile
	EventBus.lighting_override_requested.emit(&"blackout", alarm, 0.1)
	await get_tree().create_timer(0.3, true).timeout
	_check(ambient.color.is_equal_approx(alarm.ambient_color), "override with the same id is replaced")
	EventBus.lighting_override_cleared.emit(&"blackout", 0.2)
	await get_tree().create_timer(0.5, true).timeout
	_check(ambient.color.is_equal_approx(zones[follow].profile.ambient_color) and not lighting.has_override(&"blackout"), "lighting returns to the zone after the override ends")

	# 光源預算與品質：同時啟用的光源與陰影有上限、鏡頭外停用、停電時燈依序熄滅。
	var budget: LightBudget = level._light_budget
	_check(budget != null, "level builds the light budget")
	_check(LightQuality.SETTINGS[LightQuality.Tier.LOW]["max_lights"] < LightQuality.SETTINGS[LightQuality.Tier.MEDIUM]["max_lights"]
			and LightQuality.SETTINGS[LightQuality.Tier.MEDIUM]["max_lights"] < LightQuality.SETTINGS[LightQuality.Tier.HIGH]["max_lights"], "light budget grows with quality")
	for tier in LightQuality.NAMES:
		_check(not LightQuality.DESCRIPTIONS.get(tier, "").is_empty(), "every quality tier has a description")
	_check(not get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS).has(level.player._light), "the player's own light is not budgeted")
	_check(is_equal_approx(LightKit.power_gate(1.0, 0.9), 1.0) and is_equal_approx(LightKit.power_gate(0.0, 0.1), 0.0)
			and LightKit.power_gate(0.5, 0.45) > LightKit.power_gate(0.5, 0.55), "power gate is monotonic")
	var saved_settings := Settings.storage_path()
	Settings.use_storage("user://test_quality.cfg")
	_check(Settings.get_light_quality() == LightQuality.DEFAULT_TIER, "light quality defaults to high")
	for spot_tile in [30, 115, 200, 252, 275, 330]:
		level.player.global_position = Vector2(float(spot_tile) * tile, level.player.global_position.y)
		await get_tree().create_timer(0.4, true).timeout
		budget.refresh()
		var counts := _count_scene_lights()
		_check(counts[0] <= LightQuality.max_lights() and counts[1] <= LightQuality.shadow_lights() and counts[0] == budget.active_lights,
				"light budget holds at tile %d (%d lights, %d shadows)" % [spot_tile, counts[0], counts[1]])
	# 鏡頭外的燈停用、畫面內的燈啟用。
	level.player.global_position = Vector2(30.0 * tile, level.player.global_position.y)
	await get_tree().create_timer(0.5, true).timeout
	budget.refresh()
	var far_off := 0
	var near_on := 0
	var view_center := level.camera.get_screen_center_position()
	for light: PointLight2D in get_tree().get_nodes_in_group(LightKit.SCENE_LIGHTS):
		var dist := absf(light.global_position.x - view_center.x)
		if dist > 900.0:
			far_off += 0 if light.visible else 1
			_check(not light.visible, "a light far outside the camera is switched off")
		elif dist < 150.0 and light.enabled:
			near_on += 1 if light.visible else 0
	_check(far_off > 0 and near_on > 0, "lights far from the camera are off and lights in view are on (%d off, %d on)" % [far_off, near_on])
	# 品質降到低：上限立刻變小，後製顆粒與色差關閉；回到高後恢復。
	Settings.set_light_quality(LightQuality.Tier.LOW)
	var low_counts := _count_scene_lights()
	_check(low_counts[0] <= 8 and low_counts[1] <= 1, "low quality shrinks the light budget (%d lights, %d shadows)" % [low_counts[0], low_counts[1]])
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_zero_approx(post.parameter(&"grain")) and is_zero_approx(post.parameter(&"aberration")), "low quality turns off grain and aberration")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(post.parameter(&"grain") > 0.0, "high quality brings grain back")
	Settings.set_value(Settings.DISPLAY_SECTION, "light_quality", "oops")
	_check(Settings.get_light_quality() == LightQuality.DEFAULT_TIER, "corrupt light quality falls back to the default")
	Settings.set_light_quality(99)
	_check(Settings.get_light_quality() == LightQuality.Tier.HIGH, "light quality is clamped")
	Settings.reset_display()
	_check(Settings.get_light_quality() == LightQuality.DEFAULT_TIER, "reset restores the light quality")
	Settings.use_storage(saved_settings)
	DirAccess.remove_absolute("user://test_quality.cfg")
	# 部分供電：各盞燈依自己的門檻，有的亮有的滅；供電恢復後全部亮起。
	var half_power := LightingProfile.new()
	half_power.id = &"half_power"
	half_power.lamp_power = 0.5
	EventBus.lighting_override_requested.emit(&"half", half_power, 0.1)
	await get_tree().create_timer(0.4, true).timeout
	var half_on := 0
	var half_off := 0
	for node in level._world.get_children():
		var lamp := node as Lamp
		if lamp != null and not lamp.dead:
			if lamp._light.enabled:
				half_on += 1
			else:
				half_off += 1
	_check(half_on > 0 and half_off > 0, "partial power switches some lamps off and keeps others on (%d on, %d off)" % [half_on, half_off])
	EventBus.lighting_override_cleared.emit(&"half", 0.1)
	await get_tree().create_timer(0.4, true).timeout
	var all_on := true
	for node in level._world.get_children():
		var lamp := node as Lamp
		if lamp != null and not lamp.dead:
			all_on = all_on and lamp._light.enabled
	_check(all_on, "restoring power switches every lamp back on")

	var terrain := level.get_node("World/Terrain")

	# 體積光：場景燈有光錐、光暈與地面倒影；砲台的光錐跟著瞄準；低品質關閉；霧被光源染色；前景剪影。
	var shaft_count := 0
	for node in level._world.get_children():
		var lamp := node as Lamp
		if lamp == null:
			continue
		var lamp_shaft: LightShaft = null
		for child in lamp.get_children():
			if child is LightShaft:
				lamp_shaft = child
		if lamp.dead:
			_check(lamp_shaft == null, "dead lamps have no light shaft")
			continue
		shaft_count += 1
		_check(lamp_shaft != null and lamp_shaft.source == lamp._light and lamp_shaft.floor_y == lamp.floor_y, "working lamps have a light shaft tied to their light")
		_check(lamp_shaft.material == LightKit.additive_emissive_material(), "light shafts use the additive emissive material")
	_check(shaft_count > 0, "level has light shafts")
	var test_shaft := LightShaft.new()
	get_tree().root.add_child(test_shaft)
	test_shaft.intensity = 1.0
	_check(test_shaft.visible == LightQuality.volumetrics(), "shaft shows when volumetrics are on")
	test_shaft.intensity = 0.0
	test_shaft._refresh_visibility()
	_check(not test_shaft.visible, "a shaft with no intensity is hidden")
	Settings.use_storage("user://test_volumetrics.cfg")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	test_shaft.intensity = 1.0
	test_shaft._refresh_visibility()
	_check(not test_shaft.visible and not level._foreground.visible, "low quality hides shafts and the foreground layer")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	_check(level._foreground.visible and test_shaft.visible, "high quality shows shafts and the foreground layer")
	Settings.use_storage(saved_settings)
	DirAccess.remove_absolute("user://test_volumetrics.cfg")
	get_tree().root.remove_child(test_shaft)
	test_shaft.free()
	_check(is_equal_approx(level._foreground.ground_y, level._layout.ground_y) and level._foreground.z_index > 8, "foreground layer sits in front of the play field")
	var fog := FogLayer.new()
	fog.color = Color(0.3, 0.3, 0.3)
	var tint_light := LightKit.create_point_light(Color(1.0, 0.0, 0.0), 100.0, 1.0, false, false)
	tint_light.global_position = Vector2(100, 100)
	get_tree().root.add_child(tint_light)
	fog._tint_sources.append(tint_light)
	var near_tint := fog._tinted(Vector2(100, 100))
	_check(near_tint.r > fog.color.r + 0.3 and near_tint.g < fog.color.g, "fog near a light takes the light's color")
	_check(fog._tinted(Vector2(100 + FogLayer.TINT_RANGE + 50.0, 100)).is_equal_approx(fog.color), "fog far from lights keeps its own color")
	get_tree().root.remove_child(tint_light)
	tint_light.free()
	fog.free()
	var turret: Enemy = null
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if (enemy as Enemy).data.id == &"turret":
			turret = enemy
	var turret_shaft: LightShaft = turret.get(&"_shaft") if turret != null else null
	_check(turret_shaft != null, "turrets have a light shaft")
	if turret_shaft != null:
		turret.fsm.transition(&"lock")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_equal_approx(turret_shaft.intensity, 1.0) and turret_shaft.direction == turret.get(&"_aim"), "the turret's shaft brightens and follows its aim when locked")
		turret.fsm.transition(&"idle")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_zero_approx(turret_shaft.intensity), "the turret's shaft goes out when idle")

	# 戰鬥動態光影：爆炸閃光、命中與擊殺點光、低血量暗角、預兆紅光、閃電、減少閃光。
	await get_tree().create_timer(0.6, true).timeout
	var flash_before := ambient.color
	EventBus.ambient_flash_requested.emit(Color(1, 0.8, 0.6), 0.5, 0.3)
	# 閃光依實際時間衰減；機器忙的時候兩影格就過了半個閃光，所以每影格都量，取最亮的那一次。
	var peak_level := 0.0
	var peak_red := flash_before.r
	for i in 3:
		await get_tree().process_frame
		peak_level = maxf(peak_level, lighting.flash_level())
		peak_red = maxf(peak_red, ambient.color.r)
	_check(peak_level > 0.3 and peak_red > flash_before.r + 0.2, "an ambient flash lifts the ambient light")
	for i in 40:  # 以實際時間最多等 2 秒，機器忙時衰減也不會讓測試偶爾失敗
		await get_tree().create_timer(0.05, true).timeout
		if is_zero_approx(lighting.flash_level()):
			break
	await get_tree().process_frame
	_check(is_zero_approx(lighting.flash_level()) and ambient.color.is_equal_approx(lighting.current.ambient_color), "the flash decays back to the zone lighting")
	Fx.explosion(level.player.global_position + Vector2(240, 0), 40.0, 0, Combat.Team.ENEMY, &"test")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lighting.flash_level() > 0.1, "explosions flash the ambient light")
	await get_tree().create_timer(0.5, true).timeout
	EventBus.hit_confirmed.emit(level.player.global_position + Vector2(100, -30), true)
	var kill_light := false
	for fx_light: PointLight2D in Fx._lights:
		kill_light = kill_light or (fx_light.enabled and fx_light.color.is_equal_approx(Palette.WARNING))
	_check(kill_light, "a kill spawns a warm point light")
	EventBus.hit_confirmed.emit(level.player.global_position + Vector2(100, -30), false)
	var hit_light := false
	for fx_light: PointLight2D in Fx._lights:
		hit_light = hit_light or (fx_light.enabled and fx_light.texture_scale < 1.0)
	_check(hit_light, "a hit spawns a small point light")

	# 低血量：暗角收緊並紅色脈動，血量回復後淡出。
	_check(is_zero_approx(post.danger_level()), "no danger vignette at full health")
	EventBus.player_health_changed.emit(1, 6)
	await get_tree().create_timer(1.2, true).timeout
	_check(post.danger_level() > 0.9 and absf(float(post.parameter(&"danger"))) > 0.0, "low health tightens the vignette and turns it red")
	EventBus.player_health_changed.emit(6, 6)
	await get_tree().create_timer(1.2, true).timeout
	_check(is_zero_approx(post.danger_level()), "danger fades out when health recovers")

	# 攻擊預兆的紅光。
	var teller: Enemy = null
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if not (enemy as Enemy).data.is_boss:
			teller = enemy
	_check(teller != null, "level has an enemy to telegraph with")
	if teller != null:
		teller._start_telegraph(0.4)
		await get_tree().create_timer(0.2, true).timeout
		_check(teller._telegraph_light != null and teller._telegraph_light.enabled and teller._telegraph_light.energy > 0.1, "telegraphs glow red")
		await get_tree().create_timer(0.7, true).timeout
		_check(not teller._telegraph_light.enabled, "the telegraph light goes out afterwards")

	# 閃電：強烈閃光、有最短間隔；只有室外區段會打；「減少閃光」大幅降低強度。
	_check(zones[0].profile.lightning_rate > 0.0 and zones[3].profile.lightning_rate == 0.0 and zones[4].profile.lightning_rate == 0.0, "only outdoor zones have lightning")
	lighting._lightning_gap = 0.0  # 隨機打的閃電也會讓最短間隔還沒過，這裡要驗的是「打得出來」
	var storm_before := lighting.flash_level()
	_check(lighting.strike() and lighting.flash_level() > storm_before + 0.5, "a lightning strike flashes the whole scene")
	_check(not lighting.strike(), "lightning respects the minimum gap")
	await get_tree().create_timer(0.8, true).timeout
	_check(is_zero_approx(lighting.flash_level()), "lightning fades out")
	lighting._lightning_gap = 0.0
	Settings.use_storage("user://test_flash.cfg")
	_check(not Settings.get_reduce_flashes() and is_equal_approx(Settings.flash_scale(), 1.0), "flashes are at full strength by default")
	Settings.set_reduce_flashes(true)
	lighting.flash(Color.WHITE, 0.8, 0.2)
	_check(is_equal_approx(lighting.flash_level(), 0.8 * Settings.REDUCED_FLASH_SCALE), "reduced flashes cut the flash strength")
	await get_tree().create_timer(0.4, true).timeout
	lighting._lightning_gap = 0.0
	lighting.strike()
	await get_tree().create_timer(0.5, true).timeout
	_check(lighting.flash_level() < 0.1, "reduced flashes make lightning a single soft flash")
	Settings.set_value(Settings.DISPLAY_SECTION, "reduce_flashes", "oops")
	_check(not Settings.get_reduce_flashes(), "corrupt reduce-flashes value falls back to off")
	Settings.set_reduce_flashes(true)
	Settings.reset_display()
	_check(not Settings.get_reduce_flashes(), "reset turns reduced flashes off")
	Settings.use_storage(saved_settings)
	DirAccess.remove_absolute("user://test_flash.cfg")
	lighting._lightning_gap = 0.0

	# 法線貼圖與輪廓光：每張零件、武器與地形材質都有法線貼圖，角色與地形用 CanvasTexture，品質低時關閉。
	var missing_normals := 0
	for skin_id in ["rin", "trooper", "grenadier", "enforcer", "warden"]:
		var skin := RigLibrary.character(skin_id)
		for tex_name: String in skin.get("textures", {}).keys():
			var file := str(skin["textures"][tex_name].get("file", ""))
			var normal_path := RigLibrary.character_dir(skin_id).path_join(file).get_basename() + "_n.png"
			missing_normals += 0 if ResourceLoader.exists(normal_path) else 1
	for visual_id: String in RigLibrary.weapons().get("weapons", {}).keys():
		var weapon_file := str(RigLibrary.weapon(visual_id).get("file", ""))
		missing_normals += 0 if ResourceLoader.exists(RigLibrary.WEAPONS_PATH.get_base_dir().path_join(weapon_file).get_basename() + "_n.png") else 1
	missing_normals += 0 if ResourceLoader.exists("res://art/materials/metal_panel_n.png") else 1
	_check(missing_normals == 0, "every part, weapon and terrain material has a normal map (%d missing)" % missing_normals)
	var rig_part := level.player._visual.rig._part_sprites[0] as Sprite2D
	_check(rig_part.texture is CanvasTexture and (rig_part.texture as CanvasTexture).normal_texture != null, "character parts use normal-mapped textures")
	var panel_texture: Texture2D = terrain.get("_panel")
	_check(panel_texture is CanvasTexture and (panel_texture as CanvasTexture).normal_texture != null, "terrain uses a normal-mapped metal panel")
	var height_probe := LightKit.create_point_light(Color.WHITE, 50.0, 1.0, false, false)
	_check(is_equal_approx(height_probe.height, LightKit.LIGHT_HEIGHT), "scene lights are lifted off the plane so normal maps light up")
	height_probe.free()
	var plain := LitTextures.load_texture("res://icon.png", Vector2i(16, 16))
	_check(not (plain is CanvasTexture), "a texture without a normal map falls back to the plain texture")
	var rim: PointLight2D = lighting._rim_light
	_check(rim != null and is_zero_approx(rim.height) and rim.color.is_equal_approx(lighting.current.rim_color), "the rim light is a flat, zone-colored light")
	var normal_a := _make_blob_normal()
	_check(normal_a.get_pixel(4, 8).r < 0.45 and normal_a.get_pixel(11, 8).r > 0.55, "normal map tilts left on the left edge and right on the right edge")
	_check(normal_a.get_pixel(8, 4).g > 0.55 and normal_a.get_pixel(8, 11).g < 0.45, "normal map tilts up on the top edge and down on the bottom edge (Y up)")
	_check(normal_a.get_pixel(8, 8).b > 0.9 and is_equal_approx(normal_a.get_pixel(8, 8).a, 1.0) and is_zero_approx(normal_a.get_pixel(0, 0).a), "normal map keeps the flat middle flat and the alpha of the source")
	Settings.use_storage("user://test_normals.cfg")
	Settings.set_light_quality(LightQuality.Tier.LOW)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not LitTextures.is_enabled() and (rig_part.texture as CanvasTexture).normal_texture == null and not rim.enabled, "low quality turns off normal maps and the rim light")
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(LitTextures.is_enabled() and (rig_part.texture as CanvasTexture).normal_texture != null and rim.enabled == (lighting.current.rim_energy > 0.0), "high quality brings normal maps and the rim light back")
	Settings.use_storage(saved_settings)
	DirAccess.remove_absolute("user://test_normals.cfg")
	var bad_rim := LightingProfile.new()
	bad_rim.rim_energy = -1.0
	_check(not bad_rim.validate().is_empty(), "invalid rim energy is reported")

	# 發光的東西不受環境光壓暗；地形受光。
	var emissive := LightKit.emissive_material()
	_check(emissive.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "emissive material is unshaded")
	var bullet := Projectile.new()
	get_tree().root.add_child(bullet)
	_check(bullet.material == emissive, "projectiles are emissive")
	get_tree().root.remove_child(bullet)
	bullet.free()
	var enemy_count := 0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		enemy_count += 1
		_check((node as CanvasItem).material == emissive, "enemies are emissive: %s" % node.name)
	_check(enemy_count > 0, "level has enemies to check")
	_check((level.get_node("World/Terrain") as CanvasItem).material == null, "terrain is lit by ambient light")

	# 可讀性：角色最低亮度、補光、地形亮邊、亮度設定。
	var readable_profiles: Array[LightingProfile] = []
	for zone in zones:
		readable_profiles.append(zone.profile)
	for lighting_event in data.lighting_events:
		readable_profiles.append(lighting_event.profile)
	readable_profiles.append(data.boss_lighting)
	for readable in readable_profiles:
		_check(readable.character_luma() >= LightingProfile.MIN_READABLE_CHARACTER_LUMA, "character stays readable in %s (%.2f)" % [readable.id, readable.character_luma()])
		var wall := LightKit.luminance(Palette.TERRAIN_FILL) * LightKit.luminance(readable.ambient_color)
		var edge := LightKit.luminance(Palette.TERRAIN_TOP) * TerrainEdges.SOLID_EDGE_ALPHA
		_check((edge - wall) / (wall + 0.02) >= 2.0, "platform edges stand out in %s" % readable.id)
	var too_dark := LightingProfile.new()
	too_dark.ambient_color = Color(0.05, 0.05, 0.05)
	_check(not too_dark.validate().is_empty(), "a profile that makes characters unreadable is reported")
	too_dark.character_floor = 0.25
	_check(too_dark.validate().is_empty(), "a character floor makes a dark profile readable")
	var rig: CharacterRig = level.player._visual.rig
	_check(is_equal_approx(LightKit.character_fill, clampf(lighting.current.character_floor / LightKit.luminance(lighting.current.ambient_color), 1.0, LightingController.MAX_CHARACTER_FILL)), "character fill follows the current lighting")
	_check(is_equal_approx(rig._fill, LightKit.character_fill), "player rig applies the character fill")
	var edge_chunks := 0
	for chunk in terrain.get_node("Edges").get_children():
		edge_chunks += 1
		_check((chunk as CanvasItem).material == LightKit.emissive_material(), "terrain edges are emissive")
	_check(edge_chunks > 0, "terrain has edge chunks")
	var lit_chunks := 0
	for child in terrain.get_children():
		if child is StaticBody2D or child is LightOccluder2D or child.name == &"Edges":
			continue
		lit_chunks += 1
		_check((child as CanvasItem).material == null, "terrain body chunks stay lit")
	_check(lit_chunks > 0, "terrain body stays lit")

	# 亮度設定：預設是設計值，可調整、會存檔、損毀時退回預設，後製即時跟隨。
	var settings_path := Settings.storage_path()
	Settings.use_storage("user://test_brightness.cfg")
	_check(is_equal_approx(Settings.get_brightness(), Settings.BRIGHTNESS_DEFAULT) and is_equal_approx(Settings.brightness_gamma(), 1.0), "brightness defaults to the designed look")
	Settings.set_brightness(1.0)
	_check(is_equal_approx(Settings.brightness_gamma(), pow(2.0, Settings.BRIGHTNESS_RANGE * 0.5)) and is_equal_approx(post.parameter(&"brightness"), Settings.brightness_gamma()), "brightness raises gamma and the post pass follows")
	Settings.set_brightness(0.0)
	_check(Settings.brightness_gamma() < 1.0 and is_equal_approx(post.parameter(&"brightness"), Settings.brightness_gamma()), "brightness can also darken")
	Settings.set_value(Settings.DISPLAY_SECTION, "brightness", "oops")
	_check(is_equal_approx(Settings.get_brightness(), Settings.BRIGHTNESS_DEFAULT), "corrupt brightness falls back to the default")
	Settings.set_brightness(5.0)
	_check(is_equal_approx(Settings.get_brightness(), 1.0), "brightness is clamped")
	Settings.reset_display()
	_check(is_equal_approx(Settings.get_brightness(), Settings.BRIGHTNESS_DEFAULT) and is_equal_approx(post.parameter(&"brightness"), 1.0), "reset restores the designed brightness")
	Settings.use_storage(settings_path)
	DirAccess.remove_absolute("user://test_brightness.cfg")

	# 色彩腳本：越深入環境光越暗，頭目機庫最暗、暗角最重；每個區段有自己的燈風格與霓虹色盤。
	var luminances: Array[float] = []
	for zone in zones:
		var a: Color = zone.profile.ambient_color
		luminances.append(a.r * 0.2126 + a.g * 0.7152 + a.b * 0.0722)
	for i in range(1, luminances.size()):
		_check(luminances[i] < luminances[i - 1], "ambient light gets darker zone by zone (zone %d)" % i)
	var heaviest_vignette := true
	for i in range(0, zones.size() - 1):
		heaviest_vignette = heaviest_vignette and zones[zones.size() - 1].profile.vignette >= zones[i].profile.vignette
	_check(heaviest_vignette, "the boss hangar has the heaviest vignette")
	for i in zones.size():
		var style: LampStyle = zones[i].profile.lamp_style
		_check(style != null and style.validate().is_empty(), "zone %d has a valid lamp style" % i)
	_check(data.profile_at_tile(0) == zones[0].profile and data.profile_at_tile(115) == zones[1].profile and data.profile_at_tile(330) == zones[4].profile, "profile lookup by tile")
	_check(zones[1].profile.lamp_style.colors != zones[2].profile.lamp_style.colors, "zones use different lamp colors")

	# 場景燈：每個區段有數盞燈，顏色與光池取自區段風格；有壞掉與會閃的燈，壞掉的燈沒有光源。
	var lamps_per_zone: Array[int] = [0, 0, 0, 0, 0]
	var dead_lamps := 0
	var lamp_total := 0
	for node in level._world.get_children():
		var lamp := node as Lamp
		if lamp == null:
			continue
		lamp_total += 1
		var lamp_tile := int(lamp.position.x / tile)
		var lamp_profile := data.profile_at_tile(lamp_tile)
		var lamp_zone := zones.find_custom(func(z: LightingZone) -> bool: return z.profile == lamp_profile)
		lamps_per_zone[lamp_zone] += 1
		_check(lamp_profile.lamp_style.colors.has(lamp.color) and is_equal_approx(lamp.radius, lamp_profile.lamp_style.radius), "lamp uses its zone style (tile %d)" % lamp_tile)
		var has_light := false
		for child in lamp.get_children():
			has_light = has_light or child is PointLight2D
		_check(has_light != lamp.dead, "dead lamps have no light, working lamps do (tile %d)" % lamp_tile)
		dead_lamps += 1 if lamp.dead else 0
	for i in lamps_per_zone.size():
		_check(lamps_per_zone[i] >= 2, "zone %d has at least two lamps (got %d)" % [i, lamps_per_zone[i]])
	_check(dead_lamps > 0 and dead_lamps < lamp_total, "some but not all lamps are dead (%d of %d)" % [dead_lamps, lamp_total])
	_check(zones[3].profile.lamp_style.flicker_chance > zones[1].profile.lamp_style.flicker_chance, "facility lamps flicker more than market lamps")
	_check(zones[4].profile.lamp_style.pulse_hz > 0.0, "boss hangar lamps pulse")
	var lamp_seed_a := Lamp.new()
	var lamp_seed_b := Lamp.new()
	lamp_seed_a.apply_style(zones[1].profile.lamp_style, 12345)
	lamp_seed_b.apply_style(zones[1].profile.lamp_style, 12345)
	_check(lamp_seed_a.color == lamp_seed_b.color and lamp_seed_a.dead == lamp_seed_b.dead, "lamp style is deterministic for the same seed")
	lamp_seed_a.free()
	lamp_seed_b.free()

	# 光影事件：進入停電走廊時覆蓋，離開後淡回。
	_check(data.lighting_events.size() == 1 and data.lighting_events[0].profile != null and data.boss_lighting != null, "level has a blackout event and boss lighting")
	var event := data.lighting_events[0]
	var player_y := level.player.global_position.y
	level.player.global_position = Vector2(float(event.start_tile + 4) * tile, player_y)
	await get_tree().create_timer(2.0, true).timeout
	_check(lighting.has_override(event.id) and ambient.color.is_equal_approx(event.profile.ambient_color), "entering the blackout corridor dims the lights")
	level.player.global_position = Vector2(float(event.end_tile + 6) * tile, player_y)
	await get_tree().create_timer(3.5, true).timeout
	_check(not lighting.has_override(event.id), "leaving the blackout corridor restores the lights")
	var broken_event := LightingEvent.new()
	broken_event.end_tile = -1
	_check(broken_event.validate().size() >= 2, "invalid lighting event is reported")
	var broken_style := LampStyle.new()
	broken_style.colors = PackedColorArray()
	_check(not broken_style.validate().is_empty(), "invalid lamp style is reported")
	await _end_level(level)
	_check(is_equal_approx(LightKit.environment().glow_hdr_threshold, LightKit.DEFAULT_GLOW_THRESHOLD), "leaving the level restores glow defaults")

	# 從檢查點重生在停電走廊裡：一開始就是停電的光影。
	GameState.start_new_run(GameState.difficulties[1])
	GameState.set_checkpoint(Vector2(float(event.start_tile + 4) * tile, player_y), {})
	var dark_respawn := Level.new()
	dark_respawn.configure(data)
	get_tree().root.add_child(dark_respawn)
	for i in 3:
		await get_tree().process_frame
	_check((dark_respawn.get_node("Ambient") as CanvasModulate).color.is_equal_approx(event.profile.ambient_color), "respawning inside the blackout corridor starts dark")
	GameState.clear_checkpoint()
	await _end_level(dark_respawn)

	# 從檢查點重生：一開始就是該位置的光影，不從別的區段漸變。
	GameState.start_new_run(GameState.difficulties[1])
	var layout := LevelBuilder.parse(data)
	GameState.set_checkpoint(layout.checkpoints[layout.checkpoints.size() - 1], {})
	var respawn := Level.new()
	respawn.configure(data)
	get_tree().root.add_child(respawn)
	for i in 3:
		await get_tree().process_frame
	var checkpoint_zone := 0
	for i in zones.size():
		if respawn.player.global_position.x > float(zones[i].start_tile) * tile + float(zones[i].blend_tiles) * tile * 0.5:
			checkpoint_zone = i
	lighting = respawn._lighting
	lighting.zone_state_at(respawn.player.global_position.x, probe)
	_check((respawn.get_node("Ambient") as CanvasModulate).color.is_equal_approx(probe.ambient_color), "respawn starts with the lighting of the checkpoint zone (zone %d)" % checkpoint_zone)
	GameState.clear_checkpoint()
	await _end_level(respawn)


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
		# 其他敵人會撞開玩家、目標也會自己走開；終結技的檢查要的是「靠近、按近戰、算一次終結」，所以讓場上只剩暈住的目標。
		for other in spawned:
			if is_instance_valid(other) and other != target:
				other.queue_free()
		target.stun(5.0)
		await _frames(1)
		player.global_position = target.global_position + Vector2(-20, 0)
		var finishers := GameState.finishers
		Fx.thaw_all()  # 剛才那一擊的頓幀還在時玩家收不到輸入
		target.velocity = Vector2.ZERO
		player.velocity = Vector2.ZERO
		player.global_position = target.global_position + Vector2(-20, 0)  # 按下的前一刻再對位，等待期間兩邊都可能被物理推開
		# 輪詢式的輸入偶爾在機器忙時漏掉剛按下的那一格；最多按三次，第一次就成功的話只會按一次。
		for attempt in 3:
			Input.action_press(&"melee")
			await _frames(2)
			Input.action_release(&"melee")
			await _frames(2)
			if player.state == Player.State.FINISHER or GameState.finishers != finishers:
				break
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
	_check(level._lighting.has_override(&"boss"), "boss fight switches to the alarm lighting")
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
	_check(StoryItems.owns(&"nest07_shard"), "defeating the boss grants the NEST-07 shard")
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
