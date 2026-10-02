class_name PostProcess
extends CanvasLayer
## 全螢幕後製：調色、暗角、顆粒、邊緣色差。畫在場景之上、HUD 之下（layer 低於 HUD），
## 所以介面維持清晰。參數由 LightingProfile 決定（見 LightingController），只在數值改變時才更新 shader。

const LAYER := 5
const SHADER_PATH := "res://game/level/post_process.gdshader"
## 顆粒每秒更換幾次（太快會閃、太慢像貼圖）。
const GRAIN_FPS := 24.0

var _material: ShaderMaterial
var _rect: ColorRect
var _grain_time := 0.0
## 參數 -> 上一次寫進 shader 的值，沒變就不重寫。
var _cache: Dictionary[StringName, Variant] = {}


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
	_write_param(&"grain", profile.grain)
	_write_param(&"aberration", profile.aberration)


## 目前寫進 shader 的參數值（測試與除錯用）。
func parameter(name: StringName) -> Variant:
	return _material.get_shader_parameter(name) if _material != null else null


func _process(delta: float) -> void:
	if _material == null:
		return
	_grain_time += delta
	if _grain_time >= 1.0 / GRAIN_FPS:
		_grain_time = fmod(_grain_time, 1.0 / GRAIN_FPS)
		_material.set_shader_parameter(&"grain_seed", float(Time.get_ticks_msec() % 1000))


func _write_param(name: StringName, value: Variant) -> void:
	if _cache.get(name) == value:
		return
	_cache[name] = value
	_material.set_shader_parameter(name, value)
