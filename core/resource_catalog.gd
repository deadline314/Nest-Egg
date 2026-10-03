class_name ResourceCatalog
extends RefCounted
## 資料目錄載入器：把某個資料夾裡同型別的 .tres 讀成一份依 order 排序的清單（消耗品、劇情道具等共用）。
## 資料項需有 `id`（StringName）；可選 `order`（int）與 `validate() -> PackedStringArray`。
## 壞檔、型別不符、重複 id 都會記錄具體路徑並略過，不影響其他資料。


## 讀取 dir 底下所有 `type` 型別的 .tres。tag 是錯誤訊息前綴，例如 "ConsumableBag"。
static func load_dir(dir: String, type: Script, tag: String) -> Array[Resource]:
	var result: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir):
		push_error("[%s] 找不到資料夾：%s" % [tag, dir])
		return result
	var files := DirAccess.get_files_at(dir)
	if files.is_empty():
		push_warning("[%s] 資料夾沒有任何資料：%s" % [tag, dir])
		return result
	files.sort()
	var seen_ids: Dictionary[StringName, String] = {}
	for file in files:
		# 匯出後資源會多一個 .remap 副檔名。
		var path := dir.path_join(file.trim_suffix(".remap"))
		if not path.ends_with(".tres"):
			continue
		var res := load(path) as Resource
		if res == null or not _is_type(res, type):
			push_error("[%s] 無法讀取或型別不符：%s" % [tag, path])
			continue
		var id := StringName(str(res.get(&"id")))
		if seen_ids.has(id):
			push_error("[%s] id「%s」重複：%s 與 %s，已略過後者" % [tag, id, seen_ids[id], path])
			continue
		seen_ids[id] = path
		if res.has_method(&"validate"):
			for problem: String in res.call(&"validate"):
				push_error("[%s] %s：%s" % [tag, path, problem])
		result.append(res)
	result.sort_custom(_by_order)
	return result


static func _is_type(res: Resource, type: Script) -> bool:
	var script := res.get_script() as Script
	while script != null:
		if script == type:
			return true
		script = script.get_base_script()
	return false


static func _by_order(a: Resource, b: Resource) -> bool:
	# order 是可選欄位：沒有這個屬性的資料視為 0，再以 id 排序。
	var order_a := _order_of(a)
	var order_b := _order_of(b)
	if order_a != order_b:
		return order_a < order_b
	return str(a.get(&"id")) < str(b.get(&"id"))


static func _order_of(res: Resource) -> int:
	var value: Variant = res.get(&"order")
	return int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0
