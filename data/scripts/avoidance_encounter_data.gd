extends Resource
## Authored lane coordinates in tile columns, with the standing height from the layout.

@export var id: StringName
@export var rig_id: String
@export var home_column: int
@export var retry_column: int
@export var start_column: int
@export var coat_npc: StringName
@export var coat_prop: StringName
@export var identified: StringName
@export var actions: Array[Dictionary]
@export_file("*.json") var text_path: String

var _localized: Dictionary = {}


func problem(layout: LevelLayout) -> String:
	if _localized.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(text_path)) if FileAccess.file_exists(text_path) else null
		if not raw is Dictionary or raw.is_empty():
			return "missing localized copy at %s" % text_path
		_localized = raw
	if id == &"" or rig_id.is_empty() or coat_npc == &"" or coat_prop == &"" or identified == &"":
		return "missing encounter, rig, or coat identifier"
	if not (0 < retry_column and retry_column < start_column and start_column < home_column and home_column < layout.width - 6):
		return "columns must place the retry point behind the start and leave a clear commitment lane"
	if actions.size() != 4:
		return "expected two actions per phase"
	for action: Dictionary in actions:
		if str(action.get("kind")) not in ["grab", "rope", "smoke", "block"] or str(action.get("gesture")).is_empty():
			return "unrecognized action or missing gesture"
		for field in ["tell", "commit", "reach"]:
			var value: Variant = action.get(field)
			if not value is float and not value is int or not is_finite(float(value)) or float(value) <= 0.0:
				return "action %s needs a positive finite %s" % [action.get("kind"), field]
		if float(action["tell"]) > 3.0 or float(action["commit"]) > 2.0 or float(action["reach"]) > layout.tile_size * 5.0:
			return "action exceeds encounter bounds"
	return ""


func copy_for(key: String, language: String) -> String:
	var translations: Variant = _localized.get(key)
	if not translations is Dictionary:
		return ""
	return str(translations.get(language if language != "zh" else "text", translations.get("text", "")))
