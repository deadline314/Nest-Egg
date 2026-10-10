extends Node2D
## BG-31 repaired-production loader diagnostic. No Main/Story acceptance.
## Original frozen three-mode matrix is unchanged; this NEW scene tests product policy.
var _timing_rows: Array[Dictionary] = []
var _last_observed_loads := 0
var _last_observed_frame := -1
var _max_delta_ms := 0.0
var _current_delta_ms := 0.0
const LEVELS := ["res://data/levels/ch1_lounge.tres", "res://data/levels/ch1_pawnshop.tres"]
const CYCLES := 4
const DRAW_ITEMS := 64
const LIMIT_BYTES := 128 * 1024 * 1024
var _mode := ""
var _out := ""
var _failures := 0
var _checks := 0
var _overlap_phases := 0
var _levels: Array[LevelData] = []
var _batches: Array[Dictionary] = []
var _draw_textures: Array[Texture2D] = []
var _held_draw: Array[Texture2D] = []
var _queue: Array[String] = []
var _slots := PackedStringArray(["", "", "", ""])
var _cache: Dictionary[String, Texture2D] = {}
var _sizes: Dictionary[String, int] = {}
var _bytes := 0
var _requested: Dictionary[String, bool] = {}
var _sent := 0
var _collected := 0
var _events: Array[Dictionary] = []
var _observer: ErrorObserver

class ErrorObserver extends Logger:
	var mutex := Mutex.new()
	var rows: Array[Dictionary] = []
	var errors := 0
	var draws := 0
	var draw_rows: Array[Dictionary] = []
	var stage := "startup"
	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			backtraces: Array[ScriptBacktrace]) -> void:
		var traces: Array[String] = []
		for i in mini(backtraces.size(), 4):
			traces.append(backtraces[i].format().left(4096))
		mutex.lock()
		if error_type != Logger.ERROR_TYPE_WARNING:
			errors += 1
		if rows.size() < 16:
			rows.append({"ms": Time.get_ticks_msec(), "thread": OS.get_thread_caller_id(),
				"stage": stage, "function": function, "file": file, "line": line,
				"code": code.left(4096), "rationale": rationale.left(4096),
				"type": error_type, "traces": traces})
		mutex.unlock()
	func set_stage(value: String) -> void:
		mutex.lock()
		stage = value
		mutex.unlock()
	func snapshot() -> Dictionary:
		mutex.lock()
		var value := {"errors": errors, "rows": rows.duplicate(true), "draws": draws,
			"draw_rows": draw_rows.duplicate(true)}
		mutex.unlock()
		return value
	func draw() -> void:
		mutex.lock()
		draws += 1
		if draw_rows.size() < 80:
			draw_rows.append({"ms": Time.get_ticks_msec(), "thread": OS.get_thread_caller_id(), "stage": stage})
		mutex.unlock()

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
	if _mode != "prefetch-canvas" \
			or not _out.is_absolute_path() or DisplayServer.get_name() == "headless" \
			or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("[BG31] requires native Forward+, explicit --mode and isolated absolute --out")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK or FileAccess.file_exists(_out.path_join("report.json")):
		push_error("[BG31] cannot create output or report already exists; use a fresh directory")
		get_tree().quit(2)
		return
	_observer = ErrorObserver.new()
	OS.add_logger(_observer)
	RenderingServer.frame_post_draw.connect(_post_draw)
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		print("BG31_CHECK:FAIL:", label)

func _unique(paths: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for path in paths:
		if not path.is_empty() and not result.has(path):
			_check(ResourceLoader.exists(path), "texture exists: " + path)
			result.append(path)
	return result

func _run() -> void:
	_check(AssetPrefetch.stats().inflight == 0 and AssetPrefetch.stats().queued == 0 \
		and AssetPrefetch.stats().cached == 0, "fresh process has no pre-existing AssetPrefetch work/cache")
	_check(AssetPrefetch.uses_main_thread() and AssetPrefetch.inflight_limit() == 1
		and AssetPrefetch.stats().strategy == AssetPrefetch.STRATEGY_MAIN_THREAD_RD_472,
		"actual native 4.7.2 production loader selects deferred main-thread capacity one")
	for path: String in LEVELS:
		var data := load(path) as LevelData
		_check(data != null, "real authored LevelData: " + path)
		if data == null:
			_finish()
			return
		_levels.append(data)
		var level_paths := _unique(AssetPrefetch.level_texture_paths(data))
		var intro_paths := _unique(AssetPrefetch.scene_texture_paths(data.intro_scene))
		_check(level_paths.size() <= AssetPrefetch.MAX_REQUESTS_PER_CALL \
			and intro_paths.size() <= AssetPrefetch.MAX_REQUESTS_PER_CALL \
			and level_paths.size() + intro_paths.size() <= AssetPrefetch.MAX_QUEUED,
			"both request batches fit real acceptance limits")
		_batches.append({"level": path, "intro_scene": String(data.intro_scene),
			"level_paths": level_paths, "intro_paths": intro_paths})
	if _failures > 0:
		_finish()
		return
	_build_draw_items(_batches[0].level_paths)
	_check(_draw_textures.size() == DRAW_ITEMS, "fixed 64 real texture draw items created")
	if _failures > 0:
		_finish()
		return
	queue_redraw()
	for cycle in CYCLES:
		for index in LEVELS.size():
			_observer.set_stage("cycle-%d-level-%d" % [cycle, index])
			_event("before-clear", cycle, index)
			var sent_before: int = AssetPrefetch.stats().requested_total
			if _mode == "prefetch-canvas":
				AssetPrefetch.warm_level(_levels[index])
				AssetPrefetch.request(AssetPrefetch.scene_texture_paths(_levels[index].intro_scene))
			else:
				# Previous phase is drained; release precisely the same cache budget.
				_cache.clear()
				_sizes.clear()
				_bytes = 0
				_requested.clear()
				_bare_request(_batches[index].level_paths)
				_bare_request(_batches[index].intro_paths)
				_bare_dispatch()
			_check(AssetPrefetch.stats().requested_total == sent_before and AssetPrefetch.stats().inflight == 0,
				"production warm/request only queue; no immediate load or native token")
			_event("requests-issued", cycle, index)
			var draws_before := int(_observer.snapshot().draws)
			var deadline := Time.get_ticks_msec() + 15000
			while not _drained() and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
				if _mode != "prefetch-canvas":
					_bare_poll()
			_check(_drained(), "bounded actual request completion cycle %d level %d" % [cycle, index])
			if int(_observer.snapshot().draws) > draws_before:
				_overlap_phases += 1
			_event("drained", cycle, index)
			if not _drained():
				_finish()
				return
	# process_frame can resume before the rendering completion signal; never
	# write the report until the real callback has observed the final product load.
	await _settle_product_post_draw()
	_check(int(_observer.snapshot().draws) > 0, "real main viewport draw occurred during diagnostic")
	_check(_overlap_phases > 0, "at least one draw between requests-issued and drained observations")
	_check(AssetPrefetch.stats().failed_total == 0, "no actual AssetPrefetch load failure")
	_check(AssetPrefetch.stats().threaded_request_calls == 0, "production policy made no own threaded requests")
	_check(AssetPrefetch.stats().main_load_total > 0 and _timing_rows.size() == AssetPrefetch.stats().main_load_total,
		"every actual product load was independently observed in a bounded timing row")
	_check(_overlap_phases == CYCLES * LEVELS.size(), "all eight product load phases overlapped true viewport draw")
	_finish()

func _settle_product_post_draw() -> void:
	var target: int = AssetPrefetch.stats().main_load_total
	var target_frame: int = AssetPrefetch.stats().main_last_frame
	var deadline := Time.get_ticks_msec() + 15000
	while (_last_observed_loads != target or _last_observed_frame != target_frame) \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_last_observed_loads == target and _last_observed_frame == target_frame,
		"actual final product-load frame was observed by frame_post_draw before report")

func _build_draw_items(paths: PackedStringArray) -> void:
	var pairs: Array[Texture2D] = []
	for path in paths:
		if path.get_basename().ends_with("_n") or path.get_basename().ends_with("_glow"):
			continue
		var normal_path := path.get_basename() + "_n." + path.get_extension()
		if not ResourceLoader.exists(normal_path):
			continue
		var diffuse := load(path) as Texture2D
		var normal := load(normal_path) as Texture2D
		_check(diffuse != null and normal != null, "real diffuse/normal draw pair: " + path)
		if diffuse == null or normal == null:
			continue
		pairs.append(diffuse)
		pairs.append(normal)
		if pairs.size() == 8:
			break
	_check(pairs.size() == 8, "four distinct authored diffuse/normal pairs available")
	if pairs.size() != 8:
		return
	_held_draw = pairs
	for i in DRAW_ITEMS:
		var pair := (i % 4) * 2
		if _mode == "bare-direct":
			_draw_textures.append(pairs[pair])
		else:
			var texture := CanvasTexture.new()
			texture.diffuse_texture = pairs[pair]
			texture.normal_texture = pairs[pair + 1]
			_draw_textures.append(texture)

func _draw() -> void:
	for i in _draw_textures.size():
		draw_texture_rect(_draw_textures[i], Rect2(20 + (i % 8) * 180, 20 + floori(float(i) / 8.0) * 100, 160, 80), false)

func _post_draw() -> void:
	_observe_product_load()
	_observer.draw()

func _bare_request(paths: PackedStringArray) -> void:
	for path in paths:
		if _requested.has(path):
			if _cache.has(path):
				var texture := _cache[path]
				_cache.erase(path)
				_cache[path] = texture
			continue
		_requested[path] = true
		_queue.append(path)

func _bare_dispatch() -> void:
	while not _queue.is_empty() and _slots.has(""):
		var slot := _slots.find("")
		var path: String = _queue.pop_front()
		var result := ResourceLoader.load_threaded_request(path, "Texture2D")
		_check(result == OK, "bare actual request accepted: " + path)
		if result == OK:
			_slots[slot] = path
			_sent += 1
		else:
			_requested.erase(path)

func _bare_poll() -> void:
	for offset in 4:
		var slot := 3 - offset
		var path := _slots[slot]
		if path.is_empty():
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var resource: Resource = null
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			resource = ResourceLoader.load_threaded_get(path)
			_collected += 1
		_slots[slot] = ""
		_requested.erase(path)
		_check(status == ResourceLoader.THREAD_LOAD_LOADED and resource is Texture2D, "bare real completion: " + path)
		if status == ResourceLoader.THREAD_LOAD_LOADED and resource is Texture2D:
			var texture := resource as Texture2D
			var estimate := int(ceilf(float(texture.get_width()) * texture.get_height() * 16.0 / 3.0))
			if estimate > 0 and estimate <= LIMIT_BYTES:
				while not _cache.is_empty() and (_cache.size() >= 64 or _bytes + estimate > LIMIT_BYTES):
					var victim: String = _cache.keys()[0]
					_bytes -= _sizes[victim]
					_cache.erase(victim)
					_sizes.erase(victim)
					_requested.erase(victim)
				_cache[path] = texture
				_sizes[path] = estimate
				_bytes += estimate
				_requested[path] = true
		resource = null
	_bare_dispatch()

func _process(delta: float) -> void:
	_current_delta_ms = delta * 1000.0

func _observe_product_load() -> void:
	var value := AssetPrefetch.stats()
	var count: int = value.main_load_total
	var difference := count - _last_observed_loads
	if difference == 0:
		return
	_check(difference == 1 and value.main_last_frame != _last_observed_frame,
		"independent frame observation sees at most one actual production load")
	_check(value.inflight == 0 and value.threaded_request_calls == 0 and value.cached <= 64
		and value.estimated_bytes <= LIMIT_BYTES and value.queued <= AssetPrefetch.MAX_QUEUED,
		"production bounds and zero-threaded-token factor remain intact")
	_max_delta_ms = maxf(_max_delta_ms, _current_delta_ms)
	if _timing_rows.size() < CYCLES * LEVELS.size() * 2 * AssetPrefetch.MAX_REQUESTS_PER_CALL:
		_timing_rows.append({"observed_frame": Engine.get_process_frames(), "loaded_frame": value.main_last_frame,
			"process_delta_ms": _current_delta_ms, "stats": value})
	_last_observed_frame = value.main_last_frame
	_last_observed_loads = count

func _drained() -> bool:
	if _mode == "prefetch-canvas":
		var value := AssetPrefetch.stats()
		return value.queued == 0 and value.inflight == 0
	return _queue.is_empty() and _slots.count("") == 4

func _event(label: String, cycle: int, index: int) -> void:
	var stats := AssetPrefetch.stats() if _mode == "prefetch-canvas" else {
		"queued": _queue.size(), "inflight": 4 - _slots.count(""), "cached": _cache.size(),
		"estimated_bytes": _bytes, "requested_total": _sent, "collected_total": _collected}
	_events.append({"label": label, "ms": Time.get_ticks_msec(), "cycle": cycle,
		"level_index": index, "draw_count": int(_observer.snapshot().draws), "stats": stats})

func _finish() -> void:
	var errors := _observer.snapshot()
	_check(int(errors.errors) == 0, "all observed native/script errors are rejected")
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	_check(file != null, "isolated report writer opens")
	if file != null:
		file.store_string(JSON.stringify({"mode": _mode, "diagnostic_only": true,
			"engine": Engine.get_version_info(), "pid": OS.get_process_id(),
			"main_thread": OS.get_main_thread_id(), "rendering": RenderingServer.get_current_rendering_method(),
			"cycles": CYCLES, "draw_items": DRAW_ITEMS, "draw_count": int(errors.draws),
			"overlap_phases": _overlap_phases, "checks": _checks,
			"batches": _batches, "events": _events, "observer": errors, "failures": _failures,
			"product_stats": AssetPrefetch.stats(), "timing_rows": _timing_rows,
			"max_observed_process_delta_ms": _max_delta_ms, "hard_time_budget": false,
			"single_load_preemptible": false}, "\t"))
		file.close()
	print("BG31_RESULT:checks=", _checks, ":failures=", _failures, ":errors=", errors.errors)
	get_tree().quit(0 if _failures == 0 else 1)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_post_draw):
		RenderingServer.frame_post_draw.disconnect(_post_draw)
	if _observer != null:
		OS.remove_logger(_observer)
