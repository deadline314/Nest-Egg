class_name PlayerInteraction
extends Node
## 地圖交談／閱讀的呈現生命週期。裝備與遊戲狀態不隨收起外觀改變。

signal changed

var player: Player
var active := false
var _scene: StringName = &""


func _enter_tree() -> void:
	Story.scene_started.connect(_started)
	Story.scene_finished.connect(_finished)
	Story.presentation_cancelled.connect(_cancelled)
	player.health.damaged.connect(_damaged)
	if Story.is_cinematic_active():
		_started(Story._current_cinematic, Story.scene_mode(Story._current_cinematic))


func _exit_tree() -> void:
	Story.scene_started.disconnect(_started)
	Story.scene_finished.disconnect(_finished)
	Story.presentation_cancelled.disconnect(_cancelled)
	player.health.damaged.disconnect(_damaged)
	_end()


func _started(id: StringName, _mode: StringName) -> void:
	if not is_inside_tree():
		return
	var source := str(Story.current_presentation_context().get("framing_source", ""))
	var mode := Story.scene_mode(id)
	var map_overlay := mode == Story.MODE_DIALOGUE or mode == Story.MODE_CINEMATIC \
		or (mode == Story.MODE_ANIMATED and not Story.uses_cinematic_framing(id))
	if source not in ["person", "object"] or not map_overlay or player.is_dead() or player.is_on_phone():
		return
	_scene = id
	active = true
	player._visual.set_interacting(true)
	player._weapon_light.extinguish()
	changed.emit()


func _finished(id: StringName) -> void:
	if id == _scene:
		_end()


func _cancelled(id: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void:
	_finished(id)


func _damaged(_info: DamageInfo) -> void:
	if active:
		Story.reset_active_presentation(&"damage")


func _end() -> void:
	if not active:
		return
	_scene = &""
	active = false
	player._visual.set_interacting(false)
	changed.emit()
