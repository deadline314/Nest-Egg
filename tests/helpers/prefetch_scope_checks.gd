extends RefCounted

const TextureIndex := preload("res://core/navigation/level_texture_index.gd")
## Real authored scopes and real service; no fake loader or changed budget.
static func run(s: TestSuite) -> void:
	_test_index(s)
	for area: String in ["street", "pawnshop_dawn", "lounge", "stall"]:
		AssetPrefetch.clear()
		await _drain(s)
		var data := load("res://data/levels/ch1_%s.tres" % area) as LevelData
		var sent := AssetPrefetch.warm_neighbors(data)
		if area == "street": s.check(sent > 256, "the real street accepts its previously truncated neighbor tail in one scope")
		s.check(await _drain(s), "actual neighbor scope drains: " + area)
		var stages: Array[String] = []
		var unused: Array[String] = []
		var current := AssetPrefetch.level_texture_paths(data)
		for path: String in AssetPrefetch._cache:
			if path.begins_with("res://art/environment/") and (path.contains("/scenes/") or path.contains("/stages/")): stages.append(path)
			if path.begins_with("res://art/environment/backdrop/") and not current.has(path): unused.append(path)
		s.check(stages.is_empty(), "idle authored scope never pins a cutscene stage: %s %s" % [area, stages])
		s.check(unused.is_empty(), "neighbor warming never pins an unused theme sky: %s %s" % [area, unused])
		var stats := AssetPrefetch.stats()
		s.check(stats["cached"] <= AssetPrefetch.MAX_CACHED and stats["estimated_bytes"] <= AssetPrefetch.MAX_CACHE_BYTES, "authored scope preserves existing cache count and byte budgets: " + area)
	AssetPrefetch.clear()
	await _scheduled_neighbors(s)
	AssetPrefetch.clear()
	s.check(await _drain(s), "scope regression leaves no queued or native inflight requests")


static func _test_index(s: TestSuite) -> void:
	TextureIndex.prepare()
	for level: LevelData in ResourceCatalog.load_dir("res://data/levels", LevelData, "Chapter1MapSuite"):
		var indexed: Variant = TextureIndex.candidates(level.resource_path)
		var authored := AssetPrefetch.level_texture_candidates(level)
		s.check(indexed is Dictionary and indexed == authored and indexed.keys() == authored.keys(),
				"neighbor index matches authored paths, priority and order for " + level.resource_path)
	s.check(TextureIndex.candidates("res://tests/fixtures/arena_level.tres") == null,
			"an unindexed test area keeps dynamic neighbor discovery")


static func _scheduled_neighbors(s: TestSuite) -> void:
	var street := load("res://data/levels/ch1_street.tres") as LevelData
	var pawnshop := load("res://data/levels/ch1_pawnshop.tres") as LevelData
	var count := AssetPrefetch.warm_neighbors(pawnshop)
	var immediate := AssetPrefetch._requested.keys()
	AssetPrefetch.clear()
	s.check(await _drain(s), "immediate neighbor work drains before testing scheduled discovery")
	AssetPrefetch.schedule_neighbors(street)
	s.check(AssetPrefetch.stats().discovering_neighbors and AssetPrefetch.stats().queued == 0,
		"level entry schedules discovery before queueing neighbor textures")
	await s.runner.get_tree().process_frame
	await s.runner.get_tree().process_frame
	s.check(AssetPrefetch.stats().discovering_neighbors, "cold street neighbor discovery spans multiple frames")
	AssetPrefetch.schedule_neighbors(pawnshop)
	var deadline := Time.get_ticks_msec() + 10000
	while AssetPrefetch.stats().discovering_neighbors and Time.get_ticks_msec() < deadline:
		await s.runner.get_tree().process_frame
	s.check(not AssetPrefetch.stats().discovering_neighbors and count > 0 and AssetPrefetch._requested.keys() == immediate,
		"replacement scope queues exactly the same paths in the same order as immediate discovery")
	AssetPrefetch.schedule_neighbors(street)
	AssetPrefetch.clear()
	s.check(await _drain(s) and AssetPrefetch.stats().cached == 0, "clearing a scheduled search leaves no cached or pending neighbors")


static func _drain(s: TestSuite) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if not AssetPrefetch.has_pending():
			return true
		await s.runner.get_tree().process_frame
	return false
