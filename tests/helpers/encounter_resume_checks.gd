extends RefCounted
## Real authored Level -> checksum/disk/RunSnapshot boundary -> new Level regressions.

const LEVEL := "res://data/levels/ch1_street.tres"
const ZONE := &"ch1_enc_street_plaza"


static func run(s: TestSuite) -> void:
	var previous_skip := Story.auto_skip
	Story.auto_skip = true
	for dynamic_member in [false, true]:
		await _roundtrip(s, dynamic_member)
	Story.auto_skip = previous_skip


static func _create(s: TestSuite, data: LevelData, runtime: Dictionary = {}) -> Level:
	var arena := Level.new()
	arena.configure(data)
	arena.set_physics_process(false)  # Story triggers are outside this encounter regression.
	if not runtime.is_empty():
		arena.configure_resume(runtime)
	s.runner.get_tree().root.add_child(arena)
	_freeze_actors(arena)
	await s.frames(3)
	return arena


static func _freeze_actors(arena: Level) -> void:
	arena.player.set_physics_process(false)
	for node in arena._entities.get_children():
		if node is Enemy:
			node.set_physics_process(false)


static func _zone(arena: Level) -> EncounterZone:
	for node in arena._entities.get_children():
		if node is EncounterZone and node.data.id == ZONE:
			return node
	return null


static func _living(zone: EncounterZone) -> Array[Enemy]:
	var members: Array[Enemy] = []
	for ref in zone._members:
		var enemy := ref.get_ref() as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dying() and not enemy.is_queued_for_deletion():
			members.append(enemy)
	return members


static func _kill(enemy: Enemy) -> void:
	var damage := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
	damage.ignore_invulnerability = true
	damage.bypass_guard = true
	enemy.health.take_damage(damage)


static func _roundtrip(s: TestSuite, dynamic_member: bool) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var data := (load(LEVEL) as LevelData).duplicate() as LevelData
	data.intro_scene = &""
	data.show_chapter_card = false
	var arena := await _create(s, data)
	var zone := _zone(arena)
	s.check(zone != null, "resume fixture uses the authored street plaza encounter")
	if zone == null:
		await s.end_level(arena)
		return
	for node in arena._entities.get_children():
		if node is Gate and node.data.arena_gate and not node.data.lock_combat_area:
			node.restore_state(false)
			s.check(node.is_open and not node.visible and node.collision_layer == 0 and node.get_child_count() == 0,
				"disabled authored arena gate safely ignores a stale closed restore without building collision")
	zone.begin()
	var original := _living(zone)
	s.check(original.size() >= 2, "resume fixture begins with real authored enemy members")
	if original.size() < 2:
		await s.end_level(arena)
		return
	var unrelated: Enemy = null
	for node in arena._entities.get_children():
		if node is Enemy and not original.has(node):
			unrelated = node
			break
	s.check(unrelated != null, "resume fixture has an unrelated authored enemy")
	if unrelated == null:
		await s.end_level(arena)
		return
	if dynamic_member:
		for enemy in original:
			_kill(enemy)
		await s.physics_frames(20)
		_freeze_actors(arena)
		s.check(zone._reinforce_index == zone.data.reinforcements.size() and _living(zone).size() == 1,
			"the final real reinforcement has spawned before capture")
	else:
		for i in range(2, original.size()):
			_kill(original[i])
	var expected := _living(zone)
	var bounds := zone._zone_world_rect()
	for i in expected.size():
		# Authored members survive beyond both old gates; the final dynamic member is outside the right gate.
		expected[i].global_position.x = bounds.end.x + 40.0 if dynamic_member or i == 1 else bounds.position.x - 40.0
	unrelated.global_position = zone.global_position + Vector2(0, -2)
	var wave_before := zone._reinforce_index
	var runtime := arena.run_snapshot()
	var record: Dictionary = runtime["encounters"][zone.state_key()]
	s.check(record["members"].size() == expected.size(), "actual WeakRef members, not a position scan, enter the capture")
	var expected_keys: Array = []
	var unrelated_key := ""
	for key: String in arena._tracked:
		if arena._tracked[key] is Enemy and expected.has(arena._tracked[key]):
			expected_keys.append(key)
		if is_same(arena._tracked[key], unrelated):
			unrelated_key = key
	if dynamic_member:
		s.check(expected_keys.is_empty(), "final reinforcement exercises an untracked snapshot-local enemy identity")
	else:
		s.check(expected_keys.size() == 2, "both outside members retain their authored spawn correspondence")
	var saved := RunSnapshot.capture(LEVEL, runtime)
	var decoded := RunSaveCodec.decode(RunSaveCodec.encode(saved))
	s.check(decoded.has("data"), "encounter membership survives the real checksum and JSON roundtrip")
	if not decoded.has("data"):
		await s.end_level(arena)
		return
	var prepared := RunSnapshot.prepare(decoded["data"])
	s.check(prepared.has("data"), "RunSnapshot validates new encounter identities before installing live state")
	if not prepared.has("data"):
		await s.end_level(arena)
		return
	_corruption_checks(s, prepared["data"], zone.state_key())
	var scenario := "reinforcement" if dynamic_member else "authored_edges"
	var store := RunSaveStore.new("user://ne245-encounter-resume/%s.json" % scenario)
	store.validator = RunSnapshot.prepare
	s.check(store.write(prepared["data"], true), "isolated RunSaveStore writes validated %s membership to disk" % scenario)
	var disk := store.read()
	s.check(not disk.is_empty(), "real disk read retains encounter identities for %s" % scenario)
	if disk.is_empty():
		await s.end_level(arena)
		return
	s.check(disk["runtime"]["encounters"][zone.state_key()]["members"] == record["members"],
		"RunSnapshot._dynamic preserves member IDs through disk validation")
	var zone_key := zone.state_key()
	await s.end_level(arena)
	RunSnapshot.apply(disk, false)
	var restored := await _create(s, data, disk["runtime"])
	var restored_zone := _zone(restored)
	var restored_members := _living(restored_zone)
	s.check(restored_zone.state == &"active" and not restored_zone.capture_state() and restored_members.size() == expected.size(),
		"resuming outside members does not grant encounter completion")
	s.check(restored_members.all(func(enemy: Enemy) -> bool: return not restored_zone._zone_world_rect().has_point(enemy.global_position)),
		"new Level restores actual outside members without the unrelated inside enemy")
	var restored_unrelated := restored._tracked.get(unrelated_key) as Enemy
	s.check(restored_unrelated != null and not restored_members.has(restored_unrelated), "unrelated live enemy inside is never adopted as a saved member")
	if not dynamic_member:
		for key: String in expected_keys:
			s.check(restored_members.has(restored._tracked.get(key)), "outside authored member %s survives real Level restoration" % key)
	else:
		s.check(restored_members.size() == 1 and not restored._tracked.values().has(restored_members[0]),
			"the final untracked reinforcement keeps its exact snapshot correspondence")
	await s.physics_frames(20)
	s.check(restored_zone.state == &"active" and restored_zone._reinforce_index == wave_before,
		"saved living members prevent false clear and premature additional waves")
	var guard := 0
	while restored_zone.state == &"active" and guard < 8:
		_freeze_actors(restored)
		for enemy in _living(restored_zone):
			_kill(enemy)
		await s.physics_frames(20)
		guard += 1
	s.check(restored_zone.state == &"cleared" and restored_zone.capture_state(), "only real member and reinforcement deaths clear the restored encounter")
	s.check(restored_unrelated != null and not restored_unrelated.is_dying(), "encounter can finish while the unrelated inside enemy remains alive")
	await s.end_level(restored)
	# A valid old-format snapshot keeps an explicit, independently tested migration path.
	var legacy := disk.duplicate(true)
	legacy["runtime"].erase("encounter_members_version")
	for enemy: Dictionary in legacy["runtime"]["enemies"]:
		enemy.erase("snapshot_id")
	for entry: Dictionary in legacy["runtime"]["encounters"].values():
		entry.erase("members")
	var legacy_prepared := RunSnapshot.prepare(legacy)
	s.check(legacy_prepared.has("data"), "valid legacy snapshots without any identities remain loadable")
	if legacy_prepared.has("data"):
		RunSnapshot.apply(legacy_prepared["data"], false)
		var legacy_level := await _create(s, data, legacy_prepared["data"]["runtime"])
		var legacy_zone := _zone(legacy_level)
		s.check(_living(legacy_zone).has(legacy_level._tracked.get(unrelated_key)), "legacy-only restoration deliberately uses its documented spatial fallback")
		await s.end_level(legacy_level)


static func _corruption_checks(s: TestSuite, valid: Dictionary, zone_key: String) -> void:
	var cases: Array[Dictionary] = []
	var bad := valid.duplicate(true)
	bad["runtime"]["enemies"][1]["snapshot_id"] = bad["runtime"]["enemies"][0]["snapshot_id"]
	cases.append({"raw": bad, "field": "snapshot_id", "label": "duplicate enemy identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0].erase("snapshot_id")
	cases.append({"raw": bad, "field": "snapshot_id", "label": "missing enemy identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0]["snapshot_id"] = 0
	cases.append({"raw": bad, "field": "snapshot_id", "label": "non-string enemy identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0]["snapshot_id"] = "enemy:1024"
	cases.append({"raw": bad, "field": "snapshot_id", "label": "out-of-bound enemy identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0]["snapshot_id"] = "enemy:01"
	cases.append({"raw": bad, "field": "snapshot_id", "label": "noncanonical enemy identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][1]["key"] = bad["runtime"]["enemies"][0]["key"]
	bad["runtime"]["enemies"][1]["resource"] = bad["runtime"]["enemies"][0]["resource"]
	cases.append({"raw": bad, "field": "key", "label": "duplicate authored spawn correspondence"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0]["key"] = "sweeper@-1,-1"
	cases.append({"raw": bad, "field": "key", "label": "unknown authored spawn correspondence"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"][zone_key]["members"].append("enemy:1023")
	cases.append({"raw": bad, "field": "members", "label": "dangling member identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"][zone_key]["members"].append(bad["runtime"]["encounters"][zone_key]["members"][0])
	cases.append({"raw": bad, "field": "members", "label": "duplicate member identity"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"][zone_key].erase("members")
	cases.append({"raw": bad, "field": "members", "label": "missing member container"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"][zone_key]["members"] = "enemy:0"
	cases.append({"raw": bad, "field": "members", "label": "malformed member container"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"][zone_key]["members"] = []
	for i in 1025:
		bad["runtime"]["encounters"][zone_key]["members"].append("enemy:0")
	cases.append({"raw": bad, "field": "members", "label": "unbounded member container"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"] = []
	for i in 1025:
		bad["runtime"]["enemies"].append(valid["runtime"]["enemies"][0].duplicate(true))
	cases.append({"raw": bad, "field": "enemies", "label": "unbounded enemy container"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"] = {}
	for i in 1025:
		bad["runtime"]["encounters"]["encounter@%d,0" % i] = valid["runtime"]["encounters"][zone_key].duplicate(true)
	cases.append({"raw": bad, "field": "encounters", "label": "unbounded encounter container"})
	bad = valid.duplicate(true)
	bad["runtime"].erase("encounter_members_version")
	cases.append({"raw": bad, "field": "encounter_members_version", "label": "partial new format cannot silently migrate"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounter_members_version"] = true
	cases.append({"raw": bad, "field": "encounter_members_version", "label": "boolean format marker"})
	bad = valid.duplicate(true)
	bad["runtime"]["enemies"][0]["resource"] = "res://data/props/ch1_enc_street_plaza.tres"
	cases.append({"raw": bad, "field": "resource", "label": "identified enemy cannot be silently skipped"})
	bad = valid.duplicate(true)
	bad["runtime"]["encounters"]["encounter@-1,-1"] = bad["runtime"]["encounters"][zone_key].duplicate(true)
	cases.append({"raw": bad, "field": "encounter@-1,-1", "label": "unknown authored encounter correspondence"})
	var credits_before := Progression.credits
	var flags_before := GameState.world_flags.duplicate(true)
	for fixture: Dictionary in cases:
		var rejected := RunSnapshot.prepare(fixture["raw"])
		var error: String = rejected.get("error", "")
		s.check(rejected.has("error") and error.contains("run/runtime/") and error.contains(fixture["field"]),
			"%s is rejected with a specific identity path before gameplay" % fixture["label"])
	s.check(Progression.credits == credits_before and GameState.world_flags == flags_before, "corrupt identity preparation cannot mutate the live run")
