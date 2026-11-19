extends RefCounted
## Authored prop coordinates must be reachable by the actual crouching rig.
const ACTIONS := {
	"ledger_lock_check": ["ch1_t_ledger_check", "pawnshop_front"],
	"pump_case_reset": ["ch1_t_pump_reset", "dock_warehouse"],
}

static func run(s: TestSuite) -> void:
	for id: String in ACTIONS:
		var spec := WorldPropAction.definition(id)
		s.check(WorldPropAction.problem(id, ACTIONS[id][0], true).is_empty(), "first chapter authored prop action validates: " + id)
		s.check(not WorldPropAction.problem(id, "foreign_scene", true).is_empty(), "first chapter action keeps its scene owner: " + id)
		var prop := PropNode.new()
		prop.setup(load("res://data/environment/scene_props/%s/%s.tres" % [ACTIONS[id][1], spec["prop"]]), Vector2(944, 274))
		s.runner.add_child(prop)
		var rig := CharacterRig.new()
		s.runner.add_child(rig)
		s.check(rig.setup("rin"), "first chapter contact uses the real Rin rig")
		rig.global_position = prop.to_global(Vector2(spec["station"][0], spec["station"][1]))
		var input := RigInput.new()
		input.facing = 1
		input.aim_dir = Vector2.RIGHT
		input.on_floor = true
		input.hand_grip_front = true
		input.crouching = true
		for frame in 30: rig.animate(1.0 / 60.0, input)
		var action := WorldPropAction.new()
		action._spec = spec
		action._prop = weakref(prop)
		var failures := 0
		var worst := 0.0
		for frame in 120:
			for sample in 9:
				rig.animate(1.0 / 60.0, input)
				var target := action.rim_global(action._turn_angle(sample / 8.0))
				if not rig.place_hand(&"front", target, 0): failures += 1
				worst = maxf(worst, rig.hand_contact_global(&"front").distance_to(target))
		s.check(failures == 0 and worst <= WorldPropAction.CONTACT_TOLERANCE, "first chapter real hand contact: %s worst %s failures %s" % [id, worst, failures])
		rig.queue_free()
		prop.queue_free()

static func lifecycle(s: TestSuite) -> void:
	var auto := Story.auto_skip
	var previous: Node = Story.result_completion
	Story.auto_skip = false
	await _switch_and_pump_select_one_target(s)
	for id: String in ACTIONS:
		var spec := WorldPropAction.definition(id)
		var flag := &"ch1_ledger_checked" if id == "ledger_lock_check" else &"ch1_pump_case_reset"
		for mode: String in ["cancel", "death", "skip", "save"]:
			var level := await s.start_level(load(spec["level"]))
			Story.reset_active_presentation(&"maintenance_setup")
			GameState.story_autosave = false
			if id == "pump_case_reset": GameState.set_flag(&"watchdog_defeated")
			await s.frames(3)
			var actor: NpcActor
			for node: Node in level._entities.get_children():
				if node is NpcActor and node.data.resource_path == spec["source"]: actor = node
			s.check(actor != null and actor.is_present(), "actual optional maintenance object is present: " + id)
			if actor == null:
				await s.end_level(level)
				continue
			var main := preload("res://tests/helpers/npc_terminal_save_checks.gd").BoundaryMain.new()
			main._active_run = true
			main._screen = level
			main._level_path = spec["level"]
			main._run_store = RunSaveStore.new("user://ch1-maintenance/%s-%s.json" % [id, mode])
			main._run_store.validator = RunSnapshot.prepare
			var owner := preload("res://game/story_result_completion.gd").new()
			owner.main = main
			main._result_completion = owner
			main.add_child(owner)
			s.runner.get_tree().root.add_child(main)
			Story.scene_started.connect(main._on_scene_started)
			Story.scene_finished.connect(main._on_scene_finished)
			level.player.global_position = actor.global_position + Vector2(-28, 0)
			await s.physics_frames(15)
			var wallet := Progression.credits
			var items := var_to_bytes(StoryItems.snapshot())
			var loadout := var_to_bytes(level.player.loadout.snapshot())
			actor._talk()
			var reached := await _drive(s, func() -> bool:
				var action: WorldPropAction = level.player._visual.interaction_action
				return action != null and action.phase == "turn" and action._elapsed > .05)
			s.check(reached and not GameState.has_flag(flag), "turning is not a durable completion: %s %s" % [id, mode])
			if mode == "cancel": Story.reset_active_presentation(&"cancel")
			elif mode == "death": level.player.health.kill(null)
			elif mode == "skip": Story.skip_cinematic()
			await _drive(s, func() -> bool: return not actor._talking)
			await s.frames(8)
			var visual := level.player._visual
			s.check(visual.interaction_action == null and not visual._interaction_input.crouching and not visual._interaction_input.hand_grip_front, "terminal paths release the hand and crouch: %s %s" % [id, mode])
			s.check(Progression.credits == wallet and var_to_bytes(StoryItems.snapshot()) == items and var_to_bytes(level.player.loadout.snapshot()) == loadout, "optional maintenance changes no reward, item or weapon: %s %s" % [id, mode])
			s.check(not GameState.has_flag(&"ch1_flood_gate_open"), "casing service cannot open the real flood gate")
			s.check(GameState.has_flag(flag) == (mode in ["skip", "save"]), "completion or explicit skip publishes exactly its own result: %s %s" % [id, mode])
			if mode in ["skip", "save"]:
				var reader := RunSaveStore.new(main._run_store.path)
				reader.validator = RunSnapshot.prepare
				var saved := reader.read()
				s.check(saved.get("story", {}).get("flags", {}).get(String(flag), false), "independent save reader sees completed maintenance: " + id)
				if not saved.is_empty(): RunSnapshot.apply(saved, false)
				s.check(GameState.has_flag(flag), "saved maintenance survives reload: " + id)
				if id == "ledger_lock_check":
					actor._talk()
					await _drive(s, func() -> bool: return not actor._talking)
					s.check(Story.resolve_dispatch(&"ch1_dispatch_ledger_box") == &"ch1_t_ledger_revisit", "ledger revisit keeps its completed route")
				else:
					s.check(not actor.is_present(), "repaired casing keeps its indicator without repeating a prompt")
				s.check(Progression.credits == wallet, "revisiting optional maintenance awards nothing")
			Story.reset_active_presentation(&"maintenance_teardown")
			main._screen = null
			main.queue_free()
			await s.frames(2)
			Story.result_completion = previous if is_instance_valid(previous) else null
			await s.end_level(level)
	Story.auto_skip = auto

static func _switch_and_pump_select_one_target(s: TestSuite) -> void:
	var level := await s.start_level(load("res://data/levels/ch1_warehouse.tres"))
	Story.reset_active_presentation(&"maintenance_setup")
	GameState.story_autosave = false
	GameState.set_flag(&"watchdog_defeated")
	var gate_switch: ChannelSwitch
	var pump: NpcActor
	for node in level._entities.get_children():
		if node is ChannelSwitch and node.data.id == &"ch1_switch_a":
			gate_switch = node
		elif node is NpcActor and node.data.id == &"ch1_pump_service":
			pump = node
	s.check(gate_switch != null and pump != null, "warehouse has the authored switch and optional pump")
	if gate_switch == null or pump == null:
		await s.end_level(level)
		return
	# The fixture starts behind the completed watchdog approach, before either item is used.
	Story.auto_skip = true
	level.player.global_position = gate_switch.global_position + Vector2(1.0, 0.0)
	await s.physics_frames(8)
	Story.reset_active_presentation(&"maintenance_overlap_ready")
	Story.auto_skip = false
	s.check(gate_switch._player_in_range and pump.interaction_available(), "the actual switch and pump interaction ranges overlap")
	s.check(gate_switch._prompt._player_near() and not pump._prompt._player_near(), "only the gate advertises the shared key in the overlap")
	await s.runner._press_action(&"interact")
	s.check(gate_switch.active and not Story.is_cinematic_active() and not pump._talking, "one press at the switch opens the gate without starting optional maintenance")
	Story.reset_active_presentation(&"maintenance_switch_checked")
	level.player.global_position = pump.global_position
	await s.physics_frames(8)
	s.check(pump._prompt._player_near() and not gate_switch._prompt._player_near(), "the pump advertises the shared key from its own position")
	await s.runner._press_action(&"interact")
	s.check(gate_switch.active and pump._talking and not GameState.has_flag(&"ch1_pump_case_reset"), "one press at the pump offers maintenance without changing the gate or repairing it")
	Story.reset_active_presentation(&"maintenance_teardown")
	await s.end_level(level)

static func _drive(s: TestSuite, finished: Callable) -> bool:
	for frame in 1000:
		if finished.call(): return true
		var player: CutscenePlayer = Story._player
		if player != null and player.choice_active():
			var index := player._choice_options.find_custom(func(o: Dictionary) -> bool: return o.get("id", "") == "reset")
			player.choose(maxi(index, 0))
		elif Story._current_cinematic != &"" and Story.scene_mode(Story._current_cinematic) != Story.MODE_ANIMATED:
			Story._layer.advance()
		elif player != null and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		await s.frames(1)
	return finished.call()
