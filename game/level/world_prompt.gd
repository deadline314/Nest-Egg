class_name WorldPrompt
extends Node2D
## 世界提示（遊戲內的 Hover 說明）：玩家靠近時在物件上方淡入一行重點說明，離開時淡出。
## 可掛在任何物件下重複使用（道具、載具、檢查點、教學看板）。
## 文字可用 {動作} 佔位符（例如 "{interact} 搭乘"），會自動顯示玩家目前設定的按鍵；切換鍵鼠與手把時跟著換。
## keycaps = true 時，佔位符畫成按鍵帽（教學用：一眼看出要按哪個鍵），其餘提示維持純文字。

const FADE_SPEED := 6.0
## 被推開時移動的速度（像素／秒）：提示是滑到新位置，不是跳過去。
const NUDGE_SPEED := 240.0
const PADDING := Vector2(5, 3)
const FONT_SIZE := 9
const LEADER_DOT := 1.5
## 指向線的終點在文字框原位下緣再往下幾像素（人物頭頂與文字之間）。
const LEADER_STEM := 5.0
## 按鍵帽的內距與和文字的間隔；顏色與 HUD 的情境提示按鍵帽一致。
const CAP_PADDING := Vector2(3, 1)
const CAP_GAP := 3.0
const CAP_FILL := Color("20333f")
const CAP_EDGE := Color("6c8997")
const TOKEN_PATTERN := "\\{([a-z_0-9]+)\\}"

@export var text: String = "":
	set(value):
		text = value
		_refresh_text()
@export var radius: float = 48.0
@export var offset: Vector2 = Vector2(0, -34)
@export var keycaps := false:
	set(value):
		keycaps = value
		_refresh_text()

var enabled := true
## 提示出現的條件。物件有自己的「按互動鍵有效」判斷時指定它（看到提示就一定按得動）；
## 沒指定就用「玩家在 radius 內」。
var reach_check: Callable
var _alpha := 0.0
var _font: Font
var _player_ref: WeakRef
var _display_text := ""
## 文字框（以提示原點為準）的矩形；文字或字型改變時重算，不在每影格量字。
var _box := Rect2()
var _text_baseline := Vector2.ZERO
## 被自動錯開時的位移（目前、目標；x 橫向，y 往上為負）。
var _nudge := Vector2.ZERO
var _nudge_target := Vector2.ZERO
var _leader: Node2D
var _leader_spans: Array[Vector2] = []
## keycaps 模式的排版（文字或綁定改變時重算）：每段 {text, x, cap}，x 是相對文字框左緣的起點。
var _segments: Array[Dictionary] = []
static var _token_regex: RegEx


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LightKit.mark_emissive(self)
	z_index = 20
	_font = UiKit.font()
	position = offset
	_refresh_text()
	InputBindings.bindings_changed.connect(_refresh_text)
	# 指向物件的細線畫在所有提示框的後面，不會被別的提示蓋住框、也不蓋住字。
	_leader = Node2D.new()
	_leader.z_index = -1
	_leader.draw.connect(_draw_leader)
	add_child(_leader)
	PromptLayout.register(self)
	_process(0.0)


func _exit_tree() -> void:
	PromptLayout.unregister(self)


func _refresh_text() -> void:
	_display_text = InputBindings.format(text) if is_inside_tree() else text
	_segments.clear()
	if _font != null:
		var size := _font.get_string_size(_display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		if keycaps and is_inside_tree():
			size.x = _layout_keycaps()
		size.y = maxf(size.y, _font.get_ascent(FONT_SIZE) + _font.get_descent(FONT_SIZE))
		_box = Rect2(Vector2(-size.x * 0.5, -size.y) - PADDING, size + PADDING * 2.0)
		_text_baseline = _box.position + PADDING + Vector2(0, _font.get_ascent(FONT_SIZE))
	queue_redraw()


## 把文字切成「按鍵帽」與「一般文字」兩種段落，回傳總寬度。佔位符的動作不存在時照 format 的結果當文字。
func _layout_keycaps() -> float:
	if _token_regex == null:
		_token_regex = RegEx.create_from_string(TOKEN_PATTERN)
	var x := 0.0
	var cursor := 0
	for found in _token_regex.search_all(text):
		x = _add_segment(text.substr(cursor, found.get_start() - cursor), false, x)
		var action := StringName(found.get_string(1))
		var label := InputBindings.primary_label(action) if InputMap.has_action(action) else found.get_string()
		x = _add_segment(label, true, x)
		cursor = found.get_end()
	x = _add_segment(text.substr(cursor), false, x)
	return x


func _add_segment(part: String, cap: bool, x: float) -> float:
	if not cap:
		part = part.strip_edges()
		if part.is_empty():
			return x
	# 句讀緊貼前一個按鍵帽，不留空隙（「按 [Space]。」而不是「按 [Space] 。」）。
	var tight := _segments.is_empty() or (not cap and "，。；：！？、）".contains(part.left(1)))
	var start := x + (0.0 if tight else CAP_GAP)
	var width := _font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if cap:
		width += CAP_PADDING.x * 2.0
	_segments.append({"text": part, "x": start, "cap": cap, "w": width})
	return start + width


## 目前是否在顯示（含淡入淡出中）；PromptLayout 只處理正在顯示的提示。
func is_showing() -> bool:
	return enabled and visible and not _presentation_blocked() and (_alpha > 0.0 or _player_near()) and not _display_text.is_empty()


## 沒被推開時文字框在世界座標的矩形。
func base_rect() -> Rect2:
	return Rect2(global_position + _box.position, _box.size)


func set_nudge_target(value: Vector2) -> void:
	_nudge_target = value


func _process(delta: float) -> void:
	var suspended := _presentation_blocked()
	visible = not suspended
	if suspended:
		# Never retain a stale invitation through a modal or another reading surface.
		_alpha = 0.0
		_nudge_target = Vector2.ZERO
		return
	var near := enabled and _player_near()
	if near or _alpha > 0.0:
		PromptLayout.update()
	else:
		_nudge_target = Vector2.ZERO
	var target := 1.0 if near else 0.0
	var previous := _alpha
	var previous_nudge := _nudge
	_alpha = move_toward(_alpha, target, FADE_SPEED * delta)
	_nudge = _nudge.move_toward(_nudge_target, NUDGE_SPEED * delta)
	if _alpha != previous or _alpha > 0.0 or _nudge != previous_nudge:
		queue_redraw()
		_leader.queue_redraw()


func _presentation_blocked() -> bool:
	return get_tree().paused or GameplayLock.is_locked() or Story.is_cinematic_active() or DialogueLayer.radio_visible()


func _player_near() -> bool:
	# A modal owns interaction; the invitation to start another action should fade
	# out with the normal prompt animation and return after control is released.
	if _presentation_blocked():
		return false
	var player: Node2D = _player_ref.get_ref() as Node2D if _player_ref != null else null
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null:
			_player_ref = weakref(player)
	# 倒下之後死亡畫面接手；不要再對倒地的主角邀請移動、跳躍或互動。
	if player != null and player.has_method(&"is_dead") and player.call(&"is_dead"):
		return false
	if reach_check.is_valid():
		return reach_check.call()
	if player == null:
		return false
	return player.global_position.distance_to(global_position - offset) <= radius


func _draw() -> void:
	if _alpha <= 0.0 or _display_text.is_empty() or _font == null or _presentation_blocked():
		return
	var rect := Rect2(_box.position + _nudge, _box.size)
	draw_rect(rect, Color(Palette.UI_PANEL, 0.85 * _alpha))
	draw_rect(rect, Color(Palette.CYAN_DIM, _alpha), false, 1.0)
	if _segments.is_empty():
		draw_string(_font, _text_baseline + _nudge, _display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
				Color(Palette.UI_TEXT, _alpha))
		return
	var line_top := _box.position.y + PADDING.y + _nudge.y
	var line_height := _box.size.y - PADDING.y * 2.0
	for segment in _segments:
		var origin := _text_baseline + _nudge + Vector2(segment["x"], 0.0)
		if segment["cap"]:
			var cap := Rect2(Vector2(origin.x, line_top - CAP_PADDING.y), Vector2(segment["w"], line_height + CAP_PADDING.y * 2.0))
			draw_rect(cap, Color(CAP_FILL, _alpha))
			draw_rect(cap, Color(CAP_EDGE, _alpha), false, 1.0)
			origin.x += CAP_PADDING.x
		draw_string(_font, origin, segment["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(Palette.UI_TEXT, _alpha))


## 被推開的提示：從文字框下緣拉一條細線到自己原本位置下方的小圓點（物件上方），一眼看出它屬於誰。
func _draw_leader() -> void:
	if _alpha <= 0.0 or _nudge.length() < 1.0 or _presentation_blocked():
		return
	var from := Vector2(_nudge.x, _box.end.y + _nudge.y)
	var to := Vector2(0.0, _box.end.y + LEADER_STEM)
	var color := Color(Palette.CYAN, 0.7 * _alpha)
	# Clip in the real leader Node's world frame. Frobenius norm bounds a
	# transformed half-pixel stroke, including nonuniform scale/skew.
	var transform := _leader.global_transform
	if not is_finite(transform.determinant()) or is_zero_approx(transform.determinant()):
		_leader.draw_circle(to, LEADER_DOT, color)
		return
	var stroke_radius := 0.5 * sqrt(transform.x.length_squared() + transform.y.length_squared())
	var span_count := PromptLayout.leader_segments(_leader.to_global(from), _leader.to_global(to), _leader_spans, stroke_radius)
	for i in range(0, span_count, 2):
		_leader.draw_line(_leader.to_local(_leader_spans[i]), _leader.to_local(_leader_spans[i + 1]), color, 1.0)
	# The authored target remains visible, even when every line span is hidden.
	_leader.draw_circle(to, LEADER_DOT, color)
