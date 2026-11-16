extends RefCounted
## Real authored scopes and real service; no fake loader or changed budget.
static func run(s: TestSuite) -> void:
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
	s.check(await _drain(s), "scope regression leaves no queued or native inflight requests")

static func _drain(s: TestSuite) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var stats := AssetPrefetch.stats()
		if stats["queued"] == 0 and stats["inflight"] == 0: return true
		await s.runner.get_tree().process_frame
	return false
