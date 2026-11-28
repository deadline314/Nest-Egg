class_name KeyLightData
extends RefCounted
## 區段的主光（BG-67）：一個決定畫面方向與顏色的光源。寫在關卡地圖 JSON 的頂層 "key_light"，
## 新增或調整不用改程式。設計見 design/22-living-scenes/DEPTH_AND_KEY_LIGHT.md。
##
## "key_light": {
##   "x": 16, "y": 2,               光源位置（格，可以在畫面外）
##   "color": [1.0, 0.7, 0.42],     主光顏色（0~1）
##   "energy": 0.9,                 實際照亮地面、牆與角色的那盞光的強度
##   "light_radius": 520,           那盞光照得到多遠（像素）
##   "halo_radius": 230,            遮得最少時光暈的半徑（像素）
##   "halo_alpha": 0.55,            光暈中心的亮度（0~1）
##   "front_wash": 0.08,            畫在角色前面的那層淡淡漫射（0~0.2；大部分光暈在角色後面）
##   "shafts": {"count": 5, "angle": 32, "length": 380, "width": 22, "spread": 150},
##                                  光柱：數量、方向（度，0 = 正下方，正值往右偏）、長度、寬度、起點散開的範圍
##   "occlusion": [0.15, 0.85],     被遮住程度的變化範圍（0 = 完全沒遮，1 = 全遮）
##   "period": 45                   遮住程度變化一個來回要幾秒（太快會像閃爍，下限 MIN_PERIOD）
## }

const MIN_PERIOD := 20.0
const MAX_FRONT_WASH := 0.2
const MAX_SHAFTS := 9
const SOURCES: Array[String] = ["sun", "moon", "lamp"]
## 每種光源各項的範圍 [下限, 上限]。燈：光暈幾十像素、光柱最多兩道、幾乎往正下方、短而窄。
const SOURCE_LIMITS := {
	"lamp": {"halo_radius": [16.0, 72.0], "halo_alpha": [0.0, 0.5], "front_wash": [0.0, 0.04], "shaft_count": [0.0, 2.0],
		"shaft_angle": [-12.0, 12.0], "shaft_length": [16.0, 160.0], "shaft_width": [2.0, 24.0], "shaft_spread": [0.0, 24.0]},
	"moon": {"halo_alpha": [0.0, 0.3], "front_wash": [0.0, 0.04], "shaft_count": [0.0, 3.0], "shaft_width": [2.0, 20.0], "energy": [0.0, 0.5]},
}
## 燈光主光錨在多遠以內的燈（格）。
const LAMP_REACH := 4.0

## 光從哪裡來（BG-79）：sun＝太陽（不限制）、moon＝月光（天空開闊的夜景，光柱收斂）、
## lamp＝看得到的燈（夜景；主光錨在地圖上最近的一盞燈，光暈與光柱都要和燈具相稱）。
var source := "sun"
var tile := Vector2.ZERO
var color := Color(1.0, 0.72, 0.45)
var energy := 0.9
var light_radius := 520.0
var halo_radius := 230.0
var halo_alpha := 0.55
var front_wash := 0.08
var shaft_count := 5
var shaft_angle := 32.0
var shaft_length := 380.0
var shaft_width := 22.0
var shaft_spread := 150.0
var occlusion_min := 0.15
var occlusion_max := 0.85
var period := 45.0


## 從地圖 JSON 讀出主光；沒有寫就回傳 null。資料壞掉時記錄是哪個區域哪一項，回傳 null（這個區域照常顯示，沒有主光）。
static func parse(raw: Variant, where: String) -> KeyLightData:
	if raw == null:
		return null
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("[KeyLight] %s 的 key_light 必須是物件，這個區域不加主光" % where)
		return null
	var source := raw as Dictionary
	var data := KeyLightData.new()
	var problems := PackedStringArray()
	data.tile = Vector2(_number(source, "x", NAN, problems), _number(source, "y", NAN, problems))
	data.color = _color(source.get("color", [data.color.r, data.color.g, data.color.b]), problems)
	data.energy = _number(source, "energy", data.energy, problems, 0.0, 3.0)
	data.light_radius = _number(source, "light_radius", data.light_radius, problems, 16.0, 4000.0)
	data.halo_radius = _number(source, "halo_radius", data.halo_radius, problems, 16.0, 2000.0)
	data.halo_alpha = _number(source, "halo_alpha", data.halo_alpha, problems, 0.0, 1.0)
	data.front_wash = _number(source, "front_wash", data.front_wash, problems, 0.0, MAX_FRONT_WASH)
	var shafts: Variant = source.get("shafts", {})
	if typeof(shafts) != TYPE_DICTIONARY:
		problems.append("shafts 必須是物件")
	else:
		data.shaft_count = int(_number(shafts as Dictionary, "count", data.shaft_count, problems, 0.0, MAX_SHAFTS))
		data.shaft_angle = _number(shafts as Dictionary, "angle", data.shaft_angle, problems, -80.0, 80.0)
		data.shaft_length = _number(shafts as Dictionary, "length", data.shaft_length, problems, 16.0, 3000.0)
		data.shaft_width = _number(shafts as Dictionary, "width", data.shaft_width, problems, 2.0, 400.0)
		data.shaft_spread = _number(shafts as Dictionary, "spread", data.shaft_spread, problems, 0.0, 2000.0)
	var occlusion: Variant = source.get("occlusion", [data.occlusion_min, data.occlusion_max])
	if typeof(occlusion) != TYPE_ARRAY or (occlusion as Array).size() != 2 or not _all_numbers(occlusion as Array):
		problems.append("occlusion 必須是 [最小, 最大] 兩個數字")
	else:
		data.occlusion_min = float(occlusion[0])
		data.occlusion_max = float(occlusion[1])
		if data.occlusion_min < 0.0 or data.occlusion_max > 1.0 or data.occlusion_min > data.occlusion_max:
			problems.append("occlusion 要在 0~1 之間且最小不大於最大（%s）" % [occlusion])
	data.period = _number(source, "period", data.period, problems, MIN_PERIOD, 600.0)
	data.source = str(source.get("source", "sun"))
	if data.source not in SOURCES:
		problems.append("source 要是 %s（%s）" % ["／".join(SOURCES), data.source])
	else:
		problems.append_array(data.source_problems())
	if not problems.is_empty():
		push_error("[KeyLight] %s 的 key_light 有問題，這個區域不加主光：%s" % [where, "；".join(problems)])
		return null
	return data


## 光源種類的限制（BG-79）：燈的光暈和燈具相稱、光柱只是燈下短而窄的錐形；月光的光柱數量、寬度、亮度收斂。
func source_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var limits: Dictionary = SOURCE_LIMITS.get(source, {})
	for key: String in limits:
		# 沒有光柱時，光柱的其他項目是預設值，不檢查。
		if key.begins_with("shaft_") and key != "shaft_count" and shaft_count == 0:
			continue
		var value: float = get(key)
		var limit: Array = limits[key]
		if value < float(limit[0]) or value > float(limit[1]):
			problems.append("%s 光的 %s 要在 %s~%s 之間（%s）" % [source, key, limit[0], limit[1], value])
	return problems


## 主光在 t 秒時被遮住的程度：兩個不同週期的緩慢起伏疊在一起，不規律但永遠緩慢（每秒變化量有上限，見 max_rate）。
func occlusion_at(t: float) -> float:
	var phase := TAU * t / period
	var wave := 0.65 * sin(phase) + 0.35 * sin(phase * 0.43 + 1.7)
	return lerpf(occlusion_min, occlusion_max, 0.5 + 0.5 * wave)


## 遮住程度每秒最多變化多少（給「不會被當成閃爍」的檢查用）。
func max_rate() -> float:
	return (occlusion_max - occlusion_min) * 0.5 * (0.65 + 0.35 * 0.43) * TAU / period


func middle_occlusion() -> float:
	return (occlusion_min + occlusion_max) * 0.5


static func _number(source: Dictionary, key: String, fallback: float, problems: PackedStringArray, low := -INF, high := INF) -> float:
	if not source.has(key):
		if is_nan(fallback):
			problems.append("缺少 %s" % key)
		return fallback
	var value: Variant = source[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		problems.append("%s 必須是數字（%s）" % [key, value])
		return fallback
	if float(value) < low or float(value) > high:
		problems.append("%s 要在 %s~%s 之間（%s）" % [key, low, high, value])
		return fallback
	return float(value)


static func _color(value: Variant, problems: PackedStringArray) -> Color:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3 or not _all_numbers(value as Array):
		problems.append("color 必須是 [r, g, b] 三個 0~1 的數字")
		return Color.WHITE
	var color := Color(float(value[0]), float(value[1]), float(value[2]))
	if color.r < 0.0 or color.g < 0.0 or color.b < 0.0 or color.r > 1.0 or color.g > 1.0 or color.b > 1.0:
		problems.append("color 的每個值要在 0~1 之間（%s）" % [value])
	return color


static func _all_numbers(values: Array) -> bool:
	for value: Variant in values:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return true
