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
const FEEL_SECTION := "feel"
const FEEL_KEYS: PackedStringArray = ["shake", "hitstop", "particles"]
const HUD_AUTO_HIDE_DEFAULT := true
## 亮度滑桿（0~1）的預設值＝設計的壓抑程度；範圍的兩端是 gamma 2^(±0.6)。
const BRIGHTNESS_DEFAULT := 0.5
## 「減少閃光」開啟時，爆炸與閃電的閃光強度乘上這個倍率。
const REDUCED_FLASH_SCALE := 0.25
const BRIGHTNESS_RANGE := 1.2

## 設定選單顯示的音量項目；新增匯流排在這裡加一筆（執行期自動建立並送往 Master）。
const AUDIO_BUSES: Array[Dictionary] = [
	{"bus": &"Master", "label": "主音量", "tooltip": "所有聲音的整體音量", "default": 0.8},
	{"bus": &"Music", "label": "音樂", "tooltip": "各場景的背景音樂", "default": 0.7},
	{"bus": &"SFX", "label": "音效", "tooltip": "射擊、爆炸、介面等音效", "default": 1.0},
	{"bus": &"Ambience", "label": "環境音", "tooltip": "雨聲、風聲、機械嗡鳴等場景底噪", "default": 0.8},
]

## Master 限幅器的天花板（dBFS）。
const MASTER_CEILING_DB := -1.0

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
	_ensure_master_limiter()
	_load()
	_apply_audio()
	DisplayMode.ensure_scaling(get_window())
	DisplayMode.set_fullscreen(get_window(), get_fullscreen())


## F11 在任何畫面都能切換全螢幕（設定畫面開著時勾選框會跟著更新）。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


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
	UiKit.apply_text_scale()


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


## 是否全螢幕。設定檔內容損毀時退回視窗模式。
func get_fullscreen() -> bool:
	var value: Variant = get_value(DISPLAY_SECTION, "fullscreen", false)
	return value if typeof(value) == TYPE_BOOL else false


func set_fullscreen(enabled: bool) -> void:
	set_value(DISPLAY_SECTION, "fullscreen", enabled)
	DisplayMode.set_fullscreen(get_window(), enabled)
	display_changed.emit()


## F11：以視窗目前的實際狀態為準切換（視窗可能被作業系統改過）。
func toggle_fullscreen() -> void:
	var window := get_window()
	set_fullscreen(not (DisplayMode.is_fullscreen(window) if DisplayMode.has_window() else get_fullscreen()))


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


## 光影品質檔位（LightQuality.Tier）。設定檔內容損毀或超出範圍時退回預設。
func get_light_quality() -> int:
	var value: Variant = get_value(DISPLAY_SECTION, "light_quality", LightQuality.DEFAULT_TIER)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return LightQuality.DEFAULT_TIER
	return clampi(int(value), LightQuality.Tier.LOW, LightQuality.Tier.HIGH)


func set_light_quality(tier: int) -> void:
	set_value(DISPLAY_SECTION, "light_quality", clampi(tier, LightQuality.Tier.LOW, LightQuality.Tier.HIGH))
	display_changed.emit()


## 是否減少閃光（光敏感）：爆炸與閃電的畫面閃光大幅降低，閃電只閃一次。
func get_reduce_flashes() -> bool:
	var value: Variant = get_value(DISPLAY_SECTION, "reduce_flashes", false)
	return value if typeof(value) == TYPE_BOOL else false


func set_reduce_flashes(enabled: bool) -> void:
	set_value(DISPLAY_SECTION, "reduce_flashes", enabled)
	display_changed.emit()


## 介面改為立即顯示，保留清楚的靜態焦點與遊戲本身的動作。
func get_reduce_ui_motion() -> bool:
	var value: Variant = get_value(DISPLAY_SECTION, "reduce_ui_motion", false)
	return value if typeof(value) == TYPE_BOOL else false


func set_reduce_ui_motion(enabled: bool) -> void:
	set_value(DISPLAY_SECTION, "reduce_ui_motion", enabled)
	display_changed.emit()


## 是否每次都跳過過場動畫（已看過的演出本來就不會重播）。
func get_skip_cutscenes() -> bool:
	var value: Variant = get_value(DISPLAY_SECTION, "skip_cutscenes", false)
	return value if typeof(value) == TYPE_BOOL else false


func set_skip_cutscenes(enabled: bool) -> void:
	set_value(DISPLAY_SECTION, "skip_cutscenes", enabled)
	display_changed.emit()


## 介面字型樣式：smooth（平滑，預設）或 pixel（像素字）；見 UiKit.FONT_STYLES。
func get_ui_font() -> String:
	var value: Variant = get_value(DISPLAY_SECTION, "ui_font", UiKit.DEFAULT_FONT_STYLE)
	return str(value) if typeof(value) == TYPE_STRING and UiKit.FONT_STYLES.has(str(value)) else UiKit.DEFAULT_FONT_STYLE


func set_ui_font(style: String) -> void:
	set_value(DISPLAY_SECTION, "ui_font", style if UiKit.FONT_STYLES.has(style) else UiKit.DEFAULT_FONT_STYLE)
	UiKit.apply_font_style()
	display_changed.emit()


## 介面文字放大，限制在已驗證的範圍；不縮放場景或像素圖示。
func get_ui_text_scale() -> float:
	var value: Variant = get_value(DISPLAY_SECTION, "ui_text_scale", 1.0)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 1.0
	return clampf(float(value), 1.0, 1.2) if is_finite(float(value)) else 1.0


func set_ui_text_scale(scale: float) -> void:
	set_value(DISPLAY_SECTION, "ui_text_scale", clampf(scale, 1.0, 1.2) if is_finite(scale) else 1.0)
	UiKit.apply_text_scale()
	display_changed.emit()


## 畫面閃光的強度倍率（1 = 設計值）。
func flash_scale() -> float:
	return REDUCED_FLASH_SCALE if get_reduce_flashes() else 1.0


## 是否顯示傷害數字（預設關閉）：只顯示弱點、重擊與被擋。
func get_damage_numbers() -> bool:
	var value: Variant = get_value(FEEL_SECTION, "damage_numbers", false)
	return value if typeof(value) == TYPE_BOOL else false


func set_damage_numbers(enabled: bool) -> void:
	set_value(FEEL_SECTION, "damage_numbers", enabled)
	display_changed.emit()


## 打擊回饋的強度倍率（0~1，預設 1）：震動、命中停頓、粒子各一個；設定檔內容損毀時退回預設。
func get_feel_scale(key: String) -> float:
	var value: Variant = get_value(FEEL_SECTION, key, 1.0)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 1.0
	return clampf(float(value), 0.0, 1.0)


func set_feel_scale(key: String, value: float) -> void:
	set_value(FEEL_SECTION, key, clampf(value, 0.0, 1.0))
	display_changed.emit()


## 縮放脈衝（命中時畫面微微縮放）是否開啟；畫面震動調到 0 時一律關閉。
func get_zoom_pulse() -> bool:
	var value: Variant = get_value(FEEL_SECTION, "zoom_pulse", true)
	return value if typeof(value) == TYPE_BOOL else true


func set_zoom_pulse(enabled: bool) -> void:
	set_value(FEEL_SECTION, "zoom_pulse", enabled)
	display_changed.emit()


func zoom_pulse_active() -> bool:
	return get_zoom_pulse() and get_feel_scale("shake") > 0.0


func reset_display() -> void:
	set_value(DISPLAY_SECTION, "quest_objective", true)
	set_value(DISPLAY_SECTION, "quest_arrows", true)
	for key: String in FEEL_KEYS:
		set_feel_scale(key, 1.0)
	set_zoom_pulse(true)
	set_damage_numbers(false)
	set_skip_cutscenes(false)
	set_ui_font(UiKit.DEFAULT_FONT_STYLE)
	set_ui_text_scale(1.0)
	set_reduce_flashes(false)
	set_reduce_ui_motion(false)
	set_hud_auto_hide(HUD_AUTO_HIDE_DEFAULT)
	set_fullscreen(false)
	set_brightness(BRIGHTNESS_DEFAULT)
	set_light_quality(LightQuality.DEFAULT_TIER)


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


## Master 上掛一個硬限幅器：大量槍聲與爆炸同時發聲、素材又接近滿格時，總輸出也不會破音。已經有就不重複掛。
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = MASTER_CEILING_DB
	limiter.pre_gain_db = 0.0
	AudioServer.add_bus_effect(master, limiter)


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
