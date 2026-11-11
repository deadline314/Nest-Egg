extends Node
## Read actual campaign placements and appearance routes; no actors, combat or save state are simulated.

# Load the newest campaign first. Godot 4.7.2 retains a script/resource graph at
# shutdown when Janus is first loaded after the older campaigns; evidence keeps
# both orders. This report does not change gameplay resource loading.
const CHAPTERS := ["ch3_clearwater", "ch2_heron", "ch1_kasa"]
var _out := ""
var _roster := "res://data/combat/chapter_rosters.json"
var _checks := 0
var _issues: Array[String] = []
var _sources := {}
var _enemies := {}
var _output_failed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--roster="):
			_roster = arg.trim_prefix("--roster=")
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[RosterReport] --out requires a writable absolute directory")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_report()
	for frame in 4:
		await get_tree().process_frame
	get_tree().quit(2 if _output_failed else (0 if _issues.is_empty() else 1))


func _report() -> void:
	var document := _json(_roster)
	var chapters := _dictionary(document.get("chapters", {}), "roster.chapters")
	var report := {}
	for chapter: String in CHAPTERS:
		var definition := _dictionary(chapters.get(chapter, {}), "roster.chapters." + chapter)
		_check(not definition.is_empty(), "missing campaign chapter: " + chapter)
		var allowed := _strings(definition.get("enemies", []), chapter + ".enemies")
		_enemies[chapter] = {}
		var areas: Array[Dictionary] = []
		for id: String in _strings(definition.get("levels", []), chapter + ".levels"):
			var path := "res://data/levels/%s.tres" % id
			_remember(path)
			var level := load(path) as LevelData
			_check(level != null, "missing LevelData: " + path)
			if level == null:
				continue
			_check(String(level.chapter) == chapter, "%s declares chapter %s, expected %s" % [path, level.chapter, chapter])
			_remember(level.layout_path)
			var layout := LevelBuilder.parse(level)
			_check(layout.is_valid() and layout.warnings.is_empty(), "%s layout: %s" % [path, layout.warnings])
			var placed: Array[Dictionary] = []
			var reinforcements: Array[Dictionary] = []
			var spawns: Array[Dictionary] = layout.spawns.duplicate()
			if not layout.boss_spawn.is_empty():
				spawns.append(layout.boss_spawn)
			for spawn: Dictionary in spawns:
				var resource: Resource = spawn["resource"]
				var cell: Vector2i = spawn["cell"]
				if resource is EnemyData:
					var enemy := resource as EnemyData
					_register(enemy, chapter, allowed)
					placed.append({"id": String(enemy.id), "cell": [cell.x, cell.y], "feet": [spawn["position"].x, spawn["position"].y]})
				elif resource is MechanismData:
					for enemy: EnemyData in (resource as MechanismData).reinforcements:
						_register(enemy, chapter, allowed)
						reinforcements.append({"id": String(enemy.id) if enemy != null else "MISSING", "mechanism": String((resource as MechanismData).id), "cell": [cell.x, cell.y]})
			areas.append({"id": id, "name": level.display_name, "size_tiles": [layout.width, layout.height], "placed": placed, "static_reinforcements": reinforcements})
		for id: String in allowed:
			_check(_enemies[chapter].has(id), "%s declares an enemy absent from its campaign: %s" % [chapter, id])
		report[chapter] = {"declared": allowed, "areas": areas, "enemies": _enemies[chapter]}
	var repeated := {}
	for chapter: String in CHAPTERS:
		for id: String in _enemies[chapter]:
			if not repeated.has(id):
				repeated[id] = []
			(repeated[id] as Array).append(chapter)
	var shared: Array[Dictionary] = []
	for id: String in repeated:
		if (repeated[id] as Array).size() > 1:
			shared.append({"id": id, "chapters": repeated[id]})
	_check(shared.size() <= 2, "more than two repeated campaign identities: %s" % [shared])
	_remember("res://tools/chapter_roster_report.gd")
	for path: String in ["res://tools/level/build_ch2.py", "res://tools/level/build_ch3.py", "res://data/levels/ch2_design.json", "res://data/levels/ch3_design.json"]:
		_remember(path)
	var output := {"engine": Engine.get_version_info()["string"], "scope": "read-only actual LevelBuilder/resource audit; excludes legacy demo; no playthrough, difficulty, visual or art approval", "checks": _checks, "issues": _issues, "chapters": report, "shared_identities": shared, "sources": _sources}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("[RosterReport] cannot write report: " + _out)
		_output_failed = true
		return
	file.store_string(JSON.stringify(output, "\t"))
	print("ROSTER_REPORT checks=%d issues=%d shared=%d" % [_checks, _issues.size(), shared.size()])


func _register(enemy: EnemyData, chapter: String, allowed: Array) -> void:
	_check(enemy != null, "missing EnemyData in " + chapter)
	if enemy == null:
		return
	var id := String(enemy.id)
	_check(allowed.has(id), "%s places undeclared enemy: %s (%s)" % [chapter, id, enemy.resource_path])
	if _enemies[chapter].has(id):
		return
	_remember(enemy.resource_path)
	if enemy.behavior != null:
		_remember(enemy.behavior.resource_path)
	var appearance := {"rig_skin": enemy.rig_skin, "creature_skin": enemy.creature_skin, "rig_weapon": enemy.rig_weapon, "route": "behavior drawing"}
	if not enemy.rig_skin.is_empty():
		var folder := "res://art/characters/" + enemy.rig_skin
		var skin := _json(folder.path_join("character.json"))
		appearance["route"] = "character rig"
		_remember(str(skin.get("rig", "")))
		var textures: Dictionary = skin.get("textures", {})
		for texture: Dictionary in textures.values():
			var image_path := folder.path_join(str(texture.get("file", "")))
			_check(FileAccess.file_exists(image_path), "%s missing texture: %s" % [id, image_path])
	elif not enemy.creature_skin.is_empty():
		var creature := _json("res://art/creatures/%s.json" % enemy.creature_skin)
		appearance["route"] = "part creature"
		for part: Dictionary in creature.get("parts", []):
			var image_path := str(creature.get("dir", "")).path_join(str(part.get("file", "")))
			_check(FileAccess.file_exists(image_path), "%s missing creature part: %s" % [id, image_path])
	_enemies[chapter][id] = {"name": enemy.display_name, "resource": enemy.resource_path, "behavior": enemy.behavior.resource_path if enemy.behavior != null else "", "attack_category": String(enemy.attack_category), "health": enemy.max_health, "telegraph_seconds": enemy.telegraph_time, "declared_credit_value": enemy.credit_value, "appearance": appearance, "dynamic_summon": String(enemy.summon.id) if enemy.summon != null else "", "move_summons": []}
	if enemy.summon != null:
		_register(enemy.summon, chapter, allowed)
	var boss_path := "res://data/bosses/%s.json" % id
	# Story bosses need not set is_boss: that flag selects the legacy locked arena.
	if FileAccess.file_exists(boss_path):
		var pattern := _json(boss_path)
		for move_id: String in pattern.get("moves", {}):
			var move: Dictionary = pattern["moves"][move_id]
			var parameters: Dictionary = move.get("params", {})
			if not parameters.has("enemy"):
				continue
			var summon_path := str(parameters["enemy"])
			_remember(summon_path)
			var backup := load(summon_path) as EnemyData
			_check(backup != null, "%s move %s cannot load summon: %s" % [id, move_id, summon_path])
			if backup != null:
				(_enemies[chapter][id]["move_summons"] as Array).append({"move": move_id, "id": String(backup.id), "parameters": parameters})
				_register(backup, chapter, allowed)


func _json(path: String) -> Dictionary:
	_remember(path)
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	_check(error == OK and parser.data is Dictionary, "invalid JSON: %s (%s)" % [path, parser.get_error_message()])
	return parser.data if error == OK and parser.data is Dictionary else {}


func _dictionary(value: Variant, where: String) -> Dictionary:
	_check(value is Dictionary, where + " must be an object")
	return value if value is Dictionary else {}


func _strings(value: Variant, where: String) -> Array[String]:
	var result: Array[String] = []
	_check(value is Array, where + " must be an array")
	if value is Array:
		for item: Variant in value:
			_check(item is String, where + " contains a non-string entry")
			if item is String:
				result.append(item)
	return result


func _remember(path: String) -> void:
	if _sources.has(path):
		return
	_check(not path.is_empty() and FileAccess.file_exists(path), "missing source: " + path)
	if not path.is_empty() and FileAccess.file_exists(path):
		_sources[path] = FileAccess.get_sha256(path)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_issues.append(message)
		printerr("[RosterReport] " + message)
