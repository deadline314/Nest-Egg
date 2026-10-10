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
var _tween: Tween
var _presentation_suspended := false
var _title_label: Label
var _subtitle_label: Label
var _title_extent := Vector2.ZERO
var _subtitle_extent := Vector2.ZERO


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
	_title_label = UiKit.label(title, 22, LightKit.glow(Palette.MAGENTA, 1.4), HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle_label = UiKit.label(subtitle, 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title_label)
	box.add_child(_subtitle_label)
	_title_label.resized.connect(_refresh_title_extent)
	_title_label.theme_changed.connect(_refresh_title_extent)
	_subtitle_label.resized.connect(_refresh_subtitle_extent)
	_subtitle_label.theme_changed.connect(_refresh_subtitle_extent)
	_refresh_title_extent()
	_refresh_subtitle_extent()
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	_tween = create_tween()
	# 開場標題卡遇到暫停（暫停選單、背包）就凍結並藏起來；章節結束卡本身就是暫停，照常播放。
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS if block else Tween.TWEEN_PAUSE_STOP)
	_tween.tween_property(_root, "modulate:a", 1.0, FADE)
	_tween.tween_interval(hold)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE)
	_tween.tween_callback(_done)
	_update_presentation()


func _refresh_title_extent() -> void:
	_title_extent = _readable_label_extent(_title_label)


func _refresh_subtitle_extent() -> void:
	_subtitle_extent = _readable_label_extent(_subtitle_label)


func _readable_label_extent(label: Label) -> Vector2:
	if not is_instance_valid(label):
		return Vector2.ZERO
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0 or label.text.is_empty():
		return Vector2.ZERO
	var width := 0.0
	var lines := label.text.split("\n")
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return Vector2(width, font.get_height(font_size) * maxi(1, lines.size()))


func _label_world_rect(label: Label, extent: Vector2) -> Rect2:
	if not is_instance_valid(label) or extent.x <= 0.0 or extent.y <= 0.0 or not label.is_visible_in_tree():
		return Rect2()
	var local := Rect2(Vector2((label.size.x - extent.x) * 0.5, 0.0), extent)
	var canvas := get_viewport().get_canvas_transform()
	if not is_finite(canvas.determinant()) or is_zero_approx(canvas.determinant()):
		return Rect2()
	return canvas.affine_inverse() * (label.get_global_transform() * local)


func prompt_obstacle_rect() -> Rect2:
	if not is_instance_valid(_root) or not _root.is_visible_in_tree() or not _root.visible \
				or _root.modulate.a <= 0.01:
		return Rect2()
	var title_rect := _label_world_rect(_title_label, _title_extent)
	var subtitle_rect := _label_world_rect(_subtitle_label, _subtitle_extent)
	if not title_rect.has_area():
		return subtitle_rect
	if not subtitle_rect.has_area():
		return title_rect
	return title_rect.merge(subtitle_rect)


func _process(_delta: float) -> void:
	_update_presentation()


func _update_presentation() -> void:
	var suspended := not block and (get_tree().paused or DialogueLayer.radio_visible())
	_root.visible = not suspended
	if suspended == _presentation_suspended:
		return
	_presentation_suspended = suspended
	if _tween != null and _tween.is_valid():
		if suspended:
			_tween.pause()
		else:
			_tween.play()


func _input(_event: InputEvent) -> void:
	if _lock_token != 0:
		get_viewport().set_input_as_handled()


func _done() -> void:
	GameplayLock.release(_lock_token)
	_lock_token = 0
	finished.emit()
	queue_free()
