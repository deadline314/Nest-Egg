extends Node
## Actual authored Level/NpcActor/Story/DialogueLayer, scripted capture, not human play.
const Capture := preload("res://tools/viewport_capture.gd")
var _out := ""
var _width := 1280
var _height := 720
var _scale := 1.0
var _failed := false
var _expand := false
var _level: Level

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var profile := OS.get_environment("NE228_UI_CAPTURE_PROFILE").replace("\\", "/").simplify_path().to_lower()
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	if profile.is_empty() or not user_dir.begins_with(profile + "/"):
		printerr("NE228 requires an isolated APPDATA profile; refusing capture.")
		get_tree().quit(1)
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus" or DisplayServer.get_name() == "headless":
		printerr("NE228 visual probe requires native Forward+.")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
		elif arg == "--expand":
			_expand = true
		elif arg.begins_with("--text-scale="):
			_scale = float(arg.trim_prefix("--text-scale="))
	if not _out.is_absolute_path() or not _out.replace("\\", "/").simplify_path().to_lower().begins_with("c:/tmp/") or not is_finite(_scale) or _scale not in [1.0, 1.2] or _width < 640 or _height < 360:
		printerr("NE228 requires --out=C:/tmp/... and valid capture dimensions/scale.")
		get_tree().quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		get_tree().quit(1)
		return
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	if _expand:
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	Settings.set_ui_text_scale(_scale)
	_run.call_deferred()

func _run() -> void:
	print("NE228_NATIVE ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	print("NE228_SCRIPTED_ONLY ", OS.get_user_data_dir(), " | ", get_window().size, " | text ", _scale)
	GameState.story_autosave = false
	Story.auto_skip = false
	Settings.set_skip_cutscenes(false)
	# Private process only: human input cannot alter arranged capture poses.
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load("res://data/levels/ch1_pawnshop.tres") as LevelData).duplicate(true) as LevelData
	# Capture-only removal of entry movie; geometry, actor data, true interaction stay authored.
	data.intro_scene = &""
	_level = Level.new()
	_level.configure(data)
	add_child(_level)
	await _frames(5)
	await _capture("authored-pawnshop-compact-hint")
	await _capture_player_poses()
	var npc: NpcActor
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and _level.is_ancestor_of(node) and node.data.id == &"ch1_old_k":
			npc = node
	if npc == null:
		_fail("missing actual old K actor in authored Level")
	else:
		_level.player.global_position = npc.global_position + Vector2(24, 0)
		await _frames(12)
		_level.camera.snap_to_target()
		_level.camera.force_update_scroll()
		npc._talk() # real asynchronous source + lock; cancel below, no completion/reward
		await _frames(30)
		if not Story._layer.is_cinematic_active():
			_fail("old K request did not reach DialogueLayer")
		else:
			Story._layer._text.visible_ratio = 1.0 # reveal original first line, never completes it
			await _capture("authored-old-k-dialogue")
		Story.reset_active_presentation(&"leave")
		await _frames(4)
	# Authored radio text, actual Story queue; isolated capture has no Main autosave owner.
	var radio_id := &""
	for id: String in Story._scenes:
		if Story.scene_mode(StringName(id)) == Story.MODE_RADIO and not Story.resolved_lines(StringName(id)).is_empty():
			radio_id = StringName(id)
			break
	if radio_id == &"":
		_fail("no loaded authored radio line")
	else:
		Story._layer.enqueue_radio(radio_id, Story.resolved_lines(radio_id))
		await _frames(5)
		await _capture("authored-radio-ui-only")
		Story.reset_active_presentation(&"leave")
	# Objects keep real level and original definitions, no mounted billboards are added.
	_level.queue_free()
	await _frames(3)
	var reading_level :=  (load("res://data/levels/level_02.tres") as LevelData).duplicate(true) as LevelData
	reading_level.intro_scene = &""
	# The genuine object is far into the map. Teleporting past every & would start unrelated movies.
	# Capture copy only: keep exact trigger count, remove presentation IDs; no authored map/flag edits.
	for i in reading_level.story_triggers.size():
		reading_level.story_triggers[i] = ""
	_level = Level.new()
	_level.configure(reading_level)
	add_child(_level)
	await _frames(5)
	var object: NpcActor
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and _level.is_ancestor_of(node) and node.data.id == &"height_marks" and node.data.kind == NpcData.Kind.OBJECT and node.current_talk_index() >= 0:
			object = node
			break
	if object == null:
		_fail("missing available actual level_02 height_marks OBJECT")
	else:
		_level.player.global_position = object.global_position + Vector2(24, 0)
		await _frames(12)
		_level.camera.snap_to_target()
		_level.camera.force_update_scroll()
		_diagnose("object-before-talk", object)
		object._talk()
		await _frames(30)
		_diagnose("object-after-talk", object)
		if Story._layer.is_cinematic_active():
			Story._layer._text.visible_ratio = 1.0
			await _capture("authored-object-reading")
			if Story.framing.scope_count() != 0:
				_fail("actual OBJECT acquired unexpected cinematic framing scope")
		else:
			_fail("height_marks request did not reach DialogueLayer; see source/player/lock observers")
	Story.reset_active_presentation(&"leave")
	_level.queue_free()
	await _frames(3)
	get_tree().quit(1 if _failed else 0)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _capture(tag: String) -> void:
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE228-scripted-%s.png" % tag)
	var error := Capture.image(get_viewport()).save_png(path)
	if error != OK:
		_failed = true
		printerr("NE228 PNG ", path, ": ", error_string(error))
	print("NE228_CAPTURE ", path)
	print("NE228_RADIO_OBSERVER ", tag, " visible=", Story._layer._radio_root.visible, " name=", Story._layer._radio_name.text, " text=", Story._layer._radio_text.text, " portrait_visible=", Story._layer._radio_portrait.visible, " rect=", Story._layer._radio_root.get_rect())
	print("NE228_OBSERVER ", tag, " scene=", Story._current_cinematic, " viewport=", get_viewport().get_visible_rect(), " panel=", Story._layer._dialogue_panel.get_rect(), " name=", Story._layer._name.text, " body=", Story._layer._text.text, " body_min=", Story._layer._text.get_combined_minimum_size(), " body_size=", Story._layer._text.size, " safe=", Story.framing.safe_rect())
	if is_instance_valid(_level) and is_instance_valid(_level.player):
		var player := _level.player
		print("NE228_PLAYER_POSE ", tag, " facing=", player.facing, " crouch=", player.is_crouching, " floor=", player.is_on_floor(), " weapon=", player.loadout.active_weapon().id, " ui_proxy=", player.prompt_obstacle_rect(), " actual_art=", player._visual.rig.visual_bounds())
		if tag.begins_with("actual-") and not player.prompt_obstacle_rect().encloses(player._visual.rig.visual_bounds()):
			_fail("reading-space proxy failed to enclose the pictured actual player art")
		if tag.begins_with("actual-"):
			var vitals := _level.hud.vitals_tag.prompt_obstacle_rect()
			for prompt in PromptLayout._prompts:
				if not is_instance_valid(prompt) or not prompt.is_showing() or not _level.is_ancestor_of(prompt):
					continue
				var shown := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
				print("NE228_READING_SPACE ", tag, " prompt=", shown, " vitals=", vitals)
				if shown.intersects(vitals) or shown.intersects(player.prompt_obstacle_rect()):
					_fail("actual pictured world prompt intersects character or visible vitals")


func _capture_player_poses() -> void:
	var player := _level.player
	var original_direction := AimInput._last_stick_dir
	AimInput.set_virtual_gamepad(player, true)
	for direction in [Vector2.RIGHT, Vector2.LEFT]:
		AimInput.restore_direction(direction)
		Input.action_release(&"move_down")
		await get_tree().create_timer(0.35).timeout
		var face := 1 if direction.x > 0.0 else -1
		if player.facing != face or player.is_crouching or not player.is_on_floor():
			_fail("actual standing physics pose did not settle")
		await _capture("actual-standing-right" if face == 1 else "actual-standing-left")
		Input.action_press(&"move_down")
		await get_tree().create_timer(0.35).timeout
		if not player.is_crouching or player.facing != face or not player.is_on_floor():
			_fail("actual crouch physics input did not settle")
		await _capture("actual-crouching-right" if face == 1 else "actual-crouching-left")
	Input.action_release(&"move_down")
	AimInput.set_virtual_gamepad(player, false)
	AimInput.restore_direction(original_direction)
	await get_tree().create_timer(0.35).timeout


func _fail(reason: String) -> void:
	_failed = true
	printerr("NE228_FAIL ", reason)
	_diagnose("failure", null)

func _diagnose(tag: String, actor: NpcActor) -> void:
	var player: Player = _level.player if is_instance_valid(_level) and is_instance_valid(_level.player) else null
	var floor_y := INF
	if player != null:
		floor_y = _level._layout.floor_below(floori(player.global_position.x / _level._layout.tile_size), floori((player.global_position.y - 1) / _level._layout.tile_size))
	print("NE228_SOURCE ", tag, " actor=", actor.data.id if is_instance_valid(actor) else "none", " actor_pos=", actor.global_position if is_instance_valid(actor) else Vector2.ZERO, " actor_in_range=", actor._player_in_range if is_instance_valid(actor) else false, " talk_index=", actor.current_talk_index() if is_instance_valid(actor) else -1, " talking=", actor._talking if is_instance_valid(actor) else false, " player_alive=", player != null and not player.is_dead(), " player_pos=", player.global_position if player != null else Vector2.ZERO, " floor=", floor_y, " on_floor=", player.is_on_floor() if player != null else false, " lock=", GameplayLock.is_locked(), " paused=", get_tree().paused, " current=", Story._current_cinematic, " queued=", Story._cinematic_queue.size(), " dialogue=", Story._layer.is_cinematic_active())
