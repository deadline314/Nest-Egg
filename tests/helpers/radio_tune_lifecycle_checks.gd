extends RefCounted
## Real radio NPC, authored choices and whole-run writer; no direct result commit.
const LEVEL := "res://data/levels/ch2_pawnshop.tres"
const Labels := preload("res://tests/helpers/npc_terminal_save_checks.gd")

static func run(s: TestSuite) -> void:
	var auto := Story.auto_skip
	var previous: Node = Story.result_completion
	Story.auto_skip = false
	var reference: Dictionary = {}
	var reference_saved: Dictionary = {}
	for mode: String in ["baseline", "cancel", "fixture", "death", "leave", "skip", "save"]:
		var original_steps: Array = Story._scenes["ch2_t_s02_broadcast"]["steps"]
		if mode == "baseline":
			# Exact original authored broadcast; only the new visual step is absent.
			Story._scenes["ch2_t_s02_broadcast"]["steps"] = original_steps.slice(1)
		var level := await s.start_level(load(LEVEL))
		Story.reset_active_presentation(&"radio_test_setup")
		GameState.story_autosave = false
		var actor: NpcActor
		for node: Node in level._entities.get_children():
			if node is NpcActor and node.data.resource_path == "res://data/npcs/ch2_radio.tres":
				actor = node
		var main := Labels.BoundaryMain.new()
		main._active_run = true
		main._screen = level
		main._level_path = LEVEL
		main._run_store = RunSaveStore.new("user://radio-tune/" + mode + ".json")
		main._run_store.validator = RunSnapshot.prepare
		var owner := preload("res://game/story_result_completion.gd").new()
		owner.main = main
		main._result_completion = owner
		main.add_child(owner)
		s.runner.get_tree().root.add_child(main)
		if mode in ["baseline", "save"]:
			Story.scene_started.connect(main._on_scene_started)
			Story.scene_finished.connect(main._on_scene_finished)
		level.player.global_position = actor.global_position + Vector2(-28, 0)
		await s.physics_frames(15)
		s.check(main._run_store.write(RunSnapshot.capture(LEVEL, level.run_snapshot()), true), "radio writes an actual original slot: " + mode)
		var original := FileAccess.get_file_as_bytes(main._run_store.path)
		var wallet := Progression.credits
		var loadout := var_to_bytes(level.player.loadout.snapshot())
		if mode in ["baseline", "save"]:
			s.check(DirAccess.make_dir_absolute(main._run_store.path + ".tmp") == OK, "owned temp obstruction refuses ordinary autosave: " + mode)
		actor._talk()
		var reached := await _drive(s, func() -> bool:
			if mode == "baseline":
				return Story._current_cinematic == &"ch2_t_s02_broadcast" and Story._player != null and Story._player.choice_active()
			var action: WorldPropAction = level.player._visual.interaction_action
			return action != null and action.phase == "turn" and action._elapsed > 0.05)
		s.check(reached, "actual NPC reaches the unchanged broadcast choice or candidate knob: " + mode)
		var visual := level.player._visual
		if mode != "baseline":
			s.check(visual._interaction_input.crouching and not visual.rig._weapon_root.visible, "radio holds a crouch and hides the original weapon: " + mode)
		if mode == "cancel":
			var spec := WorldPropAction.definition("radio_tune_clear")
			spec["reaction"] = "missing_declared_reaction"
			s.check(not WorldPropAction.new().start("radio_tune_clear", level.player, "ch2_t_s02_broadcast"), "a declared missing reaction still refuses a live static turn")
			spec.erase("reaction")
			var source: String = spec["source"]
			spec["source"] = "res://data/npcs/ch2_old_k.tres"
			s.check(not WorldPropAction.new().start("radio_tune_clear", level.player, "ch2_t_s02_broadcast"), "a foreign talking source cannot borrow the knob")
			spec["source"] = source
		s.check(not GameState.has_flag(&"ch2_radio_repaired") and not StoryItems.holds(&"ch2_radio_clip") and Progression.credits == wallet, "turning alone publishes no result: " + mode)
		if mode == "cancel":
			Story.reset_active_presentation(&"cancel")
		elif mode == "fixture":
			var prop: PropNode = visual.interaction_action._prop.get_ref()
			prop.queue_free()
		elif mode == "death":
			level.player.health.kill(null)
		elif mode == "leave":
			actor.queue_free()
		elif mode == "skip":
			Story.skip_cinematic()
			await _drive(s, func() -> bool: return not actor._talking, "leave")
		else:
			await _drive(s, func() -> bool: return not actor._talking)
			await s.frames(3)
			var refused := {"repaired": GameState.has_flag(&"ch2_radio_repaired"), "clip": StoryItems.holds(&"ch2_radio_clip"), "credits": Progression.credits - wallet, "pending": Story._pending_next.duplicate(true), "cinematic": main._cinematic, "autosave": main._save_queued, "prompt": is_instance_valid(owner._prompt), "disk_unchanged": original == FileAccess.get_file_as_bytes(main._run_store.path)}
			if mode == "baseline": reference = refused
			s.check(refused == reference and refused["repaired"] and refused["clip"] and refused["credits"] == 20 and refused["disk_unchanged"] and not refused["prompt"], "ordinary autosave refusal preserves the original legacy live/disk semantics: " + mode)
			print("RADIO_LEGACY_REFUSED ", mode, " ", JSON.stringify(refused))
			s.check(DirAccess.remove_absolute(main._run_store.path + ".tmp") == OK, "remove only the owned radio save obstruction")
			main._save_run()
			var reader := RunSaveStore.new(main._run_store.path)
			reader.validator = RunSnapshot.prepare
			var saved := reader.read()
			var persisted := {"repaired": saved.get("story", {}).get("flags", {}).get("ch2_radio_repaired", false), "items": saved.get("story", {}).get("items", {}), "progression": saved.get("progression", {}), "pending": Story._pending_next.duplicate(true), "cinematic": main._cinematic, "autosave": main._save_queued}
			if mode == "baseline": reference_saved = persisted
			s.check(persisted == reference_saved and persisted["items"].get("held", []).has("ch2_radio_clip"), "successful save preserves original flags, items, transactions, pending scene and autosave state: " + mode)
			print("RADIO_LEGACY_SAVED ", mode, " ", JSON.stringify(persisted))
			s.check(GameState.has_flag(&"ch2_radio_repaired") and StoryItems.holds(&"ch2_radio_clip") and Progression.credits == wallet + 20, "successful ordinary save keeps original repair, clip and exactly twenty credits")
			s.check(saved.get("story", {}).get("flags", {}).get("ch2_radio_repaired", false) and saved.get("progression", {}).get("credits", -1) == wallet + 20 and saved.get("runtime", {}).get("world", {}).get(actor.state_key(), {}).get("talks", -1) == 1, "independent reader sees one durable radio completion")
			actor._talk()
			await _drive(s, func() -> bool: return not actor._talking)
			s.check(Progression.credits == wallet + 20, "revisiting the repaired radio cannot pay again")
			RunSnapshot.apply(saved, false)
			s.check(GameState.has_flag(&"ch2_radio_repaired") and StoryItems.holds(&"ch2_radio_clip") and Progression.credits == wallet + 20 and Story.resolve_dispatch(&"ch2_dispatch_radio") != &"ch2_t_s02_intro", "new reader restores the completed radio without replay or a second reward")
		await s.frames(8)
		s.check(visual.interaction_action == null and not visual._interaction_input.crouching and not visual._interaction_input.hand_grip_front, "all terminal paths release hand and crouch: " + mode)
		s.check(var_to_bytes(level.player.loadout.snapshot()) == loadout and visual.rig._weapon_root.visible == (not level.player.is_dead()), "terminal path preserves loadout and restores only a living player's weapon: " + mode)
		if mode not in ["baseline", "save"]:
			s.check(not GameState.has_flag(&"ch2_radio_repaired") and not StoryItems.holds(&"ch2_radio_clip") and Progression.credits == wallet, "interruption never publishes a repair or reward: " + mode)
		Story.reset_active_presentation(&"radio_test_teardown")
		main._screen = null
		main.queue_free()
		await s.frames(2)
		Story.result_completion = previous if is_instance_valid(previous) else null
		await s.end_level(level)
		Story._scenes["ch2_t_s02_broadcast"]["steps"] = original_steps
	Story.auto_skip = auto

static func _drive(s: TestSuite, finished: Callable, broadcast := "save") -> bool:
	var choices := {"ch2_t_s02_power": "power", "ch2_t_s02_antenna": "antenna", "ch2_t_s02_speaker": "speaker", "ch2_t_s02_tune": "middle", "ch2_t_s02_broadcast": broadcast}
	for frame in 1000:
		if finished.call(): return true
		var player: CutscenePlayer = Story._player
		if player != null and player.choice_active():
			var id: String = choices.get(String(Story._current_cinematic), str(player._choice_step.get("default", "")))
			var index := player._choice_options.find_custom(func(o: Dictionary) -> bool: return o.get("id", "") == id)
			player.choose(maxi(index, 0))
		elif Story._current_cinematic != &"" and Story.scene_mode(Story._current_cinematic) != Story.MODE_ANIMATED:
			Story._layer.advance()
		elif player != null and player.is_running() and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
		await s.frames(1)
	return finished.call()
