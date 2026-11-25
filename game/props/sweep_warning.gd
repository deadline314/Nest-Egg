extends Node2D
## Shows the authored warning over one removable cover during its rehearsal.
## Collision and progression remain owned by the cover's published story flag.

const SweepPresentation = preload("res://game/hazards/sweep_presentation.gd")
const SWEEP_SECONDS := 1.1

var scene_id := &""
var size := Vector2.ZERO
var _progress := -1.0
var _step := -1


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
	_step = SweepPresentation.scan_step(_progress, reduced)
	set_process(not reduced)
	queue_redraw()


func _on_scene_finished(id: StringName) -> void:
	if id == scene_id:
		_clear()


func _on_cancelled(id: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void:
	_on_scene_finished(id)


func _clear() -> void:
	_progress = -1.0
	_step = -1
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_progress = minf(1.0, _progress + delta / SWEEP_SECONDS)
	if _progress == 1.0:
		set_process(false)
	var step := SweepPresentation.scan_step(_progress, Settings.get_reduce_ui_motion())
	if step != _step:
		_step = step
		queue_redraw()


func _draw() -> void:
	if _step < 0:
		return
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
	SweepPresentation.draw_warning(self, rect, _step, true)
