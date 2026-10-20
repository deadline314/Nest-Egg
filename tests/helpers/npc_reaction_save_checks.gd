extends RefCounted
## Existing optional NPC world-state field, not a new campaign reaction policy.
static func run(s: TestSuite, directory: String) -> void:
	const KEY := "npc:reaction_fixture@1,2"
	var world := {KEY: {"talks": 3, "claimed": [1], "reacted": [0, 2]}}
	var before := var_to_bytes(world)
	var prepared := RunSnapshot._world(world)
	s.check(prepared[KEY].get("reacted", []) == [0, 2], "whole-run world preparation retains once-reaction memory")
	s.check(prepared[KEY]["talks"] == 3 and prepared[KEY]["claimed"] == [1], "reaction memory preserves existing talks and reward claims")
	s.check(var_to_bytes(world) == before, "reaction world preparation never mutates its captured source")
	var legacy := RunSnapshot._world({KEY: {"talks": 2, "claimed": []}})
	s.check(not legacy[KEY].has("reacted"), "legacy NPC records without reaction memory keep their original optional schema")
	for case: Array in [["wrong container", 7, []], ["bad indices", [0, 0, -1, 1.5, true, "2", 1000001, 2.0], [0, 2]], ["empty", [], []]]:
		var result := RunSnapshot._world({KEY: {"reacted": case[1]}})
		s.check(result[KEY].get("reacted", []) == case[2], "reaction memory repairs safely: " + case[0])
	var bounded := RunSnapshot._world({KEY: {"reacted": range(1025)}})
	s.check(bounded[KEY].get("reacted", []).size() == 1024, "reaction memory remains bounded")
	var save := RunSnapshot.capture("res://data/levels/ch1_pawnshop.tres", {"position": [100, 160], "health": 4, "world": world, "area": {"consumed": {}, "damage": {}, "world": world}, "loadout": {}})
	save["state"]["checkpoint_world"] = world.duplicate(true)
	save["state"]["area_states"] = {"ch1_pawnshop": {"consumed": {}, "damage": {}, "world": world.duplicate(true)}}
	var store := RunSaveStore.new(directory.path_join("npc-reactions.json"))
	store.validator = RunSnapshot.prepare
	s.check(store.write(save, true), "actual complete writer accepts NPC reaction state")
	var loaded := store.read()
	s.check(not loaded.is_empty(), "actual complete reader restores the saved run")
	if loaded.is_empty():
		return
	for item: Array in [["runtime", loaded["runtime"]["world"]], ["current area", loaded["runtime"]["area"]["world"]], ["checkpoint", loaded["state"]["checkpoint_world"]], ["persistent area", loaded["state"]["area_states"]["ch1_pawnshop"]["world"]]]:
		s.check(item[1][KEY].get("reacted", []) == [0, 2], "real disk preserves reaction memory in " + item[0])
	var awareness := NpcAwareness.new(null, NpcData.new())
	awareness.restore(loaded["runtime"]["world"][KEY].get("reacted", []))
	s.check(awareness.capture() == [0, 2], "actual awareness owner restores exactly the persisted once indices")
