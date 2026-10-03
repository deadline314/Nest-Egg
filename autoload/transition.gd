extends Node
## 畫面轉場服務：任何畫面都可以「蓋住 → 換內容 → 揭開」。
## 用法：await Transition.play(Transition.Kind.SCAN, func() -> void: _swap_screen())
## 轉場期間遊戲暫停、輸入鎖定；按任意鍵可加速。同時只會有一個轉場，重複呼叫時直接執行內容切換。
## 無頭模式（測試）預設瞬間完成；測試轉場本身時把 instant 設為 false。

enum Kind { FADE, FADE_WHITE, IRIS, SCAN, GLITCH, ELEVATOR, BLINDS }

signal covered
signal finished

const LAYER := 100
## 各轉場「蓋住」或「揭開」單程的預設秒數。死亡重來（GLITCH）總長 0.7 秒。
const DEFAULT_TIME: Dictionary[int, float] = {
	Kind.FADE: 0.45, Kind.FADE_WHITE: 0.35, Kind.IRIS: 0.5, Kind.SCAN: 0.5,
	Kind.GLITCH: 0.35, Kind.ELEVATOR: 0.7, Kind.BLINDS: 0.45,
}
const SKIP_SPEED := 4.0
const CAPTION_FADE := 0.15

var instant: bool = false
var _layer: CanvasLayer
var _rect: ColorRect
var _caption: Label
var _material: ShaderMaterial
var _active := false
var _speed := 1.0
var _paused_before := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instant = DisplayServer.get_name() == "headless"
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var shader := load("res://ui/transition/transition.gdshader") as Shader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.visible = false
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_rect.material = _material
	else:
		push_error("[Transition] 找不到轉場 shader，改用單色淡入淡出。")
		_rect.color = Color.BLACK
	_layer.add_child(_rect)
	_caption = UiKit.label("", UiKit.FS_TITLE, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_rect.add_child(_caption)
	set_process_input(false)


## 以名稱（fade、iris、scan…）取得轉場種類；不存在回傳 -1（資料檔指定轉場時用）。
static func kind_from_name(kind_name: String) -> int:
	var index := Kind.keys().find(kind_name.to_upper())
	return index if index < 0 else Kind.values()[index]


func is_active() -> bool:
	return _active


## 蓋住 → 執行 on_covered（換畫面）→ 揭開。on_covered 可以是會 await 的函式。
## center 是光圈中心（0 到 1 的螢幕比例）；caption 在完全蓋住時顯示一行字。
func play(kind: Kind, on_covered: Callable, duration := -1.0, center := Vector2(0.5, 0.5),
		caption := "", hold := 0.0) -> void:
	if instant or _active or not is_inside_tree():
		await _run(on_covered)
		return
	kind = _resolve_kind(kind)
	var half: float = duration if duration > 0.0 else _default_time(kind)
	_begin()
	await _sweep(kind, half, center, true)
	_set_caption(caption)
	covered.emit()
	await _run(on_covered)
	# 換畫面時關卡可能解除暫停；揭開前再鎖一次，揭開完才還原。
	get_tree().paused = true
	if hold > 0.0:
		await _wait(hold)
	await _sweep(kind, half, center, false)
	_set_caption("")
	_end()


## 只蓋住（例如演出開頭）；之後用 reveal 揭開。
func cover(kind: Kind, duration := -1.0, center := Vector2(0.5, 0.5), caption := "") -> void:
	if instant or _active or not is_inside_tree():
		return
	kind = _resolve_kind(kind)
	_begin()
	await _sweep(kind, duration if duration > 0.0 else _default_time(kind), center, true)
	_set_caption(caption)
	covered.emit()
	# 蓋住期間維持 _active，直到 reveal。


func reveal(kind: Kind, duration := -1.0, center := Vector2(0.5, 0.5)) -> void:
	if not _active:
		return
	kind = _resolve_kind(kind)
	await _sweep(kind, duration if duration > 0.0 else _default_time(kind), center, false)
	_set_caption("")
	_end()


## 立刻清掉轉場（場景被強制替換、或測試收尾時用）。
func abort() -> void:
	if not _active:
		return
	_set_caption("")
	_end()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			_speed = SKIP_SPEED
	get_viewport().set_input_as_handled()


func _begin() -> void:
	_active = true
	_speed = 1.0
	_paused_before = get_tree().paused
	get_tree().paused = true
	_rect.visible = true
	set_process_input(true)
	_set_progress(0.0, 0.0)


func _end() -> void:
	_active = false
	_rect.visible = false
	set_process_input(false)
	get_tree().paused = _paused_before
	finished.emit()


func _run(callback: Callable) -> void:
	if callback.is_valid():
		await callback.call()


## 減少閃光：雜訊與閃白降級成淡入淡出。
func _resolve_kind(kind: Kind) -> Kind:
	if Settings.get_reduce_flashes() and (kind == Kind.GLITCH or kind == Kind.FADE_WHITE):
		return Kind.FADE
	return kind


func _sweep(kind: Kind, seconds: float, center: Vector2, closing: bool) -> void:
	_configure(kind, center, closing)
	var from := 0.0 if closing else 1.0
	var to := 1.0 if closing else 0.0
	var elapsed := 0.0
	var total := maxf(seconds, 0.01)
	while elapsed < total:
		var delta := get_process_delta_time() * _speed
		elapsed += delta
		var t := clampf(elapsed / total, 0.0, 1.0)
		_set_progress(lerpf(from, to, _ease(t)), elapsed)
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_set_progress(to, elapsed)


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and is_inside_tree():
		left -= get_process_delta_time() * _speed
		await get_tree().process_frame


static func _default_time(kind: Kind) -> float:
	return DEFAULT_TIME.get(kind, 0.5)


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _configure(kind: Kind, center: Vector2, closing: bool) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"kind", int(kind))
	_material.set_shader_parameter(&"center", center)
	_material.set_shader_parameter(&"flip", 0.0 if closing else 1.0)
	_material.set_shader_parameter(&"seed", randf() * 10.0)
	var tint := Color.WHITE if kind == Kind.FADE_WHITE else Color.BLACK
	_material.set_shader_parameter(&"tint", tint)
	_material.set_shader_parameter(&"accent", Palette.MAGENTA if kind == Kind.GLITCH else Palette.CYAN)
	var size := _rect.get_viewport_rect().size
	_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))


func _set_progress(progress: float, time_s: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"progress", progress)
		_material.set_shader_parameter(&"time_s", time_s)
	else:
		_rect.color = Color(0, 0, 0, progress)


func _set_caption(text: String) -> void:
	_caption.text = text
	var tween := create_tween()
	tween.tween_property(_caption, "modulate:a", 1.0 if text != "" else 0.0, CAPTION_FADE)
