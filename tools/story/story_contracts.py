"""Author adapter for the same independent NPC contracts used by Godot.

No live source authority, effects, resource installation or save writes belong here.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data/story_contracts/catalog.json"
POLICIES = {"main_terminal_results_v1", "main_flags_continuation_v1", "main_source_results_continuation_v1"}


def _pairs(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key {key}")
        out[key] = value
    return out


def _read(path):
    try:
        if path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError("catalog JSON exceeds 4 MiB")
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_pairs,
                          parse_constant=_nonfinite)
        pending, count = [(data, 0)], 0
        while pending:
            raw, depth = pending.pop()
            count += 1
            if count > 32768 or depth > 16:
                raise ValueError("catalog JSON exceeds bounded node/depth limit")
            if isinstance(raw, dict): pending.extend((v, depth + 1) for v in raw.values())
            elif isinstance(raw, list): pending.extend((v, depth + 1) for v in raw)
            elif isinstance(raw, str) and len(raw) > 1024: raise ValueError("catalog JSON text too long")
            elif type(raw) in (int, float) and (abs(raw) > 1000000000 or not math.isfinite(raw)): raise ValueError("catalog JSON numeric value is not bounded finite")
        return data
    except (OSError, ValueError, RecursionError) as error:
        raise ValueError(f"{path}: {error}") from error


def _nonfinite(value):
    raise ValueError(f"nonfinite {value}")


def _keys(raw, required, optional=()):
    return isinstance(raw, dict) and set(required) <= raw.keys() <= set(required) | set(optional)


def _id(raw):
    return isinstance(raw, str) and re.fullmatch(r"[a-z][a-z0-9_.]{0,63}", raw) is not None


def _resource(raw, suffix):
    return isinstance(raw, str) and raw.startswith("res://") and raw.endswith(suffix) and len(raw) <= 256 and ".." not in raw and "\\" not in raw


def _scalar(raw):
    return isinstance(raw, bool) or isinstance(raw, str) and len(raw) <= 256


def _condition(raw, depth=1, budget=None):
    """Same bounded structural scope as runtime; never first-chapter-only IDs."""
    budget = [0] if budget is None else budget
    budget[0] += 1
    if depth > 16 or budget[0] > 256 or not isinstance(raw, dict):
        return False
    if not raw:
        return True
    if set(raw) == {"not"}:
        return _condition(raw["not"], depth + 1, budget)
    for op in ("all", "any"):
        if set(raw) == {op}:
            return isinstance(raw[op], list) and 1 <= len(raw[op]) <= 32 and all(_condition(v, depth + 1, budget) for v in raw[op])
    if _keys(raw, ["flag"], ["equals"]):
        return _id(raw["flag"]) and ("equals" not in raw or _scalar(raw["equals"]))
    if set(raw) == {"item"}:
        return _id(raw["item"])
    if set(raw) == {"receipt", "status"}:
        return _id(raw["receipt"]) and raw["status"] == "recorded"
    return set(raw) == {"account", "equals"} and _id(raw["account"]) and isinstance(raw["equals"], str) and 1 <= len(raw["equals"]) <= 256


def _rule_valid(role, rule):
    if role == "choice":
        if not _keys(rule, ["default", "options"], ["waits"]) or not _id(rule["default"]) or not isinstance(rule["options"], list) or not 2 <= len(rule["options"]) <= 4:
            return False
        ids = set()
        for row in rule["options"]:
            if not _keys(row, ["id", "target", "flags"], ["when"]) or not _id(row["id"]) or row["id"] in ids or not isinstance(row["target"], str) or row["target"] and not _id(row["target"]) or not isinstance(row["flags"], dict):
                return False
            ids.add(row["id"])
            if any(not _id(k) or not _scalar(v) for k, v in row["flags"].items()):
                return False
            if "when" in row and (not _keys(row["when"], ["flag", "equals"]) or not _id(row["when"]["flag"]) or not _scalar(row["when"]["equals"])):
                return False
        if rule["default"] not in ids or not isinstance(rule.get("waits", {}), dict):
            return False
        for index, duration in rule.get("waits", {}).items():
            if not isinstance(index, str) or not index.isascii() or not index.isdecimal() or str(int(index)) != index or not 0 <= int(index) < 64 or type(duration) not in (int, float) or not math.isfinite(duration) or not 0 < duration <= 60:
                return False
        return True
    if role != "boundary" or not _keys(rule, ["policy", "then"], ["operations", "flag", "mode", "when", "repeatable", "repeat_condition", "failures", "pending_after"]):
        return False
    if not isinstance(rule["policy"], str) or rule["policy"] not in POLICIES or not isinstance(rule["then"], str) or rule["then"] and not _id(rule["then"]):
        return False
    if "mode" in rule and rule["mode"] not in ("animated", "dialogue", "bubbles"):
        return False
    if "flag" in rule and (not isinstance(rule["flag"], str) or rule["flag"] and not _id(rule["flag"])) or "repeatable" in rule and not isinstance(rule["repeatable"], bool):
        return False
    if any(key in rule and not _condition(rule[key]) for key in ("when", "repeat_condition")) or "pending_after" in rule and not _id(rule["pending_after"]):
        return False
    failures, operations = rule.get("failures", {}), rule.get("operations", [])
    if not isinstance(failures, dict) or any(not _id(k) or not _id(v) for k, v in failures.items()) or not isinstance(operations, list) or len(operations) > 256:
        return False
    for op in operations:
        if not isinstance(op, dict) or not _id(op.get("id")):
            return False
        kind = op.get("kind")
        if kind == "flag":
            if not _keys(op, ["kind", "id", "value"]) or not _scalar(op["value"]): return False
        elif kind == "item_transfer":
            if not _keys(op, ["kind", "id", "destination"]) or not _id(op["destination"]): return False
        elif kind in ("transaction", "item_acquire"):
            if not _keys(op, ["kind", "id"]): return False
        else:
            return False
    return True


def _check_routes(ident, records, visiting):
    if ident in visiting:
        if visiting[ident] == 1: raise ValueError(f"{ident}: cyclic contract route")
        return
    if len(visiting) >= 64: raise ValueError(f"{ident}: route exceeds 64")
    visiting[ident] = 1
    record, targets = records[ident], []
    rule = record["rule"]
    if record["role"] == "choice": targets = [v["target"] for v in rule["options"] if v["target"]]
    else: targets = ([rule["then"]] if rule["then"] else []) + list(rule.get("failures", {}).values())
    for target in targets:
        if target not in records or any(records[target][key] != record[key] for key in ("source", "npc", "levels")):
            raise ValueError(f"{ident}: missing/foreign contract route {target}")
        _check_routes(target, records, visiting)
    visiting[ident] = 2


def _same(actual, expected):
    if isinstance(expected, bool):
        return isinstance(actual, bool) and actual == expected
    if isinstance(expected, str):
        return isinstance(actual, str) and actual == expected
    if isinstance(expected, (int, float)) and not isinstance(expected, bool):
        return isinstance(actual, (int, float)) and not isinstance(actual, bool) and math.isfinite(actual) and actual == expected
    if isinstance(expected, dict):
        return isinstance(actual, dict) and actual.keys() == expected.keys() and all(_same(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return isinstance(actual, list) and len(actual) == len(expected) and all(_same(a, b) for a, b in zip(actual, expected))
    return actual is expected


def load_records(path: Path | None = None) -> dict:
    """Fresh, all-or-nothing author projection; no process-global stale cache."""
    path = CATALOG if path is None else path
    manifest = _read(path)
    if not isinstance(manifest, dict) or set(manifest) != {"version", "chapters"} or not _same(manifest["version"], 1):
        raise ValueError(f"{path}: expected exact version 1 / chapters")
    if not isinstance(manifest["chapters"], list) or not manifest["chapters"]:
        raise ValueError(f"{path}/chapters: expected nonempty array")
    records, sources = {}, set()
    for index, entry in enumerate(manifest["chapters"]):
        where = f"{path}/chapters/{index}"
        if not isinstance(entry, dict) or set(entry) != {"source", "path"} or not _resource(entry["source"], ".json"):
            raise ValueError(f"{where}: invalid source/path")
        if entry["source"] in sources:
            raise ValueError(f"{where}/source: duplicate")
        sources.add(entry["source"])
        raw_path = entry["path"]
        if not isinstance(raw_path, str) or not raw_path or len(raw_path) > 256 or ".." in raw_path or "\\" in raw_path or not raw_path.startswith("res://") and (":" in raw_path or raw_path.startswith("/")):
            raise ValueError(f"{where}/path: invalid")
        child = ROOT / raw_path.removeprefix("res://") if raw_path.startswith("res://") else path.parent / raw_path
        if child.resolve().parent != path.resolve().parent or child.suffix != ".json":
            raise ValueError(f"{where}/path: child must stay inside contract directory")
        chapter = _read(child)
        if not isinstance(chapter, dict) or set(chapter) != {"version", "records"} or not _same(chapter["version"], 1) or not isinstance(chapter["records"], list) or not chapter["records"]:
            raise ValueError(f"{child}: invalid version/records")
        for i, record in enumerate(chapter["records"]):
            where = f"{child}/records/{i}"
            if not isinstance(record, dict) or set(record) != {"id", "source", "npc", "levels", "role", "rule"} or not isinstance(record.get("id"), str):
                raise ValueError(f"{where}: invalid record fields")
            ident = record["id"]
            if not _id(ident) or ident in records or record["source"] != entry["source"] or not isinstance(record["role"], str) or not _rule_valid(record["role"], record["rule"]):
                raise ValueError(f"{where}: duplicate ID or invalid source/role/rule")
            if not _resource(record["npc"], ".tres") or not isinstance(record["levels"], list) or not 1 <= len(record["levels"]) <= 32 or any(not _resource(v, ".tres") for v in record["levels"]) or len(set(record["levels"])) != len(record["levels"]):
                raise ValueError(f"{where}: missing original NPC/Levels")
            records[ident] = copy.deepcopy(record)
    for ident in records:
        _check_routes(ident, records, {})
    return records


def validate_intent(ident, option, records):
    """Only an exact registered choice may carry these new reversible intents."""
    if not option.intent:
        return ""
    record = records.get(ident, {})
    if record.get("role") != "choice":
        return f"{ident}/{option.id}: intent has no independent NPC choice contract"
    expected = next((row for row in record["rule"]["options"] if row["id"] == option.id), None)
    actual = {op.get("id"): op.get("value", True) for op in option.intent if op.get("kind") == "flag"}
    if expected is None or len(actual) != len(option.intent) or not _same(actual, expected["flags"]):
        return f"{ident}/{option.id}: intent differs from independent typed contract"
    return ""


def apply_policies(scenes, source, records):
    for ident, record in records.items():
        if record["source"] != source:
            continue
        if ident not in scenes:
            raise ValueError(f"{source}/scenes/{ident}: missing registered NPC scene")
        if record["role"] == "boundary":
            previous = scenes[ident].get("completion_policy")
            if previous is not None and previous != record["rule"]["policy"]:
                raise ValueError(f"{source}/scenes/{ident}: declared policy differs from independent contract")
            scenes[ident]["completion_policy"] = record["rule"]["policy"]


def validate_generated(scenes, source, records):
    """Check authored effects against the independent contract, not each other."""
    for ident, record in records.items():
        if record["source"] != source:
            continue
        scene, rule = scenes.get(ident, {}), record["rule"]
        where = f"{source}/scenes/{ident}"
        if not isinstance(scene, dict) or not scene:
            raise ValueError(f"{where}: missing scene")
        if record["role"] == "boundary":
            expected = copy.deepcopy(rule.get("operations", []))
            if rule.get("flag"):
                expected.append({"kind":"flag", "id":rule["flag"], "value":True})
            if not _same(scene.get("results", []), expected) or scene.get("completion_policy") != rule["policy"] or scene.get("then", "") != rule["then"] or scene.get("set_flags") or scene.get("transfer_items"):
                raise ValueError(f"{where}: results/policy/continuation differ from independent contract")
            for key in ("mode", "when"):
                if key in rule and not _same(scene.get(key, {}), rule[key]):
                    raise ValueError(f"{where}/{key}: differs from independent contract")
            if not _same(scene.get("on_failure", {}), rule.get("failures", {})):
                raise ValueError(f"{where}/on_failure: differs from independent contract")
            continue
        steps = scene.get("steps", [])
        if not isinstance(steps, list) or not 1 <= len(steps) <= 64 or not all(isinstance(step, dict) for step in steps) or steps[-1].get("do") != "choice" or scene.get("results") or scene.get("set_flags") or scene.get("transfer_items") or scene.get("then"):
            raise ValueError(f"{where}: expected result-free original choice")
        for i, step in enumerate(steps[:-1]):
            if step.get("do") not in ("scene", "actor", "say") and not (step.get("do") == "wait" and str(i) in rule.get("waits", {}) and type(step.get("time")) in (int, float) and step["time"] == rule["waits"][str(i)]):
                raise ValueError(f"{where}/steps/{i}: unsupported choice prefix")
        choice = steps[-1]
        if choice.get("default") != rule["default"] or len(choice.get("options", [])) != len(rule["options"]):
            raise ValueError(f"{where}: choice/default differs from independent contract")
        for actual, expected in zip(choice["options"], rule["options"]):
            projection = {"id":actual.get("id"), "target":actual.get("target", ""), "flags":actual.get("set_flags", {})}
            wanted = {key:expected[key] for key in ("id", "target", "flags")}
            if not _same(projection, wanted) or not _same(actual.get("when", {}), expected.get("when", {})) or actual.get("steps") or actual.get("transfer_items"):
                raise ValueError(f"{where}/options/{actual.get('id')}: differs from independent contract")


# Sealed migration projection: keep effects/flow, not dialogue or visual poses.
# This does not authorize new scene IDs or add a legacy role to the catalog.
PURE_STEPS = {"scene", "letterbox", "camera", "actor", "pose", "move", "face", "remove", "say", "narrate", "title", "fx", "sfx", "wait", "fade"}
EFFECT_FIELDS = {"when", "requires_flag", "unless_flag", "requires_item", "requires_held_item", "unless_held_item", "requires_transferred_item", "results", "set_flags", "transfer_items", "then", "on_failure", "target", "default", "completion_policy"}
DISPLAY_FIELDS = {"text", "explanation", "title", "subtitle", "end_title", "teaser", "release_note", "end_card", "background", "reward", "blocked_reason", "suggestion", "prompt", "sub"}
CONTAINERS = {"steps", "else_steps", "options", "routes"}


def effect_projection(raw):
    if isinstance(raw, list):
        return [value for child in raw if (value := effect_projection(child)) != {}]
    if not isinstance(raw, dict):
        return copy.deepcopy(raw)
    if raw.get("do") in PURE_STEPS:
        out = {key:copy.deepcopy(raw[key]) for key in EFFECT_FIELDS if key in raw}
        for key in CONTAINERS:
            if key in raw and (children := effect_projection(raw[key])):
                out[key] = children
        if out:
            out["do"] = raw["do"]
        return out
    out = {}
    for key, value in raw.items():
        if key in EFFECT_FIELDS:
            out[key] = copy.deepcopy(value)
        elif key in CONTAINERS:
            children = effect_projection(value)
            if children:
                out[key] = children
        elif key == "lines" or key in DISPLAY_FIELDS or key in {"ja", "en", "pose_policy", "overlay", "budget", "gallery_order"} or any(key == field + "_" + lang for field in DISPLAY_FIELDS for lang in ("ja", "en")):
            continue
        else:
            out[key] = copy.deepcopy(value)
    return out


# Stage-only steps (walking, reaching, props shown or held) never write flags, items or
# results; a move step's "then" is the pose after walking. Matching drops them on both
# sides, so restaging a sealed scene keeps its legacy outcome. Mirrors StoryResultCatalog.
STAGE_ONLY_STEPS = {"move", "reach", "prop", "prop_move", "prop_hold", "prop_release", "prop_visible"}


def without_stage_steps(raw):
    if isinstance(raw, list):
        kept = []
        for child in raw:
            if isinstance(child, dict) and child.get("do") in STAGE_ONLY_STEPS:
                continue
            value = without_stage_steps(child)
            if isinstance(value, dict) and (not value or (len(value) == 1 and value.get("do") in PURE_STEPS)):
                continue
            kept.append(value)
        return kept
    if isinstance(raw, dict):
        out = {}
        for key, value in raw.items():
            if key in CONTAINERS:
                value = without_stage_steps(value)
                if isinstance(value, list) and not value:
                    continue
            out[key] = value
        return out
    return raw


def same_effects(scene, sealed):
    return _same(without_stage_steps(effect_projection(scene)), without_stage_steps(sealed))


# The author may recognize old NPC content, but cannot mint a new legacy role.
MIGRATION = ROOT / "data/story_contracts/migration-5a.json"
MIGRATION_SHA = "e86b82e0a7e5d9f6988290cb7b61eb55f7459849901771d6bc95848acf93a8c8"
BINDING_KINDS = ("npc", "object", "mechanism", "map_scene", "pickup", "stage_interaction", "chapter_handoff")


def validate_author_bindings(source, path):
    """Type/scope declaration only. Runtime actor/spawn proof is still required."""
    npc = set()
    for ident, segment in source.segments.items():
        name = segment.binding
        if not isinstance(name,str):
            raise ValueError(f"{path}/scenes/{ident}: author binding must be text")
        if not name:
            continue  # Later chapters also contain unbound generic scenes.
        binding = source.bindings.get(name) if isinstance(name, str) else None
        if binding is None or getattr(binding, "kind", None) not in BINDING_KINDS:
            raise ValueError(f"{path}/scenes/{ident}: unknown/invalid author binding {name!r}")
        if binding.kind in ("npc", "object"):
            npc.add(ident)
    return npc


def _sealed_migration():
    try:
        with MIGRATION.open("rb") as stream:
            raw = stream.read(141464)
        if len(raw) != 141463 or hashlib.sha256(raw).hexdigest() != MIGRATION_SHA:
            raise ValueError("sealed legacy migration identity differs")
        return json.loads(raw)
    except (OSError, ValueError) as error:
        raise ValueError(f"{MIGRATION}: {error}") from error


def _has_effects(raw):
    pending, nodes = [raw], 0
    while pending:
        value = pending.pop(); nodes += 1
        if nodes > 32768: raise ValueError("author scene exceeds bounded node limit")
        if isinstance(value, dict):
            if any(key in value and (not isinstance(value[key], (dict, list, tuple)) or value[key]) for key in ("results", "set_flags", "transfer_items")):
                return True
            pending.extend(v for key,v in value.items() if key not in ("when", "on_failure"))
        elif isinstance(value, (list, tuple)):
            pending.extend(value)
    return False


def _flow_targets(scene):
    pending, targets, nodes = [scene], set(), 0
    while pending:
        value = pending.pop(); nodes += 1
        if nodes > 32768: raise ValueError("author route exceeds bounded node limit")
        if isinstance(value, dict):
            for key in ("target", "then"):
                if isinstance(value.get(key), str) and value[key]: targets.add(value[key])
            if isinstance(value.get("on_failure"), dict): targets.update(v for v in value["on_failure"].values() if isinstance(v,str) and v)
            pending.extend(v for key,v in value.items() if key in ("steps", "else_steps", "routes", "options"))
        elif isinstance(value, (list, tuple)):
            pending.extend(value)
    return targets


def validate_npc_declarations(scenes, path, author, records, entry_ids):
    """Finite compiler gate; no writer permission or inferred generic ownership."""
    roots = validate_author_bindings(author,path)
    migration = _sealed_migration()
    legacy = {ident:row for ident,row in migration["legacy"].items() if row["source"] == path}
    known = {ident for ident,row in records.items() if row["source"] == path} | set(legacy)
    known.update(ident for ident in migration["protected"] if ident in scenes)
    roots.update(known)
    # These are the actual generator's dispatch entries. A known NPC phase or a
    # declared NPC Binding identifies its entry without guessing by ID/speaker.
    for binding, entry in entry_ids.items():
        descriptor = author.bindings.get(binding)
        if descriptor is not None and descriptor.kind in ("npc", "object") or _flow_targets(scenes.get(entry,{})) & known:
            roots.add(entry)
    roots.update(entry for entry,graph in migration["routes"].items() if entry in scenes and all(row["source"]==path for row in graph.values()))
    scope = set()
    for root in roots:
        pending, visited = [root], set()
        while pending:
            ident = pending.pop()
            if ident in visited or ident not in scenes: continue
            visited.add(ident)
            if len(visited) > 64: raise ValueError(f"{path}/scenes/{root}: NPC entry exceeds 64 scenes")
            pending.extend(_flow_targets(scenes[ident]) - visited)
        scope.update(visited)
    accepted_legacy = []
    for ident in sorted(scope):
        if not _has_effects(scenes[ident]) or ident in records: continue
        previous = legacy.get(ident)
        if previous is None:
            raise ValueError(f"{path}/scenes/{ident}: NPC effects/intent require an independent catalog contract")
        if not same_effects(scenes[ident],previous["effects"]):
            raise ValueError(f"{path}/scenes/{ident}: legacy effects differ from sealed migration")
        segment = author.segments.get(ident)
        origins = previous["origins"]
        if segment is not None and segment.binding:
            entry = entry_ids.get(segment.binding)
            binding = author.bindings[segment.binding]
            origins = [origin for origin in origins if origin["entry"] == entry and origin["npc"] == binding.source]
        accepted_legacy.append((ident,origins))
    for ident,origins in accepted_legacy:
        if not any(all(name in scenes and same_effects(scenes[name],row["effects"]) for name,row in migration["routes"][origin["entry"]].items()) for origin in origins):
            raise ValueError(f"{path}/scenes/{ident}: legacy entry projection differs from sealed migration")
