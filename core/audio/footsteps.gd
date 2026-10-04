class_name Footsteps
extends RefCounted
## 腳步聲與落地聲：依腳下的地形材質分成金屬、混凝土、潮濕等「地面種類」。
## 資料 data/audio/footsteps.json：materials（地形材質 id → 地面種類）、default_surface（沒登記的材質）、
## 以及用聲音設定表格式寫的 default／profiles（地面種類 → step、land）。專屬音效缺檔時退回後面的通用名稱。

const PATH := "res://data/audio/footsteps.json"
const KINDS: PackedStringArray = ["step", "land"]

static var _table: SoundProfileTable
static var _materials: Dictionary = {}
static var _default_surface: StringName = &"concrete"
static var _loaded := false
## 診斷：累計播放的腳步與落地聲次數（測試與實驗室讀）。
static var played_count := 0


static func _ensure_loaded(fresh := false) -> void:
	if _loaded and not fresh:
		return
	_loaded = true
	_table = SoundProfileTable.new(PATH, "Footsteps", KINDS)
	var root := AudioData.read_root(PATH, "Footsteps", PackedStringArray(["profiles"]), fresh)
	var materials: Variant = root.get("materials", {})
	_materials = materials if typeof(materials) == TYPE_DICTIONARY else {}
	_default_surface = StringName(str(root.get("default_surface", "concrete")))


static func reload_data(fresh := false) -> void:
	_ensure_loaded(true if fresh else false)
	if not fresh:
		_loaded = false
		_ensure_loaded()


## 地形材質 id → 地面種類；空字串或沒登記的材質用 default_surface。
static func surface_for_material(material_id: StringName) -> StringName:
	_ensure_loaded()
	return StringName(str(_materials.get(String(material_id), _default_surface)))


static func name_for(surface: StringName, kind: StringName) -> StringName:
	_ensure_loaded()
	return _table.resolve(surface, kind, {}, Sfx.has_named)


## 播放腳步（step）或落地（land）；volume_db 由呼叫端依速度或衝擊力決定。
static func play(surface: StringName, kind: StringName, volume_db: float) -> void:
	var name := name_for(surface, kind)
	if name != &"":
		played_count += 1
		Sfx.play_named(name, volume_db)


static func surfaces() -> Array:
	_ensure_loaded()
	return _table.profile_ids()


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。terrain_ids 是專案內所有地形材質 id，每一個都要有對應。
static func validate(terrain_ids: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	_ensure_loaded()
	var errors := _table.validate(Sfx.has_named)
	if not _table.has_profile(_default_surface):
		errors.append("%s 的 default_surface「%s」不是已定義的地面種類" % [PATH, _default_surface])
	for material: String in _materials.keys():
		if not _table.has_profile(StringName(str(_materials[material]))):
			errors.append("%s 的材質「%s」對應不存在的地面種類「%s」" % [PATH, material, _materials[material]])
	for id in terrain_ids:
		if not _materials.has(id):
			errors.append("%s 沒有地形材質「%s」的地面種類" % [PATH, id])
	return errors
