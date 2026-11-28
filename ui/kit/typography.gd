class_name Typography
extends RefCounted
## 全遊戲共用的字體階層（NE-422）：每個角色（時刻標題、畫面標題、段落標題、內文、說明小字、外文標籤、數字）的字體、字級與字距。
## 內容在 data/ui/typography.json；檔案遺失或欄位錯誤時記錄是哪個檔案、哪個角色、哪個欄位，並用內建預設。
## 用法：UiKit.styled(text, &"title") 建立標籤，或 UiKit.apply_role(control, &"title") 套到既有控制項；字級會跟著文字大小設定與字體樣式更新。
## 規則與每個角色用在哪裡見 design/22-living-scenes/TYPOGRAPHY.md。

const PATH := "res://data/ui/typography.json"
## 字體來源：title＝標題明體、body＝內文黑體（依語言）、label＝外文標籤、numeral＝數字。
const FACES: Array[StringName] = [&"title", &"body", &"label", &"numeral"]
## 文字對比標準（WCAG AA 小字）：說明小字、外文標籤這類次要文字至少 4.5:1；主要文字要更高一階。
const MIN_CONTRAST := 4.5
const MIN_SIZE := 8
const MAX_SIZE := 160
const DEFAULTS := {
	&"hero": {"face": &"title", "size": 104, "spacing": 0},
	&"display": {"face": &"title", "size": 33, "spacing": 0},
	&"title": {"face": &"title", "size": 22, "spacing": 0},
	&"kicker": {"face": &"title", "size": 14, "spacing": 8},
	&"heading": {"face": &"body", "size": 14, "spacing": 0},
	&"body": {"face": &"body", "size": 11, "spacing": 0},
	&"caption": {"face": &"body", "size": 9, "spacing": 0},
	&"label": {"face": &"label", "size": 9, "spacing": 2},
	&"numeral": {"face": &"numeral", "size": 11, "spacing": 0},
}

static var _roles: Dictionary = {}
static var _spaced: Dictionary[StringName, FontVariation] = {}
static var issues := PackedStringArray()


## 角色表（第一次用到時讀檔）。
static func roles() -> Dictionary:
	if _roles.is_empty():
		load_table()
	return _roles


static func has_role(role: StringName) -> bool:
	return roles().has(role)


## 角色的設計字級（640×360 畫面像素，還沒乘上文字大小設定）；不認得的角色用內文。
static func base_size(role: StringName) -> int:
	return int(roles().get(role, roles()[&"body"])["size"])


static func face(role: StringName) -> StringName:
	return roles().get(role, roles()[&"body"])["face"]


static func spacing(role: StringName) -> int:
	return int(roles().get(role, roles()[&"body"])["spacing"])


## 角色的字型：字體樣式或語言切換時，UiKit 換掉底層字型，這裡回傳的物件不用重建。
static func font(role: StringName) -> Font:
	var base := _face_font(face(role))
	var gap := spacing(role)
	if gap == 0:
		return base
	var variant: FontVariation = _spaced.get(role)
	if variant == null:
		variant = FontVariation.new()
		_spaced[role] = variant
	variant.base_font = base
	variant.spacing_glyph = gap
	return variant


static func _face_font(name: StringName) -> Font:
	match name:
		&"title":
			return UiKit.special_font(&"title")
		&"label":
			return UiKit.special_font(&"display")
		&"numeral":
			return UiKit.special_font(&"readout")
	return UiKit.font()


## 讀取角色表；回傳是否完全沒有問題。錯誤記錄位置後退回該角色的內建預設。
static func load_table(path := PATH) -> bool:
	var parsed := parse(FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "", path)
	_roles = parsed["roles"]
	issues = parsed["issues"]
	for issue in issues:
		push_error("[Typography] %s" % issue)
	return issues.is_empty()


## 把 JSON 文字轉成角色表：缺的角色、錯的欄位都退回內建預設，並記錄「檔案 roles.角色.欄位：原因」。
static func parse(text: String, path := PATH) -> Dictionary:
	var result := {}
	for role: StringName in DEFAULTS:
		result[role] = (DEFAULTS[role] as Dictionary).duplicate()
	var found := PackedStringArray()
	if text.is_empty():
		found.append("%s：找不到或是空檔，全部使用內建預設" % path)
		return {"roles": result, "issues": found}
	# 用 JSON 物件解析：壞掉的檔案只回傳錯誤碼，由這裡記錄位置，不讓引擎另外印一次。
	var json := JSON.new()
	var data: Variant = json.data if json.parse(text) == OK else null
	if not data is Dictionary or not (data as Dictionary).get("roles") is Dictionary:
		found.append("%s：不是 {\"roles\": {...}} 的格式，全部使用內建預設" % path)
		return {"roles": result, "issues": found}
	var raw: Dictionary = data["roles"]
	for key: Variant in raw:
		var role := StringName(str(key))
		var entry: Variant = raw[key]
		var where := "%s roles.%s" % [path, role]
		if not entry is Dictionary:
			found.append("%s：不是物件，使用內建預設" % where)
			continue
		var spec: Dictionary = result.get(role, {"face": &"body", "size": 11, "spacing": 0}).duplicate()
		var face_name := StringName(str((entry as Dictionary).get("face", spec["face"])))
		if face_name in FACES:
			spec["face"] = face_name
		else:
			found.append("%s.face：「%s」不是 %s 之一" % [where, face_name, FACES])
		var size: Variant = (entry as Dictionary).get("size", spec["size"])
		if typeof(size) in [TYPE_INT, TYPE_FLOAT] and float(size) >= MIN_SIZE and float(size) <= MAX_SIZE:
			spec["size"] = int(size)
		else:
			found.append("%s.size：%s 不在 %d～%d" % [where, size, MIN_SIZE, MAX_SIZE])
		var gap: Variant = (entry as Dictionary).get("spacing", spec["spacing"])
		if typeof(gap) in [TYPE_INT, TYPE_FLOAT] and float(gap) >= 0.0 and float(gap) <= 32.0:
			spec["spacing"] = int(gap)
		else:
			found.append("%s.spacing：%s 不在 0～32" % [where, gap])
		result[role] = spec
	return {"roles": result, "issues": found}


## 兩個顏色的對比（WCAG 相對亮度，1～21）。
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## 半透明顏色蓋在背景上的結果（不透明）。
static func blend(top: Color, alpha: float, under: Color) -> Color:
	return Color(lerpf(under.r, top.r, alpha), lerpf(under.g, top.g, alpha), lerpf(under.b, top.b, alpha))


static func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
