class_name DialogueLayer
extends CanvasLayer
## 對話介面（由 Story 服務持有）：
##   過場：暫停遊戲、上下黑邊、頭像＋講者名＋逐字顯示；點擊／Enter／射擊／互動鍵推進（第一下先顯示完整句子），Esc 跳過整段。
##   通訊：畫面左上角的小面板，不暫停，逐字顯示後依字數停留再自動換下一句；台詞帶 delay 時先收起面板沉默那麼久。
##   重要通訊（場景資料 freeze: true，NE-246）：顯示時凍結世界（敵人、子彈、計時都停），不自動消失；
##   確認鍵先補齊句子、再前進一句。凍結期間可開暫停選單，關閉選單不會提前解凍；取消、換區、回選單時一併解除。

signal cinematic_finished(scene_id: StringName)
signal radio_finished(scene_id: StringName)

const CHARS_PER_SECOND := 42.0
const RADIO_CHARS_PER_SECOND := 60.0
const RADIO_HOLD_BASE := 1.6
const RADIO_HOLD_PER_CHAR := 0.055
const PORTRAIT_SIZE := 56.0
const RADIO_HOME := Vector2(170, 82)
const RADIO_SLIDE := 28.0

## Weak observers only; neither the query nor this table owns a removed layer.
static var _radio_layers: Dictionary[int, WeakRef] = {}

var _cinematic_root: Control
var _portrait: TextureRect
var _name: Label
var _text: Label
var _continue: Label
var _skip: Label
var _dialogue_panel: Panel
var _cinematic_id: StringName = &""
var _cinematic_lines: Array[Dictionary] = []
var _cinematic_index := 0
var _lock_token := 0

var _radio_root: PanelContainer
var _radio_portrait: TextureRect
var _radio_name: Label
var _radio_bar: ColorRect
var _radio_slide: Tween
var _radio_fade: Tween
var _radio_text: Label
var _radio_queue: Array[Dictionary] = []  # { id, line, last, freeze }
var _radio_continue: Label
## 重要通訊凍結世界用的鎖（0＝沒有凍結）；允許在上面開暫停選單。
var _radio_lock := 0
var _radio_hold := 0.0
## 這一句顯示前還要沉默幾秒（台詞的 delay）；沉默期間通訊框是收起來的。
var _radio_wait := 0.0
var _radio_active := false
var _time := 0.0
var _name_plate: Panel
var _portrait_plate: Panel
var _dialogue_kind := "dialogue"
var _reading_title := ""
var _dim: ColorRect
var _safe_rect := Rect2(Vector2.ZERO, Vector2(640, 360))
var _radio_home := RADIO_HOME
var _radio_slide_offset := 0.0
var _radio_slide_distance := RADIO_SLIDE
var _radio_obstacles: Array[Rect2] = []
var _radio_rects: Array[Rect2] = []
var _laying_out := false


func _ready() -> void:
	layer = UiLayers.DIALOGUE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_cinematic()
	_build_radio()
	_radio_layers[get_instance_id()] = weakref(self)
	_radio_root.visibility_changed.connect(EventBus.radio_visibility_changed.emit)
	Story.framing.safe_rect_changed.connect(_layout_cinematic)
	InputBindings.bindings_changed.connect(_refresh_skip_hint)
	Settings.display_changed.connect(_display_changed)
	_layout_cinematic(Story.framing.safe_rect())


## Presentation only: delay is not visible; a fade-out panel still owns reading space.
## No queue, clock, Story result, or completion is changed by this readonly query.
static func radio_visible() -> bool:
	for id: int in _radio_layers:
		var owner: Variant = _radio_layers[id].get_ref()
		if is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion() \
				and is_instance_valid(owner._radio_root) and owner._radio_root.is_visible_in_tree():
			return true
	return false


func _exit_tree() -> void:
	_radio_layers.erase(get_instance_id())
	_release_radio_lock()
	EventBus.radio_visibility_changed.emit()


# ---------------------------------------------------------------------------
# 過場
# ---------------------------------------------------------------------------

func start_cinematic(id: StringName, lines: Array[Dictionary]) -> void:
	if is_cinematic_active():
		push_warning("[Dialogue] 已在播放對話：%s" % _cinematic_id)
		return
	if lines.is_empty():
		cinematic_finished.emit(id)
		return
	_cinematic_id = id
	# 真入隊來源只決定外觀，沒有新增 Story／結果語義。
	var context := Story.current_presentation_context()
	_dialogue_kind = "object" if str(context.get("framing_source", "")) == "object" else "dialogue"
	_reading_title = ""
	if _dialogue_kind == "object":
		for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
			var actor := node as NpcActor
			if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.data != null and actor.data.kind == NpcData.Kind.OBJECT and actor.state_key() == str(context.get("source_id", "")):
				_reading_title = actor.data.display_name
				break
	_dialogue_panel.add_theme_stylebox_override(&"panel", DialogueMaterial.panel(_dialogue_kind))
	_dim.color.a = 0.12 if _dialogue_kind == "object" else 0.18
	# Cancelling this presentation must not clear the caller's reusable line array.
	_cinematic_lines = lines.duplicate()
	_cinematic_index = 0
	_lock_token = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	Fx.reset_time()
	_cinematic_root.visible = true
	_radio_root.visible = false
	_show_line()


func is_cinematic_active() -> bool:
	return _cinematic_id != &""


## 推進：句子還在逐字顯示時先顯示完整句子，否則換下一句。
func advance() -> void:
	if not is_cinematic_active():
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		return
	_cinematic_index += 1
	if _cinematic_index >= _cinematic_lines.size():
		finish_cinematic()
	else:
		_show_line()
		Sfx.play(&"ui_move", -12.0, 0.0)


func finish_cinematic() -> void:
	if not is_cinematic_active():
		return
	var id := _cinematic_id
	_cinematic_id = &""
	_cinematic_root.visible = false
	GameplayLock.release(_lock_token)
	_lock_token = 0
	cinematic_finished.emit(id)


func cancel_cinematic() -> void:
	_cinematic_id = &""
	_cinematic_lines.clear()
	_cinematic_root.visible = false
	GameplayLock.release(_lock_token)
	_lock_token = 0


func cancel_radio() -> void:
	_release_radio_lock()
	_cancel_radio_fade()
	_radio_queue.clear()
	_radio_active = false
	_radio_wait = 0.0
	_radio_hold = 0.0
	_radio_root.hide()
	if _radio_slide != null and _radio_slide.is_valid():
		_radio_slide.kill()


func _show_line() -> void:
	var line := _cinematic_lines[_cinematic_index]
	_name.text = DialogueMaterial.header(_dialogue_kind, _reading_title if not _reading_title.is_empty() else str(line["name"]))
	_name.add_theme_color_override(&"font_color", line["color"])
	_name_plate.add_theme_stylebox_override(&"panel", DialogueMaterial.nameplate(_dialogue_kind))
	_text.text = line["text"]
	_text.visible_ratio = 0.0
	_portrait.texture = _portrait_texture(line["portrait"])
	_portrait.visible = _dialogue_kind != "object" and _portrait.texture != null
	_layout_cinematic(_safe_rect)


func _input(event: InputEvent) -> void:
	if not is_cinematic_active():
		_radio_input(event)
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		finish_cinematic()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"shoot") or event.is_action_pressed(&"jump") \
			or event.is_action_pressed(&"interact") \
			or (event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		advance()
		get_viewport().set_input_as_handled()
	else:
		# 過場期間吞掉其他輸入，避免穿透到遊戲。
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 通訊
# ---------------------------------------------------------------------------

## freeze：重要通訊，顯示時凍結世界並等玩家確認（見檔頭）。
func enqueue_radio(id: StringName, lines: Array[Dictionary], freeze := false) -> void:
	if lines.is_empty():
		radio_finished.emit(id)
		return
	for i in lines.size():
		_radio_queue.append({"id": id, "line": lines[i], "last": i == lines.size() - 1, "freeze": freeze})
	if not _radio_active:
		_next_radio()


func _next_radio() -> void:
	_cancel_radio_fade()
	if _radio_queue.is_empty() or not _front_freezes():
		_release_radio_lock()
	if _radio_queue.is_empty():
		_radio_active = false
		_radio_fade = create_tween()
		_radio_fade.tween_property(_radio_root, "modulate:a", 0.0, 0.25)
		_radio_fade.tween_callback(_radio_root.set.bind("visible", false))
		return
	_radio_active = true
	var entry: Dictionary = _radio_queue.front()
	var line: Dictionary = entry["line"]
	_radio_name.text = DialogueMaterial.header("radio", str(line["name"]))
	_radio_name.add_theme_color_override(&"font_color", line["color"])
	_radio_bar.color = line["color"]
	_radio_text.text = line["text"]
	_radio_text.visible_ratio = 0.0
	_radio_continue.visible = false
	_radio_portrait.texture = _portrait_texture(line["portrait"])
	_radio_portrait.visible = _radio_portrait.texture != null
	_layout_radio()
	_radio_hold = RADIO_HOLD_BASE + str(line["text"]).length() * RADIO_HOLD_PER_CHAR
	_radio_wait = float(line.get("delay", 0.0))
	var was_hidden := not _radio_root.visible or _radio_root.modulate.a < 0.5
	_radio_root.visible = not is_cinematic_active() and _radio_wait <= 0.0
	if _radio_wait <= 0.0:
		_reveal_radio(was_hidden)


## 新句或取消取得廣播面板前，舊退場不能再改它的透明度／可見性。
func _cancel_radio_fade() -> void:
	if _radio_fade != null and _radio_fade.is_valid():
		_radio_fade.kill()
	_radio_fade = null


func _process(delta: float) -> void:
	_time += delta
	if is_cinematic_active():
		if _text.visible_ratio < 1.0:
			_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / maxf(1.0, _text.text.length()))
		_continue.visible = _text.visible_ratio >= 1.0 and (Settings.get_reduce_ui_motion() or int(_time * 3.0) % 2 == 0)
		return
	if not _radio_available():
		# A pause/block card owns the screen; preserve the exact unread radio clocks.
		_radio_root.hide()
		return
	if not _radio_active:
		return
	if _radio_wait > 0.0:
		_radio_wait -= delta
		if _radio_wait <= 0.0:
			_radio_root.visible = true
			_reveal_radio(true)
		return
	if _front_freezes() and _radio_lock == 0:
		_radio_lock = GameplayLock.acquire(self, -1, true)
	_radio_root.visible = true
	_position_radio()
	if _radio_text.visible_ratio < 1.0:
		_radio_text.visible_ratio = minf(1.0, _radio_text.visible_ratio + delta * RADIO_CHARS_PER_SECOND / maxf(1.0, _radio_text.text.length()))
		return
	if _radio_lock != 0:
		# Waiting for input: keep the required control visible, including between blink phases.
		_radio_continue.visible = true
		return
	_radio_hold -= delta
	if _radio_hold <= 0.0:
		var entry: Dictionary = _radio_queue.pop_front()
		if entry["last"]:
			radio_finished.emit(entry["id"])
		_next_radio()


## 通訊現在能不能顯示與接受確認：過場、轉場、暫停選單、背包都會讓它先收起來（時鐘不走）。
## 世界是被自己的凍結鎖停住時仍可讀。
func _radio_available() -> bool:
	if is_cinematic_active() or Story.is_cinematic_active():
		return false
	if not get_tree().paused:
		return true
	return _radio_lock != 0 and GameplayLock.held_only_by(_radio_lock) and not GameplayLock.base_paused()


func _front_freezes() -> bool:
	return not _radio_queue.is_empty() and bool(_radio_queue.front().get("freeze", false))


## 重要通訊正在凍結世界（給測試與 HUD 用的唯讀查詢）。
func is_radio_frozen() -> bool:
	return _radio_lock != 0


func _release_radio_lock() -> void:
	if _radio_lock != 0:
		GameplayLock.release(_radio_lock)
	_radio_lock = 0


## 重要通訊的確認：確認鍵、互動鍵或滑鼠左鍵；按住不連發，一次只前進一句。
func _radio_input(event: InputEvent) -> void:
	if _radio_lock == 0 or not _radio_active or _radio_wait > 0.0 or not _radio_available():
		return
	var click: bool = event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if not (click or event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact")):
		return
	get_viewport().set_input_as_handled()
	advance_radio()


## 第一下補齊句子，第二下換下一句；最後一句讀完才結束這段通訊並解凍。
func advance_radio() -> void:
	if not _radio_active or _radio_queue.is_empty() or _radio_wait > 0.0:
		return
	if _radio_text.visible_ratio < 1.0:
		_radio_text.visible_ratio = 1.0
		return
	var entry: Dictionary = _radio_queue.pop_front()
	if _radio_queue.is_empty() or not _front_freezes():
		_release_radio_lock()
	if entry["last"]:
		radio_finished.emit(entry["id"])
		# 完成的回呼可能已經取消或接上新的演出。
		if _radio_queue.is_empty() and not _radio_active:
			return
	_next_radio()


# ---------------------------------------------------------------------------
# 建立介面
# ---------------------------------------------------------------------------

func _build_cinematic() -> void:
	_cinematic_root = Control.new()
	_cinematic_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinematic_root.theme = UiKit.theme()
	_cinematic_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_cinematic_root.visible = false
	add_child(_cinematic_root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.18)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinematic_root.add_child(_dim)
	_dialogue_panel = Panel.new()
	_dialogue_panel.add_theme_stylebox_override(&"panel", DialogueMaterial.panel("dialogue"))
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinematic_root.add_child(_dialogue_panel)
	_skip = UiKit.label(InputBindings.format("{ui_cancel} 跳過"), UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_cinematic_root.add_child(_skip)
	_name_plate = Panel.new()
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.add_theme_stylebox_override(&"panel", DialogueMaterial.nameplate("dialogue"))
	_cinematic_root.add_child(_name_plate)
	_portrait_plate = Panel.new()
	_portrait_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_plate.add_theme_stylebox_override(&"panel", DialogueMaterial.nameplate("dialogue"))
	_cinematic_root.add_child(_portrait_plate)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_place(_portrait, Control.PRESET_BOTTOM_LEFT, Rect2(24, -PORTRAIT_SIZE - 26.0, PORTRAIT_SIZE, PORTRAIT_SIZE))
	_cinematic_root.add_child(_portrait)
	_name = UiKit.label("", 12, Palette.CYAN)
	_place(_name, Control.PRESET_BOTTOM_LEFT, Rect2(92, -88, 300, 16))
	_cinematic_root.add_child(_name)
	_text = UiKit.label("", 12, Palette.UI_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(500, 0)
	_place(_text, Control.PRESET_BOTTOM_LEFT, Rect2(92, -70, 500, 50))
	_cinematic_root.add_child(_text)
	_text.minimum_size_changed.connect(func() -> void: _layout_cinematic(_safe_rect))
	_continue = UiKit.label(InputBindings.format("{ui_accept} 繼續"), UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_continue, Control.PRESET_BOTTOM_RIGHT, Rect2(-40, -26, 20, 14))
	_cinematic_root.add_child(_continue)


func _layout_cinematic(rect: Rect2) -> void:
	_safe_rect = rect
	if _portrait == null or _laying_out:
		return
	_laying_out = true
	# 88px 舞台保留區不變。閱讀物件不浪費空頭像欄；大字仍用完整可換行寬度。
	var height := minf(88.0, rect.size.y * 0.36)
	var top := rect.end.y - height - 6.0
	_dialogue_panel.position = Vector2(rect.position.x + 16, top)
	_dialogue_panel.size = Vector2(maxf(0, rect.size.x - 32), height)
	_skip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_skip.position = Vector2(maxf(rect.position.x + 8, rect.end.x - 136), rect.position.y + 6)
	_skip.size = Vector2(128, 18)
	for control in [_portrait, _name, _text, _continue]:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_portrait.position = Vector2(rect.position.x + 24, top + 10)
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	var left := rect.position.x + (92.0 if _portrait.visible else 32.0)
	var width := maxf(0, rect.end.x - left - 32)
	_name.position = Vector2(left, top + 7)
	_name.size = Vector2(maxf(0, width - 128), 18)
	_name.clip_text = true
	var name_width := _name.get_theme_font(&"font").get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size(&"font_size")).x
	_name_plate.position = _name.position - Vector2(6, 2)
	_name_plate.size = Vector2(minf(name_width + 12, maxf(0, width - 116)), 22)
	_portrait_plate.visible = _portrait.visible
	_portrait_plate.position = _portrait.position - Vector2(2, 2)
	_portrait_plate.size = _portrait.size + Vector2(4, 4)
	# Scaled labels have a real minimum height; leave a gap beneath the shared
	# name/continue row rather than trusting the unscaled 16px requested size.
	var body_top := maxf(27.0, maxf(8.0 + _continue.get_combined_minimum_size().y,
			7.0 + _name.get_combined_minimum_size().y) + 4.0)
	_text.position = Vector2(left, top + body_top)
	_text.custom_minimum_size.x = width
	_text.size = Vector2(width, maxf(0.0, height - body_top - 7.0))
	# 控制提示與名牌同列，不占用正文或舞台。
	_continue.position = Vector2(rect.end.x - 144, top + 8)
	_continue.size = Vector2(112, 16)
	_layout_radio()
	_laying_out = false


func _layout_radio() -> void:
	if _radio_root == null:
		return
	# 正式任務列位於 y52；通訊不蓋該列，亦不進入21:9遮幅。
	_radio_home = Vector2(maxf(_safe_rect.position.x + 8, RADIO_HOME.x), maxf(RADIO_HOME.y, _safe_rect.position.y + 8))
	if _radio_slide == null or not _radio_slide.is_valid():
		_radio_root.position = _radio_home
	var width := minf(300.0, maxf(160.0, _safe_rect.end.x - _radio_home.x - 8))
	_radio_root.custom_minimum_size.x = width
	_radio_root.size.x = width
	_radio_text.custom_minimum_size.x = maxf(64, width - (_radio_root as RadioCard).side_width())
	_position_radio()


## Share the actual world/HUD reservations, including the complete entrance path.
## Moving the home must not restart the original slide or fade clocks.
func _position_radio() -> void:
	var origin := Vector2(maxf(_safe_rect.position.x + 8, RADIO_HOME.x), maxf(RADIO_HOME.y, _safe_rect.position.y + 8))
	var extent := _radio_root.size.max(_radio_root.get_combined_minimum_size())
	if _front_freezes() and not _radio_continue.visible:
		extent.y += _radio_continue.get_combined_minimum_size().y + 2.0
	var slide := 0.0 if Settings.get_reduce_ui_motion() else _radio_slide_distance
	var to_world := get_viewport().get_canvas_transform().affine_inverse() * get_final_transform()
	var best_cost := INF
	_radio_home = origin
	PromptLayout.collect_obstacles_except(null, _radio_obstacles)
	_radio_rects.resize(1)
	# Prefer the usual gutter; crowded views may use the shared world-text gutter.
	# Both remain inside the exact same cinematic safe rectangle.
	for gutter in 2:
		if is_finite(best_cost):
			break
		var margin := 8.0 if gutter == 0 else PromptLayout.SCREEN_MARGIN
		var bounds := to_world * _safe_rect.grow(-margin)
		# If the entire entrance path cannot fit, retain the fade in a clear static slot.
		for entrance in 2:
			if entrance == 1:
				if is_finite(best_cost):
					break
				slide = 0.0
				_radio_slide_distance = 0.0
				_radio_slide_offset = 0.0
			# Whole-height rows can skip a valid slot flush with a safe edge.
			for edge in 3:
				var anchor := origin
				if edge == 1:
					anchor.y = _safe_rect.position.y + margin
				elif edge == 2:
					anchor.y = _safe_rect.end.y - extent.y - margin
				_radio_rects[0] = to_world * Rect2(anchor - Vector2(slide, 0), extent + Vector2(slide, 0))
				var shifts := PromptLayout.solve(_radio_rects, _radio_obstacles, PromptLayout.GAP, bounds)
				if PromptLayout._fits[0] == 0:
					continue
				var candidate := anchor + to_world.affine_inverse().basis_xform(shifts[0])
				var distance := (candidate - origin).abs()
				var cost := distance.x + distance.y
				if cost < best_cost:
					best_cost = cost
					_radio_home = candidate
				if is_zero_approx(best_cost):
					break
	_radio_root.position = _radio_home + Vector2(_radio_slide_offset, 0)


func _set_radio_slide_offset(value: float) -> void:
	_radio_slide_offset = value if _radio_slide_distance > 0.0 else 0.0
	_radio_root.position = _radio_home + Vector2(_radio_slide_offset, 0)


func _display_changed() -> void:
	if Settings.get_reduce_ui_motion() and _radio_slide != null and _radio_slide.is_valid():
		_radio_slide.kill()
		_radio_slide_offset = 0.0
		_radio_root.position = _radio_home
		_radio_root.modulate.a = 1.0
	_layout_cinematic(Story.framing.safe_rect())


func _refresh_skip_hint() -> void:
	_skip.text = InputBindings.format("{ui_cancel} 跳過")
	_continue.text = InputBindings.format("{ui_accept} 繼續")
	if _radio_continue != null:
		_radio_continue.text = InputBindings.format("{ui_accept} 繼續")


func _build_radio() -> void:
	var card := RadioCard.new()
	card.hold_source = radio_hold_ratio
	_radio_root = card
	_radio_root.theme = UiKit.theme()
	_radio_root.position = RADIO_HOME
	_radio_root.custom_minimum_size = Vector2(300, 0)
	_radio_root.visible = false
	add_child(_radio_root)
	# 外觀（講者顏色、頭像格、名牌、訊號格、停留線）都在 RadioCard，這裡只管排隊、計時與擺放；設顏色條的顏色就是設講者的顏色。
	_radio_bar = card.accent
	_radio_portrait = card.portrait
	_radio_name = card.name_label
	var column := card.column
	_radio_text = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_text.custom_minimum_size = Vector2(240, 0)
	column.add_child(_radio_text)
	_radio_continue = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED)
	_radio_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_radio_continue.visible = false
	_radio_continue.text = InputBindings.format("{ui_accept} 繼續")
	column.add_child(_radio_continue)


## 顯示這一句通訊：面板原本隱藏時滑入，否則直接換字；兩者都有提示音。
func _reveal_radio(slide: bool) -> void:
	if slide:
		_slide_radio_in()
	else:
		_radio_root.modulate.a = 1.0
	Sfx.play(&"telegraph", -18.0, 0.0)


## 通訊面板從左側滑入（已經在顯示時不重播）。
func _slide_radio_in() -> void:
	if _radio_slide != null and _radio_slide.is_valid():
		_radio_slide.kill()
	_radio_slide_distance = RADIO_SLIDE
	_radio_slide_offset = 0.0
	_layout_radio()
	if Settings.get_reduce_ui_motion():
		_radio_slide_offset = 0.0
		_radio_root.position = _radio_home
		_radio_root.modulate.a = 1.0
		return
	_set_radio_slide_offset(-RADIO_SLIDE)
	_radio_root.modulate.a = 0.0
	_radio_slide = create_tween().set_parallel(true)
	_radio_slide.tween_method(_set_radio_slide_offset, -RADIO_SLIDE, 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_radio_slide.tween_property(_radio_root, "modulate:a", 1.0, 0.15)


## 以錨點為基準放置控制項（rect 的座標相對於錨點，例如底部錨點時 y 為負值）。
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x if rect.size.x > 0.0 else 0.0
	control.offset_bottom = rect.position.y + rect.size.y


func _portrait_texture(path: String) -> Texture2D:
	return RigLibrary.optional_texture(path) if not path.is_empty() else null


## 這一句通訊還剩多少停留時間（0～1，給面板畫停留線）；字還在出現、沉默中、或這一句要等玩家確認時回傳 -1（不畫）。
func radio_hold_ratio() -> float:
	if not _radio_active or _radio_wait > 0.0 or _radio_text.visible_ratio < 1.0:
		return -1.0
	# 重要通訊（凍結世界、等確認）沒有倒數。
	if has_method(&"is_radio_frozen") and bool(call(&"is_radio_frozen")):
		return -1.0
	var total := RADIO_HOLD_BASE + _radio_text.text.length() * RADIO_HOLD_PER_CHAR
	return clampf(_radio_hold / maxf(0.01, total), 0.0, 1.0)
