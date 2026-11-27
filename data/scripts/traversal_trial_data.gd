extends Resource
## Typed boundaries for a time-limited optional route inside one area.

@export var start_source: StringName
@export var arrival_source: StringName
@export var normal_scene: StringName
@export var guided_scene: StringName
@export var gate_flag: StringName
@export var resolved_flag: StringName
@export var start_cell: Vector2i
@export_range(2.0, 120.0, 0.5) var normal_seconds := 20.0
@export_range(2.0, 180.0, 0.5) var guided_seconds := 60.0
@export_file("*.json") var text_path: String


func problem(layout: LevelLayout) -> String:
	if start_source.is_empty() or arrival_source.is_empty() or start_source == arrival_source:
		return "expected separate start and arrival NPC sources"
	if not Story.has_scene(normal_scene) or not Story.has_scene(guided_scene) or normal_scene == guided_scene:
		return "missing or repeated route entry scenes"
	if gate_flag.is_empty() or resolved_flag.is_empty() or gate_flag == resolved_flag:
		return "expected separate route gate and result flags"
	if start_cell.x <= 0 or start_cell.x >= layout.width - 1 or start_cell.y < 0 or start_cell.y >= layout.height - 1:
		return "start cell is outside the room"
	if not is_finite(normal_seconds) or not is_finite(guided_seconds) or normal_seconds < 2.0 \
			or guided_seconds < normal_seconds or guided_seconds > 180.0:
		return "invalid route deadlines"
	var file := FileAccess.open(text_path, FileAccess.READ) if FileAccess.file_exists(text_path) else null
	if file == null or file.get_length() > 8192:
		return "missing route text: " + text_path
	return ""
