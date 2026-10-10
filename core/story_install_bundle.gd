class_name StoryInstallBundle
extends RefCounted
## In-memory prepared ownership, not a save format or a second wallet.
## The caller must keep a synchronous, exclusive preparation/install boundary.

const ProgressionOwner = preload("res://autoload/progression.gd")
const ItemsOwner = preload("res://autoload/story_items.gd")
const GameOwner = preload("res://autoload/game_state.gd")
const StoryOwner = preload("res://autoload/story.gd")

var _progression: ProgressionOwner.PreparedInstall
var _items: ItemsOwner.PreparedInstall
var _game: GameOwner.PreparedInstall
var _story: StoryOwner.PreparedInstall
var _source: PackedByteArray
var _consumed := false


## Receives a complete RunSnapshot.prepare result; navigation/runtime still belong
## to the future coordinator. No existing apply/rollback path calls this API.
static func prepare_components(data: Variant) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(data)
	if not errors.is_empty():
		return {"error": errors[0]}
	if not data is Dictionary or not RunSaveCodec.valid_version(data.get("version")):
		return {"error": "install/run/version invalid"}
	if data["version"] != RunSaveCodec.VERSION or data.get("release") != "demo-0.1":
		return {"error": "install/run/version or release unsupported", "unknown_version": true}
	for key: String in ["state", "progression", "story"]:
		if not data.get(key) is Dictionary:
			return {"error": "install/run/%s missing" % key}
	return _prepare(data["state"], data["progression"], data["story"], data.get("difficulty", ""), true)


## Receives only the independently validated StoryResultPlan.next projection.
## This prepares data owners; it does not authenticate producers or install Nodes.
static func prepare_story(next: Variant) -> Dictionary:
	var errors := RunSaveCodec.validate_tree(next, 32768)
	if not errors.is_empty():
		return {"error": errors[0]}
	var keys := ["flags", "items", "credits", "ledger", "area_states", "completed"]
	if not next is Dictionary or next.size() != keys.size():
		return {"error": "install/story requires the exact planner projection"}
	for key: Variant in next:
		if not key is String or not keys.has(key):
			return {"error": "install/story unknown field"}
	var source := _capture_source()
	if source.has("error"):
		return source
	var state: Dictionary = GameState._install_source()["state"].duplicate(true)
	state["area_states"] = next["area_states"]
	var progression := Progression.snapshot()
	var current := Progression.prepare_install(progression)
	if current.has("error"):
		return current
	if not next["ledger"] is Dictionary or not next["ledger"].get("receipts") is Dictionary:
		return {"error": "install/story ledger invalid"}
	for id: Variant in progression["story_transactions"]["receipts"]:
		if next["ledger"]["receipts"].get(id) != progression["story_transactions"]["receipts"][id]:
			return {"error": "install/story batch cannot erase or rewrite existing receipts"}
	progression["credits"] = next["credits"]
	progression["story_transactions"] = next["ledger"]
	var story := {"version": 1, "flags": next["flags"], "items": next["items"], "seen": next["completed"]}
	return _prepare(state, progression, story, "", false)


static func _prepare(state: Variant, progression: Variant, story: Variant, difficulty_path: Variant, whole_run: bool) -> Dictionary:
	var source := _capture_source()
	if source.has("error"):
		return source
	if not story is Dictionary or not difficulty_path is String:
		return {"error": "install/story or difficulty invalid"}
	for key: Variant in story:
		if not key is String or key not in ["version", "flags", "seen", "items", "deaths"]:
			return {"error": "install/story unsupported field: %s" % key}
	if story.has("version"):
		if not RunSaveCodec.valid_version(story["version"]):
			return {"error": "install/story/version invalid"}
		if story["version"] != 1:
			return {"error": "install/story/version unsupported", "unknown_version": true}
	# All fallible preparation completes before any live assignment. In particular,
	# invalid flags cannot arrive after a live ledger commit or owner reset.
	var game := GameState.prepare_install(state, story.get("flags"), difficulty_path, whole_run)
	if game.has("error"):
		return game
	var money := Progression.prepare_install(progression)
	if money.has("error"):
		return money
	if whole_run:
		for key: String in ["checkpoint_progress", "level_start_progress"]:
			var checkpoint := Progression.prepare_install(state[key])
			if checkpoint.has("error"):
				return {"error": "install/state/" + key + ": " + checkpoint["error"], "unknown_version": checkpoint.get("unknown_version", false)}
	var items := StoryItems.prepare_install(story.get("items"))
	if items.has("error"):
		return items
	var scenes := Story.prepare_install(story.get("seen"), whole_run)
	if scenes.has("error"):
		return scenes
	var bundle := StoryInstallBundle.new()
	bundle._game = game["data"]
	bundle._progression = money["data"]
	bundle._items = items["data"]
	bundle._story = scenes["data"]
	bundle._source = source["data"]
	return {"data": bundle}


static func _capture_source() -> Dictionary:
	if Progression._story_transaction_busy:
		return {"error": "install/source story transaction is busy"}
	var source := {"game": GameState._install_source(), "progression": Progression.snapshot(),
		"items": StoryItems.snapshot(), "story": Story._install_source()}
	var errors := RunSaveCodec.validate_tree(source)
	if not errors.is_empty():
		return {"error": "install/source " + errors[0]}
	# Finite bounded trees only. Variant bytes retain scalar types and dictionary
	# order, giving a conservative content guard without missing direct writes.
	return {"data": var_to_bytes(source)}


## Recheck before durable write, and again immediately before installation.
## No await/callback between that preflight and the four owner assignments.
func preflight() -> Dictionary:
	if _consumed:
		return {"error": "install/bundle already consumed"}
	var source := _capture_source()
	if source.has("error"):
		return source
	if source["data"] != _source:
		return {"error": "install/source stale; prepare again from the current run"}
	return {"ready": true}


## False/errors are exclusively BEFORE the first live write. The successful
## assignment section cannot call listeners, validators, loaders or saves.
func install_silent() -> Dictionary:
	var checked := preflight()
	if checked.has("error"):
		return checked
	var installed := {"installed": true}
	_consumed = true
	Progression._install_prepared(_progression)
	StoryItems._install_prepared(_items)
	GameState._install_prepared(_game)
	Story._install_prepared(_story)
	# Drop prepared aliases after transferring their containers to the owners.
	_progression = null
	_items = null
	_game = null
	_story = null
	return installed
