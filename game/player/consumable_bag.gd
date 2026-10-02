class_name ConsumableBag
extends RefCounted
## 玩家攜帶的消耗品數量。消耗品種類從 data/consumables/ 讀取（新增種類不需改程式）。
## 只管數量；效果由 Player.use_consumable() 套用。可序列化存進檢查點。

signal changed

const DATA_DIR := "res://data/consumables"

static var _catalog: Array[ConsumableData] = []

var _counts: Dictionary[StringName, int] = {}


## 所有消耗品定義（依 order 排序）。讀取失敗的檔案記錄錯誤並略過。
static func catalog() -> Array[ConsumableData]:
	if _catalog.is_empty():
		for file in DirAccess.get_files_at(DATA_DIR):
			var path := DATA_DIR.path_join(file.trim_suffix(".remap"))
			if not path.ends_with(".tres"):
				continue
			var data := load(path) as ConsumableData
			if data == null:
				push_error("[ConsumableBag] 無法讀取消耗品：%s" % path)
				continue
			for problem in data.validate():
				push_error("[ConsumableBag] %s：%s" % [path, problem])
			_catalog.append(data)
		_catalog.sort_custom(func(a: ConsumableData, b: ConsumableData) -> bool: return a.order < b.order)
	return _catalog


static func find(id: StringName) -> ConsumableData:
	for data in catalog():
		if data.id == id:
			return data
	return null


func count(id: StringName) -> int:
	return _counts.get(id, 0)


func is_full(data: ConsumableData) -> bool:
	return data != null and count(data.id) >= data.max_carry


## 加入一個；已達上限回傳 false。
func add(data: ConsumableData) -> bool:
	if data == null or is_full(data):
		return false
	_counts[data.id] = count(data.id) + 1
	changed.emit()
	return true


## 扣掉一個；沒有存貨回傳 false。
func take(id: StringName) -> bool:
	if count(id) <= 0:
		return false
	_counts[id] = count(id) - 1
	changed.emit()
	return true


func quick_use_item() -> ConsumableData:
	for data in catalog():
		if data.quick_use:
			return data
	return null


func snapshot() -> Dictionary:
	var out := {}
	for id in _counts:
		out[String(id)] = _counts[id]
	return out


## 還原；未知的道具或格式錯誤略過，數量夾在 0～上限之間。
func restore(data: Variant) -> void:
	_counts.clear()
	if typeof(data) == TYPE_DICTIONARY:
		for key in data:
			var def := find(StringName(str(key)))
			if def != null:
				_counts[def.id] = clampi(int(data[key]), 0, def.max_carry)
	changed.emit()
