extends RefCounted
const Catalog := preload("res://core/story_result_catalog.gd")
const Original := preload("res://tests/fixtures/story_result_legacy_originals.json")

static func _talk(talk: NpcTalk) -> Dictionary:
	return {"scene":String(talk.scene),"min_talks":talk.min_talks,"min_deaths":talk.min_deaths,"after_scene":String(talk.after_scene),"requires_flag":String(talk.requires_flag),"unless_flag":String(talk.unless_flag),"requires_item":String(talk.requires_item),"requires_held_item":String(talk.requires_held_item),"unless_held_item":String(talk.unless_held_item),"requires_transferred_item":String(talk.requires_transferred_item),"once":talk.once,"credits":talk.credits,"consumable":talk.consumable.resource_path if talk.consumable else "","story_item":talk.story_item.resource_path if talk.story_item else ""}

static func run(s) -> void:
	var catalog := Catalog.new()
	s.check(catalog._migration_error.is_empty(), "sealed original migration index loads: " + catalog._migration_error)
	var scenes := {}
	var sources := {}
	for path: String in ["res://data/story/ch1_kasa.json","res://data/story/ch2_heron.json"]:
		var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for id: String in chapter["scenes"]:
			scenes[id] = chapter["scenes"][id]
			sources[id] = path
	var count := 0
	var first := ""
	var origin := {}
	for id: String in Original.data:
		var bindings: Array = Original.data[id]
		if bindings.is_empty(): continue
		count += 1
		for binding: Dictionary in bindings:
			var data := load(binding["npc"]) as NpcData
			var index := int(binding["index"])
			var actual := {"npc":data.resource_path,"index":index,"entry":String(data.talks[index].scene),"talk":_talk(data.talks[index])}
			s.check(catalog._projection_equal(actual,binding), "original independent NPC/talk data retained: " + id)
			s.check(catalog._legacy_match(id,actual,scenes,sources), "original legacy effect stays on its existing writer: " + id)
			if first.is_empty(): first = id; origin = actual
	s.check(count == 30, "only the thirty independently inventoried prior NPC effects are compatibility candidates")
	s.check(not catalog._legacy_match("test_bad_cutscene_new_legacy",origin,scenes,sources), "new scene ID cannot declare itself legacy")
	var changed := scenes.duplicate(true)
	changed[first]["results"].append({"kind":"flag","id":"test_bad_cutscene_added_power","value":true})
	s.check(not catalog._legacy_match(first,origin,changed,sources), "adding a result cannot use migration compatibility")
	changed = scenes.duplicate(true)
	changed[first]["when"] = {"flag":"test_bad_cutscene_added_power","equals":true}
	s.check(not catalog._legacy_match(first,origin,changed,sources), "changed condition cannot use migration compatibility")
	var wrong := origin.duplicate(true)
	wrong["index"] = int(wrong["index"]) + 1
	s.check(not catalog._legacy_match(first,wrong,scenes,sources), "different actual talk index is not original migration source")
	wrong = origin.duplicate(true)
	wrong["talk"]["credits"] = int(wrong["talk"]["credits"]) + 1
	s.check(not catalog._legacy_match(first,wrong,scenes,sources), "new NPC reward cannot piggyback original legacy scene")
	changed = scenes.duplicate(true)
	changed[origin["entry"]]["routes"][0]["target"] = "test_bad_cutscene_added_power"
	s.check(not catalog._legacy_match(first,origin,changed,sources), "changed source dispatcher invalidates legacy projection")
	var bytes := FileAccess.get_file_as_bytes(Catalog.MIGRATION)
	bytes[0] = bytes[0] ^ 1
	var path := "user://test_bad_cutscene_corrupt_migration.json"
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_buffer(bytes);f.close()
	catalog._load_migration(path)
	s.check(not catalog._migration_error.is_empty() and not catalog._legacy_match(first,origin,scenes,sources), "wrong SHA cannot become an empty successful compatibility index")
	DirAccess.remove_absolute(path)
	catalog._load_migration("user://test_bad_cutscene_missing_migration.json")
	s.check(not catalog._migration_error.is_empty() and not catalog._legacy_match(first,origin,scenes,sources), "missing sealed index cannot authorize a legacy write")
	catalog._load_migration()
	s.check(catalog._legacy_match(first,origin,scenes,sources), "explicit restore of exact sealed index recovers original compatibility")
	for id: String in ["ch1_t_ali_order","ch2_t_s05_gate"]:
		s.check(catalog._protected.has(id), "protected original ownership survives policy deletion: " + id)
