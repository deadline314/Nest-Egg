class_name SoundLabLayout
extends RefCounted
## 實驗室各分隔的比例（0 到 1，前一格佔的份）存在使用者資料夾的小設定檔。
## 讀不到或內容損毀（不是數字、超出範圍）就退回預設比例並記錄具體位置的錯誤，不會讓實驗室打不開。

const DEFAULT_PATH := "user://sound_lab_layout.cfg"
const SECTION := "split_ratios"
## 比例的合理範圍：避免存檔被改壞後某一格縮成看不見。
const MIN_RATIO := 0.1
const MAX_RATIO := 0.9

var path: String
var _ratios := {}
var _dirty := false


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	_load()


## 這個分隔的比例；沒存過或存的值不合法時回傳預設值。
func ratio(key: String, fallback: float) -> float:
	var value: Variant = _ratios.get(key)
	return float(value) if _is_valid(value) else fallback


## 超出範圍的值夾回合理範圍；不是有限數字就忽略。
func set_ratio(key: String, value: float) -> void:
	if not is_finite(value):
		return
	_ratios[key] = clampf(value, MIN_RATIO, MAX_RATIO)
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## 有變動才寫檔；寫不進去只記錄錯誤。
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var file := ConfigFile.new()
	for key: String in _ratios:
		file.set_value(SECTION, key, _ratios[key])
	var err := file.save(path)
	if err != OK:
		push_error("音效實驗室：版面比例寫不進 %s（%s）" % [path, error_string(err)])


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var file := ConfigFile.new()
	var err := file.load(path)
	if err != OK:
		push_error("音效實驗室：版面比例檔 %s 讀不了（%s），改用預設比例" % [path, error_string(err)])
		return
	for key in file.get_section_keys(SECTION) if file.has_section(SECTION) else PackedStringArray():
		var value: Variant = file.get_value(SECTION, key)
		if _is_valid(value):
			_ratios[key] = float(value)
		else:
			push_error("音效實驗室：版面比例檔 %s 的 [%s] %s 不是 %.1f 到 %.1f 的數字，改用預設比例" % [path, SECTION, key, MIN_RATIO, MAX_RATIO])


static func _is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number := float(value)
	return is_finite(number) and number >= MIN_RATIO and number <= MAX_RATIO
