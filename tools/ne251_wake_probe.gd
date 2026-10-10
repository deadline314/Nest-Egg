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
## --legacy-fill 只用來拍修正前的對照（舞台演員跟著關卡補光）。

const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const WAKE := &"ch1_c09_wake"
const ACTOR := &"rin"
## 線性 HDR 讀回值；與 screenshot.gd 的曝光量測相同門檻。
const CLIPPED := 0.97
const CHANGED := 0.06
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


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
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
	_stage("probe-entry", {"mode": _mode, "cause": _cause, "renderer": RenderingServer.get_current_rendering_method()})
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
	if _mode == "sweep":
		await _sweep()
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
		if not await _wait(func() -> bool: return pit.triggered, "player weight triggers the pit plate", 15000):
			return false
		_stage("pit-triggered", {"rise_time": pit.data.rise_time})
	else:
		var info := DamageInfo.create(level.player.health.current, Combat.Team.ENEMY, &"probe_hit")
		info.ignore_invulnerability = true
		level.player.health.kill(info)
	if not await _wait(func() -> bool: return level.died, "actual death in the warehouse: " + _cause, 60000):
		return false
	_stage("died", _lighting_state())
	return true


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


func _screen_rect(items: Array[CanvasItem]) -> Rect2i:
	var to_screen := get_viewport().get_final_transform()
	var rect := Rect2()
	var first := true
	for item: CanvasItem in items:
		var sprite := item as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var xf := to_screen * sprite.get_global_transform_with_canvas()
		var local := sprite.get_rect()
		for corner: Vector2 in [local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]:
			var point := xf * corner
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return Rect2i(rect.grow(6.0))


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
	stats.merge({"line": dialogue._text.text, "sequence": sequence, "lighting": _lighting_state()})
	_stage("wake-measured", {"label": label, "clipped": stats.get("clipped"), "washed": stats.get("washed"),
		"luma": stats.get("luma"), "behind_luma": stats.get("behind_luma")})
	print("NE251_WAKE:", JSON.stringify(stats))
	return stats


## 藏頭、顯示、關泛光三張相減，只統計頭部自己的像素；同時存整張畫面與放大四倍的頭部。
func _measure_head(actor: CutsceneActor, shot_name: String) -> Dictionary:
	if not _check(actor != null and actor.rig != null, "stage actor with a rig: " + shot_name):
		return {}
	var rig := actor.rig
	var head := _head_sprites(rig)
	if not _check(not head.is_empty(), "head parts found on the stage actor: " + shot_name):
		return {}
	if _legacy_fill:
		rig.use_level_lighting = true
		await _frames_settle(4)
	var rect := _screen_rect(head)
	await _frames_settle(2)
	var shown := get_viewport().get_texture().get_image()
	var shot := Capture.image(get_viewport())
	shot.save_png(_out.path_join(shot_name + ".png"))
	var visible := rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	if visible.size.x > 0 and visible.size.y > 0:
		var crop := shot.get_region(visible)
		crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(_out.path_join(shot_name + "-head-x4.png"))
	for item: CanvasItem in head:
		item.visible = false
	await _frames_settle(3)
	var hidden := get_viewport().get_texture().get_image()
	for item: CanvasItem in head:
		item.visible = true
	var env := LightKit.environment()
	var glow_before := env.glow_intensity
	env.glow_intensity = 0.0
	await _frames_settle(3)
	var flat := get_viewport().get_texture().get_image()
	env.glow_intensity = glow_before
	var stats := _head_stats(hidden, shown, flat, rect)
	stats.merge({"shot": shot_name, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"actor_fill": rig._fill, "actor_light_cap": rig._light_cap, "use_level_lighting": rig.use_level_lighting,
		"passed": stats["head_pixels"] >= MIN_HEAD_PIXELS and stats["clipped"] <= MAX_CLIPPED and stats["washed"] <= MAX_WASHED})
	return stats


func _head_stats(hidden: Image, shown: Image, flat: Image, rect: Rect2i) -> Dictionary:
	var changed := 0
	var changed_flat := 0
	var clipped := 0
	var bright := 0
	var washed := 0
	var over_one := 0
	var luma_sum := 0.0
	var behind_sum := 0.0
	var peak := 0.0
	var peak_color := Color.BLACK
	for y in range(maxi(0, rect.position.y), mini(shown.get_height(), rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(shown.get_width(), rect.end.x)):
			var base := hidden.get_pixel(x, y)
			var with_head := shown.get_pixel(x, y)
			if absf(with_head.r - base.r) + absf(with_head.g - base.g) + absf(with_head.b - base.b) > CHANGED:
				changed += 1
				var luma := with_head.r * 0.2126 + with_head.g * 0.7152 + with_head.b * 0.0722
				var behind := base.r * 0.2126 + base.g * 0.7152 + base.b * 0.0722
				luma_sum += luma
				behind_sum += behind
				var top := maxf(with_head.r, maxf(with_head.g, with_head.b))
				if top > peak:
					peak = top
					peak_color = with_head
				if top > 1.0:
					over_one += 1
				if with_head.r > CLIPPED and with_head.g > CLIPPED and with_head.b > CLIPPED:
					clipped += 1
				if luma > 0.8:
					bright += 1
				if luma > WASHED_LUMA and absf(luma - behind) < WASHED_GAP:
					washed += 1
			var plain := flat.get_pixel(x, y)
			if absf(plain.r - base.r) + absf(plain.g - base.g) + absf(plain.b - base.b) > CHANGED:
				changed_flat += 1
	var count := maxf(1.0, float(changed))
	return {"head_pixels": changed, "clipped": float(clipped) / count, "washed": float(washed) / count,
		"bright": float(bright) / count, "over_one": float(over_one) / count,
		"halo": float(changed) / maxf(1.0, float(changed_flat)), "luma": luma_sum / count,
		"behind_luma": behind_sum / count, "peak": peak, "peak_color": [peak_color.r, peak_color.g, peak_color.b],
		"hdr_format": shown.get_format()}


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
					var key := "%s|%s|%s|%s" % [stage_step.get("id"), step.get("pos"), step.get("scale"), step.get("pose", "")]
					if seen.has(key):
						continue
					seen[key] = true
					cases.append({"scene": str(id), "stage": str(stage_step.get("id")), "stage_step": stage_step, "actor_step": step})
	return cases


func _sweep() -> void:
	var cases := _sweep_cases()
	_check(not cases.is_empty(), "animated scenes with the lead on a stage found")
	var results: Array[Dictionary] = []
	for index in cases.size():
		var case := cases[index]
		var stats := await _sweep_case(index, case, false)
		if int(stats.get("head_pixels", 0)) < MIN_HEAD_PIXELS:
			# 主角這一步還在畫面外（之後才走進來）：改放在鏡頭中央再量一次，舞台才不會漏掉。
			stats = await _sweep_case(index, case, true)
		_check(int(stats.get("head_pixels", 0)) >= MIN_HEAD_PIXELS, "lead's head measured on stage: " + case["stage"])
		results.append(stats)
		print("NE251_SWEEP:", JSON.stringify({"shot": stats.get("shot"), "scene": case["scene"], "passed": stats.get("passed"),
			"centered": stats.get("centered"), "clipped": stats.get("clipped"), "washed": stats.get("washed"),
			"luma": stats.get("luma"), "behind_luma": stats.get("behind_luma"), "head_pixels": stats.get("head_pixels")}))
	_report["sweep"] = results


func _sweep_case(index: int, case: Dictionary, centered: bool) -> Dictionary:
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
	var name := "sweep-%02d-%s%s" % [index, case["stage"], "-centered" if centered else ""]
	var stats: Dictionary = {}
	if player._actors.has(ACTOR):
		stats = await _measure_head(player._actors[ACTOR], name)
	else:
		_check(false, "lead actor missing on stage: " + name)
	stats.merge({"scene": case["scene"], "stage": case["stage"], "pose": str(actor_step.get("pose", "")),
		"pos": actor_step.get("pos"), "scale": actor_step.get("scale"), "centered": centered})
	player.skip()
	player.queue_free()
	await _frames_settle(2)
	return stats


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report.merge({"mode": _mode, "cause": _cause, "legacy_fill": _legacy_fill, "checks": _checks, "failures": _failures,
		"pid": OS.get_process_id(), "wake_starts": _wake_starts, "events": _events,
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
