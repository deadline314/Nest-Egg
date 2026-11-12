extends RefCounted
## Independent authored NPC contracts. MATCH validates content, never a live producer.
const ROOT := "res://data/story_contracts/catalog.json"
const MATCH := "MATCH"
const NOT_OWNED := "NOT_OWNED"
const REFUSED := "REFUSED"
const SOURCE := "res://data/story/ch1_kasa.json"
const TERMINAL := "main_terminal_results_v1"
const CONTINUATION := "main_flags_continuation_v1"
const RESULT_CONTINUATION := "main_source_results_continuation_v1"
const CONTINUATION_POLICIES := [CONTINUATION, RESULT_CONTINUATION]
const MAX_ROUTE_NODES := 64
# Immutable 5a migration adapter, not a catalog role or a new effects permit.
const MIGRATION := "res://data/story_contracts/migration-5a.json"
const MIGRATION_BYTES := 141463
const MIGRATION_SHA := "e86b82e0a7e5d9f6988290cb7b61eb55f7459849901771d6bc95848acf93a8c8"
var revision := 0
var _path: String
var _records: Dictionary = {}
var _covered: Dictionary = {}
var _error := ""
var _stamp := ""
var _reported: Dictionary = {}
var _migration: Dictionary = {}
var _migration_error := ""
var _protected: Dictionary = {}

func _init(path: String = ROOT) -> void:
	_path = path
	reload()

func reload() -> void:
	for id: String in _records: _protected[id] = true
	_load_migration()
	var staged := {}
	var covered := {}
	_error = ""
	_reported.clear()
	var root := _read(_path)
	if _error.is_empty() and not _keys(root, ["version", "chapters"]): _error = _path + ": expected version/chapters"
	if _error.is_empty() and not StoryTransactionData.integer_in(root["version"], 1, 1): _error = _path + "/version: expected 1"
	if _error.is_empty() and (not root["chapters"] is Array or root["chapters"].is_empty()): _error = _path + "/chapters: expected nonempty array"
	if _error.is_empty():
		for i in root["chapters"].size():
			var entry: Variant = root["chapters"][i]
			var where := _path + "/chapters/%d" % i
			if not _keys(entry, ["source", "path"]) or not _project_path(entry.get("source"), ".json") or _child_path(entry.get("path")).is_empty():
				_error = where + ": expected source/path JSON resources"; break
			if covered.has(entry["source"]): _error = where + "/source: duplicate coverage"; break
			covered[entry["source"]] = true
			var child_path := _child_path(entry["path"])
			var chapter := _read(child_path)
			if not _error.is_empty(): break
			if not _keys(chapter, ["version", "records"]) or not StoryTransactionData.integer_in(chapter.get("version"), 1, 1) or not chapter.get("records") is Array or chapter["records"].is_empty():
				_error = child_path + ": expected version 1 and nonempty records"; break
			for j in chapter["records"].size():
				var raw: Variant = chapter["records"][j]
				where = child_path + "/records/%d" % j
				var problem := _record_problem(raw)
				if not problem.is_empty(): _error = where + problem; break
				if raw["source"] != entry["source"]: _error = where + "/source: differs from manifest"; break
				if staged.has(raw["id"]): _error = where + "/id: duplicate " + raw["id"]; break
				staged[raw["id"]] = raw.duplicate(true)
			if not _error.is_empty(): break
	if _error.is_empty():
		for id: String in staged:
			var problem := _graph_problem(id, staged, {})
			if not problem.is_empty(): _error = _path + "/records/" + id + problem; break
	var stamp := (_error if not _error.is_empty() else JSON.stringify({"records":staged,"covered":covered,"migration_error":_migration_error}, "", true)).sha256_text()
	if stamp != _stamp: revision += 1
	_stamp = stamp
	_records = staged if _error.is_empty() else {}
	for id: String in _records: _protected[id] = true
	_covered = covered if _error.is_empty() else {}
	_freeze(_records)
	_freeze(_covered)

func inspect(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not _error.is_empty(): return _refused(_error)
	if not _records.has(id):
		var scene: Variant = scenes.get(id, {})
		if scene is Dictionary and (_covered.has(sources.get(id, "")) and _writes(scene) or scene.get("completion_policy", "") in [TERMINAL, CONTINUATION, RESULT_CONTINUATION]):
			return _refused(str(sources.get(id, _path)) + "/scenes/" + id + ": formal result/choice has no independent contract")
		return {"state":NOT_OWNED,"revision":revision}
	var record: Dictionary = _records[id]
	var result := choice_step(id, scenes, sources) if record["role"] == "choice" else boundary(id, scenes, sources)
	if result.is_empty() or (record["role"] == "boundary" and (record["rule"]["policy"] in CONTINUATION_POLICIES or record["rule"].has("failures")) and not _route_valid(id, scenes, sources, {})):
		return _refused(str(record["source"]) + "/scenes/" + id + ": live content differs from independent contract")
	return {"state":MATCH,"revision":revision,"contract":result.duplicate(true)}

func _refused(problem: String) -> Dictionary:
	if not _reported.has(problem) and _reported.size() < 128:
		_reported[problem] = true
		push_error("[StoryContracts] " + problem)
	return {"state":REFUSED,"revision":revision,"error":problem}

func _read(path: String) -> Dictionary:
	# Source JSON stays available in the current export. A remapped resource may
	# legitimately have no raw source entry: retain ResourceLoader for that case.
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: _error = path + ": cannot read JSON source"; return {}
		var length := file.get_length()
		file.close()
		if length > RunSaveCodec.MAX_BYTES: _error = path + ": JSON source exceeds 4 MiB"; return {}
	if not ResourceLoader.exists(path): _error = path + ": missing JSON resource"; return {}
	var json := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as JSON
	if json == null or not json.data is Dictionary: _error = path + ": expected JSON object"; return {}
	var problem := RunSaveCodec.validate_tree(json.data, 32768)
	if not problem.is_empty(): _error = path + ": " + "; ".join(problem); return {}
	if JSON.stringify(json.data).to_utf8_buffer().size() > RunSaveCodec.MAX_BYTES: _error = path + ": JSON data exceeds 4 MiB"; return {}
	return json.data.duplicate(true)

func _child_path(raw: Variant) -> String:
	if not raw is String or raw.is_empty() or raw.length() > 256 or not raw.ends_with(".json") or ".." in raw or "\\" in raw: return ""
	var directory := _path.get_base_dir() + "/"
	if raw.begins_with(directory): return raw
	if ":" in raw or raw.begins_with("/"): return ""
	return directory + raw

static func _keys(raw: Variant, required: Array, optional: Array = []) -> bool:
	if not raw is Dictionary: return false
	for key in required:
		if not raw.has(key): return false
	for key: Variant in raw:
		if not key is String or (not required.has(key) and not optional.has(key)): return false
	return true

static func _project_path(raw: Variant, suffix: String) -> bool:
	return raw is String and raw.begins_with("res://") and raw.ends_with(suffix) and raw.length() <= 256 and not ".." in raw and not "\\" in raw

static func _id(raw: Variant) -> bool:
	return StoryRules._condition_id(raw)

static func _scalar(raw: Variant) -> bool:
	return raw is bool or (raw is String and raw.length() <= StoryConditionTree.MAX_TEXT_LENGTH)

static func _record_problem(raw: Variant) -> String:
	if not _keys(raw, ["id", "source", "npc", "levels", "role", "rule"]): return ": expected exact record fields"
	if not _id(raw["id"]): return "/id: invalid ID"
	if not _project_path(raw["source"], ".json"): return "/source: invalid resource path"
	if not raw["role"] is String or not raw["rule"] is Dictionary: return "/role: expected role string and rule object"
	if not _project_path(raw["npc"], ".tres"): return "/npc: invalid resource path"
	if not raw["levels"] is Array or raw["levels"].is_empty() or raw["levels"].size() > 32: return "/levels: expected 1..32 original Levels"
	var seen := {}
	for level: Variant in raw["levels"]:
		if not _project_path(level, ".tres") or seen.has(level): return "/levels: invalid or duplicate resource path"
		seen[level] = true
	return _rule_problem(raw["role"], raw["rule"])

static func _rule_problem(role: Variant, rule: Variant) -> String:
	if role == "choice":
		if not _keys(rule, ["default", "options"], ["waits"]): return "/rule: expected choice fields"
		if not _id(rule["default"]) or not rule["options"] is Array or rule["options"].size() < 2 or rule["options"].size() > 4: return "/rule/options: expected 2..4 and default"
		var ids := {}
		for i in rule["options"].size():
			var option: Variant = rule["options"][i]
			if not _keys(option, ["id", "target", "flags"], ["when"]) or not _id(option.get("id")) or not option.get("target") is String or (not option["target"].is_empty() and not _id(option["target"])) or not option.get("flags") is Dictionary: return "/rule/options/%d: invalid exact fields" % i
			if ids.has(option["id"]): return "/rule/options/%d/id: duplicate" % i
			ids[option["id"]] = true
			for flag: Variant in option["flags"]:
				if not _id(flag) or not _scalar(option["flags"][flag]): return "/rule/options/%d/flags: expected typed bool/string" % i
			if option.has("when") and (not _keys(option["when"], ["flag", "equals"]) or not _id(option["when"]["flag"]) or not _scalar(option["when"]["equals"])): return "/rule/options/%d/when: unsupported condition" % i
		if not ids.has(rule["default"]): return "/rule/default: not an option"
		if rule.has("waits"):
			if not rule["waits"] is Dictionary: return "/rule/waits: expected index/duration map"
			for index: Variant in rule["waits"]:
				var duration: Variant = rule["waits"][index]
				if not index is String or not index.is_valid_int() or str(int(index)) != index or int(index) < 0 or int(index) >= 64 or not (duration is int or duration is float) or not is_finite(float(duration)) or duration <= 0 or duration > 60: return "/rule/waits: invalid finite authored wait"
		return ""
	if role != "boundary": return "/role: expected boundary/choice"
	if not _keys(rule, ["policy", "then"], ["operations", "flag", "mode", "when", "repeatable", "repeat_condition", "failures", "pending_after"]): return "/rule: unexpected boundary fields"
	if not rule["policy"] is String or rule["policy"] not in [TERMINAL, CONTINUATION, RESULT_CONTINUATION] or not rule["then"] is String or (not rule["then"].is_empty() and not _id(rule["then"])): return "/rule: invalid policy/then"
	if rule.has("mode") and rule["mode"] not in ["animated", "dialogue", "bubbles"]: return "/rule/mode: unsupported"
	if rule.has("flag") and (not rule["flag"] is String or (not rule["flag"].is_empty() and not _id(rule["flag"]))): return "/rule/flag: invalid ID"
	if rule.has("repeatable") and not rule["repeatable"] is bool: return "/rule/repeatable: expected boolean"
	for key: String in ["when", "repeat_condition"]:
		if rule.has(key):
			var problem := StoryRules.condition_error(rule[key])
			if not problem.is_empty(): return "/rule/" + key + problem
			if not _condition_literals(rule[key]): return "/rule/" + key + ": current contract supports typed bool/string literals"
	if rule.has("failures"):
		if not rule["failures"] is Dictionary: return "/rule/failures: expected map"
		for reason: Variant in rule["failures"]:
			if not _id(reason) or not _id(rule["failures"][reason]): return "/rule/failures: invalid ID"
	if rule.has("pending_after") and not _id(rule["pending_after"]): return "/rule/pending_after: invalid ID"
	var operations: Variant = rule.get("operations", [])
	if not operations is Array or operations.size() > 256: return "/rule/operations: expected bounded array"
	for i in operations.size():
		var op: Variant = operations[i]
		if not op is Dictionary or not _id(op.get("id")): return "/rule/operations/%d: invalid operation" % i
		var kind: Variant = op.get("kind")
		if kind == "flag":
			if not _keys(op, ["kind", "id", "value"]) or not _scalar(op["value"]): return "/rule/operations/%d: invalid typed flag" % i
		elif kind == "item_transfer":
			if not _keys(op, ["kind", "id", "destination"]) or not _id(op["destination"]): return "/rule/operations/%d: invalid transfer" % i
		elif kind in ["transaction", "item_acquire"]:
			if not _keys(op, ["kind", "id"]): return "/rule/operations/%d: unexpected fields" % i
		else: return "/rule/operations/%d/kind: unsupported capability" % i
	return ""

static func _condition_literals(raw: Dictionary) -> bool:
	if raw.has("equals") and not _scalar(raw["equals"]): return false
	for op: String in ["all", "any"]:
		if raw.has(op):
			for child: Dictionary in raw[op]:
				if not _condition_literals(child): return false
	return _condition_literals(raw["not"]) if raw.has("not") else true

static func _graph_problem(id: String, records: Dictionary, visiting: Dictionary) -> String:
	if visiting.has(id): return ": cyclic route" if visiting[id] == 1 else ""
	if visiting.size() >= MAX_ROUTE_NODES: return ": route exceeds 64"
	visiting[id] = 1
	var record: Dictionary = records[id]
	var rule: Dictionary = record["rule"]
	var targets: Array = []
	if record["role"] == "choice":
		for option: Dictionary in rule["options"]:
			if not option["target"].is_empty(): targets.append(option["target"])
	else:
		if not rule["then"].is_empty(): targets.append(rule["then"])
		for target: Variant in rule.get("failures", {}).values(): targets.append(target)
	for target: String in targets:
		if not records.has(target): return ": missing route " + target
		if records[target]["npc"] != record["npc"] or records[target]["levels"] != record["levels"] or records[target]["source"] != record["source"]: return ": foreign NPC route " + target
		var problem := _graph_problem(target, records, visiting)
		if not problem.is_empty(): return problem
	visiting[id] = 2
	return ""

static func _freeze(raw: Variant) -> void:
	if raw is Dictionary:
		for value: Variant in raw.values(): _freeze(value)
		raw.make_read_only()
	elif raw is Array:
		for value: Variant in raw: _freeze(value)
		raw.make_read_only()

static func _writes(scene: Dictionary) -> bool:
	if not RunSaveCodec.validate_tree(scene, 32768).is_empty(): return true
	if scene.has("completion_policy"): return true
	for entry: Dictionary in StoryRules.entries(scene):
		for key: String in ["results", "set_flags", "transfer_items"]:
			var raw: Variant = entry.get(key, [])
			if not (raw is Array or raw is Dictionary) or not raw.is_empty(): return true
	return false

func owns_choice(id: String) -> bool:
	return _records.has(id) and _records[id]["role"] == "choice"

func _choice_rule(id: String) -> Dictionary:
	return _records[id]["rule"] if owns_choice(id) else {}

func _boundary_rule(id: String) -> Dictionary:
	return _records[id]["rule"] if _records.has(id) and _records[id]["role"] == "boundary" else {}

func npc_source(id: String) -> Dictionary:
	return {"npc":_records[id]["npc"],"levels":_records[id]["levels"].duplicate()} if _records.has(id) else {}

func authored_source(id: String) -> String:
	return _records[id]["source"] if _records.has(id) else SOURCE

func _loaded(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var scene: Variant = scenes.get(id)
	if not _text_equals(sources.get(id), authored_source(id)) or not scene is Dictionary or not RunSaveCodec.validate_tree(scene, 32768).is_empty():
		return {}
	return scene


func _empty_array(data: Dictionary, key: String) -> bool:
	var value: Variant = data.get(key, [])
	return value is Array and value.is_empty()


func _text_equals(raw: Variant, expected: String) -> bool:
	return typeof(raw) in [TYPE_STRING, TYPE_STRING_NAME] and String(raw) == expected


func _value_equals(raw: Variant, expected: Variant) -> bool:
	return (raw is bool and raw == expected) if expected is bool else (expected is String and _text_equals(raw, expected))

func _option_condition(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size():
		return false
	for key: String in expected:
		if not _value_equals(raw.get(key), expected[key]):
			return false
	return true

func _condition_matches(raw: Variant, expected: Variant, depth := 0) -> bool:
	if depth > 16: return false
	if expected is Dictionary:
		if not raw is Dictionary or raw.size() != expected.size(): return false
		for key: String in expected:
			if not raw.has(key) or not _condition_matches(raw[key], expected[key], depth + 1): return false
		return true
	if expected is Array:
		if not raw is Array or raw.size() != expected.size(): return false
		for i in expected.size():
			if not _condition_matches(raw[i], expected[i], depth + 1): return false
		return true
	return _value_equals(raw, expected)

func _flags_match(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size():
		return false
	for key: String in expected:
		if not raw.has(key) or not _value_equals(raw[key], expected[key]):
			return false
	return true


func _operations_match(raw: Variant, expected: Array) -> bool:
	if not raw is Array or raw.size() != expected.size():
		return false
	for i in expected.size():
		var operation: Variant = raw[i]
		if not operation is Dictionary or operation.size() != expected[i].size():
			return false
		for key: String in expected[i]:
			if not _value_equals(operation.get(key), expected[i][key]):
				return false
	return true


func boundary(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var rule := _boundary_rule(id)
	if rule.is_empty():
		return {}
	var scene := _loaded(id, scenes, sources)
	var operations: Array = rule.get("operations", []).duplicate(true)
	if not str(rule.get("flag", "")).is_empty():
		operations.append({"kind": "flag", "id": rule["flag"], "value": true})
	if not _text_equals(scene.get("completion_policy"), rule["policy"]) or not _text_equals(scene.get("then", ""), rule["then"]) or not _operations_match(scene.get("results", []), operations) or not _empty_array(scene, "set_flags") or not _empty_array(scene, "transfer_items"):
		return {}
	if rule.has("mode") and not _text_equals(scene.get("mode"), rule["mode"]): return {}
	if rule.has("when") and not _condition_matches(scene.get("when", {}), rule["when"]): return {}
	var steps: Variant = scene.get("steps", [])
	if not steps is Array:
		return {}
	for step: Variant in steps:
		if not step is Dictionary or step.get("do") in ["choice", "branch"]:
			return {}
	if rule.get("repeatable", false):
		var expected: Dictionary = rule.get("repeat_condition", {"flag": "ch1_lamp_voice_asked", "equals": true})
		if not _option_condition(scene.get("when"), expected):
			return {}
		if id == "ch1_t_lamp_voice_later" and not operations.is_empty():
			return {}
	if not _option_condition(scene.get("on_failure", {}), rule.get("failures", {})):
		return {}
	return rule


func _option_matches(raw: Variant, expected: Dictionary) -> bool:
	return raw is Dictionary and _text_equals(raw.get("id"), expected["id"]) and _flags_match(raw.get("set_flags", {}), expected["flags"]) and _text_equals(raw.get("target", ""), expected["target"]) and _empty_array(raw, "steps") and _empty_array(raw, "transfer_items") and _option_condition(raw.get("when", {}), expected.get("when", {}))


func _local_choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	var rule := _choice_rule(id)
	if rule.is_empty():
		return {}
	var scene := _loaded(id, scenes, sources)
	if scene.is_empty() or not str(scene.get("then", "")).is_empty() or not _empty_array(scene, "results") or not _empty_array(scene, "set_flags") or not _empty_array(scene, "transfer_items"):
		return {}
	var steps: Variant = scene.get("steps")
	if not steps is Array or steps.is_empty() or steps.size() > 64:
		return {}
	for i in steps.size():
		if not steps[i] is Dictionary:
			return {}
		if i < steps.size() - 1 and steps[i].get("do") not in ["scene", "actor", "say"]:
			var waits: Dictionary = rule.get("waits", {})
			var duration: Variant = steps[i].get("time")
			if steps[i].get("do") != "wait" or not waits.has(str(i)) or not typeof(duration) in [TYPE_INT, TYPE_FLOAT] or duration != waits[str(i)]:
				return {}
	var step: Dictionary = steps.back()
	var options: Variant = step.get("options")
	if not _text_equals(step.get("do"), "choice") or not _text_equals(step.get("default"), rule["default"]) or not options is Array or options.size() != rule["options"].size():
		return {}
	for i in options.size():
		var expected: Dictionary = rule["options"][i]
		if not _option_matches(options[i], expected):
			return {}
	return step


## One bounded, memoized authored graph; gray nodes reject cycles. Metadata is
## registered here rather than inferred from arbitrary loaded story payloads.
func _route_valid(id: String, scenes: Dictionary, sources: Dictionary, visits: Dictionary) -> bool:
	if visits.has(id):
		return visits[id] == 2
	if visits.size() >= MAX_ROUTE_NODES or npc_source(id).is_empty():
		return false
	visits[id] = 1
	var targets: Array = []
	if owns_choice(id):
		if _local_choice_step(id, scenes, sources).is_empty():
			return false
		for option: Dictionary in _choice_rule(id)["options"]:
			if not option["target"].is_empty():
				targets.append(option["target"])
	else:
		var rule := boundary(id, scenes, sources)
		if rule.is_empty():
			return false
		if not rule["then"].is_empty():
			targets.append(rule["then"])
		for target: String in rule.get("failures", {}).values():
			targets.append(target)
	for target: String in targets:
		if npc_source(id) != npc_source(target) or not _route_valid(target, scenes, sources, visits):
			return false
	visits[id] = 2
	return true

func choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	return _local_choice_step(id, scenes, sources) if _route_valid(id, scenes, sources, {}) else {}

func repeatable(id: String, scenes: Dictionary, sources: Dictionary) -> bool:
	return boundary(id, scenes, sources).get("repeatable", false)

func failure(id: String, reason: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	var rule := boundary(id, scenes, sources)
	if not _route_valid(id, scenes, sources, {}):
		return &""
	return StringName(rule.get("failures", {}).get(reason, ""))

## Only two result-free goodbyes outlive their producer's dispatcher phase.
## The original data, same original talk entry and prior committed producer are
## required. Live source, spawn, index and eligibility remain caller checks.

func choice(id: String, option: Dictionary, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if not RunSaveCodec.validate_tree(option, 32768).is_empty():
		return {}
	var step := choice_step(id, scenes, sources)
	if step.is_empty():
		return {}
	var rule := _choice_rule(id)
	for i in rule["options"].size():
		var expected: Dictionary = rule["options"][i]
		if not _option_matches(option, expected):
			continue
		var operations: Array = []
		for flag: String in expected["flags"]:
			operations.append({"kind": "flag", "id": flag, "value": expected["flags"][flag]})
		return {"when": scenes[id].get("when", {}), "results": operations, "target": expected["target"], "option": step["options"][i], "return": expected["target"].is_empty()}
	return {}


func continuation(id: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	var rule := boundary(id, scenes, sources)
	if rule.is_empty() or rule["policy"] not in CONTINUATION_POLICIES or not _route_valid(id, scenes, sources, {}):
		return &""
	return StringName(rule["then"])


func _load_migration(path: String = MIGRATION) -> void:
	_migration = {}
	_migration_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_migration_error = path + ": sealed migration index missing"
		return
	if file.get_length() != MIGRATION_BYTES:
		file.close(); _migration_error = path + ": sealed migration size differs"; return
	var bytes := file.get_buffer(MIGRATION_BYTES)
	file.close()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != MIGRATION_SHA:
		_migration_error = path + ": sealed migration SHA differs"; return
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not raw is Dictionary or not _keys(raw,["version","base","protected","legacy","routes"]):
		_migration_error = path + ": sealed migration parse failed"; return
	_migration = raw
	for id: String in _migration["protected"]: _protected[id] = true
	_freeze(_migration)

func _legacy_match(id: String, origin: Dictionary, scenes: Dictionary, sources: Dictionary) -> bool:
	if not _migration_error.is_empty() or _protected.has(id) or not _migration.get("legacy",{}).has(id): return false
	var expected: Dictionary = _migration["legacy"][id]
	if sources.get(id) != expected["source"] or not scenes.get(id) is Dictionary or not RunSaveCodec.validate_tree(scenes[id],32768).is_empty() or not _projection_equal(_effects(scenes[id]),expected["effects"]): return false
	for binding: Dictionary in expected["origins"]:
		if not _projection_equal(origin,binding): continue
		var graph: Dictionary = _migration["routes"][binding["entry"]]
		for node: String in graph:
			if sources.get(node) != graph[node]["source"] or not scenes.get(node) is Dictionary or not RunSaveCodec.validate_tree(scenes[node],32768).is_empty() or not _projection_equal(_effects(scenes[node]),graph[node]["effects"]): return false
		return true
	return false

static func _projection_equal(actual: Variant, expected: Variant) -> bool:
	if expected is bool: return actual is bool and actual == expected
	if expected is String: return actual is String and actual == expected
	if expected is int or expected is float: return (actual is int or actual is float) and is_finite(float(actual)) and actual == expected
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size(): return false
		for key: String in expected:
			if not actual.has(key) or not _projection_equal(actual[key],expected[key]): return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size(): return false
		for i in expected.size():
			if not _projection_equal(actual[i],expected[i]): return false
		return true
	return actual == null and expected == null

const PURE_STEPS := ["scene","letterbox","camera","actor","pose","move","face","remove","say","narrate","title","fx","sfx","wait","fade"]
const EFFECT_FIELDS := ["when","requires_flag","unless_flag","requires_item","requires_held_item","unless_held_item","requires_transferred_item","results","set_flags","transfer_items","then","on_failure","target","default","completion_policy"]
const CONTAINERS := ["steps","else_steps","options","routes"]

static func _copy(raw: Variant) -> Variant:
	return raw.duplicate(true) if raw is Dictionary or raw is Array else raw

static func _effects(raw: Variant) -> Variant:
	if raw is Array:
		var values: Array = []
		for child: Variant in raw:
			var value: Variant = _effects(child)
			if not (value is Dictionary and value.is_empty()): values.append(value)
		return values
	if not raw is Dictionary: return raw
	var out := {}
	if raw.get("do") in PURE_STEPS:
		for key: String in EFFECT_FIELDS:
			if raw.has(key): out[key] = _copy(raw[key])
		for key: String in CONTAINERS:
			if raw.has(key):
				var children: Variant = _effects(raw[key])
				if not (children is Array and children.is_empty()): out[key] = children
		if not out.is_empty(): out["do"] = raw["do"]
		return out
	for key: String in raw:
		if key in EFFECT_FIELDS:
			out[key] = _copy(raw[key])
		elif key in CONTAINERS:
			var children: Variant = _effects(raw[key])
			if not (children is Array and children.is_empty()): out[key] = children
		elif key == "lines" or key in StoryLocale.VISIBLE_FIELDS or key in ["ja","en","pose_policy","overlay","budget","gallery_order"]:
			continue
		else:
			var translated := false
			for field: String in StoryLocale.VISIBLE_FIELDS:
				if key == field + "_ja" or key == field + "_en": translated = true; break
			if not translated: out[key] = _copy(raw[key])
	return out
