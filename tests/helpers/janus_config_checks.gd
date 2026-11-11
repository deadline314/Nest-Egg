extends RefCounted
## Repeated fights share plain settings without retaining a derived Enemy script.


static func run(suite: TestSuite) -> void:
	JanusConfig.clear_cache()
	var first := JanusBoss._load_config(&"janus")
	var original := first.duplicate(true)
	first["__ne286_cache_probe"] = 286
	var repeated := JanusBoss._load_config(&"janus")
	suite.check(repeated.get("__ne286_cache_probe") == 286,
			"repeated JANUS setup reuses the same settings rather than rereading the file")
	first.erase("__ne286_cache_probe")
	repeated.erase("__ne286_cache_probe")
	suite.check(first == original and repeated == original,
			"removing the cache probe restores every authored JANUS setting")
	JanusConfig.clear_cache()
	suite.check(first == original,
			"clearing settings for a future fight does not mutate an existing consumer")
	var reloaded := JanusBoss._load_config(&"janus")
	suite.check(reloaded == original,
			"a fresh JANUS setup reads the same authored settings after cache release")
	reloaded["__ne286_new_cache"] = true
	suite.check(not first.has("__ne286_new_cache"),
			"cache release starts a new settings object without retaining the old consumer")
	reloaded.erase("__ne286_new_cache")
	JanusConfig.clear_cache()
