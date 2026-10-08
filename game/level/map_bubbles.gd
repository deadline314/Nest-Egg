class_name MapBubbles
extends Node2D
## 地圖上的對話氣泡（ST-12）：講話的人頭上冒出一行短句，不鎖操作、不暫停、不改鏡頭，自己消失。
## 規格（見 .claude/skills/chapter-design）：每句 ≤ 30 字；同屏 ≤ 2 個，新的出現時舊的淡出；顯示時間 1.2 秒 + 0.1 秒 × 字數（上限 4.2 秒）；
## 戰鬥中只用 bark（≤ 16 字）。講者不在地圖上時（廣播裡的聲音）改用通訊面板，不會憑空冒出氣泡。
##
## 由 Level 建立並登記給 Story（Story.set_bubble_host）；劇本的 mode 為 bubbles 的場景交給它播。
## 氣泡跟著講者移動；講者不見了就留在最後的位置。

## 一個場景的最後一句收起來之後發出。
signal scene_finished(scene_id: StringName)

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


func _ready() -> void:
	z_index = 30
	_font = UiKit.font()
	LightKit.mark_emissive(self)
	set_process(false)


## 排入一個場景的句子（lines 是 Story.resolved_lines 的結果，含 speaker 與 text）。
func show_lines(scene_id: StringName, lines: Array[Dictionary]) -> void:
	if lines.is_empty():
		scene_finished.emit(scene_id)
		return
	for i in lines.size():
		_queue.append({"id": scene_id, "line": lines[i], "last": i == lines.size() - 1})
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
	for bubble in _active:
		bubble["age"] = float(bubble["age"]) + delta
	_start_next()
	_retire_finished(delta)
	if not is_busy():
		set_process(false)
	queue_redraw()


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
	_active.append({
		"id": entry["id"], "last": entry["last"], "text": text, "name": str(line.get("name", "")), "color": line.get("color", Color.WHITE),
		"target": weakref(target), "pos": target.global_position, "age": 0.0, "hold": hold_time(text), "leaving": false, "leave_age": 0.0,
	})


func _retire_finished(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for bubble in _active:
		if not bool(bubble["leaving"]) and float(bubble["age"]) >= float(bubble["hold"]):
			bubble["leaving"] = true
			bubble["leave_age"] = 0.0
		if bool(bubble["leaving"]):
			bubble["leave_age"] = float(bubble["leave_age"]) + delta
			if float(bubble["leave_age"]) >= FADE_OUT:
				if bool(bubble["last"]):
					scene_finished.emit(bubble["id"])
				continue
		kept.append(bubble)
	_active = kept


# ---------------------------------------------------------------------------
# 繪製
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _font == null:
		return
	var camera_rect := _visible_world_rect()
	var stack_offset := {}
	# 同一個講者的氣泡由新到舊往上疊。
	for i in range(_active.size() - 1, -1, -1):
		var bubble := _active[i]
		var target: Node2D = (bubble["target"] as WeakRef).get_ref() as Node2D
		if target != null:
			bubble["pos"] = target.global_position
		var key := str((bubble["pos"] as Vector2).round())
		var lift := float(stack_offset.get(key, 0.0))
		var size := _font.get_string_size(str(bubble["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE) + PADDING * 2.0
		var alpha := _alpha_of(bubble)
		var anchor: Vector2 = (bubble["pos"] as Vector2) + Vector2(0.0, -HEAD_HEIGHT - lift)
		var box := Rect2(anchor + Vector2(-size.x * 0.5, -size.y - TAIL), size)
		box.position.x = clampf(box.position.x, camera_rect.position.x + 4.0, camera_rect.end.x - size.x - 4.0)
		stack_offset[key] = lift + size.y + STACK_GAP + TAIL
		var color: Color = bubble["color"]
		draw_rect(box, Color(0.04, 0.06, 0.1, 0.88 * alpha))
		draw_rect(box, Color(color.r, color.g, color.b, alpha), false, 1.0)
		var tail_x := clampf(anchor.x, box.position.x + 4.0, box.end.x - 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(tail_x - 3.0, box.end.y), Vector2(tail_x + 3.0, box.end.y), Vector2(tail_x, box.end.y + TAIL)]),
				Color(color.r, color.g, color.b, alpha))
		draw_string(_font, box.position + Vector2(PADDING.x, PADDING.y + _font.get_ascent(FONT_SIZE)), str(bubble["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.94, 0.97, 1.0, alpha))


func _alpha_of(bubble: Dictionary) -> float:
	var fade_in := clampf(float(bubble["age"]) / FADE_IN, 0.0, 1.0)
	var fade_out := 1.0 - clampf(float(bubble["leave_age"]) / FADE_OUT, 0.0, 1.0) if bool(bubble["leaving"]) else 1.0
	return fade_in * fade_out


## 目前鏡頭看得到的世界範圍（氣泡不會被推出畫面外）。
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(-100000, -100000, 200000, 200000)
	var inverse := viewport.get_canvas_transform().affine_inverse()
	var top_left := inverse * Vector2.ZERO
	var bottom_right := inverse * viewport.get_visible_rect().size
	return Rect2(top_left, bottom_right - top_left)
