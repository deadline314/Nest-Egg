class_name CameraTuning
extends RefCounted
## 關卡鏡頭的構圖數值（NE-256）：倍率與跟著倍率調的前瞻、瞄準偏移、垂直偏移、死區與下落預視，資料在 data/feel/camera.json。
## 讀檔失敗或某一項不合理時記錄錯誤（指出檔案與欄位）並用這裡的預設值，鏡頭照常運作。
## 之後要依場景或情境（探索、戰鬥、對話）換一組數值時，在資料檔加一組設定，用 profile(名稱) 讀出來即可。

const PATH := "res://data/feel/camera.json"
const DEFAULT_PROFILE := &"level"

## 欄位 → [預設值, 下限, 上限]。預設值就是資料檔目前的數值；資料損毀時鏡頭仍是調好的樣子。
const FIELDS := {
	"zoom": [1.92, 0.5, 4.0],
	"look_ahead": [106.0, 0.0, 200.0],
	"look_ahead_speed": [2.2, 0.1, 20.0],
	"pan_max_speed": [300.0, 60.0, 4000.0],
	"aim_look": [30.0, 0.0, 120.0],
	"aim_look_speed": [5.0, 0.1, 30.0],
	"vertical_offset": [-40.0, -120.0, 120.0],
	"deadzone_up": [26.0, 0.0, 200.0],
	"deadzone_down": [16.0, 0.0, 200.0],
	"fall_look_from": [200.0, 0.0, 2000.0],
	"fall_look_gain": [0.1, 0.0, 2.0],
	"fall_look_max": [44.0, 0.0, 200.0],
	"rear_watch_range": [150.0, 0.0, 600.0],
	"rear_margin": [28.0, 0.0, 200.0],
	"above_watch_range": [140.0, 0.0, 400.0],
	"above_max_lift": [32.0, 0.0, 120.0],
	"above_margin": [20.0, 0.0, 80.0],
	"fall_look_speed": [4.0, 0.1, 30.0],
	"smoothing_speed": [7.0, 0.5, 60.0],
	"shake_reference_zoom": [1.5, 0.5, 4.0],
	"aim_look_down": [60.0, 0.0, 120.0],
	"ledge_peek_max": [66.0, 0.0, 120.0],
	"ledge_peek_delay": [0.35, 0.0, 3.0],
	"down_look_max": [66.0, 0.0, 160.0],
}

static var _profiles: Dictionary = {}
static var _loaded := false

var zoom: float
var look_ahead: float
var look_ahead_speed: float
## 鏡頭跟隨目標的水平速度上限（主角移動＋前瞻與瞄準偏移的變化，世界像素／秒）；只約束偏移的變化，不會讓主角跑出畫面。
var pan_max_speed: float
var aim_look: float
var aim_look_speed: float
var vertical_offset: float
var deadzone_up: float
var deadzone_down: float
var fall_look_from: float
var fall_look_gain: float
var fall_look_max: float
var fall_look_speed: float
var smoothing_speed: float
## 背後這段距離內有交戰中的敵人時，縮小前瞻讓牠留在畫面裡（邊距 rear_margin）；0＝關閉。
var rear_watch_range: float
var rear_margin: float
## 畫面左右範圍內、比主角腳底高 above_watch_range 以內的敵人，頭頂加 above_margin 要留在畫面裡；鏡頭最多為此上抬 above_max_lift（0＝關閉）。
var above_watch_range: float
var above_max_lift: float
var above_margin: float
## 震動與後座的幅度是在這個倍率下調的；倍率改了以後換算，讓畫面上的晃動幅度不變。
var shake_reference_zoom: float
## 往下看（NE-256：拉近後腳下只看得到約 3 格，落差的落點在畫面外）：
## aim_look_down＝準星朝正下方時鏡頭往下多看的世界像素（斜下方依比例）；
## ledge_peek_max／ledge_peek_delay＝站在落差邊緣、面向落差停住 delay 秒後，鏡頭自動往下看到落點，最多 max（0＝關閉）；
## down_look_max＝瞄準、邊緣與下落三種往下看加起來的上限，主角的頭才不會被推出畫面上緣。
var aim_look_down: float
var ledge_peek_max: float
var ledge_peek_delay: float
var down_look_max: float


## 讀出一組鏡頭設定；找不到就用 level 那組，連 level 也沒有就用程式預設值。
static func profile(id: StringName = DEFAULT_PROFILE) -> CameraTuning:
	_ensure_loaded()
	if _profiles.has(id):
		return _profiles[id]
	if id != DEFAULT_PROFILE:
		push_error("[CameraTuning] %s 沒有鏡頭設定「%s」，改用 %s" % [PATH, id, DEFAULT_PROFILE])
	return _profiles.get(DEFAULT_PROFILE, from_dictionary({}, "defaults")) as CameraTuning


## 依字典建立設定：缺的欄位用預設值；型別不對或超出範圍時記錄錯誤（指出位置與欄位）並用預設值。
static func from_dictionary(values: Dictionary, where: String) -> CameraTuning:
	var errors: Array[String] = []
	var tuning := parse(values, where, errors)
	for message in errors:
		push_error("[CameraTuning] " + message)
	return tuning


## 同 from_dictionary，但把問題收進 errors 而不是直接記錄（資料檢查與測試用）。
static func parse(values: Dictionary, where: String, errors: Array[String]) -> CameraTuning:
	var tuning := CameraTuning.new()
	for key: String in FIELDS:
		var spec: Array = FIELDS[key]
		var value: float = spec[0]
		if values.has(key):
			var raw: Variant = values[key]
			if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
				errors.append("%s 的 %s 不是數字（%s），改用預設值 %s" % [where, key, raw, spec[0]])
			elif float(raw) < float(spec[1]) or float(raw) > float(spec[2]):
				errors.append("%s 的 %s = %s 超出合理範圍 %s～%s，改用預設值 %s" % [where, key, raw, spec[1], spec[2], spec[0]])
			else:
				value = float(raw)
		tuning.set(key, value)
	for key: String in values:
		if not FIELDS.has(key):
			errors.append("%s 有不認得的欄位 %s（拼錯了嗎？）" % [where, key])
	return tuning


## 資料檢查：回傳錯誤訊息清單（測試與資料驗證用）。
static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var root := _read_root()
	if root.is_empty():
		errors.append("%s 讀不到或不是字典" % PATH)
		return errors
	var profiles: Variant = root.get("profiles")
	if typeof(profiles) != TYPE_DICTIONARY or not (profiles as Dictionary).has(String(DEFAULT_PROFILE)):
		errors.append("%s 需要 profiles.%s" % [PATH, DEFAULT_PROFILE])
		return errors
	for id: String in profiles:
		var values: Variant = profiles[id]
		if typeof(values) != TYPE_DICTIONARY:
			errors.append("%s 的 profiles.%s 不是字典" % [PATH, id])
			continue
		var found: Array[String] = []
		parse(values, "%s 的 profiles.%s" % [PATH, id], found)
		errors.append_array(PackedStringArray(found))
	return errors


## 重新讀檔（測試、開發時改了資料檔用）。
static func reload_data() -> void:
	_loaded = false
	_profiles.clear()
	_ensure_loaded()


## 複製一份並換掉倍率（量測工具比較修前修後用）。
func with_zoom(value: float) -> CameraTuning:
	var copy := CameraTuning.new()
	for key: String in FIELDS:
		copy.set(key, get(key))
	copy.zoom = value
	return copy


## 鏡頭停穩、朝面向瞄準時，前方看得到幾個世界像素（設計畫布寬度一半 ÷ 倍率 ＋ 前瞻 ＋ 瞄準偏移）。
func front_reach(canvas_width: float) -> float:
	return canvas_width * 0.5 / zoom + look_ahead + aim_look


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var root := _read_root()
	if root.is_empty():
		push_error("[CameraTuning] 無法讀取鏡頭設定 %s，改用預設值" % PATH)
		return
	var profiles: Variant = root.get("profiles")
	if typeof(profiles) != TYPE_DICTIONARY:
		push_error("[CameraTuning] %s 缺少 profiles 字典，改用預設值" % PATH)
		return
	for id: String in profiles:
		var values: Variant = profiles[id]
		if typeof(values) != TYPE_DICTIONARY:
			push_error("[CameraTuning] %s 的 profiles.%s 不是字典，略過" % [PATH, id])
			continue
		_profiles[StringName(id)] = from_dictionary(values, "%s 的 profiles.%s" % [PATH, id])


static func _read_root() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
