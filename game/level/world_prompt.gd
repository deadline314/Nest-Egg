class_name WorldPrompt
extends Node2D
## 世界提示（遊戲內的 Hover 說明）：玩家靠近時在物件上方展開一行重點說明，離開時收回。
## 外觀是從物件投出來的全像字幕（NE-390）：底色只在文字後面夠深、往兩端淡出，上下各一條會淡出的細亮線，
## 兩端有角標並疊上掃描線；出現時由一條線展開。沒有實心方塊的硬邊。
## 可掛在任何物件下重複使用（道具、載具、檢查點、教學看板）。
## 文字可用 {動作} 佔位符（例如 "{interact} 搭乘"），會自動顯示玩家目前設定的按鍵；切換鍵鼠與手把時跟著換。
## keycaps = true 時，佔位符畫成按鍵帽（教學用：一眼看出要按哪個鍵），其餘提示維持純文字。

const TEXT_LAYOUT = preload("res://game/level/world_text_layout.gd")

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
## 全像字幕的外觀：文字後面底色的不透明度（HDR 2D 以線性色彩混色，數值要接近 1 看起來才夠深）、兩端淡出的寬度（像素）、角標長度、掃描線間距與深淺。
const PLATE_COLOR := Color("0a141c")
const PLATE_ALPHA := 0.95
const PLATE_WING := 12.0
const PLATE_TICK := 3.0
const SCAN_STEP := 3.0
const SCAN_ALPHA := 0.16
## 展開：整體淡入的前這一段用來把字幕由一條線拉開，文字在後半段才淡入。
const OPEN_PORTION := 0.55
const TEXT_START := 0.4
const MIN_OPEN := 0.12
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
## 這個提示是不是「在講話」的文字（教學看板）：是的話要和氣泡輪流，只在拿到發言時展開（TextTraffic，NE-491）。
## 按鍵邀請（互動提示）維持 NONE，永遠可以顯示。
var voice: int = TextTraffic.Voice.NONE
## 提示出現的條件。物件有自己的「按互動鍵有效」判斷時指定它（看到提示就一定按得動）；
## 沒指定就用「玩家在 radius 內」。
var reach_check: Callable
## 同一個互動鍵的提示只能由目前選到的物件顯示。
var interaction_owner: Node2D
var _alpha := 0.0
var _font: Font
var _player_ref: WeakRef
var _display_text := ""
## 文字框（以提示原點為準）的矩形；文字或字型改變時重算，不在每影格量字。
var _box := Rect2()
var _text_baseline := Vector2.ZERO
var _paragraph: TextParagraph
var _layout_width := -1.0
var _font_size := FONT_SIZE
var _cursor := Vector2.ZERO
var _line_height := 0.0
var _layout_allowed := true
## 被自動錯開時的位移（目前、目標；x 橫向，y 往上為負）。
var _nudge := Vector2.ZERO
var _nudge_target := Vector2.ZERO
var _leader: Node2D
var _leader_spans: Array[Vector2] = []
## keycaps 模式的排版（文字或綁定改變時重算）：每段 {text, x, cap}，x 是相對文字框左緣的起點。
var _segments: Array[Dictionary] = []
static var _token_regex: RegEx
## 兩端淡出用的橫向漸層（左透明、右不透明）；所有提示共用一張。
static var _wing_texture: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LightKit.mark_emissive(self)
	# 絕對圖層：提示掛在角色、檢查點、拾取物底下，但一律畫在所有角色與前景之上，不跟著主人的圖層組。
	z_as_relative = false
	z_index = WorldLayers.WORLD_PROMPTS
	_font = UiKit.font()
	position = offset
	_refresh_text()
	InputBindings.bindings_changed.connect(_refresh_text)
	Settings.display_changed.connect(_refresh_text)
	_font.changed.connect(_refresh_text)
	# 指向物件的細線畫在所有提示框的後面，不會被別的提示蓋住框、也不蓋住字。
	_leader = Node2D.new()
	_leader.z_index = -1
	_leader.draw.connect(_draw_leader)
	add_child(_leader)
	PromptLayout.register(self)
	_process(0.0)


func _exit_tree() -> void:
	PromptLayout.unregister(self)
	TextTraffic.release(self)


func _refresh_text() -> void:
	_display_text = InputBindings.format(text) if is_inside_tree() else text
	_segments.clear()
	if not is_inside_tree():
		_layout_width = -1.0
		return
	if _font != null:
		_layout_width = TEXT_LAYOUT.content_width(get_viewport(), PADDING)
		_font_size = roundi(FONT_SIZE * Settings.get_ui_text_scale())
		var size: Vector2
		if keycaps and is_inside_tree():
			_paragraph = null
			size = _layout_keycaps()
		else:
			_paragraph = TEXT_LAYOUT.paragraph(_display_text, _font, _font_size, _layout_width)
			size = _paragraph.get_size()
		size.y = maxf(size.y, _font.get_ascent(_font_size) + _font.get_descent(_font_size))
		_box = Rect2(Vector2(-size.x * 0.5, -size.y) - PADDING, size + PADDING * 2.0)
		_text_baseline = _box.position + PADDING + Vector2(0, _font.get_ascent(_font_size))
		PromptLayout.invalidate()
	queue_redraw()


func _layout_keycaps() -> Vector2:
	if _token_regex == null:
		_token_regex = RegEx.create_from_string(TOKEN_PATTERN)
	_cursor = Vector2.ZERO
	_line_height = _font.get_ascent(_font_size) + _font.get_descent(_font_size) + CAP_PADDING.y * 2.0
	var cursor := 0
	for found in _token_regex.search_all(text):
		_add_segment(text.substr(cursor, found.get_start() - cursor), false)
		var action := StringName(found.get_string(1))
		var label := InputBindings.primary_label(action) if InputMap.has_action(action) else found.get_string()
		_add_segment(label, true)
		cursor = found.get_end()
	_add_segment(text.substr(cursor), false)
	var width := 0.0
	for segment in _segments:
		width = maxf(width, segment["x"] + segment["w"])
	return Vector2(width, _cursor.y + _line_height)


func _add_segment(part: String, cap: bool) -> void:
	if not cap:
		part = part.strip_edges()
		if part.is_empty():
			return
	var tight := _segments.is_empty() or (not cap and "，。；：！？、）".contains(part.left(1)))
	var gap := 0.0 if tight else CAP_GAP
	var width := _font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	if cap:
		width += CAP_PADDING.x * 2.0
	if _cursor.x > 0.0 and _cursor.x + gap + width > _layout_width:
		_cursor = Vector2(0.0, _cursor.y + _line_height)
		gap = 0.0
	if not cap and width > _layout_width:
		var paragraph := TEXT_LAYOUT.paragraph(part, _font, _font_size, _layout_width)
		for i in paragraph.get_line_count():
			var span := paragraph.get_line_range(i)
			var line := part.substr(span.x, span.y - span.x).strip_edges()
			var line_width := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
			_segments.append({"text": line, "cap": false, "x": 0.0, "y": _cursor.y, "w": line_width})
			_cursor.x = line_width
			if i < paragraph.get_line_count() - 1:
				_cursor = Vector2(0.0, _cursor.y + _line_height)
		return
	var start := _cursor.x + gap
	_segments.append({"text": part, "cap": cap, "x": start, "y": _cursor.y, "w": width})
	_cursor.x = start + width


## 目前是否在顯示（含淡入淡出中）；PromptLayout 只處理正在顯示的提示。
func is_showing() -> bool:
	return _layout_allowed and layout_requested()


## Hidden for lack of space is still eligible for the next layout pass.
func layout_requested() -> bool:
	return enabled and visible and not _presentation_blocked() and not _display_text.is_empty() \
			and ((_alpha > 0.0 and not _interaction_superseded()) or _player_near())


## 沒被推開時文字框在世界座標的矩形。
func base_rect() -> Rect2:
	return Rect2(global_position + _box.position, _box.size)


func set_nudge_target(value: Vector2, allowed := true) -> void:
	_nudge_target = value
	_layout_allowed = allowed
	if not allowed:
		_alpha = 0.0
		queue_redraw()
		_leader.queue_redraw()


func _process(delta: float) -> void:
	if not is_equal_approx(_layout_width, TEXT_LAYOUT.content_width(get_viewport(), PADDING)):
		_refresh_text()
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
	var target := 1.0 if near and _layout_allowed else 0.0
	var previous := _alpha
	var previous_nudge := _nudge
	_alpha = 0.0 if not near and previous > 0.0 and _interaction_superseded() else move_toward(_alpha, target, FADE_SPEED * delta)
	if _nudge != _nudge_target:
		if previous <= 0.0 or Settings.get_reduce_ui_motion() or not PromptLayout.can_slide(self, _nudge_target):
			# Pick a safe reading position before fading in; never sweep text through actors.
			_nudge = _nudge_target
		else:
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
	var in_reach: bool = reach_check.call() if reach_check.is_valid() \
			else player != null and player.global_position.distance_to(global_position - offset) <= radius
	var wants := in_reach and (not is_instance_valid(interaction_owner) or Story.framing.is_interaction_prompt_target(interaction_owner))
	if voice == TextTraffic.Voice.NONE:
		return wants
	if not wants:
		TextTraffic.release(self)
		return false
	return TextTraffic.claim(self, voice)


func _interaction_superseded() -> bool:
	if not is_instance_valid(interaction_owner):
		return false
	var selected := Story.framing.interaction_prompt_target()
	return is_instance_valid(selected) and selected != interaction_owner


func _draw() -> void:
	if not _layout_allowed or _alpha <= 0.0 or _display_text.is_empty() or _font == null or _presentation_blocked():
		return
	var rect := Rect2(_box.position + _nudge, _box.size)
	var open := plate_open(_alpha)
	var ink := text_alpha(_alpha)
	_draw_plate(rect, open, _alpha)
	if ink <= 0.0:
		return
	if _paragraph != null:
		_paragraph.draw(get_canvas_item(), rect.position + PADDING, Color(Palette.UI_TEXT, ink))
		return
	for segment in _segments:
		var origin := _text_baseline + _nudge + Vector2(segment["x"], segment["y"] + CAP_PADDING.y)
		if segment["cap"]:
			var cap := Rect2(rect.position + PADDING + Vector2(segment["x"], segment["y"]), Vector2(segment["w"], _line_height))
			draw_rect(cap, Color(CAP_FILL, ink))
			draw_line(Vector2(cap.position.x, cap.end.y), cap.end, Color(CAP_EDGE, ink), 1.0)
			origin.x += CAP_PADDING.x
		draw_string(_font, origin, segment["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(Palette.UI_TEXT, ink))


## 字幕展開的程度（0～1）：淡入的前段由一條線拉開。「減少動態」時不展開，直接是整片。
static func plate_open(alpha: float) -> float:
	if Settings.get_reduce_ui_motion():
		return 1.0
	return clampf(MIN_OPEN + (1.0 - MIN_OPEN) * smoothstep(0.0, OPEN_PORTION, alpha), 0.0, 1.0)


## 文字的不透明度：字幕拉開之後才淡入；完全顯示時是 1。「減少動態」時跟著整體淡入。
static func text_alpha(alpha: float) -> float:
	if Settings.get_reduce_ui_motion():
		return clampf(alpha, 0.0, 1.0)
	return smoothstep(TEXT_START, 1.0, alpha)


## 全像字幕的底：中間（文字後面）夠深，兩端淡出；上下細亮線、四個角標與掃描線。open 是垂直展開的程度。
func _draw_plate(rect: Rect2, open: float, alpha: float) -> void:
	var height := maxf(1.0, rect.size.y * open)
	var body := Rect2(rect.position.x, rect.get_center().y - height * 0.5, rect.size.x, height)
	var wing := _wing()
	# 底色比文字早到位：淡入到一半時字後面就已經夠深，文字不會直接壓在亮的場景上。
	var fill := Color(PLATE_COLOR, PLATE_ALPHA * smoothstep(0.0, TEXT_START + 0.1, alpha))
	draw_rect(body, fill)
	draw_texture_rect(wing, Rect2(body.position.x - PLATE_WING, body.position.y, PLATE_WING, height), false, fill)
	draw_texture_rect(wing, Rect2(body.end.x, body.position.y, -PLATE_WING, height), false, fill)
	var y := body.position.y + SCAN_STEP
	var scan := Color(0.0, 0.0, 0.0, SCAN_ALPHA * alpha)
	while y < body.end.y - 1.0:
		draw_line(Vector2(body.position.x, y), Vector2(body.end.x, y), scan, 1.0)
		y += SCAN_STEP
	# 負的寬度＝左右鏡像（右端由不透明淡到透明）。
	# 剛展開的那一瞬間亮線最亮，像投影機剛打亮。
	var line := Color(Palette.CYAN, alpha * lerpf(1.0, 0.6, open))
	for edge_y: float in [body.position.y, body.end.y]:
		draw_line(Vector2(body.position.x, edge_y), Vector2(body.end.x, edge_y), line, 1.0)
		draw_texture_rect(wing, Rect2(body.position.x - PLATE_WING, edge_y - 0.5, PLATE_WING, 1.0), false, line)
		draw_texture_rect(wing, Rect2(body.end.x, edge_y - 0.5, -PLATE_WING, 1.0), false, line)
	var tick := minf(PLATE_TICK, height * 0.5)
	var bright := Color(Palette.CYAN.lightened(0.35), alpha)
	for corner_x: float in [body.position.x, body.end.x]:
		draw_line(Vector2(corner_x, body.position.y), Vector2(corner_x, body.position.y + tick), bright, 1.0)
		draw_line(Vector2(corner_x, body.end.y), Vector2(corner_x, body.end.y - tick), bright, 1.0)


static func _wing() -> GradientTexture2D:
	if _wing_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0))
		gradient.set_color(1, Color(1, 1, 1, 1))
		_wing_texture = GradientTexture2D.new()
		_wing_texture.gradient = gradient
		_wing_texture.width = 16
		_wing_texture.height = 1
	return _wing_texture


## 被推開的提示：從文字框下緣拉一條細線到自己原本位置下方的小圓點（物件上方），一眼看出它屬於誰。
func _draw_leader() -> void:
	if not _layout_allowed or _alpha <= 0.0 or _nudge.length() < 1.0 or _presentation_blocked():
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
