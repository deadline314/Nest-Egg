class_name ColorScript
extends RefCounted
## 色彩腳本（BG-74）：每個區域一個主色、主光色與暗部色（設計見 design/22-living-scenes/COLOR_SCRIPT.md），
## 進入區域時套到該區域每個光影區段的複本上（原本的光影設定檔是多個區域共用的，不改它）：
## - 環境光：色相換成主色的色相、飽和度往主色靠一半，亮度（感知亮度）維持原本的值——暗場可讀性不變。
## - 角色邊緣光：直接用主光色（強度維持原本的）。
## - 暗部色：色相換成暗部色的色相，偏色的幅度與整體亮度維持原本的值。
## - 背景（天空與遠景）的染色：和暗部色一樣，偏的方向換成主色的色相（天空佔畫面最大，不跟著換整章看起來還是同一個顏色）。
## - 霧：色相換成主色的色相、亮度維持原本的值。
## 燈具與霓虹維持原本的（它們是點綴色，不在腳本裡）。
## 資料：DATA_PATH，{"areas": {區域 id: {"main": "#rrggbb", "key": "#rrggbb", "shadow": "#rrggbb", "background": 0~1（選填）}}}。
## background 是天空與遠景往主色偏的幅度（預設 BACKGROUND_SPREAD）；遠景剛好在角色身後、偏色會吃掉對比的區域調小。
## 驗收用的色相範圍（BG-75）："chapters": {章 id: {"hue": [下限, 上限]}}（度，可以跨過 0，例如 [340, 50]）：那一章各區截圖的
## 平均色相要落在這裡；區域自己寫了 "hue" 的（例如當舖）不算進章節平均，單獨檢查。
## 資料寫錯時記錄是哪個區域哪一項，那個區域維持原本的光影；沒寫到的區域也維持原本的。

const DATA_PATH := "res://data/environment/color_script.json"
const KEYS: Array[String] = ["main", "key", "shadow"]
## 環境光的飽和度往主色靠多少。
const MAIN_SATURATION_MIX := 0.5
## 背景染色至少偏多少（原本幾乎不偏色的背景也要帶出這一區的主色）。
const BACKGROUND_SPREAD := 0.45

static var _areas: Dictionary = {}
static var _chapters: Dictionary = {}
static var _loaded := false


## 區域的色彩腳本（main、key、shadow 三個 Color）；沒有或資料壞掉時回傳空字典。
static func entry_for(area_id: StringName) -> Dictionary:
	_load()
	return _areas.get(String(area_id), {})


## 章節的色相範圍（Vector2(下限, 上限)，度）；沒寫時回傳 Vector2(-1, -1)。
static func chapter_hue(chapter: String) -> Vector2:
	_load()
	return _chapters.get(chapter, Vector2(-1, -1))


## 區域自己的色相範圍；沒寫時回傳 Vector2(-1, -1)。
static func area_hue(area_id: StringName) -> Vector2:
	return entry_for(area_id).get("hue", Vector2(-1, -1))


## 色相 hue（度）在不在範圍裡（範圍可以跨過 0）。
static func hue_in(hue: float, span: Vector2) -> bool:
	hue = fposmod(hue, 360.0)
	return hue >= span.x and hue <= span.y if span.x <= span.y else hue >= span.x or hue <= span.y


## 兩個色相差幾度（0~180）。
static func hue_distance(a: float, b: float) -> float:
	var d := fposmod(a - b, 360.0)
	return minf(d, 360.0 - d)


static func area_ids() -> PackedStringArray:
	_load()
	return PackedStringArray(_areas.keys())


## 回傳套上色彩腳本的區段複本；沒有腳本時原樣回傳。
static func apply_zones(area_id: StringName, zones: Array[LightingZone]) -> Array[LightingZone]:
	var entry := entry_for(area_id)
	if entry.is_empty():
		return zones
	var result: Array[LightingZone] = []
	for zone in zones:
		if zone == null or zone.profile == null:
			result.append(zone)
			continue
		var copy := zone.duplicate() as LightingZone
		copy.profile = zone.profile.duplicate() as LightingProfile
		apply(copy.profile, entry)
		result.append(copy)
	return result


## 把一份腳本套到光影設定上（就地修改；呼叫端要先複製）。
static func apply(profile: LightingProfile, entry: Dictionary) -> void:
	var main: Color = entry["main"]
	var ambient := profile.ambient_color
	var tinted := Color.from_hsv(main.h, lerpf(ambient.s, main.s, MAIN_SATURATION_MIX), maxf(ambient.v, 0.001), ambient.a)
	profile.ambient_color = match_luminance(tinted, ambient.get_luminance())
	profile.rim_color = Color(entry["key"], profile.rim_color.a)
	profile.shadow_tint = _retint(profile.shadow_tint, entry["shadow"])
	profile.background_tint = _retint(profile.background_tint, main, float(entry.get("background", BACKGROUND_SPREAD)))
	var fog := profile.fog_color
	profile.fog_color = match_luminance(Color.from_hsv(main.h, lerpf(fog.s, main.s, MAIN_SATURATION_MIX), maxf(fog.v, 0.001), fog.a), fog.get_luminance())


## 暗部色是乘在畫面上的倍率（約 0.85~1.15）：保留它偏色的幅度與整體亮度，只把偏的方向換成腳本的色相。
static func _retint(tint: Color, shadow: Color, min_spread := 0.0) -> Color:
	var level := tint.get_luminance()
	var spread := maxf(maxf(maxf(tint.r, tint.g), tint.b) - minf(minf(tint.r, tint.g), tint.b), min_spread)
	var direction := Color.from_hsv(shadow.h, 1.0, 1.0)
	var mean := (direction.r + direction.g + direction.b) / 3.0
	var result := Color(level + (direction.r - mean) * spread, level + (direction.g - mean) * spread, level + (direction.b - mean) * spread, tint.a)
	return match_luminance(result, level)


## 把顏色等比縮放到指定的感知亮度（不夾到 1：暗部色的倍率可以大於 1）。
static func match_luminance(color: Color, luminance: float) -> Color:
	var current := color.get_luminance()
	if current <= 0.00001:
		return Color(luminance, luminance, luminance, color.a)
	var ratio := luminance / current
	return Color(color.r * ratio, color.g * ratio, color.b * ratio, color.a)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_areas.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_error("[ColorScript] 找不到色彩腳本 %s，所有區域維持原本的光影" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("areas")) != TYPE_DICTIONARY:
		push_error("[ColorScript] %s 必須是 {\"areas\": {...}}，所有區域維持原本的光影" % DATA_PATH)
		return
	var areas := (parsed as Dictionary)["areas"] as Dictionary
	for area: Variant in areas:
		var raw: Variant = areas[area]
		var entry := {}
		var problems := PackedStringArray()
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("必須是物件")
		else:
			for key in KEYS:
				var value: Variant = (raw as Dictionary).get(key)
				if typeof(value) != TYPE_STRING or not Color.html_is_valid(str(value)):
					problems.append("%s 要是 #rrggbb（%s）" % [key, value])
				else:
					entry[key] = Color.html(str(value))
			var span := _hue_span((raw as Dictionary).get("hue"))
			if span.x == -2.0:
				problems.append("hue 要是 [0~360, 0~360]")
			elif span.x >= 0.0:
				entry["hue"] = span
			var background: Variant = (raw as Dictionary).get("background", BACKGROUND_SPREAD)
			if typeof(background) not in [TYPE_INT, TYPE_FLOAT] or float(background) < 0.0 or float(background) > 1.0:
				problems.append("background 要是 0~1 的數字（%s）" % background)
			else:
				entry["background"] = float(background)
		if not problems.is_empty():
			push_error("[ColorScript] %s 的區域 %s 有問題，維持原本的光影：%s" % [DATA_PATH, area, "；".join(problems)])
			continue
		_areas[str(area)] = entry
	_chapters.clear()
	var chapters: Variant = (parsed as Dictionary).get("chapters", {})
	if typeof(chapters) == TYPE_DICTIONARY:
		for chapter: Variant in chapters:
			var raw_chapter: Variant = (chapters as Dictionary)[chapter]
			var span := _hue_span((raw_chapter as Dictionary).get("hue") if typeof(raw_chapter) == TYPE_DICTIONARY else null)
			if span.x < 0.0:
				push_error("[ColorScript] %s 的章節 %s 的 hue 要是 [0~360, 0~360]" % [DATA_PATH, chapter])
				continue
			_chapters[str(chapter)] = span
	else:
		push_error("[ColorScript] %s 的 chapters 必須是物件" % DATA_PATH)


## 色相範圍：null 回傳 (-1, -1)（沒寫）；寫錯回傳 (-2, -2)。
static func _hue_span(raw: Variant) -> Vector2:
	if raw == null:
		return Vector2(-1, -1)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2 or typeof(raw[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw[1]) not in [TYPE_INT, TYPE_FLOAT] 			or float(raw[0]) < 0.0 or float(raw[0]) > 360.0 or float(raw[1]) < 0.0 or float(raw[1]) > 360.0:
		return Vector2(-2, -2)
	return Vector2(float(raw[0]), float(raw[1]))


## 測試用：重新讀檔。
static func reload() -> void:
	_loaded = false
	_load()
