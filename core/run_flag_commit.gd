extends RefCounted
## Pure whole-run preparation, durable write, then silent boolean installation.
## The action owner alone validates its live source and publishes notifications.
const Bundle := preload("res://core/story_install_bundle.gd")

static func commit(main: Node, level: Level, results: Dictionary, scene_id: StringName, valid_source: Callable, prepare_route: Callable = Callable()) -> Dictionary:
	if not valid_source.is_valid() or not valid_source.call(): return {"error": "invalid live flag result source"}
	for flag: String in results:
		if not GameState.flag_defaults.get(flag) is bool or not results[flag] is bool:
			return {"error": "undeclared or invalid boolean result: " + flag}
	var candidate := RunSnapshot.capture(main.get("_level_path"), level.run_snapshot(), "", main.get("_chapter_complete"))
	# Canonicalize before proposing results; normalization must not silently alter
	# another live owner (item custody, economy, or legacy flags).
	var decoded := RunSaveCodec.decode(RunSaveCodec.encode(candidate))
	if decoded.has("error"): return decoded
	var original := RunSnapshot.prepare(decoded["data"])
	if original.has("error"): return original
	for pair: Array in [[original["data"]["story"]["items"], StoryItems.snapshot()], [original["data"]["story"]["flags"], GameState.world_flags], [original["data"]["progression"], Progression.snapshot()]]:
		if JSON.parse_string(JSON.stringify(pair[0])) != JSON.parse_string(JSON.stringify(pair[1])):
			return {"error": "flag result requires restoring the original whole run", "reload_original": true}
	candidate = original["data"].duplicate(true)
	var proof := Bundle._capture_source()
	if proof.has("error"): return proof
	var flags: Dictionary = candidate["story"]["flags"]
	flags.merge(results, true)
	var facts := func(kind: StringName, key: StringName) -> Variant:
		return flags.get(String(key), GameState.flag_defaults.get(String(key), false)) if kind == &"flag" else Story.fact(kind, key)
	for derived: String in Story.outcomes.derived_flags:
		flags[derived] = StoryRules.holds(Story.outcomes.derived_flags[derived], facts)
	# Preserve an unread dialogue even if the process exits immediately after the
	# durable result, before its normal scene_started save can run.
	var scene: Dictionary = Story._scenes.get(String(scene_id), {})
	var mode := str(scene.get("mode", ""))
	var resumable: bool = mode in ["dialogue", "animated", "cinematic"] or (mode == "radio" and scene.get("freeze", false) == true)
	if resumable and not Story._seen.has(scene_id) and (not scene.has("when") or StoryRules.holds(scene["when"], facts)):
		candidate["cinematic"] = String(scene_id)
	if prepare_route.is_valid():
		var route: Dictionary = prepare_route.call(candidate)
		if route.has("error"): return route
		candidate = route["data"]
	var store: RunSaveStore = main.get("_run_store")
	if store.overwrite_authorized and not store.write(original["data"]):
		return {"error": "initial save: " + "; ".join(store.issues)}
	var prepared := store.prepare_existing_write(candidate)
	if prepared.has("error"): return prepared
	var write: RunSaveStore.PreparedExistingWrite = prepared["data"]
	var normalized := write.snapshot()
	var normalized_json: Variant = JSON.parse_string(JSON.stringify(normalized))
	var candidate_json: Variant = JSON.parse_string(JSON.stringify(candidate))
	if normalized_json != candidate_json:
		return {"error": "flag result needs a whole-run repair before retry at " + _difference(candidate_json, normalized_json), "reload_original": true}
	var game := GameState.prepare_install(normalized["state"], flags, "", false)
	if game.has("error"): return game
	var changed: Array[String] = []
	for key: String in game["data"].flags:
		if GameState.get_flag(StringName(key)) != game["data"].flags[key]: changed.append(key)
	if Bundle._capture_source().get("data") != proof["data"] or not valid_source.call():
		return {"error": "live flag result source changed before durable write"}
	var outcome := store.commit_existing_write(write)
	if not outcome.committed:
		return {"error": "; ".join(outcome.issues), "reload_original": outcome.requires_recovery}
	if outcome.requires_recovery or Bundle._capture_source().get("data") != proof["data"] or not valid_source.call():
		return {"committed": true, "recovery": true}
	GameState._install_prepared_flags(game["data"])
	return {"committed": true, "changed": changed, "state": game["data"], "snapshot": normalized}


## Report only the changed schema path, never a player's saved values.
static func _difference(before: Variant, after: Variant, path := "run") -> String:
	if before is Dictionary and after is Dictionary:
		for key: Variant in before:
			if not after.has(key): return path + "." + str(key).left(128)
			if before[key] != after[key]: return _difference(before[key], after[key], path + "." + str(key).left(128))
		for key: Variant in after:
			if not before.has(key): return path + "." + str(key).left(128)
	elif before is Array and after is Array and before.size() == after.size():
		for index in before.size():
			if before[index] != after[index]: return _difference(before[index], after[index], path + "[%d]" % index)
	return path.left(512)
