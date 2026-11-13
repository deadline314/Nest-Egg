extends RefCounted
## NE-299／NE-300: old saves made before chapter two and three gained their upper layers.
## Every raised map reads layout revision 2, and old keys move by the declared 16 rows onto the real content.

const RAISED := {
	"res://data/levels/ch2_harbor_street.tres": [],
	"res://data/levels/ch2_market_gate.tres": [["npc:ch2_patroller", 18, 19]],
	"res://data/levels/ch2_market.tres": [["npc:ch2_vig", 30, 19], ["npc:ch2_hawker", 101, 19]],
	"res://data/levels/ch2_loading.tres": [["npc:ch2_collection_book", 112, 19]],
	"res://data/levels/ch3_plaza.tres": [],
	"res://data/levels/ch3_pump.tres": [],
	"res://data/levels/ch3_mezzanine.tres": [],
}
const DY := 16


static func run(suite: TestSuite) -> void:
	for path: String in RAISED:
		var data := load(path) as LevelData
		var definition := MapLayoutMigration.read(data)
		suite.check(definition.get("revision") == 2, "%s reads layout revision 2 (%s)" % [path, definition])
		if definition.get("revision") != 2:
			continue
		var rows := _rows(data.layout_path)
		suite.check(MapLayoutMigration.explored_key("5,19", definition) == "5,%d" % (19 + DY), "%s explored cells move by the declared offset" % path)
		suite.check(MapLayoutMigration.checkpoint_key(path + "@30,20", definition) == path + "@30,%d" % (20 + DY), "%s activated booths move with their surface row" % path)
		for entry: Array in RAISED[path]:
			var key := "%s@%d,%d" % [entry[0], entry[1], entry[2]]
			var moved := MapLayoutMigration.spawn_key(key, definition)
			suite.check(moved == "%s@%d,%d" % [entry[0], entry[1], entry[2] + DY], "%s %s keeps its talk history after the move" % [path, entry[0]])
			var y := int(entry[2]) + DY
			var cell := rows[y][int(entry[1])] if y < rows.size() and int(entry[1]) < rows[y].length() else "#"
			suite.check(cell not in [".", "#", "="], "%s %s's migrated key lands on the actual new spawn (%s)" % [path, entry[0], cell])
		var area := MapLayoutMigration.area({"consumed": {"credits_small@50,13": true}, "damage": {}, "world": {}}, definition)
		suite.check(area.has("data") and (area["data"]["consumed"] as Dictionary).has("credits_small@50,%d" % (13 + DY)), "%s collected pickups stay collected after the move" % path)
		suite.check(MapLayoutMigration.area(area.get("data", {}), definition).get("data") == area.get("data"), "%s migration does not translate twice" % path)


static func _rows(layout_path: String) -> PackedStringArray:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	var rows := PackedStringArray()
	if not raw is Dictionary:
		return rows
	var segments: Array = raw.get("segments", [])
	if segments.is_empty():
		return rows
	for y in (segments[0] as Array).size():
		var line := ""
		for segment: Array in segments:
			line += str(segment[y])
		rows.append(line)
	return rows
