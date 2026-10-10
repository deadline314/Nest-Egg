extends RefCounted
## Snapshot-local encounter membership. No identities persist beyond one capture.

const MEMBERS_VERSION := 1
const MAX_ENEMIES := 1024
const MAX_ENCOUNTERS := 1024
const MAX_MEMBER_REFERENCES := 4096


## Validate before any live state is applied. New-format errors never use spatial fallback.
static func prepare(runtime: Dictionary, level: LevelData, layout: LevelLayout = null) -> Dictionary:
	var enemies: Variant = runtime.get("enemies", [])
	var encounters: Variant = runtime.get("encounters", {})
	if not enemies is Array or enemies.size() > MAX_ENEMIES:
		return {"error": "run/runtime/enemies不是有界陣列"}
	if not encounters is Dictionary or encounters.size() > MAX_ENCOUNTERS:
		return {"error": "run/runtime/encounters不是有界物件"}
	if not runtime.has("encounter_members_version"):
		for i in enemies.size():
			if enemies[i] is Dictionary and enemies[i].has("snapshot_id"):
				return {"error": "run/runtime/enemies/%d/snapshot_id缺少encounter_members_version，不可當成舊檔" % i}
		for key: Variant in encounters:
			if encounters[key] is Dictionary and encounters[key].has("members"):
				return {"error": "run/runtime/encounters/%s/members缺少encounter_members_version，不可當成舊檔" % key}
		return {"data": {}}  # Explicit old-format migration, validated by RunSnapshot.
	var version: Variant = runtime["encounter_members_version"]
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or version != MEMBERS_VERSION:
		return {"error": "run/runtime/encounter_members_version不支援或型別錯誤"}
	if level == null:
		return {"error": "run/runtime/encounter_members_version缺少有效關卡資料"}
	if layout == null:
		layout = LevelBuilder.parse(level)
	if not layout.is_valid():
		return {"error": "run/runtime/encounter_members_version的關卡無法解析"}
	var authored: Dictionary = {}
	var zones: Dictionary = {}
	for spawn: Dictionary in layout.spawns:
		var resource: Resource = spawn["resource"]
		var cell: Vector2i = spawn["cell"]
		if resource is EnemyData:
			authored["%s@%d,%d" % [resource.id, cell.x, cell.y]] = resource.resource_path
		elif resource is MechanismData and resource.kind == MechanismData.Kind.ENCOUNTER:
			zones["encounter@%d,%d" % [cell.x, cell.y]] = true
	var identities: Dictionary = {}
	var authored_seen: Dictionary = {}
	var area: Variant = runtime.get("area", {})
	var consumed: Dictionary = area.get("consumed", {}) if area is Dictionary and area.get("consumed", {}) is Dictionary else {}
	for i in enemies.size():
		var raw: Variant = enemies[i]
		var where := "run/runtime/enemies/%d" % i
		if not raw is Dictionary:
			return {"error": "%s不是物件" % where}
		var snapshot_id: Variant = raw.get("snapshot_id")
		if not _valid_id(snapshot_id):
			return {"error": "%s/snapshot_id必須是有界enemy識別" % where}
		if identities.has(snapshot_id):
			return {"error": "%s/snapshot_id重複：%s" % [where, snapshot_id]}
		identities[snapshot_id] = true
		if RunSaveCodec.resource(raw.get("resource"), "enemy", "res://data/enemies/") == null:
			return {"error": "%s/resource無法載入，不能遺失已識別的敵人" % where}
		var key: Variant = raw.get("key")
		if not key is String:
			return {"error": "%s/key必須是文字" % where}
		if not key.is_empty():
			if not authored.has(key) or authored[key] != raw["resource"]:
				return {"error": "%s/key沒有對應關卡敵人：%s" % [where, key]}
			if authored_seen.has(key) or consumed.has(key):
				return {"error": "%s/key重複或敵人已消滅：%s" % [where, key]}
			authored_seen[key] = true
	var membership: Dictionary = {}
	var reference_count := 0
	for key: Variant in encounters:
		var where := "run/runtime/encounters/%s" % key
		if not key is String or not zones.has(key):
			return {"error": "%s沒有對應關卡遭遇" % where}
		var entry: Variant = encounters[key]
		if not entry is Dictionary:
			return {"error": "%s不是物件" % where}
		var members: Variant = entry.get("members")
		if not members is Array or members.size() > MAX_ENEMIES:
			return {"error": "%s/members不是有界陣列" % where}
		var seen: Dictionary = {}
		for i in members.size():
			var snapshot_id: Variant = members[i]
			if not _valid_id(snapshot_id) or not identities.has(snapshot_id):
				return {"error": "%s/members/%d不是有效敵人識別：%s" % [where, i, snapshot_id]}
			if seen.has(snapshot_id):
				return {"error": "%s/members/%d重複：%s" % [where, i, snapshot_id]}
			seen[snapshot_id] = true
			reference_count += 1
			if reference_count > MAX_MEMBER_REFERENCES:
				return {"error": "%s/members超過整份快照參照上限" % where}
		membership[key] = members.duplicate()
	return {"data": {"encounter_members_version": MEMBERS_VERSION, "members": membership}}


static func _valid_id(value: Variant) -> bool:
	if not value is String or value.length() > 16 or not value.begins_with("enemy:"):
		return false
	var suffix: String = value.substr(6)
	if not suffix.is_valid_int():
		return false
	var index := int(suffix)
	return index >= 0 and index < MAX_ENEMIES and suffix == str(index)
