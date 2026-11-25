extends Node2D
## Shows the authored warning over one removable cover during its rehearsal.
## Collision and progression remain owned by the cover's published story flag.

const SWEEP_SECONDS := 1.1

var scene_id := &""
var size := Vector2.ZERO
var _progress := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LightKit.mark_emissive(self)
	Story.scene_started.connect(_on_scene_started)
	Story.scene_finished.connect(_on_scene_finished)
	Story.presentation_cancelled.connect(_on_cancelled)
	set_process(false)


func _on_scene_started(id: StringName, _mode: StringName) -> void:
	if id != scene_id:
		return
	var reduced := Settings.get_reduce_ui_motion()
	_progress = 0.5 if reduced else 0.0
	set_process(not reduced)
	queue_redraw()


func _on_scene_finished(id: StringName) -> void:
	if id == scene_id:
		_clear()


func _on_cancelled(id: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void:
	_on_scene_finished(id)


func _clear() -> void:
	_progress = -1.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_progress = minf(1.0, _progress + delta / SWEEP_SECONDS)
	if _progress == 1.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _progress < 0.0:
		return
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
	var y := lerpf(rect.position.y, rect.end.y, _progress)
	draw_rect(rect, Color(1.0, 0.68, 0.22, 0.65), false, 1.0)
	draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Palette.WARNING, 2.0)
