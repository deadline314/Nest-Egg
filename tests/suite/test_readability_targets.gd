class_name ReadabilityTargetsSuite
extends TestSuite
## Rendering probes must stand on real floors and cover the current campaign.
## This catches a sampling baseline drifting into a wall after a map redesign.
const PROBE := preload("res://tools/ch1_readability_check.gd")
const ROSTER := "res://data/combat/chapter_rosters.json"


func run() -> void:
	var probe := PROBE.new()
	var targets: Array[Dictionary] = probe.targets()
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROSTER))["chapters"]["ch1_kasa"]
	var seen: Array[String] = []
	for target: Dictionary in targets:
		var data := load(str(target["path"])) as LevelData
		check(data != null, "probe level exists: %s" % target["path"])
		if data == null:
			continue
		check(not seen.has(String(data.id)), "campaign probes do not duplicate %s" % data.id)
		seen.append(String(data.id))
		var layout := LevelBuilder.parse(data)
		check(layout.is_valid(), "probe layout parses: %s" % data.id)
		check(not (target["spots"] as Array).is_empty(), "%s has at least one probe" % data.id)
		var enemy_path := str(target["enemy_path"])
		if not enemy_path.is_empty():
			var enemy := load(enemy_path) as EnemyData
			check(enemy != null and roster["enemies"].has(String(enemy.id)), "%s probes an enemy belonging to this chapter" % data.id)
			if enemy != null:
				check(not PlacementChecks.cells_of(layout, enemy.id).is_empty(), "%s uses a representative enemy actually present in the area" % data.id)
		else:
			var enemies := layout.spawns.filter(func(spawn: Dictionary) -> bool: return spawn["resource"] is EnemyData)
			check(enemies.is_empty(), "%s has no enemies, so no enemy contrast is required" % data.id)
		for spot: Array in target["spots"]:
			_check_floor(layout, String(data.id), str(spot[0]), int(spot[1]), int(spot[2]))
			if not enemy_path.is_empty():
				_check_floor(layout, String(data.id), str(spot[0]) + " enemy", int(spot[1]) + int(PROBE.ENEMY_DISTANCE / layout.tile_size), int(spot[2]))
	for id: String in roster["levels"]:
		check(seen.has(id), "all current campaign data are sampled: %s" % id)
	check(seen.size() == roster["levels"].size(), "probe scope equals the canonical campaign level list")
	probe.free()
	var legacy := LevelBuilder.parse(load("res://data/levels/level_01.tres") as LevelData)
	check(PROBE.probe_floor(legacy, 30, "屋頂巷弄") == 18.0 * legacy.tile_size, "legacy player probe stands on its upper roof")
	check(PROBE.probe_floor(legacy, 36, "屋頂巷弄") == 15.0 * legacy.tile_size, "legacy enemy probe stands on its own adjacent roof")


func _check_floor(layout: LevelLayout, id: String, label: String, column: int, row: int) -> void:
	check(column >= 0 and column * layout.tile_size < layout.pixel_size().x, "%s/%s: sampling column is inside the map" % [id, label])
	check(layout.cell(column, row) in ["#", "="], "%s/%s: feet have a floor at %d/%d" % [id, label, column, row])
	var clear := true
	for above in range(row - 4, row):
		clear = clear and layout.cell(column, above) != "#"
	check(clear, "%s/%s: the body sample is above ground with clear headroom" % [id, label])
