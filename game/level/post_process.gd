class_name PostProcess
extends CanvasLayer
## 全螢幕後製：調色、暗角、顆粒、邊緣色差。畫在場景之上、HUD 之下（layer 低於 HUD），
## 所以介面維持清晰。參數由 LightingProfile 決定（見 LightingController），只在數值改變時才更新 shader。

const LAYER := 5
const SHADER_PATH := "res://game/level/post_process.gdshader"
## 顆粒每秒更換幾次（太快會閃、太慢像貼圖）。
const GRAIN_FPS := 24.0
## 低血量：生命比例低於這個值就進入危險狀態（暗角收緊、紅色脈動）。
const DANGER_HEALTH_RATIO := 1.0 / 3.0
const DANGER_FADE_SPEED := 1.6
const DANGER_PULSE_SPEED := 4.2

var _material: ShaderMaterial
var _rect: ColorRect
var _grain_time := 0.0
var _health_ratio := 1.0
var _danger := 0.0
var _pulse_time := 0.0
## 參數 -> 上一次寫進 shader 的值，沒變就不重寫。
var _cache: Dictionary[StringName, Variant] = {}
## 目前的全螢幕效果：強度、總秒數、剩餘秒數與其資料；一次只播一個，新的取代舊的。
var _pulse_amount := 0.0
var _pulse_time_total := 0.0
var _pulse_left := 0.0
var _pulse_def: Dictionary = {}
static var _effects: Dictionary = {}
const EFFECTS_PATH := "res://data/feel/screen_fx.json"


func _ready() -> void:
	layer = LAYER
	var shader := load(SHADER_PATH) as Shader if ResourceLoader.exists(SHADER_PATH) else null
	if shader == null:
		# 沒有 shader 時遊戲照常進行，只是沒有後製。
		push_error("[PostProcess] 找不到後製 shader：%s" % SHADER_PATH)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	# 玩家的亮度設定即時生效。
	Settings.display_changed.connect(_apply_brightness)
	_apply_brightness()
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.screen_pulse.connect(pulse)


func is_active() -> bool:
	return _material != null


## 套用光影設定中的調色與畫面參數。
func apply(profile: LightingProfile) -> void:
	if _material == null:
		return
	_write_param(&"saturation", profile.saturation)
	_write_param(&"contrast", profile.contrast)
	_write_param(&"shadow_tint", Vector3(profile.shadow_tint.r, profile.shadow_tint.g, profile.shadow_tint.b))
	_write_param(&"highlight_tint", Vector3(profile.highlight_tint.r, profile.highlight_tint.g, profile.highlight_tint.b))
	_write_param(&"vignette", profile.vignette)
	# 顆粒與色差依光影品質縮放（中、低檔關閉）。
	var effects := LightQuality.post_effects()
	_write_param(&"grain", profile.grain * effects)
	_write_param(&"aberration", profile.aberration * effects)


func _apply_brightness() -> void:
	_write_param(&"brightness", Settings.brightness_gamma())


## 目前寫進 shader 的參數值（測試與除錯用）。
func parameter(name: StringName) -> Variant:
	return _material.get_shader_parameter(name) if _material != null else null


func _on_health_changed(current: int, maximum: int) -> void:
	_health_ratio = float(current) / float(maxi(1, maximum))


## 目前的危險程度（0~1，不含脈動；測試與除錯用）。
func danger_level() -> float:
	return _danger


func _process(delta: float) -> void:
	if _material == null:
		return
	_update_danger(delta)
	_update_pulse(delta)
	_grain_time += delta
	if _grain_time >= 1.0 / GRAIN_FPS:
		_grain_time = fmod(_grain_time, 1.0 / GRAIN_FPS)
		_material.set_shader_parameter(&"grain_seed", float(Time.get_ticks_msec() % 1000))


## 低血量時平滑進入危險狀態並脈動；「減少閃光」時脈動幅度小很多，不會明暗劇烈起伏。
func _update_danger(delta: float) -> void:
	var target := 1.0 if _health_ratio <= DANGER_HEALTH_RATIO else 0.0
	_danger = move_toward(_danger, target, DANGER_FADE_SPEED * delta)
	_pulse_time += delta
	var amplitude := 0.15 if Settings.get_reduce_flashes() else 0.4
	var pulse := 1.0 - amplitude + amplitude * sin(_pulse_time * DANGER_PULSE_SPEED)
	_write_param(&"danger", _danger * pulse)


## 全螢幕效果種類表（data/feel/screen_fx.json）；缺漏時回傳空字典並記錄一次。
static func effects() -> Dictionary:
	if _effects.is_empty():
		var json: JSON = load(EFFECTS_PATH) as JSON if ResourceLoader.exists(EFFECTS_PATH) else null
		if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("effects")) != TYPE_DICTIONARY:
			push_error("[PostProcess] 無法讀取全螢幕效果資料：%s（需要 effects 字典）" % EFFECTS_PATH)
			return {}
		_effects = (json.data as Dictionary)["effects"]
	return _effects


## 資料檢查：回傳錯誤訊息清單。
static func validate_effects() -> PackedStringArray:
	var errors := PackedStringArray()
	for id: String in effects().keys():
		var def: Variant = effects()[id]
		if typeof(def) != TYPE_DICTIONARY:
			errors.append("%s 的效果「%s」不是字典" % [EFFECTS_PATH, id])
			continue
		if not str((def as Dictionary).get("color", "")).begins_with("#"):
			errors.append("%s 的效果「%s」的 color 要是 #rrggbb" % [EFFECTS_PATH, id])
		if float((def as Dictionary).get("amount", 0.0)) <= 0.0 or float((def as Dictionary).get("amount", 0.0)) > FlashGuard.MAX_AMOUNT:
			errors.append("%s 的效果「%s」的 amount 要在 0 到 %s 之間（過曝上限）" % [EFFECTS_PATH, id, FlashGuard.MAX_AMOUNT])
		if float((def as Dictionary).get("time", 0.0)) <= 0.0:
			errors.append("%s 的效果「%s」的 time 要大於 0" % [EFFECTS_PATH, id])
	return errors


## 播放一個全螢幕效果：先過閃光防護（峰值上限、每秒最多三次、減少閃光降階），沒有 shader 或種類不存在時什麼都不做。
func pulse(kind: StringName) -> void:
	if _material == null:
		return
	var def: Variant = effects().get(String(kind))
	if typeof(def) != TYPE_DICTIONARY:
		return
	var granted := FlashGuard.request(float((def as Dictionary).get("amount", 0.0)))
	if granted <= 0.0:
		return
	_pulse_def = def as Dictionary
	_pulse_amount = granted
	_pulse_time_total = float(_pulse_def.get("time", 0.2))
	_pulse_left = _pulse_time_total
	_write_param(&"pulse_color", Vector3(Color.html(str(_pulse_def.get("color", "#ffffff"))).r, Color.html(str(_pulse_def.get("color", "#ffffff"))).g, Color.html(str(_pulse_def.get("color", "#ffffff"))).b))


func _update_pulse(delta: float) -> void:
	if _pulse_left <= 0.0:
		if _cache.get(&"pulse_amount") != 0.0:
			_write_param(&"pulse_amount", 0.0)
			_write_param(&"pulse_aberration", 0.0)
			_write_param(&"pulse_vignette", 0.0)
		return
	_pulse_left = maxf(0.0, _pulse_left - delta)
	var k := _pulse_left / _pulse_time_total
	var envelope := k * k
	_write_param(&"pulse_amount", _pulse_amount * envelope)
	_write_param(&"pulse_aberration", float(_pulse_def.get("aberration", 0.0)) * envelope * Settings.flash_scale())
	_write_param(&"pulse_vignette", float(_pulse_def.get("vignette", 0.0)) * envelope * Settings.flash_scale())


func _write_param(name: StringName, value: Variant) -> void:
	if _cache.get(name) == value:
		return
	_cache[name] = value
	_material.set_shader_parameter(name, value)
