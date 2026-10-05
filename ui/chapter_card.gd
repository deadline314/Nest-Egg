class_name ChapterCard
extends CanvasLayer
## 章節標題卡：淡入、停留、淡出後自行釋放。block = true 時暫停遊戲並蓋黑底（章節結束用）。

signal finished

const FADE := 0.6

var title := ""
var subtitle := ""
var hold := 2.2
var block := false

var _root: Control
var _lock_token := 0


func _ready() -> void:
	layer = UiLayers.CHAPTER_CARD
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)
	if block:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.92)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(shade)
		_lock_token = GameplayLock.acquire(self)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.position = Vector2(-220, -40)
	box.custom_minimum_size = Vector2(440, 80)
	_root.add_child(box)
	box.add_child(UiKit.label(title, 22, LightKit.glow(Palette.MAGENTA, 1.4), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label(subtitle, 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var tween := create_tween()
	# 開場標題卡遇到暫停（暫停選單、背包）就凍結並藏起來；章節結束卡本身就是暫停，照常播放。
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS if block else Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(_root, "modulate:a", 1.0, FADE)
	tween.tween_interval(hold)
	tween.tween_property(_root, "modulate:a", 0.0, FADE)
	tween.tween_callback(_done)


func _process(_delta: float) -> void:
	_root.visible = block or not get_tree().paused


func _input(_event: InputEvent) -> void:
	if _lock_token != 0:
		get_viewport().set_input_as_handled()


func _done() -> void:
	GameplayLock.release(_lock_token)
	_lock_token = 0
	finished.emit()
	queue_free()
