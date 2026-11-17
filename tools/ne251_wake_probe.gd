extends "res://tools/bg31_main_lifecycle_probe.gd"
## NE-251：量過場舞台上主角頭部的曝光，以及白髮和背後背景分不分得開。
## 選單、開場與死亡流程沿用返回選單驗收工具的真實輸入；進倉庫用主程式的換區入口、到水坑用擺位（不是整章通關證明）。
##
## 用法（原生 Forward+）：
##   godot --path . res://tools/ne251_wake_probe.tscn -- --out=<絕對資料夾> --slot=<絕對路徑.json> --phase=record
##     [--mode=route|isolated|resume|sweep] [--cause=flood|hit] [--deaths=N] [--frames=N] [--legacy-fill]
## route：真正的主程式進倉庫，溺斃（或受擊致死）後量診間醒來的畫面。
## isolated：不進關卡，直接播同一場過場當對照。
## resume：醒來途中回主選單再「繼續遊戲」，量重播的醒來畫面。
## sweep：所有動畫過場裡主角第一次站上每個舞台的位置各量一次，列出還會過亮或糊掉的舞台。
## --deaths=N：量完第一次醒來後再死 N−1 次，確認之後走死亡畫面、不再進診間。
## --legacy-fill 只用來拍舊補光的受控對照；--blank-mask 是必須自然失敗的原生 H=0 負控制。

const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const WAKE := &"ch1_c09_wake"
const ACTOR := &"rin"
## 線性 HDR 讀回值；與 screenshot.gd 的曝光量測相同門檻。
const CLIPPED := 0.97
## 亮的頭部像素貼著差不多亮的背景：輪廓與髮絲會糊在一起。
const WASHED_LUMA := 0.75
const WASHED_GAP := 0.2
## 通過門檻：純白與糊掉的頭部像素比例。
const MAX_CLIPPED := 0.02
const MAX_WASHED := 0.05
## 頭部至少要量到這麼多像素才算有量到（主角在畫面外時是 0）。
const MIN_HEAD_PIXELS := 200
const HEAD_PARTS: PackedStringArray = ["head", "hair", "ponytail", "bangs"]
const SWEEP_SETTLE := 1.6

var _mode := "route"
var _cause := "flood"
var _frames := 12
var _legacy_fill := false
var _deaths := 1
var _wake_starts := 0
var _report: Dictionary = {}
var _blank_mask := false
const SWAY_UNIFORMS: Array[StringName] = [&"sway_a", &"sway_a_shape", &"sway_b", &"sway_b_shape", &"sway_padding", &"sway_bounds"]


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--blank-mask":
			_blank_mask = true
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--cause="):
			_cause = argument.trim_prefix("--cause=")
		elif argument == "--legacy-fill":
			_legacy_fill = true
		elif argument.begins_with("--deaths="):
			_deaths = clampi(int(argument.trim_prefix("--deaths=")), 1, 6)
		elif argument.begins_with("--frames="):
			_frames = clampi(int(argument.trim_prefix("--frames=")), 0, 40)
	if _mode not in ["route", "isolated", "resume", "sweep"] or _cause not in ["flood", "hit"]:
		push_error("[NE251] --mode=route|isolated|resume|sweep, --cause=flood|hit")
		get_tree().quit(2)
		return
	super()


func _opening() -> bool:
	var expected_lines := 0
	for step: Dictionary in Story._scenes.get(String(INTRO), {}).get("steps", []):
		if str(step.get("do", "")) == "say":
			expected_lines += 1
		if not _check(str(step.get("do", "")) not in ["branch", "choice"], "opening has no invented branching selection"):
			return false
	if not _check(expected_lines > 0, "current authored opening contains dialogue"):
		return false
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and _failures == 0:
		if _world_ready() and _finishes == 1:
			break
		if Story.is_cinematic_active() and Story._current_cinematic != INTRO:
			_check(false, "unexpected cinematic is not guessed or bypassed")
			break
		var player := Story._player as CutscenePlayer
		if is_instance_valid(player) and player.scene_id == INTRO and player._running:
			if player.skipping or player.user_skipped or player.speed != 1.0:
				_check(false, "actual opening must retain normal speed without skip")
				break
			if player.choice_active():
				_check(false, "baseline opening unexpectedly has a choice; no invented selection")
				break
			var dialogue := player._dialogue as CutsceneDialogue
			if _opaque(dialogue) and dialogue.is_complete() and not dialogue._text.text.is_empty() \
					and (not dialogue._frame.visible or _opaque(dialogue._frame)) \
					and player._fade.color.a <= 0.001 and not Transition.is_active():
				var line := player._current_where + "|" + dialogue._text.text
				if line != _last_line:
					if not _opening_shot:
						await _shot("cinematic")
						_opening_shot = _failures == 0
					if _failures != 0:
						break
					_last_line = line
					_accept_lines += 1
					_stage("authored-line-accept", {"where": player._current_where,
						"text": dialogue._text.text, "scene": String(player.scene_id)})
					_action(&"ui_accept", true)
					await get_tree().process_frame
					_action(&"ui_accept", false)
		await get_tree().process_frame
	return _check(_world_ready() and _starts == 1 and _finishes == 1 and _accept_lines == expected_lines
		and _opening_shot and Story._completed.has(INTRO),
		"natural current opening: all authored complete lines, one start/completion, playable world")


func _level_ready(path: String) -> bool:
	if not _route_idle() or not _main._screen is Level or Story.is_cinematic_active() or GameplayLock.is_locked():
		return false
	var level := _main._screen as Level
	return level.is_initialized() and level.data.resource_path == path and is_instance_valid(level.player) \
		and not level.player.is_dead() and not get_tree().paused


func _find_pit(root: Node) -> FloodPit:
	for child: Node in root.get_children():
		if child is FloodPit:
			return child as FloodPit
		var nested := _find_pit(child)
		if nested != null:
			return nested
	return null


func _on_wake_started(id: StringName, _mode_name: StringName) -> void:
	if id == WAKE:
		_wake_starts += 1


func _run() -> void:
	_stage("probe-entry", {"mode": _mode, "cause": _cause, "renderer": RenderingServer.get_current_rendering_method(), "user_data_dir": OS.get_user_data_dir(), "tool_sha256": FileAccess.get_sha256(get_script().resource_path)})
	var store := RunSaveStore.new(_slot)
	store.validator = RunSnapshot.prepare
	if not _check(not store.exists(), "fresh isolated slot"):
		await _finish()
		return
	Story.scene_started.connect(_on_started)
	Story.scene_finished.connect(_on_finished)
	Story.scene_started.connect(_on_wake_started)
	_main = MainScene.instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	_main._run_store = store
	add_child(_main)
	if not await _wait(_menu_ready, "real Main initial menu route"):
		await _finish()
		return
	if _mode == "isolated":
		Story.play(WAKE, false)
		_report["wake"] = await _measure_wake("isolated")
		await _finish()
		return
	var menu := _main._screen as MainMenu
	if not await _press(menu._start_button, "MainMenu / 開始任務") or not await _press(menu._confirm_button, "difficulty / 出發"):
		await _finish()
		return
	menu = null
	if not await _opening():
		await _finish()
		return
	_main._on_area_requested(WAREHOUSE)
	if not await _wait(func() -> bool: return _level_ready(WAREHOUSE), "real area route into the warehouse", 60000):
		await _finish()
		return
	if _mode == "sweep":
		var level := _main._screen as Level
		if not _check(not level._layout.checkpoints.is_empty(), "authored safe warehouse checkpoint for dark-stage fixture"):
			await _finish()
			return
		# Explicit arrangement, not natural chapter traversal. Keep the actual Level/LightKit owner alive.
		level.player.global_position = level._layout.checkpoints[0]
		level.player.velocity = Vector2.ZERO
		await _frames_settle(4)
		if not await _wait_death_condition(func() -> bool: return not get_tree().paused and not GameplayLock.is_locked() \
				and level.player.is_on_floor(), "warehouse important readings complete and checkpoint feet grounded", 90000):
			await _finish()
			return
		await get_tree().create_timer(1.0, true).timeout
		if not _check(LightKit.character_fill > 1.0 and _main._screen == level and not level.died,
				"live dark warehouse retains amplified level fill before independent stages"):
			await _finish()
			return
		var context := _lighting_state()
		context.merge({"level": level.data.resource_path, "checkpoint": str(level.player.global_position),
			"arrangement": "Main warehouse route, authored safe checkpoint placement, real important-radio input"})
		_report["sweep_dark_source"] = context
		_stage("sweep-dark-source", context)
		await _sweep()
		await _finish()
		return
	if not await _die():
		await _finish()
		return
	if _mode == "resume":
		# 醒來途中回主選單，再用「繼續遊戲」進診間。
		await _wait(func() -> bool: return _story_actor() != null, "wake scene running before leaving", 30000)
		_main._show_main_menu()
		if not await _wait(_menu_ready, "menu after leaving the wake scene"):
			await _finish()
			return
		var resume_menu := _main._screen as MainMenu
		if not _check(resume_menu.continue_available, "Continue available after leaving mid-scene") \
				or not await _press(resume_menu._continue_button, "MainMenu / 繼續遊戲"):
			await _finish()
			return
		resume_menu = null
	_report["wake"] = await _measure_wake(_mode)
	_check(_wake_starts == (2 if _mode == "resume" else 1), "wake scene started the expected number of times")
	var later: Array[Dictionary] = []
	for number in range(2, _deaths + 1):
		var record := await _later_death(number)
		later.append(record)
		if record.is_empty():
			break
	_report["later_deaths"] = later
	await _finish()


## 真實死亡：水坑用擺位讓主角落在踏板上，由水坑自己淹死他；hit 用一次足以致死的敵方傷害。
func _die() -> bool:
	var level := _main._screen as Level
	if _cause == "flood":
		var pit := _find_pit(level)
		if not _check(pit != null, "warehouse flood pit present"):
			return false
		level.player.global_position = pit.global_position + Vector2(0.0, -4.0)
		level.player.velocity = Vector2.ZERO
		_stage("pit-placement", {"pit": str(pit.global_position), "player": str(level.player.global_position),
			"player_state": level.player.state, "collision_layer": level.player.collision_layer,
			"tree_paused": get_tree().paused, "lock": GameplayLock.is_locked(), "pit_processing": pit.can_process()})
		if not await _wait_death_condition(func() -> bool: return pit.triggered, "player weight triggers the pit plate", 90000):
			return false
		_stage("pit-triggered", {"rise_time": pit.data.rise_time})
	else:
		var info := DamageInfo.create(level.player.health.current, Combat.Team.ENEMY, &"probe_hit")
		info.ignore_invulnerability = true
		level.player.health.kill(info)
	if not await _wait_death_condition(func() -> bool: return level.died, "actual death in the warehouse: " + _cause, 90000):
		return false
	var death_state := _lighting_state()
	death_state.merge({"actual_cause": String(level._death_cause), "deaths": GameState.deaths, "health": level.player.health.current})
	_check(level._death_cause == (&"flood" if _cause == "flood" else &"probe_hit"), "Level records the actual requested death cause")
	_stage("died", death_state)
	return true


## 擺位會經過正式重要通訊觸發器；讀完真實完整句子，讓自己的世界凍結鎖自然釋放。
func _wait_death_condition(predicate: Callable, label: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	var last_line := ""
	while Time.get_ticks_msec() < deadline and _failures == 0:
		if predicate.call():
			return _check(true, label)
		var layer := Story._layer as DialogueLayer
		if is_instance_valid(layer) and layer.is_radio_frozen() and _opaque(layer._radio_root) \
				and _opaque(layer._radio_text) and layer._radio_text.visible_ratio >= 1.0:
			var line := str(layer._radio_queue.front().get("id", "")) + "|" + layer._radio_text.text
			if line != last_line:
				last_line = line
				_stage("important-radio-accept", {"line": line, "player_input": "ui_accept"})
				_action(&"ui_accept", true)
				await get_tree().process_frame
				_action(&"ui_accept", false)
		await get_tree().process_frame
	return _check(false, label + " (timeout or earlier failed check)")


func _find_death_screen(root: Node) -> DeathScreen:
	for child: Node in root.get_children():
		if child is DeathScreen:
			return child as DeathScreen
	return null


func _first_button(root: Node) -> Button:
	for child: Node in root.get_children():
		if child is Button and (child as Button).is_visible_in_tree():
			return child as Button
		var nested := _first_button(child)
		if nested != null:
			return nested
	return null


## 第一次醒來之後的死亡：跳過剩下的過場、重生、再受擊致死，預期出現死亡畫面而不是診間。
func _later_death(number: int) -> Dictionary:
	if Story.is_cinematic_active():
		Story.skip_cinematic()
	if not await _wait(func() -> bool: return _level_ready(WAREHOUSE), "respawned in the warehouse before death %d" % number, 60000):
		return {}
	var wakes_before := _wake_starts
	var level := _main._screen as Level
	var info := DamageInfo.create(level.player.health.current, Combat.Team.ENEMY, &"probe_hit")
	info.ignore_invulnerability = true
	level.player.health.kill(info)
	if not await _wait(func() -> bool: return level.died and _find_death_screen(level) != null,
			"death %d shows the death screen" % number, 30000):
		return {}
	var screen := _find_death_screen(level)
	if not await _wait(func() -> bool: return screen.sequence_complete and _first_button(screen) != null,
			"death screen %d ready for retry" % number, 30000):
		return {}
	await RenderingServer.frame_post_draw
	Capture.image(get_viewport()).save_png(_out.path_join("death-%d.png" % number))
	_check(_wake_starts == wakes_before and not Story.is_cinematic_active(), "death %d does not replay the clinic wake scene" % number)
	var record := {"death": number, "wake_starts": _wake_starts, "deaths_counted": GameState.deaths}
	if not await _press(_first_button(screen), "DeathScreen / retry %d" % number):
		return {}
	return record


func _story_player() -> CutscenePlayer:
	if not is_instance_valid(Story._player):
		return null
	var player := Story._player as CutscenePlayer
	return player if player != null and player.scene_id == WAKE else null


func _story_actor() -> CutsceneActor:
	var player := _story_player()
	return player._actors[ACTOR] if player != null and player._actors.has(ACTOR) else null


func _lighting_state() -> Dictionary:
	var env := LightKit.environment()
	return {"character_fill": LightKit.character_fill, "character_light_cap": LightKit.character_light_cap,
		"glow_threshold": env.glow_hdr_threshold, "glow_intensity": env.glow_intensity,
		"level_alive": _main._screen is Level, "tree_paused": get_tree().paused}


func _head_sprites(rig: CharacterRig) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	for part: CanvasItem in rig._parts:
		if part == null or not part.is_visible_in_tree():
			continue
		for key: String in HEAD_PARTS:
			if str(part.name).to_lower().contains(key):
				result.append(part)
				break
	return result


func _part_bounds(item: Node2D) -> Rect2:
	var bounds := Rect2()
	if item is Sprite2D and item.texture != null:
		bounds = item.get_rect()
	elif item is Polygon2D and item.get_bone_count() == 0 and not item.polygon.is_empty():
		bounds = Rect2(item.polygon[0], Vector2.ZERO)
		for point: Vector2 in item.polygon:
			bounds = bounds.expand(point)
	for uniform: StringName in [&"sway_a_shape", &"sway_b_shape"]:
		var shape: Variant = item.get_instance_shader_parameter(uniform)
		if shape is Vector2 and shape.x > 0.0:
			var padding: Variant = item.get_instance_shader_parameter(&"sway_padding")
			bounds = bounds.grow(absf(float(padding)) if padding != null else 24.0)
			break
	return bounds


func _screen_rect(items: Array[CanvasItem]) -> Rect2i:
	var rect := Rect2()
	var first := true
	for item: CanvasItem in items:
		var bounds := _part_bounds(item as Node2D)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			continue
		var xf := get_viewport().get_final_transform() * item.get_global_transform_with_canvas()
		for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
			var point := xf * corner
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	if first:
		return Rect2i()
	var start := Vector2i(floori(rect.position.x), floori(rect.position.y))
	var end := Vector2i(ceili(rect.end.x), ceili(rect.end.y))
	return Rect2i(start, end - start)


func _frames_settle(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 等第一句台詞完整顯示（白閃已結束）後量頭部。
func _measure_wake(label: String) -> Dictionary:
	if not await _wait(func() -> bool: return _story_actor() != null, "wake scene actor on stage: " + label, 60000):
		return {}
	var player := _story_player()
	var sequence: Array[Dictionary] = []
	for index in _frames:
		await get_tree().create_timer(0.25, true).timeout
		await RenderingServer.frame_post_draw
		if not is_instance_valid(player) or not player._running:
			break
		Capture.image(get_viewport()).save_png(_out.path_join("wake-%s-frame-%02d.png" % [label, index]))
		sequence.append({"index": index, "ticks_ms": Time.get_ticks_msec(), "flash_alpha": player._flash.color.a,
			"fade_alpha": player._fade.color.a})
	var dialogue := player._dialogue as CutsceneDialogue
	if not await _wait(func() -> bool: return is_instance_valid(player) and _opaque(dialogue) and dialogue.is_complete() \
			and not dialogue._text.text.is_empty() and player._fade.color.a <= 0.001 and player._flash.color.a <= 0.001,
			"first wake line fully shown after the flash: " + label, 60000):
		return {}
	var stats := await _measure_head(_story_actor(), "wake-" + label)
	stats.merge({"line": dialogue._text.text, "sequence": sequence, "lighting": _lighting_state(),
		"camera": {"pos": [player.cam_pos.x, player.cam_pos.y], "zoom": player.cam_zoom}})
	_stage("wake-measured", {"label": label, "clipped": stats.get("clipped"), "washed": stats.get("washed"),
		"luma": stats.get("luma"), "behind_luma": stats.get("behind_luma")})
	print("NE251_WAKE:", JSON.stringify(stats))
	return stats


## 量實際舞台 CanvasLayer 的不透明頭部；不把泛光或背景 RGB 差分當成面積。
## 此工具只支援未被前景遮住的頭部。PNG 必須另看；未知 shader、GPU 骨骼、祖先透明／裁切均拒絕。
func _measure_head(actor: CutsceneActor, shot_name: String, enforce := true) -> Dictionary:
	if not _check(actor != null and actor.rig != null, "stage actor with a rig: " + shot_name):
		return {}
	var rig := actor.rig
	var lighting_mode_before := rig.use_level_lighting
	var visual_head := _head_sprites(rig)
	var head: Array[CanvasItem] = []
	for part: CanvasItem in visual_head:
		if part.name == &"head":
			head.append(part)
	if not _check(head.size() == 1, "head parts found on the stage actor: " + shot_name):
		return {}
	for item: CanvasItem in visual_head:
		var shader := item.material as ShaderMaterial
		var supported := (item is Sprite2D or item is Polygon2D) and _part_bounds(item as Node2D).has_area() \
			and (item.material == null or (shader != null and shader.shader == CharacterRig.LIGHT_SHADER)) and is_equal_approx(item.self_modulate.a, 1.0)
		var ancestor: Node = item
		while ancestor is CanvasItem:
			supported = supported and is_equal_approx(ancestor.modulate.a, 1.0) \
				and ancestor.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED
			ancestor = ancestor.get_parent()
		if not _check(supported, "known CPU drawable, shader and opaque ancestor chain: " + String(item.name)):
			return {}
	if _legacy_fill:
		rig.use_level_lighting = true
		await _frames_settle(4)
	# All changes below are temporary probe state, restored before validation or return.
	# Explicit ALWAYS actors and bound camera tweens must be held as well as the Level.
	var modes: Array = []
	var nodes: Array[Node] = [get_tree().root]
	while not nodes.is_empty():
		var node := nodes.pop_back() as Node
		for child: Node in node.get_children():
			nodes.append(child)
		if node != self and not node.is_ancestor_of(self):
			modes.append([node, node.process_mode])
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var tweens: Array[Tween] = []
	for tween: Tween in get_tree().get_processed_tweens():
		if tween.is_running():
			tweens.append(tween)
			tween.pause()
	var clock := Engine.time_scale
	Engine.time_scale = 0.0
	var rect := _screen_rect(head)
	var visual_rect := _screen_rect(visual_head)
	var content := _content_rect()
	var before := _head_signature(visual_head)
	var viewport := get_viewport()
	var view := SubViewport.new()
	view.size = viewport.get_texture().get_image().get_size()
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.use_hdr_2d = true
	view.disable_3d = true
	view.canvas_item_default_texture_filter = viewport.canvas_item_default_texture_filter
	view.canvas_item_default_texture_repeat = viewport.canvas_item_default_texture_repeat
	view.msaa_2d = viewport.msaa_2d
	view.snap_2d_transforms_to_pixel = viewport.snap_2d_transforms_to_pixel
	view.snap_2d_vertices_to_pixel = viewport.snap_2d_vertices_to_pixel
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	for item: CanvasItem in head:
		var copy := item.duplicate(0) as Node2D
		for child: Node in copy.get_children():
			copy.remove_child(child)
			child.free()
		copy.process_mode = Node.PROCESS_MODE_DISABLED
		view.add_child(copy)
		# get_global_transform_with_canvas contains this actor's actual CanvasLayer/camera.
		copy.transform = viewport.get_final_transform() * item.get_global_transform_with_canvas()
		copy.z_index = 0
		var parent := item.get_parent()
		while parent is CanvasItem:
			if copy.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and parent.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
				copy.texture_filter = parent.texture_filter
			if copy.texture_repeat == CanvasItem.TEXTURE_REPEAT_PARENT_NODE and parent.texture_repeat != CanvasItem.TEXTURE_REPEAT_PARENT_NODE:
				copy.texture_repeat = parent.texture_repeat
			parent = parent.get_parent()
		for uniform: StringName in SWAY_UNIFORMS:
			var value: Variant = item.get_instance_shader_parameter(uniform)
			if value != null:
				copy.set_instance_shader_parameter(uniform, value)
		if _blank_mask:
			copy.hide()
	await _frames_settle(3)
	var mask := view.get_texture().get_image()
	var shown := viewport.get_texture().get_image()
	await _frames_settle(2)
	var shown_repeat := viewport.get_texture().get_image()
	var held := before == _head_signature(visual_head)
	var visibility: Array[bool] = []
	for item: CanvasItem in head:
		visibility.append(item.visible)
		item.hide()
	await _frames_settle(3)
	var hidden := viewport.get_texture().get_image()
	await _frames_settle(2)
	var hidden_repeat := viewport.get_texture().get_image()
	for index in head.size():
		head[index].visible = visibility[index]
	view.queue_free()
	Engine.time_scale = clock
	for entry: Array in modes:
		if is_instance_valid(entry[0]):
			entry[0].process_mode = entry[1]
	for tween: Tween in tweens:
		if tween.is_valid():
			tween.play()
	var restored := is_equal_approx(Engine.time_scale, clock) and before == _head_signature(visual_head)
	for entry: Array in modes:
		restored = restored and is_instance_valid(entry[0]) and entry[0].process_mode == entry[1]
	for tween: Tween in tweens:
		restored = restored and tween.is_valid() and tween.is_running()
	var stats := _head_stats(hidden, shown, mask, rect)
	var fits := Rect2i(Vector2i.ZERO, shown.get_size()).encloses(rect) and rect.has_area()
	stats.merge({"shot": shot_name, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"actor_fill": rig._fill, "actor_light_cap": rig._light_cap, "use_level_lighting": rig.use_level_lighting,
		"source_held": held, "geometry_fits": fits, "source": before, "probe_state_restored": restored,
		"head_inside_content": _inside_content(visual_rect, content),
		"visual_rect": [visual_rect.position.x, visual_rect.position.y, visual_rect.size.x, visual_rect.size.y],
		"content_rect": [content.position.x, content.position.y, content.size.x, content.size.y],
		"shown_stable": _same_region(shown, shown_repeat, rect), "hidden_stable": _same_region(hidden, hidden_repeat, rect),
		"blank_mask": _blank_mask,
		"scope": "primary name=head opaque source alpha on actual stage canvas; back hair excluded from H and visually reviewed in full-hair crop; unobstructed primary head requires native visual review; stable held scene, glow retained"})
	rig.use_level_lighting = lighting_mode_before
	stats["files_ok"] = true
	var files: Array[Dictionary] = []
	for pair: Array in [[shot_name, shown], [shot_name + "-shown-repeat", shown_repeat], [shot_name + "-hidden", hidden],
			[shot_name + "-hidden-repeat", hidden_repeat], [shot_name + "-head-alpha", mask]]:
		var image := pair[1] as Image
		var raw := _out.path_join(String(pair[0]) + ".bin")
		var writer := FileAccess.open(raw, FileAccess.WRITE)
		if writer == null:
			stats["files_ok"] = false
		else:
			writer.store_buffer(image.get_data())
			writer.close()
		var png := _out.path_join(String(pair[0]) + ".png")
		stats["files_ok"] = Capture.encode(image, true).save_png(png) == OK and stats["files_ok"]
		files.append({"raw": raw.get_file(), "png": png.get_file(), "format": image.get_format(),
			"width": image.get_width(), "height": image.get_height(), "bytes": image.get_data().size(),
			"sha256": FileAccess.get_sha256(raw), "png_sha256": FileAccess.get_sha256(png)})
	stats["files"] = files
	var visible := visual_rect.intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
	if visible.has_area():
		var crop := Capture.encode(shown.get_region(visible), true)
		crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		stats["files_ok"] = crop.save_png(_out.path_join(shot_name + "-head-x4.png")) == OK and stats["files_ok"]
	stats["passed"] = _exposure_passes(stats)
	if enforce:
		_check(stats["passed"], "valid HDR opaque head and exposure <= 2% clipped / 5% washed: " + shot_name)
	return stats


func _content_rect() -> Rect2:
	var safe := Story.framing.safe_rect()
	var final := get_viewport().get_final_transform()
	var rect := Rect2(final * safe.position, Vector2.ZERO)
	for corner: Vector2 in [Vector2(safe.end.x, safe.position.y), safe.end, Vector2(safe.position.x, safe.end.y)]:
		rect = rect.expand(final * corner)
	return rect


func _shift_actor_in_image(actor: Node2D, shift: Vector2) -> void:
	var parent := actor.get_parent() as CanvasItem
	var from_parent := get_viewport().get_final_transform() * parent.get_global_transform_with_canvas()
	actor.position += from_parent.affine_inverse().basis_xform(shift)


func _inside_content(head: Rect2i, content: Rect2) -> bool:
	return head.has_area() and content.encloses(Rect2(head))


func _head_signature(head: Array[CanvasItem]) -> Array:
	var result: Array = []
	for item: CanvasItem in head:
		var xf := get_viewport().get_final_transform() * item.get_global_transform_with_canvas()
		var state := {"path": str(item.get_path()), "class": item.get_class(), "visible": item.visible,
			"screen_transform": [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y],
			"geometry": hash(item.polygon) if item is Polygon2D else item.get_rect(),
			"modulate": item.modulate, "self_modulate": item.self_modulate,
			"texture": item.texture.resource_path, "colors": hash(item.vertex_colors) if item is Polygon2D else 0}
		for uniform: StringName in SWAY_UNIFORMS:
			state[String(uniform)] = item.get_instance_shader_parameter(uniform)
		result.append(state)
	return result


func _same_region(a: Image, b: Image, rect: Rect2i) -> bool:
	if a.get_format() != b.get_format() or a.get_size() != b.get_size():
		return false
	var visible := rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	return visible.has_area() and a.get_region(visible).get_data() == b.get_region(visible).get_data()


func _exposure_passes(stats: Dictionary) -> bool:
	return bool(stats.get("hdr_valid", false)) and bool(stats.get("source_held", false)) and bool(stats.get("probe_state_restored", false)) \
		and bool(stats.get("geometry_fits", false)) and bool(stats.get("head_inside_content", false)) and bool(stats.get("shown_stable", false)) \
		and bool(stats.get("hidden_stable", false)) and bool(stats.get("files_ok", false)) \
		and int(stats.get("head_pixels", 0)) >= MIN_HEAD_PIXELS \
		and float(stats.get("clipped", 1.0)) <= MAX_CLIPPED and float(stats.get("washed", 1.0)) <= MAX_WASHED


func _head_stats(hidden: Image, shown: Image, mask: Image, rect: Rect2i) -> Dictionary:
	var count := 0
	var clipped := 0
	var washed := 0
	var over_one := 0
	var luma_sum := 0.0
	var behind_sum := 0.0
	var peak := 0.0
	var hdr := shown.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBF, Image.FORMAT_RGBAH, Image.FORMAT_RGBAF] \
		and hidden.get_format() == shown.get_format() and mask.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF] \
		and shown.get_size() == hidden.get_size() and shown.get_size() == mask.get_size()
	if hdr:
		for y in range(maxi(0, rect.position.y), mini(shown.get_height(), rect.end.y)):
			for x in range(maxi(0, rect.position.x), mini(shown.get_width(), rect.end.x)):
				if mask.get_pixel(x, y).a < 0.999:
					continue
				count += 1
				var pixel := shown.get_pixel(x, y)
				var base := hidden.get_pixel(x, y)
				var luma := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
				var behind := base.r * 0.2126 + base.g * 0.7152 + base.b * 0.0722
				luma_sum += luma
				behind_sum += behind
				peak = maxf(peak, maxf(pixel.r, maxf(pixel.g, pixel.b)))
				over_one += int(maxf(pixel.r, maxf(pixel.g, pixel.b)) > 1.0)
				clipped += int(pixel.r > CLIPPED and pixel.g > CLIPPED and pixel.b > CLIPPED)
				washed += int(luma > WASHED_LUMA and absf(luma - behind) < WASHED_GAP)
	var denominator := maxf(1.0, count)
	return {"head_pixels": count, "clipped_pixels": clipped, "washed_pixels": washed, "hdr_valid": hdr,
		"clipped": float(clipped) / denominator, "washed": float(washed) / denominator,
		"over_one": float(over_one) / denominator, "luma": luma_sum / denominator,
		"behind_luma": behind_sum / denominator, "peak": peak, "hdr_format": shown.get_format(), "mask_format": mask.get_format()}


## 每個「舞台＋主角位置、縮放、姿勢」的組合只量一次：取自所有動畫過場裡主角登場的那一步。
func _sweep_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var seen: Dictionary = {}
	var ids := Story.scene_ids()
	ids.sort()
	for id: Variant in ids:
		var scene: Dictionary = Story._scenes.get(str(id), {})
		if str(scene.get("mode", "")) != String(Story.MODE_ANIMATED):
			continue
		var stage_step: Dictionary = {}
		for step: Variant in scene.get("steps", []):
			if typeof(step) != TYPE_DICTIONARY:
				continue
			match str(step.get("do", "")):
				"scene":
					stage_step = step
				"actor":
					if stage_step.is_empty() or str(step.get("kind", step.get("id", ""))) != String(ACTOR):
						continue
					var key := JSON.stringify([stage_step.get("id"), stage_step.get("pos"), stage_step.get("zoom", 1.0),
						step.get("pos"), step.get("scale"), step.get("pose", ""), step.get("facing", 1)])
					if seen.has(key):
						cases[seen[key]]["represented_scenes"].append(str(id))
						continue
					seen[key] = cases.size()
					cases.append({"scene": str(id), "represented_scenes": [str(id)], "stage": str(stage_step.get("id")), "stage_step": stage_step, "actor_step": step})
	return cases


func _sweep() -> void:
	var cases := _sweep_cases()
	_report["sweep_coverage"] = {"cases": cases, "scope": "actual Story animated stage and actor setup pairs including camera/facing variants; direct CutscenePlayer over live dark warehouse; existing skip hint excluded only during capture and restored; not product UI composition, full authored scene progression or natural gameplay"}
	_check(not cases.is_empty(), "animated scenes with the lead on a stage found")
	var results: Array[Dictionary] = []
	for index in cases.size():
		var case := cases[index]
		var stats := await _sweep_case(index, case, false)
		if int(stats.get("head_pixels", 0)) < MIN_HEAD_PIXELS or not bool(stats.get("head_inside_content", false)):
			# 畫外演員不能當成曝光通過；保留原位，再做明示的舞台曝光診斷擺位，不宣稱產品鏡頭已修。
			var authored := stats
			var bounds: Array = stats.get("visual_rect", [0, 0, 0, 0])
			var content: Array = stats.get("content_rect", [0, 0, 0, 0])
			var needs_x := float(bounds[0]) < float(content[0]) or float(bounds[0]) + float(bounds[2]) > float(content[0]) + float(content[2])
			if needs_x:
				stats = await _sweep_case(index, case, true)
			if not bool(stats.get("head_inside_content", false)):
				var prior := stats
				stats = await _sweep_case(index, case, needs_x, true)
				if needs_x:
					stats["x_centered_cut_head_attempt"] = prior
			stats["authored_offscreen_attempt"] = authored
		_check(bool(stats.get("passed", false)), "valid head and exposure on stage: " + case["stage"])
		results.append(stats)
		print("NE251_SWEEP:", JSON.stringify({"shot": stats.get("shot"), "scene": case["scene"], "passed": stats.get("passed"),
			"centered": stats.get("centered"), "clipped": stats.get("clipped"), "washed": stats.get("washed"),
			"luma": stats.get("luma"), "behind_luma": stats.get("behind_luma"), "head_pixels": stats.get("head_pixels")}))
	_report["sweep"] = results


func _sweep_case(index: int, case: Dictionary, centered: bool, fit_frame := false) -> Dictionary:
	var stage_step: Dictionary = case["stage_step"].duplicate(true)
	stage_step["fade"] = 0.3
	var actor_step: Dictionary = case["actor_step"].duplicate(true)
	actor_step["id"] = String(ACTOR)
	if centered:
		var camera: Array = stage_step.get("pos", [320.0, 180.0])
		var pos: Array = actor_step.get("pos", [320.0, 280.0])
		actor_step["pos"] = [float(camera[0]), float(pos[1])]
	var player := CutscenePlayer.new()
	add_child(player)
	player.play(&"ne251_sweep", {"mode": "animated", "steps": [stage_step, actor_step, {"do": "wait", "time": 60.0}]})
	await get_tree().create_timer(SWEEP_SETTLE, true).timeout
	_check(player._fade.color.a <= 0.001, "stage fully faded in before measuring: " + case["stage"])
	var name := "sweep-%02d-%s%s" % [index, case["stage"], "-xy-diagnostic" if fit_frame else ("-centered" if centered else "")]
	var stats: Dictionary = {}
	if player._actors.has(ACTOR):
		var actor: CutsceneActor = player._actors[ACTOR]
		var before_pos := actor.position
		if fit_frame:
			var bounds := _screen_rect(_head_sprites(actor.rig))
			var content := _content_rect()
			var shift := Vector2.ZERO
			if bounds.position.y < content.position.y:
				shift.y = content.position.y + 2.0 - bounds.position.y
			elif bounds.end.y > content.end.y:
				shift.y = content.end.y - 2.0 - bounds.end.y
			_shift_actor_in_image(actor, shift)
			await _frames_settle(2)
		# This is a stage-exposure fixture; the existing UI hint must not cover the head sample.
		var hint_before := player._skip_hint.visible
		player._skip_hint.hide()
		stats = await _measure_head(actor, name, false)
		var hint_hidden := not player._skip_hint.visible
		player._skip_hint.visible = hint_before
		var hint_restored := player._skip_hint.visible == hint_before
		stats["skip_hint_measurement"] = {"before_visible": hint_before, "hidden_during_capture": hint_hidden,
			"after_visible": player._skip_hint.visible, "restored": hint_restored,
			"scope": "stage exposure diagnostic only; existing skip hint temporarily excluded, not product UI composition acceptance"}
		stats["passed"] = bool(stats.get("passed", false)) and hint_hidden and hint_restored
		stats["diagnostic_actor_shift"] = {"before": str(before_pos), "after": str(actor.position),
			"scope": "XY diagnostic arrangement only; authored camera/position not repaired"} if fit_frame else {}
	else:
		_check(false, "lead actor missing on stage: " + name)
	stats.merge({"scene": case["scene"], "stage": case["stage"], "pose": str(actor_step.get("pose", "")), "lighting": _lighting_state(),
		"pos": actor_step.get("pos"), "scale": actor_step.get("scale"), "centered": centered, "xy_diagnostic": fit_frame})
	player.skip()
	player.queue_free()
	await _frames_settle(2)
	return stats


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report.merge({"mode": _mode, "cause": _cause, "legacy_fill": _legacy_fill, "checks": _checks, "failures": _failures,
		"pid": OS.get_process_id(), "tool_sha256": FileAccess.get_sha256(get_script().resource_path), "user_data_dir": OS.get_user_data_dir(), "measurement_protocol": "stage-opaque-alpha-held-hdr-v1", "wake_starts": _wake_starts, "events": _events,
		"thresholds": {"clipped": MAX_CLIPPED, "washed": MAX_WASHED, "washed_luma": WASHED_LUMA, "washed_gap": WASHED_GAP},
		"scope": "real Main, real death flow and wake cutscene; warehouse entry by Main's area route and pit by placement"})
	var file := FileAccess.open(_out.path_join("ne251-%s-%s.json" % [_mode, _cause]), FileAccess.WRITE)
	if file == null:
		push_error("[NE251] cannot write report: %s" % FileAccess.get_open_error())
		_failures += 1
	else:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	print("NE251_RESULT:", _checks, " checks / ", _failures, " failures")
	if is_instance_valid(_main):
		await _main._quit(0 if _failures == 0 else 1)
	else:
		get_tree().quit(1)
