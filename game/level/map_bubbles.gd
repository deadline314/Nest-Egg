class_name MapBubbles
extends Node2D
## 地圖上的對話氣泡（ST-12）：講話的人頭上冒出一行短句，不鎖操作、不暫停、不改鏡頭，自己消失。
## 規格（見 .claude/skills/chapter-design）：每句 ≤ 30 字；同屏 ≤ 2 個，新的出現時舊的淡出；顯示時間 1.2 秒 + 0.1 秒 × 字數（上限 4.2 秒）；
## 戰鬥中只用 bark（≤ 16 字）。講者不在地圖上時（廣播裡的聲音）改用通訊面板，不會憑空冒出氣泡。
##
## 由 Level 建立並登記給 Story（Story.set_bubble_host）；劇本的 mode 為 bubbles 的場景交給它播。
## 氣泡跟著講者移動；來源宣告離場即取消該次對話。沒有在場介面的已釋放錨點仍保留最後位置閱讀。

## 一個場景的最後一句收起來之後發出。
signal scene_finished(scene_id: StringName)
## 精確取消原請求，不把來源離場當作讀完或發布故事結果。
signal scene_cancelled(scene_id: StringName, request: int)

const TEXT_LAYOUT = preload("res://game/level/world_text_layout.gd")

const MAX_VISIBLE := 2
const HOLD_BASE := 1.2
const HOLD_PER_CHAR := 0.1
const HOLD_MAX := 4.2
const FADE_IN := 0.12
const FADE_OUT := 0.3
const FONT_SIZE := 9
const PADDING := Vector2(6, 3)
## 氣泡底邊離講者腳底的高度（站立的人頭頂上方）。
const HEAD_HEIGHT := 52.0
const STACK_GAP := 3.0
const TAIL := 4.0
const NAME_GAP := 4.0

## 講者 id -> 世界裡的 Node2D（講者在地圖上時回傳它，不在回傳 null）。由 Level 指定。
var anchor_resolver: Callable

var _font: Font
## 還沒開始顯示的句子：{ id, line, last }。
var _queue: Array[Dictionary] = []
## 正在顯示（含淡入淡出）的氣泡。
var _active: Array[Dictionary] = []
var _batch_serial := 0
var _absent_batches: Dictionary = {}
var _layout_frame := -1
var _layout_entries: Array[Dictionary] = []
var _layout_rects: Array[Rect2] = []
var _layout_obstacles: Array[Rect2] = []


func _ready() -> void:
	# Continue observing modal ownership while the world is paused, without
	# consuming an unseen line's reading time or reporting its completion.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	_font = UiKit.font()
	_font.changed.connect(_invalidate_layout)
	Settings.display_changed.connect(_invalidate_layout)
	LightKit.mark_emissive(self)
	set_process(false)


## 排入一個場景的句子（lines 是 Story.resolved_lines 的結果，含 speaker 與 text）。
func show_lines(scene_id: StringName, lines: Array[Dictionary], request := 0) -> void:
	if lines.is_empty():
		scene_finished.emit(scene_id)
		return
	_batch_serial += 1
	for i in lines.size():
		var target := _anchor_of(str(lines[i].get("speaker", "")))
		# Optional pure presence interface; Callable binds weakly to its original
		# source. Plain anchors and already-freed last positions keep legacy reading.
		var presence := Callable(target, &"is_present") if target != null and target.has_method(&"is_present") else Callable()
		_queue.append({"id": scene_id, "line": lines[i], "last": i == lines.size() - 1, "batch": _batch_serial, "request": request, "presence": presence})
	set_process(true)


## 這些句子的講者是不是全都在地圖上（是才用氣泡，否則整段改用通訊面板）。
func can_show_all(lines: Array[Dictionary]) -> bool:
	for line in lines:
		if _anchor_of(str(line.get("speaker", ""))) == null:
			return false
	return true


## 目前同時存在的氣泡數（測試與診斷用）。
func visible_count() -> int:
	return _active.size()


func is_busy() -> bool:
	return not _queue.is_empty() or not _active.is_empty()


static func hold_time(text: String) -> float:
	return minf(HOLD_MAX, HOLD_BASE + HOLD_PER_CHAR * float(text.length()))


func _anchor_of(speaker_id: String) -> Node2D:
	if not anchor_resolver.is_valid():
		return null
	var node: Variant = anchor_resolver.call(speaker_id)
	return node as Node2D if is_instance_valid(node) else null


func _exit_tree() -> void:
	# 關卡結束時還沒播完的場景一併結束，等著它的流程（Story.play_and_wait）不會卡住。
	for id in _pending_scene_ids():
		scene_finished.emit(id)
	_queue.clear()
	_active.clear()


func _pending_scene_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _queue + _active:
		if bool(entry.get("last", false)) and not ids.has(entry["id"]):
			ids.append(entry["id"])
	return ids


func _process(delta: float) -> void:
	_layout_frame = -1
	_cancel_absent_sources()
	var suspended := get_tree().paused or GameplayLock.is_locked() or Story.is_cinematic_active() or DialogueLayer.radio_visible()
	visible = not suspended
	if suspended:
		return
	for bubble in _active:
		bubble["age"] = float(bubble["age"]) + delta
	_start_next()
	_retire_finished(delta)
	if not is_busy():
		set_process(false)
	queue_redraw()


func _source_is_absent(entry: Dictionary) -> bool:
	var presence: Callable = entry.get("presence", Callable())
	if not presence.is_valid():
		return false
	var present: Variant = presence.call()
	return present is bool and not present


func _has_absent_active() -> bool:
	for bubble in _active:
		if _source_is_absent(bubble):
			return true
	return false


func _cancel_absent_sources() -> void:
	_absent_batches.clear()
	for entry in _queue:
		if _source_is_absent(entry):
			_absent_batches[entry["batch"]] = {"id": entry["id"], "request": entry["request"]}
	for bubble in _active:
		if _source_is_absent(bubble):
			_absent_batches[bubble["batch"]] = {"id": bubble["id"], "request": bubble["request"]}
	if _absent_batches.is_empty():
		return
	_queue = _queue.filter(func(entry: Dictionary) -> bool: return not _absent_batches.has(entry["batch"]))
	var kept: Array[Dictionary] = []
	for bubble in _active:
		if _absent_batches.has(bubble["batch"]):
			var owner: Node = bubble["bounds_owner"]
			if is_instance_valid(owner):
				owner.queue_free()
		else:
			kept.append(bubble)
	_active = kept
	_layout_frame = -1
	PromptLayout.invalidate()
	queue_redraw()
	# Install the remaining queues before callbacks. A resumed waiter may enqueue
	# another request, including the same scene id; never erase that new work.
	var cancelled := _absent_batches.values()
	_absent_batches.clear()
	for entry: Dictionary in cancelled:
		scene_cancelled.emit(entry["id"], entry["request"])


## 最新的一個氣泡顯示滿時間後，下一句才出來；超過同屏上限就讓最舊的先淡出。
func _start_next() -> void:
	if _queue.is_empty():
		return
	var newest: Dictionary = _active.back() if not _active.is_empty() else {}
	if not newest.is_empty() and float(newest["age"]) < float(newest["hold"]):
		return
	var entry: Dictionary = _queue.pop_front()
	var line: Dictionary = entry["line"]
	var speaker_id := str(line.get("speaker", ""))
	var target := _anchor_of(speaker_id)
	if target == null:
		# 講者剛好離開了地圖：略過這一句，不卡住場景。
		if bool(entry["last"]):
			scene_finished.emit(entry["id"])
		return
	var text := str(line.get("text", ""))
	var live := _active.filter(func(b: Dictionary) -> bool: return not bool(b["leaving"]))
	while live.size() >= MAX_VISIBLE:
		var oldest: Dictionary = live.pop_front()
		oldest["leaving"] = true
		oldest["leave_age"] = 0.0
	var bubble := {
		"id": entry["id"], "last": entry["last"], "batch": entry["batch"], "request": entry["request"], "presence": entry["presence"], "text": text, "name": str(line.get("name", "")), "color": line.get("color", Color.WHITE),
		"target": weakref(target), "pos": target.global_position, "age": 0.0, "hold": hold_time(text), "leaving": false, "leave_age": 0.0,
	}
	# Each bubble owns its obstacle; normal tree teardown removes it.
	var bounds := Node.new()
	add_child(bounds)
	bubble["bounds_owner"] = bounds
	_active.append(bubble)
	PromptLayout.add_obstacle(bounds, func() -> Rect2:
		if _source_is_absent(bubble):
			return Rect2()
		_layout_boxes()
		return bubble.get("rect", Rect2()), true)


func _retire_finished(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for bubble in _active:
		if not bool(bubble["leaving"]) and float(bubble["age"]) >= float(bubble["hold"]):
			bubble["leaving"] = true
			bubble["leave_age"] = 0.0
		if bool(bubble["leaving"]):
			bubble["leave_age"] = float(bubble["leave_age"]) + delta
			if float(bubble["leave_age"]) >= FADE_OUT:
				(bubble["bounds_owner"] as Node).queue_free()
				if bool(bubble["last"]):
					scene_finished.emit(bubble["id"])
				continue
		kept.append(bubble)
	_active = kept


# ---------------------------------------------------------------------------
# 繪製
# ---------------------------------------------------------------------------

func _invalidate_layout() -> void:
	_layout_frame = -1
	PromptLayout.invalidate()
	for bubble in _active:
		bubble.erase("paragraph")
	queue_redraw()


func _layout_boxes() -> void:
	var frame := Engine.get_process_frames()
	if frame == _layout_frame and not _has_absent_active():
		return
	_layout_frame = frame
	var suspended := get_tree().paused or GameplayLock.is_locked() or Story.is_cinematic_active() or DialogueLayer.radio_visible()
	var camera_rect := _visible_world_rect()
	var width := TEXT_LAYOUT.content_width(get_viewport(), PADDING)
	var font_size := roundi(FONT_SIZE * Settings.get_ui_text_scale())
	var stack_offset := {}
	_layout_entries.clear()
	_layout_rects.clear()
	for i in range(_active.size() - 1, -1, -1):
		var bubble := _active[i]
		var target: Node2D = (bubble["target"] as WeakRef).get_ref() as Node2D
		if target != null:
			bubble["pos"] = target.global_position
		bubble["rect"] = Rect2()
		if suspended or _source_is_absent(bubble) or not camera_rect.grow(32.0).has_point(bubble["pos"]):
			continue
		if not bubble.has("paragraph") or not is_equal_approx(bubble.get("layout_width", -1.0), width) or bubble.get("font_size", -1) != font_size:
			bubble["paragraph"] = TEXT_LAYOUT.paragraph(str(bubble["text"]), _font, font_size, width)
			bubble["layout_width"] = width
			bubble["font_size"] = font_size
		var key := str((bubble["pos"] as Vector2).round())
		var lift := float(stack_offset.get(key, 0.0))
		var paragraph: TextParagraph = bubble["paragraph"]
		var size := paragraph.get_size() + PADDING * 2.0
		var anchor: Vector2 = bubble["pos"] + Vector2(0.0, -HEAD_HEIGHT - lift)
		var box := Rect2(anchor + Vector2(-size.x * 0.5, -size.y - TAIL), size)
		box.position.x = clampf(box.position.x, camera_rect.position.x + 4.0, camera_rect.end.x - size.x - 4.0)
		box.position.y = clampf(box.position.y, camera_rect.position.y + 4.0, camera_rect.end.y - size.y - 4.0)
		bubble["rect"] = box
		_layout_entries.append(bubble)
		_layout_rects.append(box)
		stack_offset[key] = lift + size.y + STACK_GAP + TAIL
	PromptLayout.collect_obstacles_except(self, _layout_obstacles)
	var nudges := PromptLayout.solve(_layout_rects, _layout_obstacles, STACK_GAP, camera_rect.grow(-4.0))
	for i in _layout_entries.size():
		_layout_entries[i]["rect"] = Rect2(_layout_rects[i].position + nudges[i], _layout_rects[i].size) if PromptLayout._fits[i] != 0 else Rect2()


func _draw() -> void:
	if _font == null or DialogueLayer.radio_visible():
		return
	_layout_boxes()
	for bubble in _active:
		var box: Rect2 = bubble.get("rect", Rect2())
		if not box.has_area():
			continue
		var alpha := _alpha_of(bubble)
		var color: Color = bubble["color"]
		draw_rect(box, Color(0.04, 0.06, 0.1, alpha))
		draw_rect(box, Color(color.r, color.g, color.b, alpha), false, 1.0)
		var tail_x := clampf((bubble["pos"] as Vector2).x, box.position.x + 4.0, box.end.x - 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(tail_x - 3.0, box.end.y), Vector2(tail_x + 3.0, box.end.y), Vector2(tail_x, box.end.y + TAIL)]), Color(color.r, color.g, color.b, alpha))
		var paragraph: TextParagraph = bubble["paragraph"]
		paragraph.draw(get_canvas_item(), box.position + PADDING, Color(0.94, 0.97, 1.0, alpha))


func _alpha_of(bubble: Dictionary) -> float:
	var fade_in := clampf(float(bubble["age"]) / FADE_IN, 0.0, 1.0)
	var fade_out := 1.0 - clampf(float(bubble["leave_age"]) / FADE_OUT, 0.0, 1.0) if bool(bubble["leaving"]) else 1.0
	return fade_in * fade_out


## 目前鏡頭看得到的世界範圍（氣泡不會被推出畫面外）。
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(-100000, -100000, 200000, 200000)
	return TEXT_LAYOUT.world_rect(viewport)
