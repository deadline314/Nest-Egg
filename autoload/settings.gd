extends Node
## 玩家設定服務：統一讀寫 user://settings.cfg，並套用音量。
## 其他系統（例如 InputBindings）透過 get_value / set_value 存取自己的區段，
## 不需要各自管理檔案。寫入會延遲合併（拖動滑桿時不會每格都寫檔）。

signal volume_changed(bus: StringName, linear: float)
signal display_changed

const DEFAULT_PATH := "user://settings.cfg"
const SAVE_DELAY := 0.4
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
const HUD_AUTO_HIDE_DEFAULT := true
## 亮度滑桿（0~1）的預設值＝設計的壓抑程度；範圍的兩端是 gamma 2^(±0.6)。
const BRIGHTNESS_DEFAULT := 0.5
const BRIGHTNESS_RANGE := 1.2

## 設定選單顯示的音量項目。之後加入背景音樂時，在這裡加一筆 Music 即可。
const AUDIO_BUSES: Array[Dictionary] = [
	{"bus": &"Master", "label": "主音量", "tooltip": "所有聲音的整體音量", "default": 0.8},
	{"bus": &"SFX", "label": "音效", "tooltip": "射擊、爆炸、介面等音效", "default": 1.0},
]

var _path := DEFAULT_PATH
var _config := ConfigFile.new()
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_ensure_buses()
	_load()
	_apply_audio()


func _exit_tree() -> void:
	# 關閉遊戲時若還有未寫入的變更，立即寫入。
	if _save_timer != null and not _save_timer.is_stopped():
		save_now()


# ---------------------------------------------------------------------------
# 通用存取
# ---------------------------------------------------------------------------

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	# ConfigFile 把 null 預設值視為「沒給預設」並報錯，所以先檢查是否存在。
	if not _config.has_section_key(section, key):
		return default
	return _config.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_config.set_value(section, key, value)
	_save_timer.start()


func erase_section(section: String) -> void:
	if _config.has_section(section):
		_config.erase_section(section)
		_save_timer.start()


func save_now() -> void:
	_save_timer.stop()
	var err := _config.save(_path)
	if err != OK:
		push_warning("[Settings] 設定寫入失敗（%s）：%s" % [_path, error_string(err)])


## 切換存檔位置（測試用，避免覆蓋玩家設定）。會重新讀取並套用。
func use_storage(path: String) -> void:
	if not _save_timer.is_stopped():
		save_now()
	_path = path
	_load()
	_apply_audio()


func storage_path() -> String:
	return _path


func _load() -> void:
	_config = ConfigFile.new()
	var err := _config.load(_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[Settings] 設定檔損毀或無法讀取（%s），改用預設值。" % error_string(err))
		_config = ConfigFile.new()


# ---------------------------------------------------------------------------
# 音量
# ---------------------------------------------------------------------------

## 0.0 ~ 1.0 線性音量。
func get_volume(bus: StringName) -> float:
	return clampf(float(get_value(AUDIO_SECTION, String(bus), _default_volume(bus))), 0.0, 1.0)


func set_volume(bus: StringName, linear: float) -> void:
	var value := clampf(linear, 0.0, 1.0)
	set_value(AUDIO_SECTION, String(bus), value)
	_apply_bus(bus, value)
	volume_changed.emit(bus, value)


func reset_audio() -> void:
	for entry in AUDIO_BUSES:
		set_volume(entry["bus"], entry["default"])


## 動態 HUD 閒置時是否自動淡出。設定檔內容損毀時退回預設值。
func get_hud_auto_hide() -> bool:
	var value: Variant = get_value(DISPLAY_SECTION, "hud_auto_hide", HUD_AUTO_HIDE_DEFAULT)
	return value if typeof(value) == TYPE_BOOL else HUD_AUTO_HIDE_DEFAULT


func set_hud_auto_hide(enabled: bool) -> void:
	set_value(DISPLAY_SECTION, "hud_auto_hide", enabled)
	display_changed.emit()


## 亮度滑桿位置（0~1）。設定檔內容損毀時退回預設值。
func get_brightness() -> float:
	var value: Variant = get_value(DISPLAY_SECTION, "brightness", BRIGHTNESS_DEFAULT)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return BRIGHTNESS_DEFAULT
	return clampf(float(value), 0.0, 1.0)


func set_brightness(value: float) -> void:
	set_value(DISPLAY_SECTION, "brightness", clampf(value, 0.0, 1.0))
	display_changed.emit()


## 亮度換算成後製的 gamma（1 = 設計值，大於 1 提亮暗部）。
func brightness_gamma() -> float:
	return pow(2.0, (get_brightness() - BRIGHTNESS_DEFAULT) * BRIGHTNESS_RANGE)


func reset_display() -> void:
	set_hud_auto_hide(HUD_AUTO_HIDE_DEFAULT)
	set_brightness(BRIGHTNESS_DEFAULT)


func _default_volume(bus: StringName) -> float:
	for entry in AUDIO_BUSES:
		if entry["bus"] == bus:
			return entry["default"]
	return 1.0


func _apply_audio() -> void:
	for entry in AUDIO_BUSES:
		_apply_bus(entry["bus"], get_volume(entry["bus"]))


func _apply_bus(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("[Settings] 找不到音訊匯流排：%s" % bus)
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


## 專案沒有自訂匯流排配置時，於執行期建立（送往 Master）。
func _ensure_buses() -> void:
	for entry in AUDIO_BUSES:
		var bus: StringName = entry["bus"]
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
