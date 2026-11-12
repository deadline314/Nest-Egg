extends RefCounted
const Sources := preload("res://game/story_result_sources.gd")
const Catalog := preload("res://core/story_result_catalog.gd")
const ROOT := "user://test_bad_cutscene_contract_catalog"
const STORY := "res://tests/fixtures/test_bad_cutscene_contract_story.json"
const LEAF := "test_bad_cutscene_contract_leaf"
const MENU := "test_bad_cutscene_contract_menu"
static func _record(id: String, role: String, rule: Dictionary) -> Dictionary:
	return {"id":id,"source":STORY,"npc":"res://data/npcs/ch2_patroller.tres","levels":["res://data/levels/ch2_market_gate.tres"],"role":role,"rule":rule}
static func _records() -> Array:
	return [_record(LEAF,"boundary",{"policy":Catalog.TERMINAL,"then":"","mode":"dialogue","when":{},"operations":[{"kind":"flag","id":"test_bad_cutscene_contract_seen","value":true}]}),_record(MENU,"choice",{"default":"return","options":[{"id":"ask","target":LEAF,"flags":{}},{"id":"return","target":"","flags":{}}]})]
static func _write(records: Array, version: Variant = 1) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var f := FileAccess.open(ROOT + "/chapter.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":version,"records":records})); f.close()
	f = FileAccess.open(ROOT + "/catalog.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":version,"chapters":[{"source":STORY,"path":"chapter.json"}]})); f.close()
static func _fixture(records: Array, version: Variant = 1):
	_write(records, version)
	return Catalog.new(ROOT + "/catalog.json")
static func run(s) -> void:
	var records := _records()
	var scenes := {LEAF:{"mode":"dialogue","completion_policy":Catalog.TERMINAL,"when":{},"results":[{"kind":"flag","id":"test_bad_cutscene_contract_seen","value":true}],"lines":[]},MENU:{"mode":"animated","steps":[{"do":"choice","default":"return","options":[{"id":"ask","target":LEAF},{"id":"return","target":""}]}]}}
	var locations := {LEAF:STORY,MENU:STORY}
	var catalog = _fixture(records)
	s.check(catalog.inspect(LEAF,scenes,locations)["state"] == Catalog.MATCH, "catalog accepts independent typed leaf")
	s.check(catalog.inspect(MENU,scenes,locations)["state"] == Catalog.MATCH, "catalog validates complete original NPC choice route")
	var revision: int = catalog.revision
	catalog.reload()
	s.check(catalog.revision == revision, "same-content reload preserves revision")
	var original_catalog = Sources._catalog
	Sources._catalog = catalog
	s.check(not Sources.reload_catalog() and Sources.revision() == revision,"unchanged facade reload preserves revision and requests")
	var reloaded := records.duplicate(true)
	reloaded[0]["rule"]["operations"][0]["value"] = false
	_write(reloaded)
	s.check(Sources.reload_catalog() and Sources.revision() > revision,"facade invokes catalog reload rather than native Script.reload")
	s.check(catalog.inspect(LEAF,scenes,locations)["state"] == Catalog.REFUSED,"live old source is refused after valid expected contract reload")
	_write(records);Sources.reload_catalog()
	Sources._catalog = original_catalog
	var result: Dictionary = catalog.inspect(LEAF,scenes,locations)
	if result["state"] == Catalog.MATCH:
		result["contract"]["operations"][0]["value"] = false
		s.check(catalog.inspect(LEAF,scenes,locations)["state"] == Catalog.MATCH, "caller copy cannot mutate expected catalog")
	var changed := scenes.duplicate(true)
	changed[LEAF]["results"][0]["value"] = false
	s.check(catalog.inspect(LEAF,changed,locations)["state"] == Catalog.REFUSED, "live leaf changed in same dictionary is refused")
	s.check(catalog.inspect(MENU,changed,locations)["state"] == Catalog.REFUSED, "distant changed leaf invalidates incoming menu")
	var foreign := locations.duplicate()
	foreign[LEAF] = "res://tests/fixtures/test_bad_cutscene_foreign.json"
	s.check(catalog.inspect(MENU,scenes,foreign)["state"] == Catalog.REFUSED, "foreign same-named route cannot impersonate original source")
	s.check(catalog.inspect("test_bad_cutscene_unregistered",{"test_bad_cutscene_unregistered":{"results":[{"kind":"flag","id":"test_bad_cutscene_contract_seen","value":true}]}},{"test_bad_cutscene_unregistered":STORY})["state"] == Catalog.REFUSED, "unregistered formal write does not fall through as unowned")
	var invalid: Array = []
	var bad := records.duplicate(true); bad[0]["rule"]["operations"][0]["value"] = 1; invalid.append(["numeric flag is not boolean",bad,1])
	bad = records.duplicate(true); bad[0]["role"] = "plugin"; invalid.append(["unknown role",bad,1])
	bad = records.duplicate(true); bad[0]["rule"]["operations"][0]["credits_delta"] = 7; invalid.append(["extra amount override",bad,1])
	bad = records.duplicate(true); bad.append(bad[0].duplicate(true)); invalid.append(["duplicate ID",bad,1])
	bad = records.duplicate(true); bad[1]["rule"]["options"][0]["target"] = "test_bad_cutscene_missing"; invalid.append(["missing route",bad,1])
	bad = records.duplicate(true); bad[0]["rule"]["policy"] = Catalog.CONTINUATION; bad[0]["rule"]["then"] = MENU; invalid.append(["cyclic route",bad,1])
	bad = records.duplicate(true); bad[1]["npc"] = "res://data/npcs/ch2_hawker.tres"; invalid.append(["foreign NPC route",bad,1])
	bad = records.duplicate(true); bad[1]["rule"]["default"] = "missing"; invalid.append(["missing default",bad,1])
	bad = records.duplicate(true); bad[1]["rule"]["waits"] = {"1":-0.35}; invalid.append(["negative wait",bad,1])
	bad = records.duplicate(true); bad[1]["rule"]["waits"] = {"1.5":0.35}; invalid.append(["fractional step index",bad,1])
	bad = records.duplicate(true); bad[0]["rule"]["when"] = {"not":{"unknown":true}}; invalid.append(["unknown nested operator",bad,1])
	bad = records.duplicate(true); bad[0]["rule"]["when"] = {"flag":"test_bad_cutscene_contract_seen","equals":1}; invalid.append(["unsupported numeric contract condition",bad,1])
	invalid.append(["fractional schema version",records,1.5])
	invalid.append(["boolean schema version",records,true])
	for entry: Array in invalid:
		catalog = _fixture(entry[1],entry[2])
		s.check(catalog.inspect(LEAF,scenes,locations)["state"] == Catalog.REFUSED and catalog._records.is_empty(), "entire catalog fails closed: " + entry[0])
	catalog = _fixture(records,1.0)
	s.check(catalog.inspect(MENU,scenes,locations)["state"] == Catalog.MATCH, "integral JSON version accepted without flag coercion")
	catalog = Catalog.new(ROOT + "/test_bad_cutscene_missing.json")
	s.check(catalog.inspect(LEAF,scenes,locations)["state"] == Catalog.REFUSED and catalog._records.is_empty(), "missing root fails closed")
	for file: String in ["catalog.json","chapter.json"]: DirAccess.remove_absolute(ROOT + "/" + file)
	DirAccess.remove_absolute(ROOT)
