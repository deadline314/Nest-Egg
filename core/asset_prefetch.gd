class_name AssetPrefetch
extends RefCounted
## 有界預載：額外持有的貼圖使用 LRU 預算，clear 不釋放場景自己的引用。
## 4.7.2 原生 RD 由主線 Pump 逐影格載入；其他後端保留真正背景請求。
## 主線載入前先由背景執行緒把檔案讀進系統快取（見「檔案暖身」），主線那一格只剩解碼與上傳，不等磁碟。

## 一個區域一次送出的上限。第一章街道有四種各自外觀的敵人（NE-218），連同場景貼圖約 200 張；上限太低時剩下的不會被預載，換區才臨時讀檔。
const MAX_REQUESTS_PER_CALL := 256
const MAX_INFLIGHT := 4
const MAIN_SOFT_BUDGET_US := 2000
const STRATEGY_THREADED_NATIVE := 0
const STRATEGY_THREADED_HEADLESS := 1
const STRATEGY_MAIN_THREAD_RD_472 := 2
const MAX_QUEUED := 512
## 預載最多留幾張：要裝得下一個區域所有鄰居的環境貼圖（第一章街道的鄰居約 190 張），否則回到隔壁時還是得當場重載（BG-32）。
## 真正的上限是下面的位元組數。
const MAX_CACHED := 512
const MAX_CACHE_BYTES := 128 * 1024 * 1024
const STAGE_DIR := "res://data/cutscene/stages"
## 檔案暖身（主線策略、有畫面時才用）：背景執行緒先把貼圖的匯入檔讀進作業系統的檔案快取，主線再載入時不用等磁碟。
## 實測（第一章街道、檔案沒被快取、機器忙）：主線直接載單張最久 65 毫秒、14 秒內 10 次超過 33 毫秒的停頓；檔案已在快取時單張最久 4 毫秒。
## 一個背景工作最多讀幾個檔；等一張暖身最多多久（毫秒），逾時就照舊由主線直接載，佇列不會卡住。
const WARM_BATCH := 24
const WARM_TIMEOUT_MSEC := 3000
const WARM_CHUNK_BYTES := 262144
## 上一格比平常長這麼多倍時，這一格先不載（不把載入疊在已經慢的那一格上）。
const BUSY_FRAME_RATIO := 1.6
const FRAME_SMOOTHING := 0.1

## 相容既有診斷工具，僅記有界的 queue／active／cache，不保留全歷史。
static var _requested: Dictionary[String, bool] = {}
static var _queued: Dictionary[String, bool] = {}
static var _active_paths: Array[String] = ["", "", "", ""]
static var _active_epochs: Array[int] = [0, 0, 0, 0]
static var _cache: Dictionary[String, Texture2D] = {}
static var _cache_sizes: Dictionary[String, int] = {}
static var _cache_bytes := 0
static var _retiring: Array[Texture2D] = []
static var _retiring_bytes := 0
static var _generation := 0
static var _scope := ""
static var _pump: Node
static var _install_pending := false
static var _sent_total := 0
static var _collected_total := 0
static var _failed_total := 0
static var _evicted_total := 0
static var _strategy := -1
static var _threaded_request_calls := 0
static var _main_load_total := 0
static var _main_last_frame := -1
static var _main_max_load_us := 0
static var _main_max_work_us := 0
static var _main_last_load_us := 0
static var _main_last_work_us := 0
static var _main_over_budget_total := 0
static var _main_loading := false
static var _warm_mutex := Mutex.new()
## 背景執行緒寫、主線讀：已經讀進檔案快取的路徑。
static var _warm_ready: Dictionary[String, bool] = {}
## 只有主線用：已經交給背景執行緒的路徑與交出去的時間（毫秒）。
static var _warm_sent: Dictionary[String, int] = {}
static var _warm_task := -1
static var _warm_files_total := 0
static var _warm_waits_total := 0
static var _warm_timeouts_total := 0
static var _busy_skips_total := 0
static var _frame_average := 0.0
static var _frame_last := 0.0
## 測試用：-1＝依環境決定（有畫面才暖身）、0＝關、1＝開。
static var _warm_override := -1


class Pump extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		AssetPrefetch._refresh_pump()
	func _process(delta: float) -> void:
		AssetPrefetch._note_frame(delta)
		AssetPrefetch._poll()
	func _exit_tree() -> void:
		AssetPrefetch._shutdown()


## 預載一個區域；主選單使用此入口建立新範圍，釋放上一輪額外快取。
static func warm_level(data: Variant) -> int:
	var level := _resolve_level(data)
	if level == null:
		return 0
	_select_scope("level:%s:%s" % [level.resource_path, level.id], true)
	return request(level_texture_paths(level))


static func _resolve_level(data: Variant) -> LevelData:
	match typeof(data):
		TYPE_OBJECT:
			return data as LevelData
		TYPE_STRING, TYPE_STRING_NAME:
			var path := str(data)
			if ResourceLoader.exists(path):
				return load(path) as LevelData
			push_warning("[AssetPrefetch] 找不到要預載的區域：%s" % path)
	return null


## 全部鄰居與過場共用同一範圍，不讓逐個鄰居互相清除。
static func warm_neighbors(data: LevelData) -> int:
	if data == null:
		return 0
	_select_scope("neighbors:%s:%s" % [data.resource_path, data.id], false)
	var wanted := PackedStringArray()
	var targets: Dictionary[String, bool] = {}
	for resource in data.legend.values():
		if resource is PortalData and not (resource as PortalData).target_level.is_empty():
			targets[(resource as PortalData).target_level] = true
	for path in targets:
		var neighbor := _resolve_level(path)
		if neighbor != null:
			wanted.append_array(level_texture_paths(neighbor))
	wanted.append_array(scene_texture_paths(data.intro_scene))
	for scene in data.story_triggers:
		wanted.append_array(scene_texture_paths(StringName(scene)))
	for scene in data.channel_scenes.values():
		wanted.append_array(scene_texture_paths(scene))
	for scene in Story.respawn_scene_ids(data.chapter, 1):
		wanted.append_array(scene_texture_paths(scene))
	# 只留這個區域的鄰居與過場用得到的：前幾個區域留下來的預載不再佔著記憶體（BG-32）。
	_retain_only(wanted)
	return request(wanted)


## 把預載裡不在 paths 的貼圖放掉（場景自己還在用的不受影響）。
static func _retain_only(paths: PackedStringArray) -> void:
	var keep: Dictionary[String, bool] = {}
	for path in paths:
		keep[path] = true
	var retire := inflight_limit() == 1 and _active_paths.count("") < MAX_INFLIGHT
	for path: String in _cache.keys():
		if keep.has(path):
			continue
		if retire:
			# 背景載入進行中時不並行釋放：先留著，等這批載入領完再放（同 _reset_scope）。
			_retiring.append(_cache[path])
			_retiring_bytes += _cache_sizes[path]
		_cache_bytes -= _cache_sizes[path]
		_cache.erase(path)
		_cache_sizes.erase(path)
		_requested.erase(path)
		_evicted_total += 1


## 回傳新接受的排隊數；重複路徑不增加引擎的 user token 次數。
static func request(paths: PackedStringArray) -> int:
	var accepted := 0
	for path in paths:
		if accepted >= MAX_REQUESTS_PER_CALL:
			break
		if path.is_empty():
			continue
		var active_slot := _active_paths.find(path)
		if active_slot >= 0:
			_active_epochs[active_slot] = _generation
			continue
		if _requested.has(path):
			if _cache.has(path):
				var texture := _cache[path]
				_cache.erase(path)
				_cache[path] = texture
			continue
		if not ResourceLoader.exists(path):
			push_warning("[AssetPrefetch] 找不到要預載的貼圖：%s" % path)
			continue
		if _queued.size() >= MAX_QUEUED:
			push_warning("[AssetPrefetch] 待載已達 %d，略過本次剩餘貼圖（首項：%s）。" % [MAX_QUEUED, path])
			break
		_requested[path] = true
		_queued[path] = true
		accepted += 1
	_refresh_pump()
	if is_instance_valid(_pump) and _pump.is_inside_tree():
		_dispatch()
	return accepted


static func _select_scope(key: String, release_cache: bool) -> void:
	if _scope == key:
		return
	_reset_scope(key, release_cache)


static func clear() -> void:
	_reset_scope("", true)


static func _reset_scope(key: String, release_cache: bool) -> void:
	_generation += 1
	_scope = key
	_queued.clear()
	_warm_sent.clear()
	_warm_mutex.lock()
	_warm_ready.clear()
	_warm_mutex.unlock()
	if release_cache:
		# Dummy 的 RID owner 沒有執行緒保護；清除引用也不可與自己的
		# 背景配置並行。只短暫保留原有 ≤64 份引用，完成領取後釋放。
		if inflight_limit() == 1 and _active_paths.count("") < MAX_INFLIGHT:
			for path in _cache:
				_retiring.append(_cache[path])
			_retiring_bytes += _cache_bytes
		_cache.clear()
		_cache_sizes.clear()
		_cache_bytes = 0
	_requested.clear()
	for path in _cache:
		_requested[path] = true
	for path in _active_paths:
		if not path.is_empty():
			_requested[path] = true
	_refresh_pump()


## 快照只讀；估算採 RGBA8 加完整 mip chain，不代表實際 RAM 或 VRAM。
static func stats() -> Dictionary:
	_ensure_strategy()
	var active := 0
	for path in _active_paths:
		active += 0 if path.is_empty() else 1
	return {"queued": _queued.size(), "inflight": active, "inflight_limit": inflight_limit(),
		"cached": _cache.size(), "retiring": _retiring.size(),
		"estimated_bytes": _cache_bytes + _retiring_bytes, "requested_total": _sent_total,
		"collected_total": _collected_total, "failed_total": _failed_total,
		"evicted_total": _evicted_total, "scope": _scope, "generation": _generation,
		"strategy": _strategy, "threaded_request_calls": _threaded_request_calls,
		"main_load_total": _main_load_total, "main_last_frame": _main_last_frame,
		"main_max_load_us": _main_max_load_us, "main_max_work_us": _main_max_work_us,
		"main_last_load_us": _main_last_load_us, "main_last_work_us": _main_last_work_us,
		"main_over_budget_total": _main_over_budget_total,
		"warm_files_total": _warm_files_total, "warm_waits_total": _warm_waits_total,
		"warm_timeouts_total": _warm_timeouts_total, "busy_skips_total": _busy_skips_total,
		"main_assets_per_frame_limit": 1 if uses_main_thread() else 0,
		"main_soft_budget_us": MAIN_SOFT_BUDGET_US if uses_main_thread() else 0}


## 策略只初始化一次；原生 RD 的 CanvasTexture／背景 texture 配置錯誤有
## 實測關聯，這是有界 workaround，不宣稱已定位或修正引擎 RID owner。
static func _strategy_for(major: int, minor: int, patch: int, display: String, renderer: String) -> int:
	if display == "headless":
		return STRATEGY_THREADED_HEADLESS
	if major == 4 and minor == 7 and patch == 2 and renderer in ["forward_plus", "mobile"]:
		return STRATEGY_MAIN_THREAD_RD_472
	return STRATEGY_THREADED_NATIVE


static func _ensure_strategy() -> void:
	if _strategy >= 0:
		return
	var version := Engine.get_version_info()
	_strategy = _strategy_for(int(version.major), int(version.minor), int(version.patch),
		DisplayServer.get_name(), RenderingServer.get_current_rendering_method())


static func uses_main_thread() -> bool:
	_ensure_strategy()
	return _strategy == STRATEGY_MAIN_THREAD_RD_472


## 此數值是服務容量；主線策略的 inflight 始終為零，工作在下一影格完成。
## Dummy 保留真正非同步單槽，其他原生版本／Compatibility 保留四槽。
static func inflight_limit() -> int:
	_ensure_strategy()
	return MAX_INFLIGHT if _strategy == STRATEGY_THREADED_NATIVE else 1


static func _refresh_pump() -> void:
	var working := not _queued.is_empty() or _active_paths.count("") < MAX_INFLIGHT
	if working and not is_instance_valid(_pump) and not _install_pending:
		_install_pending = true
		_install_pump.call_deferred()
	if is_instance_valid(_pump):
		_pump.set_process(working)


static func _install_pump() -> void:
	_install_pending = false
	if is_instance_valid(_pump) or (_queued.is_empty() and _active_paths.count("") == MAX_INFLIGHT):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		_pump = Pump.new()
		_pump.name = "AssetPrefetchPump"
		_pump.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_pump)


static func _first_path(entries: Dictionary) -> String:
	for path: String in entries:
		return path
	return ""


static func _dispatch() -> void:
	if uses_main_thread():
		return  # request/scope changes never perform a synchronous texture load.
	var attempts := 0
	while not _queued.is_empty() and attempts < MAX_INFLIGHT:
		if MAX_INFLIGHT - _active_paths.count("") >= inflight_limit():
			return
		var slot := _active_paths.find("")
		if slot < 0:
			return
		var path := _first_path(_queued)
		_queued.erase(path)
		attempts += 1
		_threaded_request_calls += 1
		var error := ResourceLoader.load_threaded_request(path, "Texture2D")
		if error == OK:
			_active_paths[slot] = path
			_active_epochs[slot] = _generation
			_sent_total += 1
		else:
			_requested.erase(path)
			_failed_total += 1
			push_warning("[AssetPrefetch] 無法請求貼圖：%s（%s）" % [path, error_string(error)])


## 固定四槽逆序檢查；沒有每影格 keys() 或整佇列副本。
static func _poll() -> void:
	if uses_main_thread():
		_poll_main_thread()
		_refresh_pump()
		return
	for offset in MAX_INFLIGHT:
		var slot := MAX_INFLIGHT - 1 - offset
		var path := _active_paths[slot]
		if path.is_empty():
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var resource: Resource = null
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			resource = ResourceLoader.load_threaded_get(path)
			_collected_total += 1
		_active_paths[slot] = ""
		_requested.erase(path)
		if not _retiring.is_empty() and _active_paths.count("") == MAX_INFLIGHT:
			_retiring.clear()
			_retiring_bytes = 0
		if status == ResourceLoader.THREAD_LOAD_LOADED and resource is Texture2D:
			if _active_epochs[slot] == _generation:
				_remember(path, resource as Texture2D)
		else:
			_failed_total += 1
			push_warning("[AssetPrefetch] 背景載入失敗或請求已不存在：%s（狀態 %d）" % [path, status])
		# 下一次背景配置前，放掉這個完成結果的最後一份區域引用。
		resource = null
	_dispatch()
	_refresh_pump()


## Pump 的主線 process 入口；不是 whole-level load，也不等待／同步 renderer。
## 每個 process frame 至多開始一張，即使 clear／scope 在同一影格改變。
## 2ms 只在載入前守門，單張 ResourceLoader.load 無法中止，超時如實記錄。
static func _poll_main_thread() -> void:
	if _queued.is_empty() or _main_loading:
		return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		push_warning("[AssetPrefetch] 主線貼圖 Pump 在非主線呼叫，保留待載佇列。")
		return
	var frame := Engine.get_process_frames()
	if frame == _main_last_frame:
		return
	var work_start := Time.get_ticks_usec()
	var deadline := work_start + MAIN_SOFT_BUDGET_US
	var path := _first_path(_queued)
	var warming := _warming()
	if warming:
		# 上一格已經比平常慢很多，這一格不再加一張。
		if _frame_average > 0.0 and _frame_last > _frame_average * BUSY_FRAME_RATIO:
			_busy_skips_total += 1
			return
		_warm_schedule()
		path = _first_warm_path()
		if path.is_empty():
			_warm_waits_total += 1
			return
	var epoch := _generation
	var scope := _scope
	var load_start := Time.get_ticks_usec()
	if load_start >= deadline:
		return
	# Reserve the frame before calling ResourceLoader, also preventing reentrant loads.
	_main_last_frame = frame
	_main_loading = true
	_queued.erase(path)
	if warming:
		# A budget rejection above must leave the completed read available.
		# Count a timeout only when its fallback really starts loading.
		_warm_mutex.lock()
		if not _warm_ready.erase(path):
			_warm_timeouts_total += 1
		_warm_mutex.unlock()
	_warm_sent.erase(path)
	_sent_total += 1
	_main_load_total += 1
	var resource := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	_main_last_load_us = Time.get_ticks_usec() - load_start
	_main_max_load_us = maxi(_main_max_load_us, _main_last_load_us)
	_collected_total += 1
	if epoch == _generation:
		_requested.erase(path)
	if resource is Texture2D:
		if epoch == _generation:
			_remember(path, resource as Texture2D)
	else:
		_failed_total += 1
		push_warning("[AssetPrefetch] 主線貼圖載入失敗或型別錯誤：%s（範圍 %s，generation %d）。" % [path, scope, epoch])
	resource = null
	_main_loading = false
	var work_us := Time.get_ticks_usec() - work_start
	_main_last_work_us = work_us
	_main_max_work_us = maxi(_main_max_work_us, work_us)
	if work_us > MAIN_SOFT_BUDGET_US:
		_main_over_budget_total += 1


## 主線策略而且有畫面時才暖身：無頭執行沒有停頓的問題，維持原本「排到就載」的行為。
static func _warming() -> bool:
	if _warm_override >= 0:
		return _warm_override == 1
	return uses_main_thread() and DisplayServer.get_name() != "headless"


static func _note_frame(delta: float) -> void:
	_frame_last = delta
	_frame_average = delta if _frame_average <= 0.0 else lerpf(_frame_average, delta, FRAME_SMOOTHING)


## 背景工作閒著時，把還沒交出去的前幾張交給它讀；一次只有一個背景工作。
static func _warm_schedule() -> void:
	if _warm_task >= 0:
		if not WorkerThreadPool.is_task_completed(_warm_task):
			return
		_warm_join()
	var batch := PackedStringArray()
	var now := Time.get_ticks_msec()
	for path: String in _queued:
		if _warm_sent.has(path):
			continue
		_warm_sent[path] = now
		batch.append(path)
		if batch.size() >= WARM_BATCH:
			break
	if not batch.is_empty():
		_warm_task = WorkerThreadPool.add_task(_warm_files.bind(batch), false, "AssetPrefetch 暖檔")


static func _warm_join() -> void:
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1


## 佇列裡第一張已經暖好（或等太久）的；都還沒好回傳空字串。只看最前面一批，不整個佇列掃。
static func _first_warm_path() -> String:
	var now := Time.get_ticks_msec()
	var looked := 0
	var found := ""
	_warm_mutex.lock()
	for path: String in _queued:
		if _warm_ready.has(path):
			found = path
			break
		if _warm_sent.has(path) and now - _warm_sent[path] > WARM_TIMEOUT_MSEC:
			found = path
			break
		looked += 1
		if looked >= WARM_BATCH:
			break
	_warm_mutex.unlock()
	return found


## 背景執行緒：把每張貼圖實際的匯入檔整個讀過一遍（只為了讓系統把它放進檔案快取，內容丟掉），再標記成暖好。
## 讀不到也標記：主線載入時自己會報錯，佇列不能卡在這裡。
static func _warm_files(paths: PackedStringArray) -> void:
	for path in paths:
		var file := FileAccess.open(_imported_path(path), FileAccess.READ)
		if file != null:
			var left := file.get_length()
			while left > 0:
				var got := file.get_buffer(mini(left, WARM_CHUNK_BYTES)).size()
				if got <= 0:
					break
				left -= got
			file.close()
		_warm_mutex.lock()
		_warm_ready[path] = true
		_warm_files_total += 1
		_warm_mutex.unlock()


## 貼圖實際被載入的匯入檔（.import 裡 path 開頭那一行，例如 path="res://.godot/imported/….ctex"）；找不到就用原路徑。
static func _imported_path(path: String) -> String:
	for line in FileAccess.get_file_as_string(path + ".import").split(String.chr(10), false):
		if line.begins_with("path") and line.contains("="):
			var value := line.get_slice("=", 1).strip_edges()
			if value.length() >= 2 and value.begins_with(String.chr(34)):
				return value.substr(1, value.length() - 2)
	return path


static func _remember(path: String, texture: Texture2D) -> void:
	# 不 get_image()，避免為估算觸發 GPU readback／另一份大像素副本。
	var estimate := int(ceilf(float(texture.get_width()) * float(texture.get_height()) * 16.0 / 3.0))
	if estimate <= 0 or estimate > MAX_CACHE_BYTES:
		return
	if _cache.has(path):
		_cache_bytes -= _cache_sizes[path]
		_cache.erase(path)
	while not _cache.is_empty() and (_cache.size() >= MAX_CACHED or _cache_bytes + estimate > MAX_CACHE_BYTES):
		var victim := _first_path(_cache)
		_cache_bytes -= _cache_sizes[victim]
		_cache.erase(victim)
		_cache_sizes.erase(victim)
		_requested.erase(victim)
		_evicted_total += 1
	_cache[path] = texture
	_cache_sizes[path] = estimate
	_cache_bytes += estimate
	_requested[path] = true


## 只在整棵 SceneTree 退出時等自己最多四個請求；遊戲中的 clear 不等待。
static func _shutdown() -> void:
	_queued.clear()
	_warm_join()
	_warm_sent.clear()
	for slot in MAX_INFLIGHT:
		var path := _active_paths[slot]
		if path.is_empty():
			continue
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
			_collected_total += 1
		_active_paths[slot] = ""
	_cache.clear()
	_retiring.clear()
	_retiring_bytes = 0
	_cache_sizes.clear()
	_cache_bytes = 0
	_requested.clear()
	_scope = ""
	_pump = null


## 一個區域用到的貼圖：場景擺設（含法線與發光層）、環境主題的地形材質、立面、室內牆面、背景與天空、敵人的角色零件。
static func level_texture_paths(data: LevelData) -> PackedStringArray:
	var paths := PackedStringArray()
	var theme := data.environment
	if theme != null:
		var dirs := theme.prop_dirs()
		for entry in data.load_props():
			var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
			if prop != null:
				_add_with_variants(paths, prop.texture)
		for zone in theme.zones:
			if zone == null:
				continue
			if zone.material != null:
				for path in [zone.material.body, zone.material.top, zone.material.side]:
					_add_with_variants(paths, path)
			for facade in zone.facades:
				if facade != null:
					for list in [facade.ground, facade.body, facade.cap]:
						for path in list:
							_add_with_variants(paths, path)
			_add_with_variants(paths, zone.interior)
		for layer in theme.backdrop:
			if layer != null:
				_add_with_variants(paths, layer.texture)
		if theme.sky != null:
			_add_with_variants(paths, theme.sky.texture)
	var skins: Dictionary[String, bool] = {}
	for resource in data.legend.values():
		if resource is EnemyData and not (resource as EnemyData).rig_skin.is_empty():
			skins[(resource as EnemyData).rig_skin] = true
	for skin in skins:
		_add_rig_parts(paths, skin)
	return paths


## 一個場景（含接續的下一段）用到的舞台貼圖。
static func scene_texture_paths(scene_id: StringName) -> PackedStringArray:
	var paths := PackedStringArray()
	var seen: Dictionary[String, bool] = {}
	var id := String(scene_id)
	while id != "" and not seen.has(id) and Story.has_scene(StringName(id)):
		seen[id] = true
		var scene: Dictionary = Story._scenes[id]
		for step: Variant in scene.get("steps", []):
			if typeof(step) == TYPE_DICTIONARY and str(step.get("do", "")) == "scene":
				_add_stage(paths, StringName(str(step.get("id", ""))))
		id = str(scene.get("then", ""))
	return paths


static func _add_stage(paths: PackedStringArray, stage_id: StringName) -> void:
	var stage_path := StageLibrary.path_of(stage_id)
	var json := load(stage_path) as JSON if ResourceLoader.exists(stage_path) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		return
	for layer: Variant in (json.data as Dictionary).get("layers", []):
		if typeof(layer) == TYPE_DICTIONARY and str(layer.get("kind", "")) == "sprite":
			_add_with_variants(paths, str(layer.get("path", "")))
			var states: Variant = layer.get("states", {})
			if states is Dictionary:
				for state: Variant in states.values():
					if state is Dictionary and state.get("path") is String:
						_add_with_variants(paths, state["path"])


static func _add_rig_parts(paths: PackedStringArray, skin: String) -> void:
	var dir := RigLibrary.character_dir(skin).path_join("parts")
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".png") or file.ends_with(".webp"):
			paths.append(dir.path_join(file))


## 貼圖本身，加上同名的法線（_n）與發光（_glow）層。
static func _add_with_variants(paths: PackedStringArray, path: String) -> void:
	if path.is_empty():
		return
	paths.append(path)
	var base := path.get_basename()
	var ext := path.get_extension()
	var normal := "%s_n.%s" % [base, ext]
	if ResourceLoader.exists(normal):
		paths.append(normal)
	var glow := "%s_glow.%s" % [base, ext]
	if ResourceLoader.exists(glow):
		paths.append(glow)
