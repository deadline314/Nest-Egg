extends RefCounted

const FIXTURE := "res://tests/fixtures/map_revision_2.tres"
const TEST_PATH := "res://data/levels/ne297_test_only.tres"


static func run(suite: TestSuite) -> void:
	var data := (load(FIXTURE) as LevelData).duplicate(false) as LevelData
	data.take_over_path(TEST_PATH)
	var definition := MapLayoutMigration.read(data)
	suite.check(not definition.has("error") and definition.get("revision") == 2, "authored layout revision reads without changing the save format (%s)" % definition)
	if definition.has("error"):
		data.take_over_path("")
		return
	var old := {"consumed": {"grunt@14,18": true, "pistol@16,18": true, "health@200,304": true},
		"damage": {"grunt@8,18": 1}, "world": {"switch@6,18": true, "gate@17,18": true}}
	var untouched := old.duplicate(true)
	var moved := MapLayoutMigration.area(old, definition)
	suite.check(old == untouched and moved.has("data"), "area migration prepares a copy without mutating the old save")
	if not moved.has("data"):
		data.take_over_path("")
		return
	var area: Dictionary = moved["data"]
	suite.check(area["consumed"].has("grunt@14,50") and area["consumed"].has("pistol@16,50"), "consumed actors and weapon rewards keep their new spawn keys")
	suite.check(area["consumed"].has("health@200,816") and not area["consumed"].has("health@200,336"), "built-in health keys move pixel feet rather than pretending to be cells")
	suite.check(area["damage"].get("grunt@10,50") == 1 and area["world"].get("gate@17,50") == true, "explicit spawn overrides preserve damage and mechanism state")
	suite.check(MapLayoutMigration.area(area, definition).get("data") == area, "a second preparation never translates already migrated keys again")
	suite.check(MapLayoutMigration.spawn_key("npc:doctor@3,18", definition) == "npc:doctor@3,50", "NPC namespace and talk history retain their actor identity")
	suite.check(MapLayoutMigration.checkpoint_key(TEST_PATH + "@4,19", definition) == TEST_PATH + "@4,51", "activated checkpoints use surface rows, not spawn rows")
	suite.check(MapLayoutMigration.explored_key("4,18", definition) == "4,50", "explored cells use grid coordinates")
	suite.check(MapLayoutMigration.spawn_key("grunt@4294967300,18", definition) == "grunt@4294967300,18", "oversized cell keys cannot wrap through Vector2i into another actor")
	suite.check(MapLayoutMigration.spawn_key("health@4294967496,304", definition) == "health@4294967496,304", "oversized pixel keys cannot wrap into a real collected health pickup")
	var conflict := MapLayoutMigration.keys({"gate@8,18": false, "gate@10,18": true}, definition)
	suite.check(conflict.has("error"), "conflicting migrated keys refuse instead of silently overwriting durable state")
	var future := old.duplicate(true)
	future["layout_revision"] = 3
	suite.check(MapLayoutMigration.area(future, definition).has("error"), "unknown future area revisions preserve the original save")
	var runtime := {"position": [200, 304], "velocity": [10, -20], "health": 4, "area": old, "world": old["world"],
		"enemies": [{"snapshot_id": "enemy:0", "resource": "res://data/enemies/grunt.tres", "key": "grunt@8,18", "position": [136, 304], "lost": 1}],
		"loose": [{"kind": "credit", "value": 7, "position": [280, 304]}], "encounters": {}, "encounter_members_version": preload("res://game/level/encounter_snapshot.gd").MEMBERS_VERSION}
	runtime["cinematic_context"] = {"framing_source": "person", "source_id": "npc:doctor@3,18", "talk_index": 1}
	var layout := LevelBuilder.parse(data)
	var migrated := MapLayoutMigration.runtime(runtime, data, layout)
	suite.check(migrated.has("data") and runtime["position"] == [200, 304], "runtime migration leaves its source unmodified")
	if migrated.has("data"):
		var ready: Dictionary = migrated["data"]
		suite.check(ready["cinematic_context"]["source_id"] == "npc:doctor@3,50" and ready["cinematic_context"]["talk_index"] == 1 and runtime["cinematic_context"]["source_id"] == "npc:doctor@3,18", "direct pending NPC resume migrates its origin while preserving talk identity and original bytes")
		suite.check(ready["position"] == [40.0, 816.0] and ready["velocity"] == [0, 0], "old player positions return to a safe entrance in the same area")
		suite.check(ready["enemies"][0]["key"] == "grunt@10,50" and ready["enemies"][0]["snapshot_id"] == "enemy:0" and ready["enemies"][0]["lost"] == 1, "alive enemy identities and health loss survive re-anchoring")
		suite.check(ready["enemies"][0]["position"] == [168.0, 816.0], "moving enemies use their actual new authored spawn")
		suite.check(ready["loose"][0]["value"] == 7 and ready["loose"][0]["position"] == ready["position"], "uncollected loose rewards remain reachable without changing their value")
		suite.check(MapLayoutMigration.runtime(ready, data, layout).get("data") == ready, "runtime preparation is idempotent")
		suite.check(not preload("res://game/level/encounter_snapshot.gd").prepare(ready, data, layout).has("error"), "strict encounter membership still validates the migrated real spawn")
	var pending := {"state": {"area_states": {}, "checkpoint_world": {}, "checkpoint_level_path": ""}, "runtime": runtime.duplicate(true), "cinematic_context": runtime["cinematic_context"].duplicate(true)}
	var pending_result := MapLayoutMigration.prepare_run(pending, data)
	suite.check(not pending_result.has("error") and pending["cinematic_context"]["source_id"] == "npc:doctor@3,50" and pending["cinematic_context"]["talk_index"] == 1, "whole-run pending NPC origin follows the revised map before strict source authentication")
	suite.check(not MapLayoutMigration.prepare_run(pending, data).has("error") and pending["cinematic_context"]["source_id"] == "npc:doctor@3,50", "whole-run pending origin is translated only once")
	var entry := runtime.duplicate(true)
	entry["cinematic_context"] = {"framing_source": "entry", "source_id": "npc:doctor@3,18"}
	suite.check(MapLayoutMigration.runtime(entry, data, layout)["data"]["cinematic_context"]["source_id"] == "npc:doctor@3,18", "entrance origins are never reclassified as NPC requests")
	var catalog := QuestCatalog.new()
	var maps := QuestMapIndex.new()
	maps.add_area(data)
	var navigation := QuestMapState.new()
	navigation.restore({"version": 1, "pinned_id": "", "explored": {TEST_PATH: {"4,18": true}}, "activated": {TEST_PATH + "@4,19": true}}, catalog, maps)
	suite.check(navigation.knows(TEST_PATH, Vector2i(4, 50)) and navigation.activated.has(TEST_PATH + "@4,51"), "old navigation and phone activations follow their actual new cells")
	var saved := navigation.snapshot()
	navigation.restore(saved, catalog, maps)
	suite.check(navigation.knows(TEST_PATH, Vector2i(4, 50)) and navigation.issues.is_empty(), "saved layout revisions prevent navigation from moving twice")
	_destination_entries(suite, data, old)
	await _direct_level(suite, data, old, runtime)
	await _rejection_is_atomic(suite, data, future, false)
	await _rejection_is_atomic(suite, data, {}, true)
	GameState.start_new_run(GameState.difficulties[1])
	data.take_over_path("")


static func _direct_level(suite: TestSuite, data: LevelData, old: Dictionary, runtime: Dictionary) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	GameState.area_states[String(data.id)] = old.duplicate(true)
	var level := Level.new()
	level.configure(data)
	var resume := runtime.duplicate(true)
	resume["loose"] = []
	level.configure_resume(resume)
	suite.runner.get_tree().root.add_child(level)
	for actor in suite.runner.get_tree().get_nodes_in_group(&"enemies"):
		if level.is_ancestor_of(actor):
			actor.set_physics_process(false)
	await suite.frames(3)
	var ready := is_instance_valid(level.player) and level._initialization_complete
	suite.check(ready, "direct Level resumes use the same migration before spawning actors")
	if not ready:
		await suite.end_level(level)
		return
	suite.check(level.player.health.current == 4, "direct resume retains actual saved player health")
	suite.check(level._area["consumed"].has("health@200,816"), "direct resume keeps the already collected health marker")
	var health_count := 0
	var weapon_count := 0
	for node in level._entities.get_children():
		health_count += 1 if node is HealthPickup else 0
		weapon_count += 1 if node is WeaponPickup else 0
	suite.check(health_count == 0 and weapon_count == 0, "already collected health and weapons are not spawned again")
	suite.check(level._tracked.has("grunt@10,50") and not level._tracked.has("grunt@14,50"), "alive and killed enemy state stays distinct after direct resume")
	var enemy := level._tracked.get("grunt@10,50") as Enemy
	suite.check(enemy != null and enemy.lost_health() == 1, "actual resumed enemies retain saved damage")
	await suite.end_level(level)


static func _rejection_is_atomic(suite: TestSuite, data: LevelData, previous: Dictionary, bad_checkpoint: bool) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	GameState.current_level_path = "preserved_previous_level"
	GameState.pending_portal = &"preserved_pending_portal"
	if not previous.is_empty():
		GameState.area_states[String(data.id)] = previous.duplicate(true)
	if bad_checkpoint:
		GameState.has_checkpoint = true
		GameState.checkpoint_level_path = data.resource_path
		GameState.checkpoint_position = Vector2(72, 304)
		GameState.checkpoint_world = {"gate@8,18": false, "gate@10,18": true}
	var before := {"areas": GameState.area_states.duplicate(true), "world": GameState.checkpoint_world.duplicate(true), "position": GameState.checkpoint_position}
	var level := Level.new()
	level.configure(data)
	suite.runner.get_tree().root.add_child(level)
	await suite.frames(2)
	suite.check(level.player == null and not level._initialization_complete, "refused migration never builds a partial live player")
	suite.check(GameState.current_level_path == "preserved_previous_level" and GameState.pending_portal == &"preserved_pending_portal", "refused migration cannot change the live route or consume its pending portal")
	suite.check(GameState.area_states == before["areas"] and GameState.checkpoint_world == before["world"] and GameState.checkpoint_position == before["position"], "refused area or checkpoint preparation leaves all durable dictionaries untouched")
	await suite.end_level(level)


static func _entry_runtime(revision: int) -> Dictionary:
	var area := {"consumed": {}, "damage": {}, "world": {}}
	var result := {"position": [-1, -1], "velocity": [0, 0], "health": 4, "loadout": {}, "area": area, "world": {}, "enemies": [], "loose": [], "encounters": {}, "encounter_members_version": preload("res://game/level/encounter_snapshot.gd").MEMBERS_VERSION}
	if revision > 1:
		area["layout_revision"] = revision
		result["layout_revision"] = revision
	return result


static func _destination_entries(suite: TestSuite, revised: LevelData, old_area: Dictionary) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var producer := preload("res://core/run_destination.gd")
	var owners := var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot()])
	# The reader canonicalizes vector components to floats; compare exact coordinates, not Array element storage types.
	suite.check(RunSaveCodec.vector([-1, -1], Vector2.INF) == Vector2(-1, -1) and RunSaveCodec.vector([-1.0, -1.0], Vector2.INF) == Vector2(-1, -1) and RunSaveCodec.vector([0.0, -1.0], Vector2.INF) != Vector2(-1, -1) and RunSaveCodec.vector([-1.0, 0.0], Vector2.INF) != Vector2(-1, -1) and RunSaveCodec.vector([true, -1], Vector2.INF) != Vector2(-1, -1), "fresh destination sentinel accepts the same exact numeric coordinates and rejects changed axes or invalid values")
	for source_revision: int in [1, 2]:
		for target: String in [revised.resource_path, "res://data/levels/level_01.tres"]:
			var original := RunSnapshot.capture(target, _entry_runtime(source_revision))
			var untouched := original.duplicate(true)
			var prepared: Dictionary = producer.prepare(original, target)
			suite.check(prepared.has("data") and original == untouched, "destination revision %d to %s prepares a copy" % [source_revision, target])
			if not prepared.has("data"):
				continue
			var entry: Dictionary = prepared["data"]["runtime"]
			var expected := 2 if target == revised.resource_path else 1
			suite.check(entry.get("layout_revision", 1) == expected and entry["area"].get("layout_revision", 1) == expected and entry["position"] == [-1, -1], "fresh destination runtime and area use the target revision without moving the entrance sentinel")
			var checked := RunSnapshot.prepare(prepared["data"])
			var read_position: Variant = checked.get("data", {}).get("runtime", {}).get("position")
			var component_types: Array = []
			if read_position is Array:
				for component: Variant in read_position:
					component_types.append(typeof(component))
			print("[NE297 destination reader] ", JSON.stringify({"source_revision": source_revision, "target": target, "has_data": checked.has("data"), "error": checked.get("error", ""), "position": read_position, "component_types": component_types, "raw_container_equal": read_position == [-1, -1], "exact_coordinate_equal": RunSaveCodec.vector(read_position, Vector2.INF) == Vector2(-1, -1)}))
			suite.check(checked.has("data") and RunSaveCodec.vector(read_position, Vector2.INF) == Vector2(-1, -1), "actual run reader preserves the fresh destination entry rather than applying legacy relocation")
			if checked.has("data"):
				suite.check(RunSnapshot.prepare(checked["data"]).get("data") == checked["data"], "destination run preparation is idempotent")
	var original := RunSnapshot.capture(revised.resource_path, _entry_runtime(2))
	original["state"]["area_states"][String(revised.id)] = old_area.duplicate(true)
	original["state"]["has_checkpoint"] = true
	original["state"]["checkpoint_level_path"] = revised.resource_path
	original["state"]["checkpoint_position"] = [72, 304]
	original["state"]["checkpoint_world"] = {"gate@17,18": true}
	var untouched := original.duplicate(true)
	var migrated: Dictionary = producer.prepare(original, revised.resource_path)
	suite.check(migrated.has("data") and original == untouched, "destination area and checkpoint migration leaves the original source snapshot unchanged")
	if migrated.has("data"):
		var ready: Dictionary = migrated["data"]
		var area: Dictionary = ready["runtime"]["area"]
		suite.check(area["consumed"].has("health@200,816") and area["world"].has("gate@17,50") and ready["state"]["area_states"][String(revised.id)] == area, "destination runtime and persistent area preserve the same migrated rewards and mechanisms")
		suite.check(ready["state"]["checkpoint_world"].has("gate@17,50") and not ready["state"]["checkpoint_world"].has("gate@17,18"), "cross-area checkpoint world is migrated before its revision marker advances")
		var again: Dictionary = producer.prepare(ready, revised.resource_path)
		suite.check(again.has("data") and again["data"]["state"]["checkpoint_world"] == ready["state"]["checkpoint_world"] and again["data"]["state"]["checkpoint_position"] == ready["state"]["checkpoint_position"] and again["data"]["runtime"]["area"] == area, "preparing the destination again never moves checkpoint or rewards twice")
	for invalid: Variant in [3, true, 1.5]:
		var broken := original.duplicate(true)
		broken["state"]["area_states"][String(revised.id)]["layout_revision"] = invalid
		var before := broken.duplicate(true)
		suite.check(producer.prepare(broken, revised.resource_path).has("error") and broken == before, "invalid destination revision %s refuses without changing the original" % str(invalid))
	var conflict := original.duplicate(true)
	conflict["state"]["area_states"][String(revised.id)]["world"] = {"gate@8,18": false, "gate@10,18": true}
	suite.check(producer.prepare(conflict, revised.resource_path).has("error"), "destination migration cannot overwrite colliding durable mechanism keys")
	var future_source := original.duplicate(true)
	future_source["runtime"]["layout_revision"] = 3
	suite.check(producer.prepare(future_source, revised.resource_path).has("error"), "a future source revision is not erased by a destination reset")
	var missing := RunSnapshot.capture(revised.resource_path, _entry_runtime(2))
	missing["level"] = "res://data/levels/no_such_level_ne297.tres"
	var recovered := RunSnapshot.prepare(missing)
	suite.check(recovered.has("data") and recovered["data"]["level"] == CampaignEdition.current().first_level and recovered["data"]["runtime"]["health"] == 4 and recovered["data"]["runtime"].get("layout_revision", 1) == recovered["data"]["runtime"]["area"].get("layout_revision", 1), "missing revision2 area safely falls back without carrying its stale runtime revision")
	missing["runtime"]["layout_revision"] = 3
	suite.check(RunSnapshot.prepare(missing).has("error"), "unknown future runtime stays refused even when its old area resource is missing")
	suite.check(owners == var_to_bytes([GameState._install_source(), Progression.snapshot(), StoryItems.snapshot()]), "destination and fallback preparation never install changes into live owners")
