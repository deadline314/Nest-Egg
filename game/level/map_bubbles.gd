class_name MapBubbles
extends Node2D
## 地圖上的對話氣泡（ST-12）：講話的人頭上冒出一行短句，不鎖操作、不暫停、不改鏡頭，自己消失。
## 規格（見 .claude/skills/chapter-design）：每句 ≤ 30 字；同屏 1 個（NE-491：文字的交通管制，和教學看板輪流講話，見 TextTraffic），新的出現時舊的淡出；顯示時間 1.2 秒 + 0.1 秒 × 字數（上限 4.2 秒）；
## 戰鬥中只用 bark（≤ 16 字）。講者不在地圖上時（廣播裡的聲音）改用通訊面板，不會憑空冒出氣泡。
## 錨在世界、大小在螢幕（NE-493）：氣泡跟著講者（世界座標），字級、寬度、內距與尾巴是畫面像素（WorldText 的 addressed／ambient），不隨鏡頭倍率變大變小。
##
## 由 Level 建立並登記給 Story（Story.set_bubble_host）；劇本的 mode 為 bubbles 的場景交給它播。
## 氣泡跟著講者移動；來源宣告離場即取消該次對話。沒有在場介面的已釋放錨點仍保留最後位置閱讀。

## 一個場景的最後一句收起來之後發出。
signal scene_finished(scene_id: StringName)
## 精確取消原請求，不把來源離場當作讀完或發布故事結果。
signal scene_cancelled(scene_id: StringName, request: int)

const TEXT_LAYOUT = preload("res://game/level/world_text_layout.gd")

const MAX_VISIBLE := 1
const HOLD_BASE := 1.2
const HOLD_PER_CHAR := 0.1
const HOLD_MAX := 4.2
const FADE_IN := 0.12
const FADE_OUT := 0.3
## 內距、尾巴與圓角是畫面像素。
const PADDING := Vector2(6, 3)
## 氣泡底邊離講者腳底的高度（站立的人頭頂上方）。
const HEAD_HEIGHT := 52.0
const STACK_GAP := 3.0
const TAIL := 4.0
const NAME_GAP := 4.0
## 樣子（NE-491）：不是黑色方框，是圓角的淡色底；路人閒聊比對主角說的話更小、更窄、更淡（可以不讀；寬度與字級見 WorldText）。
const AMBIENT_ALPHA := 0.72
const PLATE_COLOR := Color("0a1219")
const PLATE_ALPHA := 0.82
const CORNER := 3.0
## 氣泡被擠開後離講者頭頂太遠（水平超過這麼多，或掉到頭頂以下）就先不顯示、等有位置再出來，不飛到別的地方。
const MAX_DRIFT := 56.0
## 等位置最多等多久（秒）：路人閒聊超過就安靜結束；對凜說的話等兩倍久後退回避讓後的位置照常顯示。場景不會因為一直沒有位置而卡住。
const DEFER_MAX := 6.0

## 講者 id -> 世界裡的 Node2D（講者在地圖上時回傳它，不在回傳 null）。由 Level 指定。
var anchor_resolver: Callable

var _font: Font
## 還沒開始顯示的句子：{ id, line, last }。
var _queue: Array[Dictionary] = []
## 正在顯示（含淡入淡出）的氣泡。
var _active: Array[Dictionary] = []
var _batch_serial := 0
var _absent_batches: Dictionary = {}
var crosshair: Crosshair
var _layout_frame := -1
var _layout_entries: Array[Dictionary] = []
var _layout_rects: Array[Rect2] = []
var _aim_clearance_rects: Array[Rect2] = []
var _layout_obstacles: Array[Rect2] = []


func _ready() -> void:
	# Continue observing modal ownership while the world is paused, without
	# consuming an unseen line's reading time or reporting its completion.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = WorldLayers.MAP_BUBBLES
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
	# 有凜參與的是對她說的話；其餘是路人自己的閒聊（優先順序較低、樣子更小更淡）。
	var voice: int = TextTraffic.Voice.ADDRESSED if lines.any(func(l: Dictionary) -> bool: return str(l.get("speaker", "")) == "rin") else TextTraffic.Voice.AMBIENT
	for i in lines.size():
		var target := _anchor_of(str(lines[i].get("speaker", "")))
		# Optional pure presence interface; Callable binds weakly to its original
		# source. Plain anchors and already-freed last positions keep legacy reading.
		var presence := Callable(target, &"is_present") if target != null and target.has_method(&"is_present") else Callable()
		_queue.append({"id": scene_id, "line": lines[i], "last": i == lines.size() - 1, "batch": _batch_serial, "request": request, "presence": presence, "voice": voice})
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
	TextTraffic.release(self)
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
	# 交通管制：要講話就提出要求；沒輪到（理論上氣泡優先於看板，不會發生）就先不出下一句。
	var granted := true
	if is_busy():
		granted = TextTraffic.claim(self, _current_voice())
	else:
		TextTraffic.release(self)
	_layout_boxes()
	for bubble in _active:
		# 等位置的氣泡不消耗閱讀時間；路人閒聊等超過 DEFER_MAX 就安靜地結束（沒顯示也不補）。
		if bool(bubble.get("deferred", false)):
			bubble["waited"] = float(bubble.get("waited", 0.0)) + delta
			if int(bubble.get("voice", 0)) == TextTraffic.Voice.AMBIENT and float(bubble["waited"]) > DEFER_MAX:
				bubble["age"] = float(bubble["hold"])
		else:
			bubble["age"] = float(bubble["age"]) + delta
	if granted:
		_start_next()
	_retire_finished(delta)
	# 前一句在這一格淡完：下一句同一格接上，不多等一格。
	if granted:
		_start_next()
	if not is_busy():
		set_process(false)
	queue_redraw()


## 目前在講（或下一句要講）的優先順序。
func _current_voice() -> int:
	if not _active.is_empty():
		return int(_active.back().get("voice", TextTraffic.Voice.AMBIENT))
	if not _queue.is_empty():
		return int(_queue.front().get("voice", TextTraffic.Voice.AMBIENT))
	return TextTraffic.Voice.NONE


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


## Admission belongs to the caller; a valid false result withdraws only this
## original batch. Query once per original request, outside the frame loop.
func cancel_unavailable(available: Callable) -> void:
	if not available.is_valid():
		return
	var cancelled := {}
	var checked := {}
	for entries: Array[Dictionary] in [_queue, _active]:
		for entry: Dictionary in entries:
			var batch: int = entry["batch"]
			if not checked.has(batch):
				var admitted: Variant = available.call(entry["id"], entry["request"])
				checked[batch] = not (admitted is bool and not admitted)
			if not checked[batch]:
				cancelled[batch] = {"id": entry["id"], "request": entry["request"]}
	_cancel_batches(cancelled)


func _cancel_absent_sources() -> void:
	_absent_batches.clear()
	for entry in _queue:
		if _source_is_absent(entry):
			_absent_batches[entry["batch"]] = {"id": entry["id"], "request": entry["request"]}
	for bubble in _active:
		if _source_is_absent(bubble):
			_absent_batches[bubble["batch"]] = {"id": bubble["id"], "request": bubble["request"]}
	_cancel_batches(_absent_batches)


func _release_bounds(bubble: Dictionary) -> void:
	bubble["rect"] = Rect2()
	var owner: Node = bubble["bounds_owner"]
	if is_instance_valid(owner):
		# Reading geometry must leave synchronously, before deferred Node deletion.
		PromptLayout.remove_obstacle(owner)
		owner.queue_free()


func _cancel_batches(cancelled: Dictionary) -> void:
	if cancelled.is_empty():
		return
	_queue = _queue.filter(func(entry: Dictionary) -> bool: return not cancelled.has(entry["batch"]))
	var kept: Array[Dictionary] = []
	for bubble in _active:
		if cancelled.has(bubble["batch"]):
			_release_bounds(bubble)
		else:
			kept.append(bubble)
	_active = kept
	_layout_frame = -1
	PromptLayout.invalidate()
	queue_redraw()
	set_process(is_busy())
	# Install the remaining queues and retire scratch data before callbacks.
	# A resumed waiter may enqueue another same-id request; preserve that work.
	var notifications := cancelled.values()
	cancelled.clear()
	for entry: Dictionary in notifications:
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
	# 同屏上限已滿：先讓舊的淡出，等它完全消失再出下一句（兩個氣泡不會同時在畫面上）。
	if _active.size() >= MAX_VISIBLE:
		for old: Dictionary in _active:
			if not bool(old["leaving"]):
				old["leaving"] = true
				old["leave_age"] = 0.0
		_queue.push_front(entry)
		return
	var bubble := {
		"id": entry["id"], "last": entry["last"], "batch": entry["batch"], "request": entry["request"], "presence": entry["presence"], "text": text, "name": str(line.get("name", "")), "color": line.get("color", Color.WHITE),
		"target": weakref(target), "pos": target.global_position, "age": 0.0, "hold": hold_time(text), "leaving": false, "leave_age": 0.0,
		"voice": entry.get("voice", TextTraffic.Voice.AMBIENT), "deferred": false,
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
	var finished: Array[StringName] = []
	for bubble in _active:
		if not bool(bubble["leaving"]) and float(bubble["age"]) >= float(bubble["hold"]):
			bubble["leaving"] = true
			bubble["leave_age"] = 0.0
		if bool(bubble["leaving"]):
			bubble["leave_age"] = float(bubble["leave_age"]) + delta
			if float(bubble["leave_age"]) >= FADE_OUT:
				_release_bounds(bubble)
				if bool(bubble["last"]):
					finished.append(bubble["id"])
				continue
		kept.append(bubble)
	_active = kept

	for id: StringName in finished:
		scene_finished.emit(id)

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
	var unit := WorldText.unit(self)
	var tail := TAIL * unit
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
		var kind := kind_of(bubble)
		var font_size := WorldText.font_size(kind)
		if not bubble.has("paragraph") or bubble.get("font_size", -1) != font_size:
			bubble["paragraph"] = WorldText.paragraph(str(bubble["text"]), kind)
			bubble["font_size"] = font_size
		bubble["unit"] = unit
		var key := str((bubble["pos"] as Vector2).round())
		var lift := float(stack_offset.get(key, 0.0))
		var paragraph: TextParagraph = bubble["paragraph"]
		var size := (paragraph.get_size() + PADDING * 2.0) * unit
		var anchor: Vector2 = bubble["pos"] + Vector2(0.0, -HEAD_HEIGHT - lift)
		var box := Rect2(anchor + Vector2(-size.x * 0.5, -size.y - tail), size)
		box.position.x = clampf(box.position.x, camera_rect.position.x + 4.0, camera_rect.end.x - size.x - 4.0)
		box.position.y = clampf(box.position.y, camera_rect.position.y + 4.0, camera_rect.end.y - size.y - 4.0)
		bubble["rect"] = box
		_layout_entries.append(bubble)
		_layout_rects.append(box)
		stack_offset[key] = lift + size.y + STACK_GAP + tail
	if _layout_rects.is_empty():
		return
	# Aiming stays a second pass here so a crowded ambient caption retains its original place.
	PromptLayout.collect_obstacles_except(self, _layout_obstacles, crosshair)
	var bounds := camera_rect.grow(-4.0)
	var nudges := PromptLayout.solve(_layout_rects, _layout_obstacles, STACK_GAP, bounds)
	for i in _layout_entries.size():
		_layout_entries[i]["rect"] = Rect2(_layout_rects[i].position + nudges[i], _layout_rects[i].size) if PromptLayout._fits[i] != 0 else Rect2()
		_defer_if_drifted(_layout_entries[i], _layout_rects[i], i, bounds)
	if PromptLayout._fits.has(0) or not is_instance_valid(crosshair):
		return
	var aim_bounds := crosshair.prompt_obstacle_rect()
	if not aim_bounds.has_area():
		return
	var overlaps := false
	_aim_clearance_rects.clear()
	for bubble in _layout_entries:
		var rect: Rect2 = bubble["rect"]
		_aim_clearance_rects.append(rect)
		overlaps = overlaps or rect.intersects(aim_bounds)
	if not overlaps:
		return
	# Use the reading rows already placed around actors, leaving the original layout when no row fits.
	_layout_obstacles.append(aim_bounds)
	nudges = PromptLayout.solve(_aim_clearance_rects, _layout_obstacles, STACK_GAP, bounds, true)
	if not PromptLayout._fits.has(0):
		for i in _layout_entries.size():
			_layout_entries[i]["rect"] = Rect2(_aim_clearance_rects[i].position + nudges[i], _aim_clearance_rects[i].size)
			_defer_if_drifted(_layout_entries[i], _layout_rects[i], i, bounds)


## 被擠到離講者太遠（或頭頂以下）時，先在講者頭頂往上、再在頭的兩側找一個不壓到別的東西的位置；
## 都沒有就先不顯示，等有位置再出來。尾巴永遠指得到講者。
func _defer_if_drifted(bubble: Dictionary, natural: Rect2, index: int, bounds: Rect2) -> void:
	var box: Rect2 = bubble.get("rect", Rect2())
	if box.has_area() and not _drifted(bubble, box):
		bubble["deferred"] = false
		return
	for candidate in _near_candidates(natural):
		if bounds.encloses(candidate) and not _blocked(candidate, index):
			bubble["rect"] = candidate
			bubble["deferred"] = false
			return
	# 等太久（玩家一直站在擠的地方）：路人閒聊本來就可以不讀，安靜地過去；對凜說的話等兩倍久後退回避讓後的位置照常顯示。
	var waited := float(bubble.get("waited", 0.0))
	if int(bubble.get("voice", 0)) == TextTraffic.Voice.ADDRESSED and waited > DEFER_MAX * 2.0 and box.has_area():
		bubble["deferred"] = false
		return
	bubble["rect"] = Rect2()
	bubble["deferred"] = true


func _drifted(bubble: Dictionary, box: Rect2) -> bool:
	var head: Vector2 = bubble["pos"] + Vector2(0.0, -HEAD_HEIGHT)
	return absf(box.get_center().x - head.x) > MAX_DRIFT + box.size.x * 0.5 or box.position.y > head.y


## 頭頂正上方往上疊（越過跟著主角的 HUD 與提示），再試頭的左右兩側。
func _near_candidates(natural: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var lift := 0.0
	while lift <= MAX_DRIFT * 1.5:
		result.append(Rect2(natural.position - Vector2(0.0, lift), natural.size))
		lift += 4.0
	var side := natural.size.x * 0.5 + 18.0
	for dy: float in [natural.size.y * 0.5, 0.0, -natural.size.y * 0.5]:
		for dx: float in [side, -side]:
			result.append(Rect2(natural.position + Vector2(dx, dy), natural.size))
	return result


func _blocked(candidate: Rect2, index: int) -> bool:
	for obstacle in _layout_obstacles:
		if obstacle.grow(PromptLayout.OBSTACLE_MARGIN).intersects(candidate):
			return true
	for j in _layout_entries.size():
		if j != index:
			var other: Rect2 = _layout_entries[j].get("rect", Rect2())
			if other.has_area() and other.grow(STACK_GAP).intersects(candidate):
				return true
	return false

func _draw() -> void:
	if _font == null or DialogueLayer.radio_visible():
		return
	_layout_boxes()
	for bubble in _active:
		var box: Rect2 = bubble.get("rect", Rect2())
		if not box.has_area():
			continue
		var ambient := int(bubble.get("voice", 0)) == TextTraffic.Voice.AMBIENT
		var alpha := _alpha_of(bubble) * (AMBIENT_ALPHA if ambient else 1.0)
		var color: Color = bubble["color"]
		var plate := Color(PLATE_COLOR, PLATE_ALPHA * alpha)
		var unit := float(bubble.get("unit", 1.0))
		# 尾巴（世界座標，尺寸換成畫面像素）：從最靠近講者的那一邊指向講者頭頂。
		var head: Vector2 = bubble["pos"] + Vector2(0.0, -HEAD_HEIGHT + 2.0)
		var tip := Vector2(clampf(head.x, box.position.x + (CORNER + 3.0) * unit, box.end.x - (CORNER + 3.0) * unit), box.end.y)
		var reach := minf((TAIL + 2.0) * unit, maxf(2.0 * unit, head.y - box.end.y))
		var point := tip + (head - tip).normalized() * reach if head.distance_to(tip) > 0.5 * unit else tip + Vector2(0, reach)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-3.0, -0.5) * unit, tip + Vector2(3.0, -0.5) * unit, point]), plate)
		# 被擠高或擠到旁邊時，尾巴到講者頭頂之間補一條淡淡的點線，看得出是誰在講。
		if head.distance_to(point) > 6.0 * unit:
			var steps := int(head.distance_to(point) / (4.0 * unit))
			for s in range(1, steps):
				draw_circle(point.lerp(head, float(s) / float(steps)), 0.8 * unit, Color(color.r, color.g, color.b, 0.55 * alpha))
		# 底、細軌與文字在畫面像素的座標裡畫（字在螢幕上的大小固定）。
		draw_set_transform(box.position, 0.0, Vector2.ONE * unit)
		var local := Rect2(Vector2.ZERO, box.size / unit)
		_draw_rounded(local, plate)
		if not ambient:
			# 對主角說的話：左邊一小段講者顏色的細軌（和地點標示同一種語言），標出是誰在講。
			draw_rect(Rect2(Vector2(1.5, CORNER), Vector2(1.5, local.size.y - CORNER * 2.0)), Color(color.r, color.g, color.b, 0.9 * alpha))
		var paragraph: TextParagraph = bubble["paragraph"]
		paragraph.draw(get_canvas_item(), PADDING + Vector2(1.5 if not ambient else 0.0, 0.0), Color(0.94, 0.97, 1.0, alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)


## 圓角的底（四個角各用一段弧），不是方框。
func _draw_rounded(box: Rect2, color: Color) -> void:
	var r := minf(CORNER, minf(box.size.x, box.size.y) * 0.5)
	var points := PackedVector2Array()
	var centers := [Vector2(box.end.x - r, box.position.y + r), Vector2(box.end.x - r, box.end.y - r), Vector2(box.position.x + r, box.end.y - r), Vector2(box.position.x + r, box.position.y + r)]
	for i in 4:
		for k in 4:
			var angle := -PI * 0.5 + PI * 0.5 * (float(i) + float(k) / 3.0)
			points.append((centers[i] as Vector2) + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)

## 氣泡是哪一類世界文字：有凜參與的是對她說的話，其餘是路人閒聊。
static func kind_of(bubble: Dictionary) -> StringName:
	return &"ambient" if int(bubble.get("voice", 0)) == TextTraffic.Voice.AMBIENT else &"addressed"


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
