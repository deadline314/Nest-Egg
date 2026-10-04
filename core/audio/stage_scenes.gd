class_name StageScenes
extends RefCounted
## 實驗室的畫面情境目錄：一個情境 = 一個動作加參數（例如「手槍射擊三發」）；每個聲音位置（P-XXX-NNN）對應一個以上的情境，
## 或明確標示沒有畫面的原因。資料：data/audio/stage_scenes.json（格式見 design/16-audio/DESIGN.md 5.3）。
## 這裡只管資料的讀取與檢查；動作怎麼執行在 tools/sound_lab/stage_actions.gd。

const PATH := "res://data/audio/stage_scenes.json"

var path := ""
var _scenes: Dictionary = {}
var _slots: Dictionary = {}
var _groups: Dictionary = {}

static var _shared: StageScenes


static func shared() -> StageScenes:
	if _shared == null:
		_shared = StageScenes.new(PATH)
	return _shared


func _init(p_path: String = PATH) -> void:
	path = p_path
	reload()


func reload(fresh := false) -> void:
	_scenes = {}
	_slots = {}
	_groups = {}
	var root := AudioData.read_root(path, "StageScenes", PackedStringArray(["scenes", "slots"]), fresh)
	if root.is_empty():
		return
	_scenes = (root["scenes"] as Dictionary).duplicate(true)
	_slots = (root["slots"] as Dictionary).duplicate(true)
	if typeof(root.get("groups")) == TYPE_DICTIONARY:
		_groups = (root["groups"] as Dictionary).duplicate(true)


func is_loaded() -> bool:
	return not _scenes.is_empty()


## 所有情境 id（依檔案順序）。
func ids() -> Array:
	return _scenes.keys()


func has_scene(id: String) -> bool:
	return _scenes.has(id)


func scene(id: String) -> Dictionary:
	var value: Variant = _scenes.get(id)
	return value if typeof(value) == TYPE_DICTIONARY else {}


## 情境分組（武器、命中、…）的顯示順序與名稱：{ 代碼: 名稱 }。
func groups() -> Dictionary:
	return _groups


## 某個位置對應的情境 id；沒有對應（或明確標示沒有畫面）回傳空陣列。
func scenes_for_slot(slot_id: String) -> PackedStringArray:
	var value: Variant = _slots.get(slot_id)
	var out := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for id: Variant in value:
			out.append(str(id))
	return out


## 這個位置沒有畫面的原因；有對應情境或根本沒登記時回傳空字串。
func slot_reason(slot_id: String) -> String:
	var value: Variant = _slots.get(slot_id)
	return str((value as Dictionary).get("none", "")) if typeof(value) == TYPE_DICTIONARY else ""


func has_slot_entry(slot_id: String) -> bool:
	return _slots.has(slot_id)


## 某個情境服務哪些位置（情境清單顯示用）。
func slots_for_scene(scene_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for slot_id: String in _slots.keys():
		if scenes_for_slot(slot_id).has(scene_id):
			out.append(slot_id)
	return out


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
## slot_ids 是位置登記裡的所有位置（每個都必須有對應或原因）；has_action 檢查動作是否存在。
func validate(slot_ids: Array, has_action: Callable) -> PackedStringArray:
	var errors := PackedStringArray()
	if _scenes.is_empty():
		errors.append("%s 沒有任何情境（需要 scenes 字典）" % path)
		return errors
	for id: String in _scenes.keys():
		var entry: Variant = _scenes[id]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s 的情境「%s」不是字典" % [path, id])
			continue
		var d := entry as Dictionary
		if str(d.get("name", "")).is_empty():
			errors.append("%s 的情境「%s」缺少 name" % [path, id])
		var group := str(d.get("group", ""))
		if group.is_empty() or (not _groups.is_empty() and not _groups.has(group)):
			errors.append("%s 的情境「%s」的 group「%s」不在 groups 裡" % [path, id, group])
		var action := str(d.get("action", ""))
		if action.is_empty() or not has_action.call(action):
			errors.append("%s 的情境「%s」的動作「%s」不存在" % [path, id, action])
		if d.has("params") and typeof(d["params"]) != TYPE_DICTIONARY:
			errors.append("%s 的情境「%s」的 params 要是字典" % [path, id])
		if str(d.get("tip", "")).is_empty():
			errors.append("%s 的情境「%s」缺少 tip（一句話說明這個情境做了什麼）" % [path, id])
	for slot_id: Variant in slot_ids:
		if not _slots.has(str(slot_id)):
			errors.append("%s 沒有位置 %s 的對應（要有情境，或寫 {\"none\": 原因}）" % [path, slot_id])
	for slot_id: String in _slots.keys():
		var value: Variant = _slots[slot_id]
		if typeof(value) == TYPE_ARRAY and not (value as Array).is_empty():
			for scene_id: Variant in value:
				if not _scenes.has(str(scene_id)):
					errors.append("%s 的位置 %s 引用不存在的情境「%s」" % [path, slot_id, scene_id])
		elif typeof(value) == TYPE_DICTIONARY and not str((value as Dictionary).get("none", "")).is_empty():
			pass
		else:
			errors.append("%s 的位置 %s 要是情境陣列，或 {\"none\": 原因}" % [path, slot_id])
		if not slot_ids.is_empty() and not slot_ids.has(slot_id):
			errors.append("%s 有不存在的位置 %s" % [path, slot_id])
	return errors
