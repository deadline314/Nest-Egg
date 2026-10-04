class_name SoundProfileTable
extends RefCounted
## 聲音設定表：profile id（武器 id、角色 id）→ 動作（kind）→ 聲音名稱（音效或聲音事件）。
## 資料格式：{ "default": { kind: 名稱 }, "profiles": { id: { "extends": 另一個 id, kind: 名稱 } } }
## 查詢順序：自己 → extends 的 profile（可串接）→ default；欄位存在但為空字串代表「這個動作刻意不發聲」。
## 名稱可以是字串，或字串陣列（依序挑第一個存在的）；名稱裡的 {key} 會用呼叫端給的 ctx 代入（例如 {attack_category}）。

const MAX_DEPTH := 8

var path := ""
var tag := ""
var kinds: PackedStringArray = PackedStringArray()
## 值不是名稱的欄位（例如換彈時間軸）：查表與繼承照常，但名稱檢查略過，由擁有者自己驗證。
var list_kinds: PackedStringArray = PackedStringArray()
var _default: Dictionary = {}
var _profiles: Dictionary = {}


func _init(p_path: String, p_tag: String, p_kinds: PackedStringArray, p_list_kinds := PackedStringArray()) -> void:
	path = p_path
	tag = p_tag
	kinds = p_kinds
	list_kinds = p_list_kinds
	reload()


func reload(fresh := false) -> void:
	_default = {}
	_profiles = {}
	var root := AudioData.read_root(path, tag, PackedStringArray(["default", "profiles"]), fresh)
	if root.is_empty():
		return
	# 複製一份：實驗室的試聽修改只動記憶體裡的資料，不能污染資源快取。
	_default = (root["default"] as Dictionary).duplicate(true)
	_profiles = (root["profiles"] as Dictionary).duplicate(true)


func has_profile(id: StringName) -> bool:
	return _profiles.has(String(id))


func profile_ids() -> Array:
	return _profiles.keys()


func raw_profiles() -> Dictionary:
	return _profiles


func raw_default() -> Dictionary:
	return _default


## 只改記憶體裡的設定（實驗室試聽用，不寫檔）；id 為 "default" 改預設，沒有這個 profile 時建立。reload(true) 還原。
func override(id: StringName, kind: StringName, value: Variant) -> void:
	if id == &"default":
		_default[String(kind)] = value
		return
	if typeof(_profiles.get(String(id))) != TYPE_DICTIONARY:
		_profiles[String(id)] = {}
	(_profiles[String(id)] as Dictionary)[String(kind)] = value


## 找出這個動作的設定值（字串或陣列）；找不到回傳 null。
func lookup(id: StringName, kind: StringName) -> Variant:
	var current := String(id)
	for depth in MAX_DEPTH:
		var profile: Variant = _profiles.get(current)
		if typeof(profile) != TYPE_DICTIONARY:
			break
		if (profile as Dictionary).has(String(kind)):
			return (profile as Dictionary)[String(kind)]
		var parent: Variant = (profile as Dictionary).get("extends")
		if parent == null:
			break
		current = str(parent)
	return _default.get(String(kind))


## 解析成實際要播的名稱；沒有設定或刻意靜音時回傳空字串。has_name 用來檢查名稱是否存在（陣列取第一個存在的）。
func resolve(id: StringName, kind: StringName, ctx: Dictionary, has_name: Callable) -> StringName:
	var value: Variant = lookup(id, kind)
	var candidates: Array = value if typeof(value) == TYPE_ARRAY else [value]
	for candidate: Variant in candidates:
		var name := str(candidate).format(ctx) if candidate != null else ""
		if name.is_empty():
			if typeof(value) != TYPE_ARRAY:
				return &""
			continue
		if has_name.call(StringName(name)):
			return StringName(name)
	return &""


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。has_name 檢查名稱是否存在（陣列內只要有一個存在就算通過）。
func validate(has_name: Callable) -> PackedStringArray:
	var errors := PackedStringArray()
	for kind in kinds:
		if not _default.has(kind):
			errors.append("%s 的 default 缺少動作「%s」" % [path, kind])
	_check_entries("default", _default, errors, has_name)
	for id: String in _profiles.keys():
		var profile: Variant = _profiles[id]
		if typeof(profile) != TYPE_DICTIONARY:
			errors.append("%s 的「%s」不是字典" % [path, id])
			continue
		var parent: Variant = (profile as Dictionary).get("extends")
		if parent != null and not _profiles.has(str(parent)):
			errors.append("%s 的「%s」extends 不存在的「%s」" % [path, id, parent])
		elif parent != null and _has_cycle(id):
			errors.append("%s 的「%s」的 extends 形成迴圈" % [path, id])
		_check_entries(id, profile as Dictionary, errors, has_name)
	return errors


func _check_entries(id: String, entries: Dictionary, errors: PackedStringArray, has_name: Callable) -> void:
	for key: String in entries.keys():
		if key == "extends" or list_kinds.has(key):
			continue
		if not kinds.has(key):
			errors.append("%s 的「%s」有不認得的動作「%s」（可用：%s）" % [path, id, key, ", ".join(kinds)])
			continue
		var value: Variant = entries[key]
		var candidates: Array = value if typeof(value) == TYPE_ARRAY else [value]
		var any_found := false
		for candidate: Variant in candidates:
			if typeof(candidate) != TYPE_STRING:
				errors.append("%s 的「%s」的「%s」要是字串或字串陣列" % [path, id, key])
				any_found = true
				break
			var text := str(candidate)
			# 含 {} 的名稱要等到執行時才知道，這裡不檢查；空字串代表刻意靜音。
			if text.is_empty() or text.contains("{") or has_name.call(StringName(text)):
				any_found = true
		if not any_found:
			errors.append("%s 的「%s」的「%s」引用不存在的聲音：%s" % [path, id, key, value])


func _has_cycle(start: String) -> bool:
	var current := start
	for depth in MAX_DEPTH:
		var profile: Variant = _profiles.get(current)
		if typeof(profile) != TYPE_DICTIONARY or not (profile as Dictionary).has("extends"):
			return false
		current = str((profile as Dictionary)["extends"])
		if current == start:
			return true
	return true
