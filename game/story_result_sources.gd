extends RefCounted
## Compatibility facade. Catalog matching never replaces Main's actual producer.
const Catalog := preload("res://core/story_result_catalog.gd")
const Clinic := preload("res://game/story_result_clinic.gd")
const Flags := preload("res://game/story_flag_sources.gd")
const SOURCE := "res://data/story/ch1_kasa.json"
const TERMINAL := Catalog.TERMINAL
const CONTINUATION := Catalog.CONTINUATION
const RESULT_CONTINUATION := Catalog.RESULT_CONTINUATION
const CONTINUATION_POLICIES := Catalog.CONTINUATION_POLICIES
const MAX_ROUTE_NODES := Catalog.MAX_ROUTE_NODES
const BOUNDARIES := {
  "ch1_b_dinner_food": {
    "policy": "main_terminal_results_v1",
    "then": "",
    "mode": "bubbles",
    "when": {},
    "operations": [
      {
        "kind": "transaction",
        "id": "ch1.daily_dinner"
      },
      {
        "kind": "flag",
        "id": "ch1_dinner_done",
        "value": true
      }
    ]
  }
}
static var _catalog

static func _catalog_instance():
	if _catalog == null: _catalog = Catalog.new()
	return _catalog

static func reload_catalog() -> bool:
	var previous := revision()
	_catalog_instance().reload()
	return previous != revision()

static func revision() -> int:
	return int(_catalog_instance().revision)

static func inspect(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if _catalog_instance()._protected.has(id): return _catalog_instance().inspect(id, scenes, sources)
	# These remain subject to their original live owners, never catalog metadata.
	if Clinic.owns(id) or Flags.owns(id) or BOUNDARIES.has(id):
		return {"state":Catalog.NOT_OWNED,"revision":revision()}
	var scene: Variant = scenes.get(id, {})
	if scene is Dictionary and (scene.get("completion_policy", "") == "main_flags_v1" or (scene.get("mode") == "radio" and scene.get("freeze", false) == true and scene.get("results", []) is Array and scene.get("results", []).is_empty() and scene.get("transfer_items", []) is Array and scene.get("transfer_items", []).is_empty())):
		return {"state":Catalog.NOT_OWNED,"revision":revision()}
	return _catalog_instance().inspect(id, scenes, sources)

static func owns_choice(id: String) -> bool:
	return _catalog_instance().owns_choice(id)

static func owns_boundary(id: String) -> bool:
	return Clinic.owns(id) or BOUNDARIES.has(id) or not _catalog_instance()._boundary_rule(id).is_empty()

static func npc_source(id: String) -> Dictionary:
	return _catalog_instance().npc_source(id)

static func authored_source(id: String) -> String:
	return _catalog_instance().authored_source(id)

static func boundary(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	if Clinic.owns(id): return Clinic.boundary(id, scenes, sources)
	if not BOUNDARIES.has(id): return _catalog_instance().boundary(id, scenes, sources).duplicate(true)
	var rule: Dictionary = BOUNDARIES[id]
	var scene: Dictionary = _catalog_instance()._loaded(id, scenes, sources)
	if scene.is_empty() or not _catalog_instance()._text_equals(scene.get("completion_policy"), rule["policy"]) or not _catalog_instance()._text_equals(scene.get("then", ""), rule["then"]) or not _catalog_instance()._operations_match(scene.get("results", []), rule["operations"]) or not _catalog_instance()._empty_array(scene, "set_flags") or not _catalog_instance()._empty_array(scene, "transfer_items") or not _catalog_instance()._text_equals(scene.get("mode"), rule["mode"]): return {}
	for step: Variant in scene.get("steps", []):
		if not step is Dictionary or step.get("do") in ["choice", "branch"]: return {}
	return rule.duplicate(true)

static func choice_step(id: String, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	return _catalog_instance().choice_step(id, scenes, sources).duplicate(true)

static func choice(id: String, option: Dictionary, scenes: Dictionary, sources: Dictionary) -> Dictionary:
	return _catalog_instance().choice(id, option, scenes, sources).duplicate(true)

static func continuation(id: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	return Clinic.continuation(id, scenes, sources) if Clinic.owns(id) else _catalog_instance().continuation(id, scenes, sources)

static func repeatable(id: String, scenes: Dictionary, sources: Dictionary) -> bool:
	return boundary(id, scenes, sources).get("repeatable", false)

static func failure(id: String, reason: String, scenes: Dictionary, sources: Dictionary) -> StringName:
	return _catalog_instance().failure(id, reason, scenes, sources)

static func pending_terminal(npc_path: String, entry: StringName, id: String, scenes: Dictionary, sources: Dictionary, completed: Dictionary) -> bool:
	if entry != &"ch1_dispatch_ali_stall" or npc_path != npc_source(id).get("npc", "") or completed.has(StringName(id)) or _catalog_instance()._loaded(String(entry), scenes, sources).is_empty(): return false
	var rule := boundary(id, scenes, sources)
	var previous: String = rule.get("pending_after", "")
	return not previous.is_empty() and completed.has(StringName(previous)) and continuation(previous, scenes, sources) == StringName(id) and _catalog_instance()._route_valid(id, scenes, sources, {})


## Caller selection only. The live Main computes origin; metadata never grants
## a producer. A sealed original legacy route is selected before catalog inspect.
static func _route(id: String, scenes: Dictionary, sources: Dictionary, origin: Dictionary) -> Dictionary:
	var catalog = _catalog_instance()
	if catalog._protected.has(id): return catalog.inspect(id,scenes,sources)
	if Clinic.owns(id) or Flags.owns(id) or BOUNDARIES.has(id): return {"state":Catalog.NOT_OWNED}
	var scene: Variant = scenes.get(id,{})
	if not scene is Dictionary: return catalog._refused(str(sources.get(id,"")) + "/scenes/" + id + ": malformed scene")
	if scene.get("completion_policy","") == "main_flags_v1" or (scene.get("mode") == "radio" and scene.get("freeze",false) == true and scene.get("results",[]) is Array and scene.get("results",[]).is_empty() and scene.get("transfer_items",[]) is Array and scene.get("transfer_items",[]).is_empty()): return {"state":Catalog.NOT_OWNED}
	if not catalog._writes(scene): return {"state":Catalog.NOT_OWNED}
	if scene.get("completion_policy","") in [TERMINAL,CONTINUATION,RESULT_CONTINUATION]: return catalog.inspect(id,scenes,sources)
	if not catalog._error.is_empty() and not catalog._migration_error.is_empty(): return catalog._refused(catalog._error + "; " + catalog._migration_error)
	if origin.get("kind") == "none": return {"state":Catalog.NOT_OWNED}
	if origin.get("kind") != "npc": return catalog._refused(str(sources.get(id,"")) + "/scenes/" + id + ": " + str(origin.get("error","invalid actual NPC origin")))
	# Unmanaged chapter writers are unchanged; this is not a chapter coordinator.
	if catalog._error.is_empty() and not catalog._covered.has(sources.get(id,"")): return {"state":Catalog.NOT_OWNED}
	if catalog._legacy_match(id,origin["metadata"],scenes,sources): return {"state":Catalog.NOT_OWNED}
	return catalog._refused(str(sources.get(id,"")) + "/scenes/" + id + ": NPC effects need an independent supported contract; " + catalog._migration_error)
