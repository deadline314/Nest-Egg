class_name StoryResultInputSeal
extends RefCounted
## Exact proof for the input of an independently authorized terminal NPC result.
const Bundle := preload("res://core/story_install_bundle.gd")
const MAX_DEPENDENCIES := 192
const MAX_DISPATCH_ROWS := 512
const MAX_NODES := 16384
const MAX_BYTES := 1024 * 1024


class Reads:
	var ids: Dictionary[String, bool] = {}
	var problem := ""
	var _dispatch_rows := 0

	func include(id: StringName, rows := 0) -> bool:
		if not problem.is_empty():
			return false
		_dispatch_rows += rows
		if _dispatch_rows > MAX_DISPATCH_ROWS:
			problem = "terminal source has too many dispatcher rows"
			return false
		if id == &"" or ids.has(String(id)):
			return true
		if ids.size() >= MAX_DEPENDENCIES or String(id).length() > RunSaveCodec.MAX_TEXT:
			problem = "terminal source has too many or invalid authored dependencies"
			return false
		ids[String(id)] = true
		return true


var _ids: Array[String] = []
var _bytes: PackedByteArray


static func capture(reads: Reads) -> Dictionary:
	if not reads.problem.is_empty() or reads.ids.is_empty():
		return {"error": reads.problem if not reads.problem.is_empty() else "terminal source has no dependency reads"}
	var proof := StoryResultInputSeal.new()
	proof._ids.assign(reads.ids.keys())
	var packet: Dictionary = proof._packet()
	if packet.has("error"):
		return packet
	proof._bytes = packet["data"]
	return {"data": proof}


func matches() -> bool:
	var packet := _packet()
	return packet.has("data") and packet["data"] == _bytes


func _packet() -> Dictionary:
	var records: Array = []
	for id: String in _ids:
		var present := Story._scenes.has(id)
		var body: Variant = Story._scenes.get(id)
		var source: Variant = Story._scene_sources.get(id)
		if present and not body is Dictionary:
			return {"error": "terminal authored dependency is malformed: " + id}
		if Story._scene_sources.has(id) and not source is String:
			return {"error": "terminal authored dependency has an invalid source: " + id}
		records.append([id, present, body, Story._scene_sources.has(id), source])
	var inputs := {"records": records, "next": Story._pending_next,
		"transfers": Story._pending_transfers, "context_request": Story._context_request,
		"context_facts": Story.outcomes.context_facts, "runtime_facts": Story.outcomes.runtime_facts,
		"derived_flags": Story.outcomes.derived_flags, "transaction_sources": Story.outcomes.transactions,
		"transaction_lock": Progression._story_transactions._locked}
	# Body depth is measured from its own root. The packet adds a dictionary,
	# a records array and one tuple. Registry-wide saves keep their own limits.
	var limits := RunSaveCodec.validate_marshaled_tree(inputs, MAX_NODES, MAX_BYTES, Bundle.AUTHORED_CATALOG_DEPTH + 3)
	if not limits.is_empty():
		return {"error": "terminal source exceeds its bounded authority: " + limits[0]}
	var bytes := var_to_bytes(inputs)
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return {"error": "terminal source could not encode its bounded authority"}
	return {"data": bytes}
