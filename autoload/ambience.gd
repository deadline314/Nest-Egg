extends Node
## 環境音：依光影區段（EventBus.zone_changed）播放雨聲、風聲、機械嗡鳴等底噪，掛在 Ambience 匯流排。
## 資料 data/audio/ambience.json：profiles 以光影設定 id 為鍵，每個 profile 最多 MAX_LAYERS 層（sound 是音效庫的 id，volume_db 微調）；
## 沒寫的區段用 default。換區段時舊的淡出、新的淡入；音效庫沒有那個檔案時記錄一次並略過（該層無聲）。

const PATH := "res://data/audio/ambience.json"
const BUS := &"Ambience"
const MAX_LAYERS := 3
const TAG := "Ambience"

var enabled := true
var _layers: Array[CrossfadePlayer] = []
var _profiles: Dictionary = {}
var _default: Array = []
var _fade := 2.0
var _zone: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_LAYERS:
		var layer := CrossfadePlayer.new(BUS)
		add_child(layer)
		_layers.append(layer)
	load_data()
	EventBus.zone_changed.connect(set_zone)


func load_data(fresh := false) -> void:
	_profiles = {}
	_default = []
	var root := AudioData.read_root(PATH, TAG, PackedStringArray(["profiles"]), fresh)
	if root.is_empty():
		return
	_profiles = root["profiles"]
	_default = root.get("default", []) if typeof(root.get("default", [])) == TYPE_ARRAY else []
	_fade = clampf(float(root.get("fade", 2.0)), 0.0, 10.0)


## 切到某個區段的環境音（空 id = 離開關卡，全部淡出）。
func set_zone(zone_id: StringName) -> void:
	_zone = zone_id
	if not enabled:
		return
	var wanted := layers_for(zone_id) if zone_id != &"" else []
	for i in _layers.size():
		var layer := _layers[i]
		if i >= wanted.size():
			layer.stop(_fade)
			continue
		var entry: Dictionary = wanted[i]
		var sound := StringName(str(entry.get("sound", "")))
		var stream := _stream_for(sound)
		if stream == null:
			layer.stop(_fade)
			continue
		layer.play(stream, float(entry.get("volume_db", 0.0)) + Sfx.bank().volume_db(sound), _fade, _fade, true)


## 這個區段要播的層（區段沒有登記時用 default）。
func layers_for(zone_id: StringName) -> Array:
	var raw: Variant = _profiles.get(String(zone_id), _default)
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for entry: Variant in raw:
		if typeof(entry) == TYPE_DICTIONARY and result.size() < MAX_LAYERS:
			result.append(entry)
	return result


func current_zone() -> StringName:
	return _zone


func playing_layers() -> int:
	var count := 0
	for layer in _layers:
		count += 1 if layer.is_playing() else 0
	return count


func layer_player(index: int) -> CrossfadePlayer:
	return _layers[index]


func stop_all(fade := 0.0) -> void:
	for layer in _layers:
		layer.stop(fade)


func _stream_for(sound: StringName) -> AudioStream:
	var variants := Sfx.bank().variants(sound)
	if variants.is_empty():
		AudioData.report("ambience:" + String(sound), "[%s] 環境音「%s」在音效庫沒有可用的檔案（%s），該層無聲" % [TAG, sound, PATH])
		return null
	return variants[0]


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var all: Dictionary = _profiles.duplicate()
	all["default"] = _default
	for id: String in all.keys():
		var raw: Variant = all[id]
		if typeof(raw) != TYPE_ARRAY:
			errors.append("%s 的「%s」要是陣列" % [PATH, id])
			continue
		if (raw as Array).size() > MAX_LAYERS:
			errors.append("%s 的「%s」最多 %d 層（現在 %d）" % [PATH, id, MAX_LAYERS, (raw as Array).size()])
		for entry: Variant in raw:
			if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has("sound"):
				errors.append("%s 的「%s」有項目缺少 sound" % [PATH, id])
			elif not Sfx.bank().has_files(StringName(str((entry as Dictionary)["sound"]))):
				errors.append("%s 的「%s」引用音效庫沒有檔案的環境音「%s」" % [PATH, id, (entry as Dictionary)["sound"]])
	return errors
