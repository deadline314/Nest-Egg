extends Node
## BG-32 managed environment residency. Direct stage construction, never story play.
## Native: --out=<absolute> [--rounds=1] [--dwell=300] [--levels=a,b,a]
## CPU: --self-test. Native negative control: --control=skip-stage|hold-stage.
const DEFAULT_LEVELS: PackedStringArray = ["ch1_street", "ch1_booth_alley", "ch1_street", "ch1_warehouse", "ch1_vault", "ch1_lounge", "ch1_stall", "ch1_pawnshop_dawn", "ch1_rooftop", "ch1_pawnshop", "ch1_street"]
const ENV := "res://art/environment/"
const ENTER_FRAMES := 90
const STAGE_FRAMES := 12
const MAX_WHITE_SHARE := 0.05
const MAX_RATIO := 1.10
const MAX_SCENES := 1024
var _levels := DEFAULT_LEVELS
var _rounds := 1
var _dwell := 300
var _out := ""
var _control := ""
var _level: Level
var _held_control: Texture2D
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _self_test := false
var _skipped_control := false
var _observer := ErrorObserver.new()
var _owner_runs: Array[Dictionary] = []
var _checks := 0
var _source_shas := {}

# Same bounded, thread-safe Logger pattern as the existing BG-31 native probe.
class ErrorObserver extends Logger:
	var mutex := Mutex.new()
	var count := 0
	var rows: Array[Dictionary] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		# Gate failures already live in _failures; the engine reports push_error
		# as variant_utility.cpp, so distinguish our exact diagnostic prefix.
		if kind == Logger.ERROR_TYPE_WARNING or code.begins_with("[TextureRouteProbe] "): return
		mutex.lock()
		count += 1
		if rows.size() < 16: rows.append({"function": function, "file": file, "line": line, "code": code, "rationale": rationale, "type": kind})
		mutex.unlock()
	func snapshot() -> Dictionary:
		mutex.lock()
		var result := {"count": count, "rows": rows.duplicate(true)}
		mutex.unlock()
		return result

func _ready() -> void:
	OS.add_logger(_observer)
	for path: String in ["core/asset_prefetch.gd", "core/texture_release.gd", "core/lit_textures.gd", "game/rig/rig_library.gd"]:
		_source_shas[path] = FileAccess.get_sha256("res://" + path)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="): _levels = arg.trim_prefix("--levels=").split(",", false)
		elif arg.begins_with("--rounds="): _rounds = int(arg.trim_prefix("--rounds="))
		elif arg.begins_with("--dwell="): _dwell = int(arg.trim_prefix("--dwell="))
		elif arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--control="): _control = arg.trim_prefix("--control=")
		elif arg == "--self-test": _self_test = true
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[TextureRouteProbe] " + message)

func _run() -> void:
	if _self_test:
		_self_checks()
		if _control == "engine-error": push_error("[BG32 self-test] intentional Logger negative control")
		get_tree().quit(0 if _failures.is_empty() and _observer.snapshot()["count"] == 0 else 1)
		return
	_check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus", "acceptance requires native Forward+")
	_check(_levels.size() >= 2 and _levels[0] == _levels[-1] and _rounds in range(1, 5) and _dwell in range(40, 3601), "route must be bounded, nonempty, and return to its first area")
	_check(_out.is_absolute_path() and not FileAccess.file_exists(_out.path_join("report.json")), "fresh absolute output directory required")
	_check(_control in ["", "skip-stage", "hold-stage"], "unknown negative control")
	if not _failures.is_empty():
		get_tree().quit(2)
		return
	_check(DirAccess.make_dir_recursive_absolute(_out) == OK, "create output directory")
	Story.auto_skip = true
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	for id: String in Story.scene_ids(): Story._seen[StringName(id)] = true
	add_child(LightKit.create_environment())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for round_index in _rounds:
		for index in _levels.size():
			var record := await _visit(_levels[index], round_index + 1, index + 1)
			_records.append(record)
			print("ROUTE level=%s payload=%d stage_residents=%d built=%d enter_max_ms=%.3f" % [_levels[index], record["payload_bytes"], record.get("stage_residents", []).size(), record["built_stages"].size(), record.get("enter_max_ms", 0)])
	var first: Dictionary = _records[0]
	var last: Dictionary = _records[-1]
	var ratio := float(last["payload_bytes"]) / maxf(1.0, float(first["payload_bytes"]))
	_check(first["payload_bytes"] > 0 and ratio <= MAX_RATIO, "returned environment payload ratio %.6f exceeds original 110%% gate" % ratio)
	var built := 0
	for row: Dictionary in _records: built += row["built_stages"].size()
	_check(built > 0, "route did not exercise any actual stage")
	if _control != "": _check(not _failures.is_empty(), "negative control failed to trigger a gate")
	var report := {"schema": 2, "scope": "direct Level/stage resource lifecycle plus representative actual CutscenePlayer; not natural story or Main route", "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "tool_sha256": FileAccess.get_sha256(get_script().resource_path), "source_shas": _source_shas, "control": _control, "ratio": ratio, "records": _records, "owner_runs": _owner_runs, "checks": _checks, "failures": _failures, "prefetch": AssetPrefetch.stats()}
	report["runtime"] = {"light_quality": Settings.get_light_quality(), "viewport": [get_viewport().size.x, get_viewport().size.y], "hdr_2d": get_viewport().use_hdr_2d, "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	Story.reset_active_presentation(&"probe_cleanup")
	if is_instance_valid(_level): _level.queue_free()
	_held_control = null
	for frame in 6: await get_tree().process_frame
	await AudioRelease.settle(get_tree())
	report["observer"] = _observer.snapshot()
	_check(report["observer"]["count"] == 0, "engine or script errors occurred; inspect observer/raw log")
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	_check(file != null, "report must be writable")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		_check(file.get_error() == OK, "report write must succeed")
		file.close()
	print("ROUTE_SUMMARY ratio_with_prefetch=%.6f stages_built=%d failures=%d" % [ratio, built, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _exit_tree() -> void:
	OS.remove_logger(_observer)

func _visit(id: String, round_index: int, stop: int) -> Dictionary:
	var started := Time.get_ticks_usec() # Before synchronous old teardown/load/configure/add_child.
	Story.reset_active_presentation(&"route")
	if is_instance_valid(_level): _level.queue_free()
	_level = null
	var data := load("res://data/levels/%s.tres" % id) as LevelData
	_check(data != null, "missing LevelData: " + id)
	if data == null: return {"payload_bytes": 0, "built_stages": []}
	GameState.pending_portal = &""
	_level = Level.new()
	_level.configure(data)
	add_child(_level)
	var sync_ms := (Time.get_ticks_usec() - started) / 1000.0
	var entering := await _frame_times(ENTER_FRAMES, started)
	_level.hud.visible = false
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"): enemy.queue_free()
	var coverage := _coverage(data, _level._layout)
	for issue: String in coverage["issues"]: _check(false, id + ": " + issue)
	var stages := await _watch_scenes(coverage["stages"])
	if round_index == 1 and stop == 1:
		await _exercise_owner(false)
		await _exercise_owner(true)
	await _drain()
	for frame in _dwell: await get_tree().process_frame
	TextureRelease.request()
	for frame in 6: await get_tree().process_frame
	if _control == "hold-stage" and _held_control == null and not coverage["stages"].is_empty():
		var definition := StageLibrary.definition(StringName(coverage["stages"].keys()[0]))
		for layer: Dictionary in definition.get("layers", []):
			if layer.get("kind") == "sprite" and _is_stage(str(layer.get("path", ""))):
				_held_control = RigLibrary.texture(layer["path"])
				break
	var record := _loaded()
	record["neighbor_requests"] = _neighbor_inventory(data)
	record["unexpected_backdrop"] = _unexpected_backdrop(record, data)
	_check(record["unexpected_backdrop"].is_empty(), id + ": backdrop textures not used by the current theme: " + JSON.stringify(record["unexpected_backdrop"]))
	var white := await _capture("r%d-s%02d-%s" % [round_index, stop, id])
	for issue: String in _record_issues(record, coverage["stages"].keys(), stages["built"], white): _check(false, id + ": " + issue)
	record.merge({"round": round_index, "stop": stop, "level": id, "sync_load_build_ms": sync_ms, "enter_frames_ms": entering, "enter_max_ms": entering.max(), "white_share": white, "coverage": coverage, "built_stages": stages["built"], "stage_timings": stages["timings"], "prefetch": AssetPrefetch.stats()})
	return record

static func _unexpected_backdrop(record: Dictionary, data: LevelData) -> Array:
	var wanted := {}
	# Every real Level creates ForegroundLayer. These are live foreground strips,
	# despite sharing the backdrop directory; use its authored constants.
	for path: String in [ForegroundLayer.TOP_TEXTURE, ForegroundLayer.BOTTOM_TEXTURE]:
		wanted[path] = true
		wanted[path.get_basename() + "_glow." + path.get_extension()] = true
	if data.environment != null:
		var layers: Array = Array(data.environment.backdrop)
		if data.environment.sky != null: layers.append(data.environment.sky)
		for layer: BackdropLayer in layers:
			if layer == null: continue
			for path: String in [layer.texture, layer.glow_path(), layer.texture.get_basename() + "_n." + layer.texture.get_extension()]: wanted[path] = true
	var unused: Array = []
	for row: Dictionary in record.get("textures", []):
		if row["path"].begins_with(ENV + "backdrop/") and not wanted.has(row["path"]): unused.append(row)
	return unused

static func _neighbor_inventory(data: LevelData) -> Dictionary:
	var expected := {}
	for resource: Resource in data.legend.values():
		if resource is PortalData and not resource.target_level.is_empty():
			var neighbor := load(resource.target_level) as LevelData
			if neighbor != null:
				for path: String in AssetPrefetch.level_texture_paths(neighbor): expected[path] = true
	var missing: Array[String] = []
	for path: String in expected:
		if not AssetPrefetch._cache.has(path): missing.append(path)
	return {"expected_unique": expected.size(), "missing_from_prefetch": missing, "note": "budget eviction may explain misses; this is an observation, not an extra cache-size gate"}

func _drain() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var stats := AssetPrefetch.stats()
		if stats["queued"] == 0 and stats["inflight"] == 0 and stats["retiring"] == 0: return
		await get_tree().process_frame
	_check(false, "prefetch failed to drain before bounded deadline")

func _frame_times(count: int, previous: int) -> Array[float]:
	var times: Array[float] = []
	for frame in count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
	return times

## Traverse all authored alternatives, without evaluating eligibility or writing outcomes.
static func _scene_manifest(seeds: Dictionary, scenes: Dictionary) -> Dictionary:
	var pending: Array = seeds.keys()
	var sources := seeds.duplicate(true)
	var visited := {}
	var stages := {}
	var issues: Array[String] = []
	while not pending.is_empty() and visited.size() < MAX_SCENES:
		var id: String = str(pending.pop_front())
		if visited.has(id) or id.is_empty(): continue
		visited[id] = true
		if not scenes.get(id) is Dictionary:
			issues.append("missing authored scene " + id)
			continue
		var scene: Dictionary = scenes[id]
		var entries := StoryRules.entries(scene)
		# Dispatch routes are intentionally not containers in StoryRules.entries.
		for route: Variant in scene.get("routes", []):
			if route is Dictionary: entries.append_array(StoryRules.entries(route))
		for entry: Dictionary in entries:
			if entry.get("do") == "scene":
				var stage: String = str(entry.get("id", ""))
				if stage.is_empty(): issues.append("empty stage in " + id)
				elif not stages.has(stage): stages[stage] = {"scene": id, "source": sources[id]}
			# move.then is the post-movement pose, never a story edge.
			var targets: Array = [entry.get("then", "") if entry.get("do") != "move" else "", entry.get("target", "")]
			var failures: Variant = entry.get("on_failure", {})
			if failures is Dictionary: targets.append_array(failures.values())
			for target: Variant in targets:
				if target is String and not target.is_empty() and not visited.has(target):
					if not sources.has(target): sources[target] = str(sources[id]) + " -> " + id
					pending.append(target)
	if not pending.is_empty(): issues.append("scene graph exceeds bounded coverage")
	return {"stages": stages, "scenes": visited.keys(), "seeds": seeds, "issues": issues}

static func _coverage(data: LevelData, layout: LevelLayout) -> Dictionary:
	var seeds := {}
	if data.intro_scene != &"": seeds[String(data.intro_scene)] = "level intro: " + data.resource_path
	for id: String in data.story_triggers: seeds[id] = "level trigger: " + data.resource_path
	for id: Variant in data.channel_scenes.values(): seeds[String(id)] = "level channel: " + data.resource_path
	for spawn: Dictionary in layout.spawns:
		var npc := spawn["resource"] as NpcData
		if npc == null: continue
		for talk: NpcTalk in npc.talks:
			if talk != null and talk.scene != &"": seeds[String(talk.scene)] = "NPC " + npc.resource_path + " @ " + str(spawn["cell"])
	for key: String in ["_death_scenes", "_respawn_scenes"]:
		var chapter: Variant = Story.get(key).get(data.chapter, [])
		for entry: Variant in chapter:
			if entry is Dictionary and not str(entry.get("scene", "")).is_empty(): seeds[str(entry["scene"])] = key + ": " + String(data.chapter)
	return _scene_manifest(seeds, Story._scenes)

func _watch_scenes(expected: Dictionary) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var built: Array[String] = []
	var timings: Array[Dictionary] = []
	for id: String in expected:
		if _control == "skip-stage" and not _skipped_control:
			_skipped_control = true
			continue
		if not ResourceLoader.exists(StageLibrary.path_of(StringName(id))):
			_check(false, "missing stage resource " + id)
			continue
		var started := Time.get_ticks_usec()
		var stage := StageLibrary.build(StringName(id))
		if stage == null:
			_check(false, "stage build failed " + id)
			continue
		layer.add_child(stage)
		var sync := (Time.get_ticks_usec() - started) / 1000.0
		var enter := await _frame_times(STAGE_FRAMES, started)
		started = Time.get_ticks_usec()
		stage.queue_free()
		TextureRelease.request()
		var leaving := await _frame_times(6, started)
		built.append(id)
		timings.append({"stage": id, "source": expected[id], "sync_build_ms": sync, "enter_frames_ms": enter, "exit_release_frames_ms": leaving})
	layer.queue_free()
	return {"built": built, "timings": timings}

## Actual authored scene and actual player UI/tweens/actor/FX holder lifecycle.
## Standalone owner: does not simulate a real death or commit Story results.
func _exercise_owner(cancelled: bool) -> void:
	var id := &"ch1_c09_wake"
	var before := var_to_bytes([GameState.story_progress_snapshot(), Progression.snapshot()])
	var player := CutscenePlayer.new()
	add_child(player)
	var finished := [false]
	player.finished.connect(func(_id: StringName) -> void: finished[0] = true)
	var retired: WeakRef = weakref(player)
	var started := Time.get_ticks_usec()
	player.play(id, Story._scenes[String(id)])
	var sync_play_ms := (Time.get_ticks_usec() - started) / 1000.0
	var samples: Array[float] = []
	var observed := false
	var held: Dictionary = {}
	var previous := started
	var deadline := Time.get_ticks_msec() + 30000
	while is_instance_valid(player) and player.is_running() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
		if not is_instance_valid(player): break
		if player._stage != null and not observed:
			observed = true
			# Readback is excluded from this frame clock, as in the per-area inventory.
			held = _loaded()
			held["stage_instance"] = player._stage.get_instance_id()
			held["scene"] = String(id)
			previous = Time.get_ticks_usec()
			if cancelled: player.cancel()
		if is_instance_valid(player) and player._dialogue.visible:
			player._dialogue.complete()
			player._advance_requested = true
	if is_instance_valid(player): player.cancel()
	player = null
	var release_started := Time.get_ticks_usec()
	var release := await _frame_times(6, release_started)
	_check(observed and retired.get_ref() == null and finished[0] != cancelled, "actual CutscenePlayer must enter and naturally finish/cancel, then retire")
	_check(before == var_to_bytes([GameState.story_progress_snapshot(), Progression.snapshot()]), "standalone player lifecycle must not apply story outcomes")
	var after := _loaded()
	_check(after["stage_residents"].is_empty(), "actual CutscenePlayer teardown left a stage texture")
	_owner_runs.append({"scene": String(id), "cancelled": cancelled, "finished_signal": finished[0], "held": held, "sync_play_ms": sync_play_ms, "frames_ms": samples, "exit_release_frames_ms": release, "after": after})

static func _is_stage(path: String) -> bool:
	return path.begins_with(ENV) and (path.contains("/stages/") or path.contains("/scenes/"))

## Exact imported image payload, outside timing. This is not dedicated VRAM.
static func _loaded() -> Dictionary:
	var textures := {}
	var owners := {}
	var groups := {"rig_cache": RigLibrary._texture_cache, "lit_normal": {}, "prefetch": AssetPrefetch._cache, "prefetch_retiring": {}}
	for path: String in LitTextures._normals:
		var normal: Texture2D = LitTextures._normals[path]
		groups["lit_normal"][normal.resource_path] = normal
	for texture: Texture2D in AssetPrefetch._retiring: groups["prefetch_retiring"][texture.resource_path] = texture
	for owner: String in groups:
		for path: String in groups[owner]:
			if not path.begins_with(ENV): continue
			textures[path] = groups[owner][path]
			if not owners.has(path): owners[path] = []
			owners[path].append(owner)
	var renderer := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	var scope: String = AssetPrefetch.stats()["scope"]
	var rows: Array[Dictionary] = []
	var stages: Array[Dictionary] = []
	var bytes := 0
	for path: String in textures:
		var texture: Texture2D = textures[path]
		var image := texture.get_image()
		var row := {"path": path, "owners": owners[path], "prefetch_scope": scope if owners[path].has("prefetch") else "", "bytes": image.get_data_size() if image != null else 0, "width": texture.get_width(), "height": texture.get_height(), "format": image.get_format() if image != null else -1, "mipmaps": image.has_mipmaps() if image != null else false}
		bytes += row["bytes"]
		rows.append(row)
		if _is_stage(path): stages.append(row)
	return {"payload_bytes": bytes, "textures": rows, "stage_residents": stages, "renderer_texture_bytes": renderer}

static func _record_issues(record: Dictionary, expected: Array, built: Array, white: float) -> Array[String]:
	var issues: Array[String] = []
	for id: String in expected:
		if not built.has(id): issues.append("missing stage coverage: " + id)
	if not record.get("stage_residents", []).is_empty(): issues.append("stage textures remain while no cutscene is playing: " + JSON.stringify(record["stage_residents"]))
	if not is_finite(white) or white > MAX_WHITE_SHARE: issues.append("white share exceeds original 5% gate: " + str(white))
	if record.get("payload_bytes", 0) <= 0: issues.append("empty environment inventory")
	return issues

func _capture(name: String) -> float:
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image != null and not image.is_empty(), "native viewport readback")
	if image == null or image.is_empty(): return INF
	_check(image.save_png(_out.path_join(name + ".png")) == OK, "native screenshot write: " + name)
	image.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var white := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.r > .92 and pixel.g > .92 and pixel.b > .92: white += 1
	return float(white) / (image.get_width() * image.get_height())

func _self_checks() -> void:
	var fixtures := {"root": {"routes": [{"target": "choice"}]}, "choice": {"steps": [{"do": "branch", "steps": [{"do": "choice", "options": [{"target": "stage"}]}]}]}, "stage": {"steps": [{"do": "scene", "id": "real"}, {"do": "move", "then": "idle"}], "then": "root"}}
	var result := _scene_manifest({"root": "actual fixture NPC"}, fixtures)
	_check(result["issues"].is_empty() and result["stages"].has("real") and result["scenes"].size() == 3, "dispatch/branch/choice/cycle coverage")
	_check(not _scene_manifest({"missing": "source"}, fixtures)["issues"].is_empty(), "missing scene must fail")
	var valid := {"payload_bytes": 100, "stage_residents": []}
	_check(_record_issues(valid, ["real"], ["real"], .05).is_empty(), "original exact white boundary passes")
	_check(not _record_issues(valid, ["real"], [], .0).is_empty(), "omitted stage cannot pass")
	_check(not _record_issues({"payload_bytes": 100, "stage_residents": [{"owners": ["prefetch"]}]}, [], [], .0).is_empty(), "prefetch-only stage cannot pass")
	_check(not _record_issues(valid, [], [], .05001).is_empty(), "white gate cannot pass above 5%")
	_check(not _record_issues({"payload_bytes": 0}, [], [], .0).is_empty(), "empty inventory cannot pass")
	_check(110.0 / 100.0 <= MAX_RATIO and not 110.01 / 100.0 <= MAX_RATIO, "original 110% ratio boundary remains strict")
	var street := load("res://data/levels/ch1_street.tres") as LevelData
	var actual := _coverage(street, LevelBuilder.parse(street))
	_check(actual["issues"].is_empty() and actual["stages"].has("ch1_revival_room"), "actual chapter death stage is covered beyond old trigger-only scan")
	_check(_unexpected_backdrop({"textures": [{"path": ENV + "backdrop/sky_storm.webp"}]}, street).is_empty(), "the real street sky is admitted")
	_check(not _unexpected_backdrop({"textures": [{"path": ENV + "backdrop/sky_dawn.webp", "owners": ["prefetch"]}]}, street).is_empty(), "an unused prefetched sky cannot pass")
	_check(_unexpected_backdrop({"textures": [{"path": ForegroundLayer.TOP_TEXTURE}]}, street).is_empty(), "a real current Level foreground strip is not an unused sky")
	print("ROUTE_SELF_TEST checks=", _checks, " failures=", _failures.size(), " actual_stages=", actual["stages"].keys())
