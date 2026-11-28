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
## "neighbor_gap": 度：相鄰兩章（ch1 與 ch2、ch2 與 ch3…）的平均色相至少要差這麼多。
## 時段（BG-79）：區域寫 "time"（night／day／dawn／dusk／undecided，照故事線的時段表），可以再寫
## "time_after": {"flag": 劇情旗標, "time": 時段}（同一區後來的另一場，例如屋頂早上與夜裡）；進入區域時依旗標選一個。
## "outdoor_zones": "all" 或光影設定 id 的陣列：時段只改這些區段（室內的暖燈區段不動，例如當舖店裡）。
## 時段的差異寫在頂層 "times"：{時段: {"ambient": 環境光至少多亮, "sky": 天空染色至少多亮, "fog": 霧至少多亮,
## "tint": "#rrggbb", "tint_mix": 0~1（環境光往這個色相靠）, "sky_tint"、"sky_mix"（天空往這個顏色靠）, "saturation": 倍率, "contrast": 上限, "lamp_power": 上限,
## "neon": 倍率, "rim": 倍率, "lightning": 倍率}}。夜晚是基底、不改；亮度只往上調（白天的室外不會比原本暗）。
## 資料寫錯時記錄是哪個區域哪一項，那個區域維持原本的光影；沒寫到的區域也維持原本的。

const DATA_PATH := "res://data/environment/color_script.json"
const KEYS: Array[String] = ["main", "key", "shadow"]
## 環境光的飽和度往主色靠多少。
const MAIN_SATURATION_MIX := 0.5
## 背景染色至少偏多少（原本幾乎不偏色的背景也要帶出這一區的主色）。
const BACKGROUND_SPREAD := 0.45

static var _areas: Dictionary = {}
static var _chapters: Dictionary = {}
static var _times: Dictionary = {}
const TIMES: Array[String] = ["night", "day", "dawn", "dusk", "undecided"]
const TIME_KEYS: Array[String] = ["ambient", "sky", "sky_mix", "fog", "tint_mix", "grade_neutral", "saturation", "contrast", "lamp_power", "neon", "rim", "lightning"]
## 相鄰兩章的平均色相至少要差幾度（BG-77）；資料沒寫時是 0（不檢查）。
static var neighbor_gap := 0.0
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
	var time := time_for(area_id)
	var result: Array[LightingZone] = []
	for zone in zones:
		if zone == null or zone.profile == null:
			result.append(zone)
			continue
		var copy := zone.duplicate() as LightingZone
		copy.profile = zone.profile.duplicate() as LightingProfile
		apply(copy.profile, entry)
		if _times.has(time) and _outdoor(entry, zone.profile.id):
			apply_time(copy.profile, _times[time])
		result.append(copy)
	return result


## 這一區現在的時段：寫了 time_after 而且旗標已經成立時用後來的那個。
static func time_for(area_id: StringName) -> String:
	var entry := entry_for(area_id)
	var after: Dictionary = entry.get("time_after", {})
	if not after.is_empty() and GameState.has_flag(StringName(after["flag"])):
		return after["time"]
	return entry.get("time", "undecided")


## 所有寫過的時段（預設的與 time_after 的），檢查用。
static func times_of(area_id: StringName) -> PackedStringArray:
	var entry := entry_for(area_id)
	var result := PackedStringArray([entry.get("time", "undecided")])
	var after: Dictionary = entry.get("time_after", {})
	if not after.is_empty():
		result.append(after["time"])
	return result


## 時段的差異設定；沒有時回傳空字典。
static func time_preset(time: String) -> Dictionary:
	_load()
	return _times.get(time, {})


## 這個光影設定的區段在這一區算不算室外（時段只改室外的區段）。
static func is_outdoor(area_id: StringName, profile_id: StringName) -> bool:
	return _outdoor(entry_for(area_id), profile_id)


static func _outdoor(entry: Dictionary, profile_id: StringName) -> bool:
	var zones: Variant = entry.get("outdoor_zones", [])
	return (typeof(zones) == TYPE_STRING and zones == "all") or (typeof(zones) == TYPE_ARRAY and (zones as Array).has(String(profile_id)))


## 把時段的差異套到光影設定上（就地修改）。亮度只往上調，色相往 tint 靠但亮度不變。
static func apply_time(profile: LightingProfile, preset: Dictionary) -> void:
	var ambient := profile.ambient_color
	if preset.has("tint"):
		var tint: Color = preset["tint"]
		ambient = match_luminance(ambient.lerp(match_luminance(tint, ambient.get_luminance()), float(preset.get("tint_mix", 0.0))), ambient.get_luminance())
	if preset.has("ambient") and ambient.get_luminance() < float(preset["ambient"]):
		ambient = match_luminance(ambient, float(preset["ambient"]))
	profile.ambient_color = ambient
	if preset.has("sky_tint"):
		# 陰天、清晨的天空往灰靠（只拉亮會把原本的色相也放大，變成很艷的藍或粉紅）。
		var level := profile.background_tint.get_luminance()
		profile.background_tint = match_luminance(profile.background_tint.lerp(match_luminance(preset["sky_tint"], level), float(preset.get("sky_mix", 0.0))), level)
	if preset.has("sky") and profile.background_tint.get_luminance() < float(preset["sky"]):
		profile.background_tint = match_luminance(profile.background_tint, float(preset["sky"]))
	if preset.has("sky_tint"):
		# 霧跟天空同一個顏色（暖色的霧蓋在藍天上會變成紫）。
		var fog_level := profile.fog_color.get_luminance()
		profile.fog_color = match_luminance(profile.fog_color.lerp(match_luminance(preset["sky_tint"], fog_level), float(preset.get("sky_mix", 0.0))), fog_level)
	if preset.has("fog") and profile.fog_color.get_luminance() < float(preset["fog"]):
		profile.fog_color = match_luminance(profile.fog_color, float(preset["fog"]))
	# 陰天的散射光：暗部與亮部的色調往中性靠（grade_neutral 0~1）。
	var neutral := float(preset.get("grade_neutral", 0.0))
	profile.shadow_tint = profile.shadow_tint.lerp(Color(1, 1, 1, profile.shadow_tint.a), neutral)
	profile.highlight_tint = profile.highlight_tint.lerp(Color(1, 1, 1, profile.highlight_tint.a), neutral)
	profile.saturation = minf(profile.saturation * float(preset.get("saturation", 1.0)), 2.0)
	profile.contrast = minf(profile.contrast, float(preset.get("contrast", profile.contrast)))
	profile.lamp_power = minf(profile.lamp_power, float(preset.get("lamp_power", 1.0)))
	profile.neon_energy *= float(preset.get("neon", 1.0))
	profile.rim_energy *= float(preset.get("rim", 1.0))
	profile.lightning_rate *= float(preset.get("lightning", 1.0))


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
			var time: Variant = (raw as Dictionary).get("time", "undecided")
			if typeof(time) != TYPE_STRING or str(time) not in TIMES:
				problems.append("time 要是 %s（%s）" % ["／".join(TIMES), time])
			else:
				entry["time"] = str(time)
			var after: Variant = (raw as Dictionary).get("time_after")
			if after != null:
				if typeof(after) != TYPE_DICTIONARY or typeof((after as Dictionary).get("flag")) != TYPE_STRING or str((after as Dictionary).get("time", "")) not in TIMES:
					problems.append("time_after 要是 {flag: 旗標, time: 時段}")
				else:
					entry["time_after"] = {"flag": str(after["flag"]), "time": str(after["time"])}
			var outdoor: Variant = (raw as Dictionary).get("outdoor_zones", [])
			if not ((typeof(outdoor) == TYPE_STRING and outdoor == "all") or typeof(outdoor) == TYPE_ARRAY):
				problems.append("outdoor_zones 要是 all 或光影設定 id 的陣列")
			else:
				entry["outdoor_zones"] = outdoor
			var background: Variant = (raw as Dictionary).get("background", BACKGROUND_SPREAD)
			if typeof(background) not in [TYPE_INT, TYPE_FLOAT] or float(background) < 0.0 or float(background) > 1.0:
				problems.append("background 要是 0~1 的數字（%s）" % background)
			else:
				entry["background"] = float(background)
		if not problems.is_empty():
			push_error("[ColorScript] %s 的區域 %s 有問題，維持原本的光影：%s" % [DATA_PATH, area, "；".join(problems)])
			continue
		_areas[str(area)] = entry
	neighbor_gap = 0.0
	var gap: Variant = (parsed as Dictionary).get("neighbor_gap", 0)
	if typeof(gap) in [TYPE_INT, TYPE_FLOAT] and float(gap) >= 0.0 and float(gap) <= 180.0:
		neighbor_gap = float(gap)
	else:
		push_error("[ColorScript] %s 的 neighbor_gap 要是 0~180 的數字（%s）" % [DATA_PATH, gap])
	_times.clear()
	var times: Variant = (parsed as Dictionary).get("times", {})
	if typeof(times) == TYPE_DICTIONARY:
		for time: Variant in times:
			var raw_time: Variant = (times as Dictionary)[time]
			if str(time) not in TIMES or typeof(raw_time) != TYPE_DICTIONARY:
				push_error("[ColorScript] %s 的 times.%s 不是已知的時段或不是物件，略過" % [DATA_PATH, time])
				continue
			var preset := {}
			for key: Variant in raw_time:
				var value: Variant = (raw_time as Dictionary)[key]
				if key in ["tint", "sky_tint"] and typeof(value) == TYPE_STRING and Color.html_is_valid(str(value)):
					preset[str(key)] = Color.html(str(value))
				elif str(key) in TIME_KEYS and typeof(value) in [TYPE_INT, TYPE_FLOAT] and float(value) >= 0.0 and float(value) <= 3.0:
					preset[str(key)] = float(value)
				else:
					push_error("[ColorScript] %s 的 times.%s.%s 不認得或數值不對（%s），略過這一項" % [DATA_PATH, time, key, value])
			_times[str(time)] = preset
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
