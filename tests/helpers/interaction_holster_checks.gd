extends RefCounted
## NE-278：真實 NPC 入口、暫停中的呈現、取消與當下裝備恢復。

const OVERLAY := &"test_holster_overlay"
const CHAIN := &"test_holster_chain"
const STAGE := &"test_holster_stage"
const CHOICE := &"test_holster_choice"


static func run(s: NpcSuite) -> void:
	var gamepad := InputBindings.using_gamepad
	var device := InputBindings.active_device
	var aim_gamepad := AimInput.using_gamepad
	var aim_dir := AimInput._last_stick_dir
	Story.auto_skip = false
	Story._scenes[String(OVERLAY)] = {"mode": "animated", "overlay": true, "steps": [{"do": "say", "speaker": "rin", "text": "閱讀時放下武器。"}]}
	Story._scenes[String(CHAIN)] = {"mode": "dialogue", "lines": [{"speaker": "rin", "text": "下一段仍在交談。"}], "then": String(OVERLAY)}
	Story._scenes[String(STAGE)] = {"mode": "animated", "steps": [{"do": "wait", "time": 30.0}]}
	Story._scenes[String(CHOICE)] = {"mode": "animated", "overlay": true, "steps": [{"do": "choice", "text": "讀完了？", "options": [{"id": "close", "text": "關閉"}]}]}
	var person := s._npc(&"holster_person", [s._talk(s.TEST_SCENE_A)])
	var object := s._npc(&"holster_object", [s._talk(OVERLAY)])
	object.kind = NpcData.Kind.OBJECT
	var level := await s.start_level(s._level_data({"A": person, "Z": object}))
	var player := level.player
	var crosshair := Crosshair.new()
	s.runner.add_child(crosshair)
	var npc := s._find_npc(level, 14)
	var marker := s._find_npc(level, 24)
	await s._stand_next_to(level, npc)
	for weapon_path in ["pistol", "melee/melee_blade", "melee/melee_glaive", "melee/melee_whip"]:
		player.loadout.reset(load("res://data/weapons/%s.tres" % weapon_path) as WeaponData)
		for facing in [-1, 1]:
			player.facing = facing
			player.aim_dir = Vector2(facing, -0.5).normalized()
			AimInput.using_gamepad = true
			AimInput._last_stick_dir = player.aim_dir
			await s.frames(2)
			var snapshot := player.loadout.snapshot()
			npc._talk()
			var position := player.global_position
			s.check(player.interaction.active and not crosshair.visible, "%s %d synchronously holsters and hides crosshair before pause" % [weapon_path, facing])
			s.check(not player._visual.rig.weapon_root().visible and not player._visual.shows_melee_weapon() and not player._weapon_light.is_lit(), "gun, melee and gun light disappear in the first reading frame")
			await s.frames(18)
			s.check(s.runner.get_tree().paused and player.global_position == position and player.loadout.snapshot() == snapshot, "%s %d presentation eases while world position, ammunition and equipment stay frozen" % [weapon_path, facing])
			s.check(player._visual._blade_light.energy() == 0.0 or not player._visual._blade_light.is_visible_in_tree(), "holstered blade casts no light")
			await _switch_devices(s)
			s.check(player.interaction.active and not crosshair.visible and not player._visual.rig.weapon_root().visible and not player._visual.melee_held().visible, "synthetic controller, keyboard and mouse switching cannot reveal the held weapon or crosshair")
			Story.skip_cinematic()
			await s.frames(3)
			s.check(not player.interaction.active and crosshair.visible and player.loadout.snapshot() == snapshot, "normal completion restores crosshair and keeps the same loadout")
			s.check(player._visual.shows_melee_weapon() if player.holds_melee_weapon() else player._visual.rig.weapon_root().visible, "normal completion restores the appropriate gun or melee visual")
	# 物件的 animated overlay 與同一人物的 dialogue 都涵蓋；取消沒有完成獎勵。
	await s._stand_next_to(level, marker)
	marker._talk()
	await s.frames(3)
	s.check(player.interaction.active and not crosshair.visible, "map animated overlay holsters just like person dialogue")
	player.loadout.reset(load("res://data/weapons/pistol.tres") as WeaponData)
	s.check(not player._visual.rig.weapon_root().visible, "external equipment refresh during reading cannot reveal a gun")
	Story.reset_active_presentation(&"leave")
	await s.frames(3)
	s.check(not player.interaction.active and crosshair.visible and player._visual.rig.weapon_root().visible and marker.talk_count == 0, "cancellation restores current equipment without awarding talk completion")
	# 非地圖演出與 radio 不取得收起所有權。
	Story.play(STAGE, false, {"framing_source": "person"})
	await s.frames(2)
	s.check(not player.interaction.active and player._visual.rig.weapon_root().visible, "full stage presentation leaves gameplay actor presentation unchanged")
	Story.reset_active_presentation(&"probe")
	Story.play(s.TEST_SCENE_A, false)
	await s.frames(2)
	s.check(not player.interaction.active, "dialogue without a map interaction context does not holster")
	Story.reset_active_presentation(&"probe")
	Story.play(CHAIN, false, {"framing_source": "object"})
	await s.frames(2)
	Story.skip_cinematic()
	await s.frames(3)
	s.check(Story._current_cinematic == OVERLAY and player.interaction.active and not crosshair.visible, "chained overlay keeps a new presentation ownership after dialogue completes")
	Story.reset_active_presentation(&"probe")
	# 地圖選擇也維持收起狀態，直到真正選擇後才恢復。
	marker.data.talks[0].scene = CHOICE
	marker._talk()
	await s.frames(3)
	s.check(Story._player != null and Story._player.choice_active() and player.interaction.active and not crosshair.visible, "a real object interaction also holsters throughout a map choice")
	await _switch_devices(s)
	s.check(player.interaction.active and not crosshair.visible and not player._visual.rig.weapon_root().visible, "device changes while choosing do not reveal the gun or crosshair")
	Story._player.choose(0)
	await s.frames(4)
	s.check(not player.interaction.active and crosshair.visible and marker.talk_count == 1, "choosing the close option completes the actual object talk and restores the weapon scope")
	marker.data.talks[0].scene = OVERLAY
	# 搬運物件不當成武器藏掉，也不把手放下留下浮空箱子。
	var crate := Throwable.new()
	crate.configure(load("res://data/throwables/crate_small.tres") as ThrowableData)
	level._entities.add_child(crate)
	player.carry.pick(crate)
	await s.frames(35)
	var carry_time := player.carry._phase_t
	var carry_position := crate.global_position
	marker._talk()
	await s.frames(18)
	s.check(player.interaction.active and player._visual._interaction_input.action == PlayerCarry.POSE_HOLD and crate.global_position == carry_position and player.carry._phase_t == carry_time, "reading preserves the frozen carried-object support pose and object position")
	Story.reset_active_presentation(&"probe")
	await s.frames(3)
	s.check(player.carry.is_holding() and not player._visual.rig.weapon_root().visible, "return from reading keeps the carried object and does not reveal its hidden gun")
	player.carry.put_down()
	await s.frames(3)
	await s._stand_next_to(level, npc)
	npc._talk()
	await s.frames(2)
	var damage := DamageInfo.create(1, Combat.Team.ENEMY, &"test_holster")
	damage.ignore_invulnerability = true
	player.health.take_damage(damage)
	await s.frames(3)
	s.check(not player.interaction.active and not Story.is_cinematic_active() and not GameplayLock.is_locked() and crosshair.visible, "combat interruption cancels reading and releases both presentation and gameplay lock")
	npc._talk()
	await s.frames(2)
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"test_holster")
	lethal.ignore_invulnerability = true
	player.health.take_damage(lethal)
	await s.frames(3)
	s.check(player.is_dead() and not player.interaction.active and not crosshair.visible, "death cannot leave a holster scope or crosshair on the corpse")
	s.runner.remove_child(crosshair)
	s.check(not EventBus.player_spawned.is_connected(crosshair._bind_player) and not player.interaction.changed.is_connected(crosshair._refresh_visibility), "detached HUD releases both global spawn and old-player interaction callbacks")
	EventBus.player_spawned.emit(player)
	await s.frames(1)
	s.runner.add_child(crosshair)
	s.check(crosshair._player() == player and EventBus.player_spawned.is_connected(crosshair._bind_player), "reattached HUD binds safely without requiring ready again")
	var replacement := Player.new()
	replacement.configure(player.tuning, 5, {})
	replacement.position = player.position
	level._entities.add_child(replacement)
	await s.frames(2)
	s.check(crosshair._player() == replacement and crosshair.visible and not player.interaction.changed.is_connected(crosshair._refresh_visibility), "new player takes over even while the old corpse still exists")
	level._entities.remove_child(player)
	s.check(not Story.scene_started.is_connected(player.interaction._started), "detached player's holster component releases global story callbacks")
	Story.play(OVERLAY, false, {"framing_source": "object"})
	await s.frames(3)
	s.check(replacement.interaction.active and not player.interaction.active and not crosshair.visible, "a new player's reading cannot animate a detached old player")
	Story.reset_active_presentation(&"probe")
	level._entities.add_child(player)
	await s.frames(2)
	s.check(Story.scene_started.is_connected(player.interaction._started) and not player.interaction.active and crosshair.visible, "reattached holster component reconnects without affecting the current player")
	crosshair.queue_free()
	await s.end_level(level)
	for id in [OVERLAY, CHAIN, STAGE, CHOICE]:
		Story._scenes.erase(String(id))
	InputBindings.using_gamepad = gamepad
	InputBindings.active_device = device
	AimInput.using_gamepad = aim_gamepad
	AimInput._last_stick_dir = aim_dir
	Story.auto_skip = true


static func _switch_devices(s: TestSuite) -> void:
	var joy := InputEventJoypadMotion.new()
	joy.axis = JOY_AXIS_RIGHT_X
	joy.axis_value = 0.8
	Input.parse_input_event(joy)
	await s.frames(2)
	joy = joy.duplicate() as InputEventJoypadMotion
	joy.axis_value = 0.0
	Input.parse_input_event(joy)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	var mouse := InputEventMouseMotion.new()
	mouse.position = Vector2(100, 100)
	mouse.relative = Vector2(8, 3)
	Input.parse_input_event(mouse)
	await s.frames(2)
