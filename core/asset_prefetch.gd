class_name AssetPrefetch
extends RefCounted
## 預載：玩家還在別處的時候，用背景執行緒先把「接下來要去的區域」與「接下來要播的過場」用到的貼圖載進資源快取，
## 進場時 load() 直接拿到，不用當場解碼（第一次進場的卡頓就是從磁碟讀取與解碼貼圖）。
## 只請求、不等待：請求過的路徑不重複請求；缺檔、請求失敗都略過並記錄，不影響遊戲。
## 區域的出入口目標、進場過場與劇情觸發點的場景舞台都會預載（見 warm_neighbors）。

## 一次最多請求的貼圖數量（避免背景載入一口氣占滿記憶體與磁碟）。
const MAX_REQUESTS_PER_CALL := 160
const STAGE_DIR := "res://data/cutscene/stages"

static var _requested: Dictionary[String, bool] = {}


## 預載一個區域用到的貼圖。data 可以是 LevelData 或 .tres 路徑。回傳新發出的請求數量。
static func warm_level(data: Variant) -> int:
	# 字串不能直接 as 成物件型別（會是執行期錯誤），所以先依型別分流。
	var level: LevelData = null
	match typeof(data):
		TYPE_OBJECT:
			level = data as LevelData
		TYPE_STRING, TYPE_STRING_NAME:
			var path := str(data)
			if ResourceLoader.exists(path):
				level = load(path) as LevelData
			else:
				push_warning("[AssetPrefetch] 找不到要預載的區域：%s" % path)
	if level == null:
		return 0
	return request(level_texture_paths(level))


## 預載一個區域的鄰居（出入口通往的區域）與這個區域會播的過場舞台。
static func warm_neighbors(data: LevelData) -> int:
	var count := 0
	var targets: Dictionary[String, bool] = {}
	for resource in data.legend.values():
		if resource is PortalData and not (resource as PortalData).target_level.is_empty():
			targets[(resource as PortalData).target_level] = true
	for path in targets:
		count += warm_level(path)
	count += request(scene_texture_paths(data.intro_scene))
	for scene in data.story_triggers:
		count += request(scene_texture_paths(StringName(scene)))
	for scene in data.channel_scenes.values():
		count += request(scene_texture_paths(scene))
	# 死亡重生後的過場（第一次死亡就播）。
	for scene in Story.respawn_scene_ids(data.chapter, 1):
		count += request(scene_texture_paths(scene))
	return count


## 發出背景載入請求；回傳新發出的數量。
static func request(paths: PackedStringArray) -> int:
	var sent := 0
	for path in paths:
		if sent >= MAX_REQUESTS_PER_CALL:
			break
		if _requested.has(path) or not ResourceLoader.exists(path):
			continue
		_requested[path] = true
		if ResourceLoader.load_threaded_request(path) == OK:
			sent += 1
	return sent


static func clear() -> void:
	_requested.clear()


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
	paths.append("%s_n.%s" % [base, ext])
	paths.append("%s_glow.%s" % [base, ext])
