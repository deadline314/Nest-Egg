class_name RunSnapshot
extends RefCounted
## 整輪資料的唯一聚合邊界。先準備完整有效快照，再套用單例。

const SCALARS := ["lives_left", "deaths", "kills", "finishers", "run_time", "last_death_clock", "respawn_pending", "checkpoint_notice_pending", "has_checkpoint", "checkpoint_level_path", "current_level_path", "carried_health"]
const DICTIONARIES := ["area_states", "checkpoint_world", "checkpoint_progress", "level_start_progress", "level_start_loadout", "checkpoint_loadout"]


static func capture(level_path: String, runtime: Dictionary, cinematic := "", completed := false, context: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {}
	for key: String in SCALARS:
		state[key] = GameState.get(key)
	for key: String in DICTIONARIES:
		state[key] = GameState.get(key).duplicate(true)
	state["checkpoint_position"] = [GameState.checkpoint_position.x, GameState.checkpoint_position.y]
	state["pending_portal"] = String(GameState.pending_portal)
	return {"version": RunSaveCodec.VERSION, "release": "demo-0.1", "saved_at": Time.get_datetime_string_from_system(true), "level": level_path,
		"difficulty": GameState.difficulty.resource_path, "state": state, "progression": Progression.snapshot(),
		"story": GameState.story_progress_snapshot(), "navigation": QuestMapState.for_run().snapshot(),
		"runtime": runtime, "cinematic": cinematic, "cinematic_context": Story.presentation_context(context), "chapter_complete": completed}


static func prepare(raw: Dictionary) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(raw)
	if not errors.is_empty():
		return {"error": errors[0]}
	if not RunSaveCodec.valid_version(raw.get("version")):
		return {"error": "run/version缺漏或格式損毀"}
	var release: Variant = raw.get("release")
	if not release is String or release.is_empty() or release.length() > 64 or not release.is_valid_filename() or release != release.strip_edges():
		return {"error": "run/release缺漏或格式損毀"}
	if raw.get("version") != RunSaveCodec.VERSION or raw.get("release") != "demo-0.1":
		return {"error": "run/version或release不支援；原檔保留", "unknown_version": true}
	var level := RunSaveCodec.resource(raw.get("level"), "level", "res://data/levels/") as LevelData
	if level == null:
		return {"error": "run/level找不到有效專案關卡，原檔保留"}
	for key in ["state", "progression", "story", "navigation", "runtime"]:
		if not raw.get(key) is Dictionary:
			return {"error": "run/%s缺漏或型別不符，不能套用半份存檔" % key}
	var story: Dictionary = raw["story"]
	if not story.get("flags") is Dictionary or not story.get("seen") is Array or not story.get("items") is Dictionary:
		return {"error": "run/story缺漏旗標、演出或物品；原檔保留"}
	var items := StoryItems.prepare_snapshot(story["items"], "run/story/items")
	if items.has("error"):
		return items
	for flag: Variant in story["flags"]:
		if not GameState._flag_value_valid(story["flags"][flag]):
			return {"error": "run/story/flags/%s不是有效旗標值" % flag}
	for scene: Variant in story["seen"]:
		if typeof(scene) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {"error": "run/story/seen包含非文字場景"}
	var result := raw.duplicate(true)
	result["story"]["items"] = items["data"]
	var state: Dictionary = result["state"]
	for key: String in DICTIONARIES:
		if not state.get(key, {}) is Dictionary:
			return {"error": "run/state/%s必須是物件" % key}
		state[key] = state.get(key, {})
	for key in ["has_checkpoint", "respawn_pending", "checkpoint_notice_pending"]:
		if not state.get(key, false) is bool:
			return {"error": "run/state/%s必須是布林值" % key}
		state[key] = state.get(key, false)
	for key in ["deaths", "kills", "finishers"]:
		state[key] = int(RunSaveCodec.number(state.get(key), 0, 0, 1000000))
	state["lives_left"] = int(RunSaveCodec.number(state.get("lives_left"), -1, -1, 1000))
	state["run_time"] = RunSaveCodec.number(state.get("run_time"), 0, 0, 100000000)
	state["carried_health"] = int(RunSaveCodec.number(state.get("carried_health"), -1, -1, 1000))
	state["last_death_clock"] = state.get("last_death_clock", "") if state.get("last_death_clock", "") is String else ""
	state["current_level_path"] = level.resource_path
	var checkpoint: Variant = state.get("checkpoint_level_path", "")
	if checkpoint != "" and RunSaveCodec.resource(checkpoint, "level", "res://data/levels/") == null:
		push_warning("[RunSave] run/state/checkpoint_level_path 無效，保留首次建檔規則並退有效起點")
		state["has_checkpoint"] = false
		checkpoint = ""
	state["checkpoint_level_path"] = checkpoint
	state["checkpoint_position"] = _vector_array(RunSaveCodec.vector(state.get("checkpoint_position")))
	state["pending_portal"] = state.get("pending_portal", "") if state.get("pending_portal", "") is String else ""
	for id: Variant in state["area_states"]:
		var area: Variant = state["area_states"][id]
		if not area is Dictionary or not area.get("consumed", {}) is Dictionary or not area.get("damage", {}) is Dictionary or not area.get("world", {}) is Dictionary:
			return {"error": "run/state/area_states/%s型別不符" % id}
		for key in ["consumed", "damage", "world"]:
			area[key] = area.get(key, {})
		for key: Variant in area["damage"]:
			area["damage"][key] = int(RunSaveCodec.number(area["damage"][key], 0, 0, 1000000))
		area["world"] = _world(area["world"])
	state["checkpoint_world"] = _world(state["checkpoint_world"])
	result["progression"] = _progression(result["progression"])
	state["checkpoint_progress"] = _progression(state["checkpoint_progress"])
	state["level_start_progress"] = _progression(state["level_start_progress"])
	for key in ["checkpoint_loadout", "level_start_loadout"]:
		state[key] = _loadout(state[key])
	var runtime: Dictionary = result["runtime"]
	if not runtime.get("loadout", {}) is Dictionary or not runtime.get("world", {}) is Dictionary:
		return {"error": "run/runtime/loadout或world型別不符"}
	runtime["loadout"] = _loadout(runtime.get("loadout", {}))
	runtime["world"] = runtime.get("world", {})
	runtime["world"] = _world(runtime["world"])
	if not runtime.get("area", {}) is Dictionary:
		return {"error": "run/runtime/area必須是物件"}
	var area: Dictionary = runtime.get("area", {})
	for key in ["consumed", "damage", "world"]:
		if not area.get(key, {}) is Dictionary:
			return {"error": "run/runtime/area/%s必須是物件" % key}
		area[key] = area.get(key, {})
	area["world"] = _world(area["world"])
	for key: Variant in area["damage"]:
		area["damage"][key] = int(RunSaveCodec.number(area["damage"][key], 0, 0, 1000000))
	runtime["area"] = area
	runtime["health"] = int(RunSaveCodec.number(runtime.get("health"), 1, 0, 1000))
	runtime["facing"] = -1 if runtime.get("facing") == -1 else 1
	var fallback := Vector2.LEFT if runtime["facing"] == -1 else Vector2.RIGHT
	var aim := RunSaveCodec.vector(runtime.get("aim_dir"), fallback)
	runtime["aim_dir"] = _vector_array(aim.normalized() if aim.length_squared() > 0.000001 else fallback)
	runtime["crouching"] = runtime.get("crouching") == true
	runtime["guard"] = RunSaveCodec.number(runtime.get("guard"), 100, 0, 1000)
	runtime["position"] = _vector_array(RunSaveCodec.vector(runtime.get("position"), Vector2(-1, -1)))
	runtime["velocity"] = _vector_array(RunSaveCodec.vector(runtime.get("velocity")))
	runtime["dead"] = runtime.get("dead") == true
	if runtime["health"] == 0 and not runtime["dead"]:
		return {"error": "run/runtime/health歸零但沒有已結算死亡，不套用半份死亡"}
	runtime["ending"] = runtime.get("ending") == true
	runtime["arena"] = runtime.get("arena") == true
	runtime["boss_pending"] = runtime.get("boss_pending") == true
	runtime["can_continue"] = runtime.get("can_continue", true) == true
	runtime["death_cause"] = runtime.get("death_cause", "unknown") if runtime.get("death_cause", "unknown") is String else "unknown"
	var entry: Variant = runtime.get("death_entry", {})
	if not entry is Dictionary or (not entry.is_empty() and (not entry.get("scene") is String or not Story.has_scene(StringName(entry["scene"])))):
		return {"error": "run/runtime/death_entry不是有效死亡場景"}
	runtime["death_entry"] = entry
	for key in ["register_checkpoint", "free"]:
		if runtime["death_entry"].has(key):
			runtime["death_entry"][key] = runtime["death_entry"][key] == true
	var dynamic := _dynamic(runtime)
	if dynamic.has("error"):
		return dynamic
	runtime.merge(dynamic, true)
	result["story"]["deaths"] = state["deaths"]
	var difficulty := RunSaveCodec.resource(result.get("difficulty"), "difficulty", "res://data/difficulty/") as DifficultyData
	if difficulty == null:
		push_warning("[RunSave] run/difficulty 無效，改用標準難度")
		result["difficulty"] = GameState.DIFFICULTY_PATHS[GameState.DEFAULT_DIFFICULTY_INDEX]
	if not result.get("cinematic", "") is String or (result.get("cinematic", "") != "" and not Story.has_scene(StringName(result["cinematic"]))):
		push_warning("[RunSave] run/cinematic 找不到場景，保留未完成旗標並恢復區域入口")
		result["cinematic"] = ""
	result["cinematic"] = result.get("cinematic", "")
	var context: Variant = result.get("cinematic_context", {})
	result["cinematic_context"] = Story.presentation_context(context) if context is Dictionary and result["cinematic"] != "" else {}
	result["chapter_complete"] = result.get("chapter_complete") == true
	return {"data": result}


## Additive data-owner preparation only. Main/Level/navigation installation and
## old-state presentation cancellation must be supplied by a later coordinator.
## Existing apply/rollback intentionally keep their legacy behavior this phase.
static func prepare_install(raw: Dictionary) -> Dictionary:
	var checked := prepare(raw)
	if checked.has("error"):
		return checked
	return StoryInstallBundle.prepare_components(checked["data"])


static func apply(data: Dictionary) -> void:
	# 呼叫端只交 prepare 的結果；此處沒有新的讀檔或任意資源載入。
	GameState.story_autosave = false
	GameState.start_new_run(load(data["difficulty"]) as DifficultyData)
	_apply_components(data)


## 中止演出時撤回暫定效果，保留場景中的玩家死亡事實；死亡計數／費用由Level隨後結算。
static func rollback_presentation(data: Dictionary) -> void:
	# 演出期間經過的時計、戰鬥統計與live死亡事實並非劇情暫定效果。
	var actual: Dictionary = {}
	for key in ["run_time", "kills", "finishers", "deaths", "lives_left", "last_death_clock"]:
		actual[key] = GameState.get(key)
	_apply_components(data.duplicate(true))
	for key in actual:
		GameState.set(key, actual[key])


static func _apply_components(data: Dictionary) -> void:
	var state: Dictionary = data["state"]
	for key: String in SCALARS + DICTIONARIES:
		GameState.set(key, state[key])
	GameState.checkpoint_position = RunSaveCodec.vector(state["checkpoint_position"])
	GameState.pending_portal = StringName(state["pending_portal"])
	Progression.restore(data["progression"])
	GameState.restore_story_progress(data["story"], "run/story")
	# 先還原故事與 area_states，再建正式導覽索引。
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var index := QuestMapIndex.new()
	for chapter in Story.chapter_ids():
		var source := QuestMapIndex.for_chapter(chapter)
		index.areas.merge(source.areas)
		index.checkpoint_keys.append_array(source.checkpoint_keys)
	QuestMapState.for_run().restore(data["navigation"], catalog, index)
	EventBus.lives_changed.emit(GameState.lives_left)


static func _progression(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result["credits"] = int(RunSaveCodec.number(raw.get("credits"), 0, 0, Progression.MAX_CREDITS))
	for key in ["upgrades", "pawned"]:
		result[key] = raw.get(key, {}) if raw.get(key, {}) is Dictionary else {}
	result["abilities"] = raw.get("abilities", []) if raw.get("abilities", []) is Array else []
	result["equipped"] = raw.get("equipped", "") if raw.get("equipped", "") is String else ""
	for key: Variant in result["upgrades"]:
		if not result["upgrades"][key] is Array:
			result["upgrades"][key] = []
		else:
			result["upgrades"][key] = result["upgrades"][key].filter(func(id: Variant) -> bool: return id is String)
	result["abilities"] = result["abilities"].filter(func(id: Variant) -> bool: return id is String)
	for key: Variant in result["pawned"]:
		result["pawned"][key] = int(RunSaveCodec.number(result["pawned"][key], 0, 0, Progression.MAX_PAWNED))
	return result


static func _loadout(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var paths: Array = raw.get("weapons", []) if raw.get("weapons", []) is Array else []
	result["weapons"] = paths.slice(0, Loadout.MAX_SLOTS)
	for i in result["weapons"].size():
		var path: Variant = result["weapons"][i]
		if RunSaveCodec.resource(path, "weapon", "res://data/weapons/") == null:
			push_warning("[RunSave] run/loadout/weapons/%d 無效資源：%s，略過該欄" % [i, path])
			result["weapons"][i] = ""
	for key in ["mag", "reserve", "ammo"]:
		var values: Array = raw.get(key, []) if raw.get(key, []) is Array else []
		result[key] = values.slice(0, Loadout.MAX_SLOTS)
		for i in result[key].size():
			result[key][i] = int(RunSaveCodec.number(result[key][i], 0, -1, 1000000))
	result["active"] = int(RunSaveCodec.number(raw.get("active"), 0, 0, Loadout.MAX_SLOTS - 1))
	var items: Dictionary = raw.get("consumables", {}) if raw.get("consumables", {}) is Dictionary else {}
	for id: Variant in items:
		items[id] = int(RunSaveCodec.number(items[id], 0, 0, 1000))
	result["consumables"] = items
	return result


static func _vector_array(value: Vector2) -> Array:
	return [value.x, value.y]


static func _world(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in raw:
		var value: Variant = raw[key]
		if key.begins_with("npc:"):
			var state: Dictionary = value if value is Dictionary else {}
			var claimed: Array = state.get("claimed", []) if state.get("claimed", []) is Array else []
			claimed = claimed.filter(func(id: Variant) -> bool: return typeof(id) in [TYPE_INT, TYPE_FLOAT])
			result[key] = {"talks": int(RunSaveCodec.number(state.get("talks"), 0, 0, 1000000)),
				"claimed": claimed.map(func(id: Variant) -> int: return int(RunSaveCodec.number(id, 0, 0, 1000000)))}
		else:
			result[key] = value == true
	return result


static func _dynamic(runtime: Dictionary) -> Dictionary:
	var result := {"loose": [], "enemies": [], "encounters": {}}
	for key in ["loose", "enemies"]:
		if not runtime.get(key, []) is Array or runtime.get(key, []).size() > 1024:
			return {"error": "run/runtime/%s不是有界陣列" % key}
		for raw: Variant in runtime.get(key, []):
			if not raw is Dictionary:
				return {"error": "run/runtime/%s包含非物件" % key}
			var entry: Dictionary = raw.duplicate(true)
			entry["position"] = _vector_array(RunSaveCodec.vector(entry.get("position")))
			if key == "enemies":
				if RunSaveCodec.resource(entry.get("resource"), "enemy", "res://data/enemies/") == null or not entry.get("key", "") is String:
					push_warning("[RunSave] run/runtime/enemies無效敵人資源，略過")
					continue
				entry["key"] = entry.get("key", "")
				entry["lost"] = int(RunSaveCodec.number(entry.get("lost"), 0, 0, 1000000))
			else:
				if not entry.get("kind") in ["credit", "health", "weapon", "consumable"]:
					return {"error": "run/runtime/loose包含未知掉落種類"}
				if entry["kind"] == "credit":
					entry["value"] = int(RunSaveCodec.number(entry.get("value"), 0, 0, Progression.MAX_CREDITS))
				elif entry["kind"] == "weapon" or entry["kind"] == "consumable":
					var folder := "res://data/weapons/" if entry["kind"] == "weapon" else "res://data/consumables/"
					if RunSaveCodec.resource(entry.get("resource"), entry["kind"], folder) == null:
						push_warning("[RunSave] run/runtime/loose無效掉落資源，略過")
						continue
			result[key].append(entry)
	if not runtime.get("encounters", {}) is Dictionary:
		return {"error": "run/runtime/encounters必須是物件"}
	for key: String in runtime.get("encounters", {}):
		var entry: Variant = runtime["encounters"][key]
		if not entry is Dictionary:
			return {"error": "run/runtime/encounters/%s必須是物件" % key}
		result["encounters"][key] = {"reinforce": int(RunSaveCodec.number(entry.get("reinforce"), 0, 0, 1024)), "time": RunSaveCodec.number(entry.get("time"), 0, 0, 3600)}
	return result
