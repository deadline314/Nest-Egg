class_name RunSnapshot
extends RefCounted
## 整輪資料的唯一聚合邊界。先準備完整有效快照，再套用單例。

const ENCOUNTER_SNAPSHOT = preload("res://game/level/encounter_snapshot.gd")
const SCALARS := ["lives_left", "deaths", "kills", "finishers", "run_time", "last_death_clock", "respawn_pending", "checkpoint_notice_pending", "has_checkpoint", "checkpoint_level_path", "current_level_path", "carried_health"]
const DICTIONARIES := ["area_states", "checkpoint_world", "checkpoint_progress", "level_start_progress", "level_start_loadout", "checkpoint_loadout"]
const MAX_NPC_REACTIONS := 1024


static func capture(level_path: String, runtime: Dictionary, cinematic := "", completed := false, context: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {}
	for key: String in SCALARS:
		state[key] = GameState.get(key)
	for key: String in DICTIONARIES:
		state[key] = GameState.get(key).duplicate(true)
	state["checkpoint_position"] = [GameState.checkpoint_position.x, GameState.checkpoint_position.y]
	state["pending_portal"] = String(GameState.pending_portal)
	return {"version": RunSaveCodec.VERSION, "release": CampaignEdition.current().id, "saved_at": Time.get_datetime_string_from_system(true), "level": level_path,
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
	var edition := CampaignEdition.current()
	var origin := edition.describe(release)
	if raw.get("version") != RunSaveCodec.VERSION or origin == null:
		return {"error": "run/version或release不支援；原檔保留", "unknown_version": true}
	var level := RunSaveCodec.resource(raw.get("level"), "level", "res://data/levels/") as LevelData
	var notices := PackedStringArray()
	if level == null:
		# 區域資源遺失時保留整輪進度，退回復原點所在區域或本版本的起點。
		level = _fallback_level(raw)
		if level == null:
			return {"error": "run/level找不到有效專案關卡，也沒有可用的復原點；原檔保留"}
		notices.append("存檔所在區域已不存在，改從%s繼續。" % ("復原點" if level.resource_path != edition.first_level else "本版本起點"))
		push_warning("[RunSave] run/level %s 無效，退回 %s" % [str(raw.get("level")).left(RunSaveCodec.MAX_DIAGNOSTIC_PATH), level.resource_path])
	if not edition.includes_level(level):
		# 較新累積版本寫的存檔：不降級、不覆寫，說明該用哪個版本。
		return {"error": "存檔停在%s，本版本只到%s；請用「%s」繼續，原檔保留。" % [edition.chapter_title(level.chapter), edition.chapter_title(edition.through), origin.title()],
			"unknown_version": true, "newer_edition": true}
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
	result.erase("notices")  # 修復說明只屬於這一次讀取，不從資料帶入。
	result["level"] = level.resource_path
	var relocated := not notices.is_empty()
	if relocated:
		_reset_location(result)
	result["story"]["items"] = items["data"]
	var repaired := RequiredItemRepair.apply(result["story"]["items"], result["story"]["flags"])
	if repaired.has("error"):
		return repaired
	notices.append_array(repaired["notices"])
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
	var dynamic := _dynamic(runtime, level)
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
	result["chapter_complete"] = result.get("chapter_complete") == true and not relocated
	# 玩家看得到的修復說明；不寫回存檔，下一次保存即是修復後的狀態。
	if not notices.is_empty():
		result["notices"] = Array(notices)
	return {"data": result}


## Strict preparation for the future atomic-result coordinator. Legacy restore
## below retains migration rules and separates installation from publication.
static func prepare_install(raw: Dictionary) -> Dictionary:
	var checked := prepare(raw)
	if checked.has("error"):
		return checked
	return StoryInstallBundle.prepare_components(checked["data"])


static func apply(data: Dictionary, notify := true) -> void:
	# 舊演出的取消通知先看到完整舊局。還原時不呼叫新遊戲，避免
	# wallet=0、物品清空、死亡歸零等中間狀態觸發監聽與保存。
	Story.reset_active_presentation(&"load")
	GameState.story_autosave = false
	GameState.difficulty = load(data["difficulty"]) as DifficultyData
	GameState._carried_loadout = {}
	_apply_components_silent(data)
	# 衍生旗標依讀入的旗標與帳務重算（舊存檔缺少新加的衍生旗標時補上，例如走過晚飯就算走過序章）。
	Story.outcomes.refresh_derived()
	if notify:
		publish_restored()


## 中止演出時撤回暫定效果，保留場景中的玩家死亡事實；死亡計數／費用由Level隨後結算。
static func rollback_presentation(data: Dictionary, notify := true) -> void:
	# 演出期間經過的時計、戰鬥統計與live死亡事實並非劇情暫定效果。
	var actual: Dictionary = {}
	for key in ["run_time", "kills", "finishers", "deaths", "lives_left", "last_death_clock"]:
		actual[key] = GameState.get(key)
	var restored := data.duplicate(true)
	for key in actual:
		restored["state"][key] = actual[key]
	restored["story"]["deaths"] = actual["deaths"]
	# 由取消回呼呼叫；不再次取消正在退場的請求。
	_apply_components_silent(restored)
	if notify:
		publish_restored()


static func _apply_components_silent(data: Dictionary) -> void:
	var state: Dictionary = data["state"]
	for key: String in SCALARS + DICTIONARIES:
		GameState.set(key, state[key])
	GameState.checkpoint_position = RunSaveCodec.vector(state["checkpoint_position"])
	GameState.pending_portal = StringName(state["pending_portal"])
	Progression.restore(data["progression"], false)
	GameState.restore_story_progress(data["story"], "run/story", false)
	# 先還原故事與 area_states，再建正式導覽索引。
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var index := QuestMapIndex.new()
	for chapter in Story.chapter_ids():
		var source := QuestMapIndex.for_chapter(chapter)
		index.areas.merge(source.areas)
		index.checkpoint_keys.append_array(source.checkpoint_keys)
	QuestMapState.for_run().restore(data["navigation"], catalog, index, false)


## 呼叫端先還原 live Level 及 Main 路由欄位，再開放觀察者。
static func publish_restored() -> void:
	Progression.publish_restored()
	QuestMapState.for_run().changed.emit()
	EventBus.lives_changed.emit(GameState.lives_left)


## 退回的區域與存檔的現場無關：清掉現場位置、掉落、敵人與演出，保留整輪成長、故事與各區域紀錄。
static func _reset_location(result: Dictionary) -> void:
	if result.get("runtime") is Dictionary:
		var runtime: Dictionary = result["runtime"]
		for key in ["loose", "enemies", "encounters", "encounter_members_version"]:
			runtime.erase(key)
		runtime["area"] = {}
		runtime["world"] = {}
		runtime["position"] = [-1, -1]
		runtime["velocity"] = [0, 0]
		for key in ["ending", "arena", "boss_pending"]:
			runtime[key] = false
	result["cinematic"] = ""
	result["cinematic_context"] = {}


## 區域資源遺失時的退路：本版本收錄的復原點區域，否則本版本起點。
static func _fallback_level(raw: Dictionary) -> LevelData:
	var edition := CampaignEdition.current()
	var state: Variant = raw.get("state")
	var checkpoint: Variant = state.get("checkpoint_level_path", "") if state is Dictionary else ""
	for path: Variant in [checkpoint, edition.first_level]:
		var level := RunSaveCodec.resource(path, "level", "res://data/levels/") as LevelData
		if edition.includes_level(level):
			return level
	return null


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
	# 臂盾零件（NE-269）只有買過才會出現；不是清單就整欄拿掉（視為沒有零件）。
	if result.has("arm_shield"):
		if result["arm_shield"] is Array:
			result["arm_shield"] = result["arm_shield"].filter(func(id: Variant) -> bool: return id is String)
		else:
			result.erase("arm_shield")
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
			if state.has("reacted"):
				var reacted: Array = []
				var invalid := not state["reacted"] is Array
				if state["reacted"] is Array:
					invalid = state["reacted"].size() > MAX_NPC_REACTIONS
					for i in mini(state["reacted"].size(), MAX_NPC_REACTIONS):
						var index: Variant = state["reacted"][i]
						if StoryTransactionData.integer_in(index, 0, 1000000):
							if not reacted.has(int(index)):
								reacted.append(int(index))
						else:
							invalid = true
				result[key]["reacted"] = reacted
				if invalid:
					push_warning("[RunSave] world/%s/reacted invalid reaction indices omitted" % key.left(192))
		else:
			result[key] = value == true
	return result


static func _dynamic(runtime: Dictionary, level: LevelData = null) -> Dictionary:
	var membership := ENCOUNTER_SNAPSHOT.prepare(runtime, level)
	if membership.has("error"):
		return membership
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
		if membership["data"].has("encounter_members_version"):
			result["encounters"][key]["members"] = membership["data"]["members"][key]
	if membership["data"].has("encounter_members_version"):
		result["encounter_members_version"] = ENCOUNTER_SNAPSHOT.MEMBERS_VERSION
	return result
