class_name AssetPrefetch
extends RefCounted
## 有界預載：只有背景請求完成後才領取，額外持有的貼圖使用 LRU 預算。
## 清除保留進行中請求的追蹤；遊戲影格不等待背景執行緒。

const MAX_REQUESTS_PER_CALL := 160
const MAX_INFLIGHT := 4
const MAX_QUEUED := 512
const MAX_CACHED := 64
const MAX_CACHE_BYTES := 128 * 1024 * 1024
const STAGE_DIR := "res://data/cutscene/stages"

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


class Pump extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		AssetPrefetch._refresh_pump()
	func _process(_delta: float) -> void:
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
	var count := 0
	var targets: Dictionary[String, bool] = {}
	for resource in data.legend.values():
		if resource is PortalData and not (resource as PortalData).target_level.is_empty():
			targets[(resource as PortalData).target_level] = true
	for path in targets:
		var neighbor := _resolve_level(path)
		if neighbor != null:
			count += request(level_texture_paths(neighbor))
	count += request(scene_texture_paths(data.intro_scene))
	for scene in data.story_triggers:
		count += request(scene_texture_paths(StringName(scene)))
	for scene in data.channel_scenes.values():
		count += request(scene_texture_paths(scene))
	for scene in Story.respawn_scene_ids(data.chapter, 1):
		count += request(scene_texture_paths(scene))
	return count


## 回傳新接受的非同步請求數；重複路徑不增加引擎的 user token 次數。
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
	var active := 0
	for path in _active_paths:
		active += 0 if path.is_empty() else 1
	return {"queued": _queued.size(), "inflight": active, "inflight_limit": inflight_limit(),
		"cached": _cache.size(), "retiring": _retiring.size(),
		"estimated_bytes": _cache_bytes + _retiring_bytes, "requested_total": _sent_total,
		"collected_total": _collected_total, "failed_total": _failed_total,
		"evicted_total": _evicted_total, "scope": _scope}


## 4.7.2 Dummy TextureStorage 的 RID_PtrOwner 非 thread-safe；最小探針
## 已重現四槽 alloc/free 錯誤，單槽與 Forward+ 四槽均乾淨。
## 無頭仍用真正非同步請求／領取，只串行配置，沒有停用或 blocking load。
static func inflight_limit() -> int:
	return 1 if DisplayServer.get_name() == "headless" else MAX_INFLIGHT


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
