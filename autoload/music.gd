extends Node
## 背景音樂：依情境（主選單、關卡、通關、死亡）與關卡內的狀態（平靜 calm、戰鬥 combat、頭目 boss）切換曲目。
## 資料 data/audio/music.json：tracks（曲目檔、音量）、cues（曲目＋淡入淡出秒數）、map（情境與關卡／光影區段對應哪個 cue）。
## 對應從具體到一般：關卡 id → 光影設定 id → default；該狀態沒有 cue 時，頭目退回戰鬥、戰鬥退回平靜。
## 戰鬥：玩家附近有進入戰鬥的敵人就切過去，附近都沒有之後再過一陣子才退回，避免來回跳。
## 暫停與背包開啟時音樂變悶且變小，過場動畫時壓低；曲目遺失或格式錯誤時記錄具體位置並維持靜音，不崩潰。

const PATH := "res://data/audio/music.json"
const BUS := &"Music"
const TAG := "Music"
const STATES: PackedStringArray = ["calm", "combat", "boss"]
const SCREENS: PackedStringArray = ["menu", "victory", "death"]
## 戰鬥偵測：每隔多久檢查一次、敵人離玩家多近算數、都沒有敵人後多久才退回平靜（秒）。
const COMBAT_CHECK_INTERVAL := 0.25
const COMBAT_RANGE := 420.0
const COMBAT_EXIT_DELAY := 4.0
## 暫停時的低通截止頻率（Hz）與降低的音量（dB）；過場動畫時降低的音量。
const PAUSE_CUTOFF_HZ := 800.0
const OPEN_CUTOFF_HZ := 20500.0
const PAUSE_DUCK_DB := -6.0
const CINEMATIC_DUCK_DB := -8.0
const FILTER_RATE_HZ := 40000.0
const DUCK_RATE_DB := 24.0
const FILTERED_BUSES: Array[StringName] = [&"Music", &"Ambience"]

enum Context { NONE, MENU, LEVEL, VICTORY, DEATH }

var enabled := true

var _player: CrossfadePlayer
var _tracks: Dictionary = {}
var _cues: Dictionary = {}
var _map: Dictionary = {}
var _context := Context.NONE
var _level_id: StringName = &""
var _zone_id: StringName = &""
var _state: StringName = &"calm"
var _boss := false
var _cue: StringName = &""
var _positions: Dictionary = {}
var _check_left := 0.0
var _no_enemy_time := 0.0
var _cutoff := OPEN_CUTOFF_HZ
var _duck_db := 0.0
var _filters: Dictionary = {}  # 匯流排 -> [低通效果, 增益效果]
var _data_path := PATH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = CrossfadePlayer.new(BUS)
	add_child(_player)
	_setup_pause_filters()
	load_data()
	EventBus.zone_changed.connect(_on_zone_changed)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.player_died.connect(_on_player_died)


## 讀取音樂資料；fresh 為 true 時略過快取（實驗室寫回後重讀）。可指定另一份資料檔（測試用）。
func load_data(path := PATH, fresh := false) -> void:
	_data_path = path
	_tracks = {}
	_cues = {}
	_map = {}
	var root := AudioData.read_root(path, TAG, PackedStringArray(["tracks", "cues", "map"]), fresh)
	if root.is_empty():
		return
	_tracks = root["tracks"]
	_cues = root["cues"]
	_map = root["map"]


# ---------------------------------------------------------------------------
# 情境
# ---------------------------------------------------------------------------

func show_menu() -> void:
	_context = Context.MENU
	_play_screen(&"menu")


func show_victory() -> void:
	_context = Context.VICTORY
	_play_screen(&"victory")


## 進入關卡：從平靜開始，之後依光影區段與戰鬥狀態切換。
func enter_level(level_id: StringName) -> void:
	_context = Context.LEVEL
	_level_id = level_id
	_zone_id = &""
	_state = &"calm"
	_boss = false
	_no_enemy_time = 0.0
	_refresh_level_cue()


func leave_level() -> void:
	if _context != Context.LEVEL:
		return
	_context = Context.NONE
	_level_id = &""
	_zone_id = &""
	_remember_position()
	_cue = &""
	_player.stop(1.0)


func stop(fade := 1.0) -> void:
	_context = Context.NONE
	_cue = &""
	_player.stop(fade)


func current_cue() -> StringName:
	return _cue


func current_state() -> StringName:
	return _state


func is_playing() -> bool:
	return _player.is_playing()


func player() -> CrossfadePlayer:
	return _player


## 直接播放一個 cue（實驗室與測試用）。
func play_cue(cue_id: StringName, force := false) -> bool:
	return _switch_to(cue_id, force)


# ---------------------------------------------------------------------------
# 對應
# ---------------------------------------------------------------------------

## 這個關卡、區段、狀態該播哪個 cue；找不到回傳空字串。
func resolve_cue(level_id: StringName, zone_id: StringName, state: StringName) -> StringName:
	var order: Array[StringName] = [state]
	if state == &"boss":
		order.append(&"combat")
	if state != &"calm":
		order.append(&"calm")
	for wanted in order:
		for scope in [_scope(&"levels", level_id), _scope(&"zones", zone_id), _map.get("default", {})]:
			if typeof(scope) == TYPE_DICTIONARY and (scope as Dictionary).has(String(wanted)):
				var cue := StringName(str((scope as Dictionary)[String(wanted)]))
				if _cues.has(String(cue)):
					return cue
	return &""


func screen_cue(screen: StringName) -> StringName:
	var screens: Variant = _map.get("screens", {})
	var cue := StringName(str((screens as Dictionary).get(String(screen), ""))) if typeof(screens) == TYPE_DICTIONARY else &""
	return cue if _cues.has(String(cue)) else &""


func _scope(group: StringName, id: StringName) -> Variant:
	var table: Variant = _map.get(String(group), {})
	return (table as Dictionary).get(String(id)) if typeof(table) == TYPE_DICTIONARY else null


func cue_def(cue_id: StringName) -> Dictionary:
	return _cues.get(String(cue_id), {})


func track_def(track_id: StringName) -> Dictionary:
	return _tracks.get(String(track_id), {})


func cue_ids() -> Array:
	return _cues.keys()


func track_ids() -> Array:
	return _tracks.keys()


# ---------------------------------------------------------------------------
# 播放
# ---------------------------------------------------------------------------

func _play_screen(screen: StringName) -> void:
	_boss = false
	_state = &"calm"
	_switch_to(screen_cue(screen))


func _refresh_level_cue() -> void:
	if _context == Context.LEVEL:
		_switch_to(resolve_cue(_level_id, _zone_id, &"boss" if _boss else _state))


## 換到某個 cue。空字串 = 淡出成靜音。回傳是否真的換了。
func _switch_to(cue_id: StringName, force := false) -> bool:
	if not enabled:
		return false
	if cue_id == &"":
		if _cue != &"":
			_remember_position()
			_cue = &""
			_player.stop(1.5)
		return false
	if cue_id == _cue and _player.is_playing() and not force:
		return false
	if not _cues.has(String(cue_id)):
		AudioData.report("music_cue:%s" % cue_id, "[%s] 沒有這個 cue「%s」（%s），維持目前的音樂" % [TAG, cue_id, _data_path])
		return false
	var def := cue_def(cue_id)
	var track_id := StringName(str(def.get("track", "")))
	var track := track_def(track_id)
	var stream := _load_stream(cue_id, track_id, track)
	if stream == null:
		return false
	_remember_position()
	var loop := bool(track.get("loop", true))
	var start := float(_positions.get(String(cue_id), 0.0)) if loop else 0.0
	if start >= stream.get_length() - 1.0:
		start = 0.0
	_cue = cue_id
	return _player.play(stream, float(def.get("volume_db", 0.0)) + float(track.get("volume_db", 0.0)),
			float(def.get("fade_in", 1.5)), float(def.get("fade_out", 1.5)), loop, start)


func _remember_position() -> void:
	if _cue != &"" and _player.is_playing() and bool(track_def(StringName(str(cue_def(_cue).get("track", "")))).get("loop", true)):
		_positions[String(_cue)] = _player.playback_position()


func _load_stream(cue_id: StringName, track_id: StringName, track: Dictionary) -> AudioStream:
	var file := str(track.get("file", ""))
	if file.is_empty() or not ResourceLoader.exists(file):
		AudioData.report("music:%s" % track_id, "[%s] cue「%s」的曲目「%s」找不到檔案：%s（%s），維持靜音" % [TAG, cue_id, track_id, file, _data_path])
		return null
	var stream := load(file) as AudioStream
	if stream == null:
		AudioData.report("music:%s" % track_id, "[%s] cue「%s」的曲目「%s」無法載入：%s（%s），維持靜音" % [TAG, cue_id, track_id, file, _data_path])
	return stream


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _on_zone_changed(zone_id: StringName) -> void:
	if _context != Context.LEVEL:
		return
	_zone_id = zone_id
	_refresh_level_cue()


func _on_boss_started(_name: String, _max_health: int) -> void:
	if _context == Context.LEVEL:
		_boss = true
		_refresh_level_cue()


func _on_boss_defeated() -> void:
	if _context == Context.LEVEL:
		_boss = false
		_refresh_level_cue()


func _on_player_died(_cause: StringName) -> void:
	if _context == Context.LEVEL:
		_context = Context.DEATH
		_boss = false
		_play_screen(&"death")


# ---------------------------------------------------------------------------
# 每影格：戰鬥偵測、暫停與過場時的音色
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_filters(delta)
	if _context != Context.LEVEL or _boss:
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = COMBAT_CHECK_INTERVAL
	var engaged := engaged_enemies()
	if engaged > 0:
		_no_enemy_time = 0.0
		if _state != &"combat":
			_state = &"combat"
			_refresh_level_cue()
	elif _state == &"combat":
		_no_enemy_time += COMBAT_CHECK_INTERVAL
		if _no_enemy_time >= COMBAT_EXIT_DELAY:
			_state = &"calm"
			_refresh_level_cue()


## 玩家附近進入戰鬥（警戒或出招中）的敵人數。
func engaged_enemies() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var player := tree.get_first_node_in_group(&"player") as Node2D
	if player == null:
		return 0
	var count := 0
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.is_engaged() and enemy.global_position.distance_to(player.global_position) <= COMBAT_RANGE:
			count += 1
	return count


func _setup_pause_filters() -> void:
	for bus_name in FILTERED_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = OPEN_CUTOFF_HZ
		var amp := AudioEffectAmplify.new()
		amp.volume_db = 0.0
		AudioServer.add_bus_effect(bus, low)
		AudioServer.add_bus_effect(bus, amp)
		_filters[bus_name] = [low, amp]


## 暫停時低通加降音量、過場動畫時只降音量；都是平滑漸變。
func _update_filters(delta: float) -> void:
	var paused := get_tree().paused
	var cutoff_goal := PAUSE_CUTOFF_HZ if paused else OPEN_CUTOFF_HZ
	var duck_goal := (PAUSE_DUCK_DB if paused else 0.0) + (CINEMATIC_DUCK_DB if Story.is_cinematic_active() else 0.0)
	_cutoff = move_toward(_cutoff, cutoff_goal, FILTER_RATE_HZ * delta)
	_duck_db = move_toward(_duck_db, duck_goal, DUCK_RATE_DB * delta)
	for pair: Array in _filters.values():
		(pair[0] as AudioEffectLowPassFilter).cutoff_hz = _cutoff
		(pair[1] as AudioEffectAmplify).volume_db = _duck_db


func filter_state() -> Dictionary:
	return {"cutoff_hz": _cutoff, "duck_db": _duck_db}


# ---------------------------------------------------------------------------
# 資料檢查
# ---------------------------------------------------------------------------

## 回傳錯誤訊息清單（空 = 沒問題）。
func validate(path := "") -> PackedStringArray:
	var where := path if not path.is_empty() else _data_path
	var errors := PackedStringArray()
	for id: String in _tracks.keys():
		var track: Variant = _tracks[id]
		if typeof(track) != TYPE_DICTIONARY:
			errors.append("%s 的曲目「%s」不是字典" % [where, id])
			continue
		var file := str((track as Dictionary).get("file", ""))
		if file.is_empty() or not ResourceLoader.exists(file):
			errors.append("%s 的曲目「%s」找不到檔案：%s" % [where, id, file])
		elif not (load(file) is AudioStream):
			errors.append("%s 的曲目「%s」不是音訊檔：%s" % [where, id, file])
	for id: String in _cues.keys():
		var cue: Variant = _cues[id]
		if typeof(cue) != TYPE_DICTIONARY:
			errors.append("%s 的 cue「%s」不是字典" % [where, id])
			continue
		if not _tracks.has(str((cue as Dictionary).get("track", ""))):
			errors.append("%s 的 cue「%s」引用不存在的曲目「%s」" % [where, id, (cue as Dictionary).get("track", "")])
		for key in ["fade_in", "fade_out"]:
			if float((cue as Dictionary).get(key, 1.0)) < 0.0:
				errors.append("%s 的 cue「%s」的 %s 不能是負的" % [where, id, key])
	for group in ["levels", "zones"]:
		var table: Variant = _map.get(group, {})
		if typeof(table) != TYPE_DICTIONARY:
			errors.append("%s 的 map.%s 要是字典" % [where, group])
			continue
		for key: String in (table as Dictionary).keys():
			_check_states("%s.%s" % [group, key], (table as Dictionary)[key], errors, where)
	_check_states("default", _map.get("default", {}), errors, where)
	var screens: Variant = _map.get("screens", {})
	if typeof(screens) == TYPE_DICTIONARY:
		for key: String in (screens as Dictionary).keys():
			if not SCREENS.has(key):
				errors.append("%s 的 map.screens 有不認得的畫面「%s」（可用：%s）" % [where, key, ", ".join(SCREENS)])
			elif not _cues.has(str((screens as Dictionary)[key])):
				errors.append("%s 的 map.screens.%s 引用不存在的 cue「%s」" % [where, key, (screens as Dictionary)[key]])
	return errors


func _check_states(label: String, scope: Variant, errors: PackedStringArray, where: String) -> void:
	if typeof(scope) != TYPE_DICTIONARY:
		errors.append("%s 的 map.%s 要是字典" % [where, label])
		return
	for state: String in (scope as Dictionary).keys():
		if not STATES.has(state):
			errors.append("%s 的 map.%s 有不認得的狀態「%s」（可用：%s）" % [where, label, state, ", ".join(STATES)])
		elif not _cues.has(str((scope as Dictionary)[state])):
			errors.append("%s 的 map.%s.%s 引用不存在的 cue「%s」" % [where, label, state, (scope as Dictionary)[state]])
