class_name PromptLayout
extends RefCounted
## 世界提示的自動錯開：同時顯示的提示文字在原位置互相重疊，或蓋住人物時，由左到右依序找到不重疊的位置（優先上下錯開，人物擋住時改往旁邊讓開）。
## 提示（WorldPrompt）加入與離開場景時登記；每影格第一個更新的提示重算一次，之後各提示照自己的結果移動。
## 人物這類不能被蓋住的東西用 add_obstacle 登記。只處理「正在顯示」的提示，平常沒有提示時不花任何運算。

## 上下兩個提示之間的間隙。
const GAP := 2.0
## 提示框離人物（障礙）的最小距離。
const OBSTACLE_MARGIN := 2.0
## 最多往上疊幾格（保底，避免異常資料讓提示飛出畫面）。
const MAX_STACK := 6
## 提示框離畫面左右邊緣至少留這麼多（世界像素）：地圖邊上的看板文字不能被畫面切掉。
const SCREEN_MARGIN := 4.0
const TEXT_LAYOUT = preload("res://game/level/world_text_layout.gd")

static var _prompts: Array[WorldPrompt] = []
static var _obstacles: Dictionary[Node, Callable] = {}
static var _reading_surfaces: Dictionary[Node, Callable] = {}
static var _frame := -1
# 重複使用的暫存，避免每影格配置。
static var _active: Array[WorldPrompt] = []
static var _rects: Array[Rect2] = []
static var _obstacle_rects: Array[Rect2] = []
static var _placed: Array[Rect2] = []
static var _nudges := PackedVector2Array()
static var _fits := PackedByteArray()
static var _shifts := PackedFloat32Array()
static var _edge_shifts := PackedVector2Array()


static func invalidate() -> void:
	_frame = -1


static func register(prompt: WorldPrompt) -> void:
	if not _prompts.has(prompt):
		_prompts.append(prompt)
		invalidate()


static func unregister(prompt: WorldPrompt) -> void:
	_prompts.erase(prompt)
	_active.erase(prompt)
	_frame = -1


## owner 是障礙物所在的節點；rect_getter 回傳它目前在世界座標的矩形。節點離開場景樹時自動取消。
static func add_obstacle(owner: Node, rect_getter: Callable, reading_surface := false) -> void:
	_obstacles[owner] = rect_getter
	if reading_surface:
		_reading_surfaces[owner] = rect_getter
	owner.tree_exiting.connect(remove_obstacle.bind(owner), CONNECT_ONE_SHOT)
	invalidate()


static func remove_obstacle(owner: Node) -> void:
	_obstacles.erase(owner)
	_reading_surfaces.erase(owner)
	_frame = -1


## 有沒有正在顯示的提示框（照目前錯開後的位置）和這個世界座標矩形重疊。HUD 元件用它判斷要不要讓位。
static func covers(rect: Rect2) -> bool:
	if not rect.has_area():
		return false
	for prompt in _prompts:
		if is_instance_valid(prompt) and prompt.is_showing() and Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size).intersects(rect):
			return true
	for owner in _reading_surfaces:
		if is_instance_valid(owner) and not owner.is_queued_for_deletion() and _reading_surfaces[owner].is_valid():
			var surface: Rect2 = _reading_surfaces[owner].call()
			if surface.has_area() and surface.intersects(rect):
				return true
	return false


## 每影格由正在顯示的提示呼叫；同一影格只算一次。
static func update() -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	_active.clear()
	for prompt in _prompts:
		if is_instance_valid(prompt) and prompt.layout_requested():
			_insert_sorted(prompt)
	if _active.is_empty():
		return
	_rects.clear()
	for prompt in _active:
		_rects.append(prompt.base_rect())
	_collect_obstacles()
	# 先把靠在畫面邊外的提示推回畫面內，再錯開：錯開的結果才不會又被推回去疊在一起。
	_keep_on_screen(_active[0].get_viewport())
	var viewport := _active[0].get_viewport()
	var bounds := TEXT_LAYOUT.world_rect(viewport)
	solve(_rects, _obstacle_rects, GAP, bounds.grow(-SCREEN_MARGIN))
	for i in _active.size():
		_active[i].set_nudge_target(_nudges[i] + _edge_shifts[i], _fits[i] != 0)


## Clamp initial rectangles to the view before the bounded obstacle search.
static func _keep_on_screen(viewport: Viewport) -> void:
	_edge_shifts.resize(_rects.size())
	_edge_shifts.fill(Vector2.ZERO)
	if viewport == null:
		return
	var view := TEXT_LAYOUT.world_rect(viewport)
	view = view.grow(-SCREEN_MARGIN)
	for i in _rects.size():
		var rect := _rects[i]
		if rect.size.x > view.size.x or rect.size.y > view.size.y:
			continue
		var position := Vector2(clampf(rect.position.x, view.position.x, view.end.x - rect.size.x), clampf(rect.position.y, view.position.y, view.end.y - rect.size.y))
		_edge_shifts[i] = position - rect.position
		_rects[i].position = position


## 由左到右排好（x 相同時以實例編號決定，順序固定不會閃動）。
static func _insert_sorted(prompt: WorldPrompt) -> void:
	var key := prompt.base_rect().position.x
	var index := _active.size()
	while index > 0:
		var other := _active[index - 1]
		var other_x := other.base_rect().position.x
		if other_x < key or (other_x == key and other.get_instance_id() < prompt.get_instance_id()):
			break
		index -= 1
	_active.insert(index, prompt)


## 純運算：rects 是各提示在原位置的矩形（已由左到右排好），obstacles 是不能蓋住的矩形。
## 每個提示從「原位」開始，找移動代價最小的空位：往上疊一格的代價與橫向移動同單位，
## 所以一般是上下錯開，遇到人物擋在上方時改成往旁邊讓開。結果是每個提示的位移（x 橫向、y 往上為負），放在 _nudges 並回傳。
static func solve(rects: Array[Rect2], obstacles: Array[Rect2], gap := GAP, bounds := Rect2()) -> PackedVector2Array:
	_nudges.resize(rects.size())
	_fits.resize(rects.size())
	_fits.fill(0)
	_placed.clear()
	for i in rects.size():
		var rect := rects[i]
		var best := Vector2.ZERO if bounds.has_area() else Vector2(0.0, -MAX_STACK * (rect.size.y + gap))
		var best_cost := INF
		for step in (MAX_STACK * 2 + 1 if bounds.has_area() else MAX_STACK + 1):
			var row := int((step + 1) / 2) if bounds.has_area() else step
			var dy := row * (rect.size.y + gap) * (1.0 if bounds.has_area() and step > 0 and step % 2 == 0 else -1.0)
			if absf(dy) >= best_cost:
				break
			_collect_shifts(rect, obstacles, gap)
			if bounds.has_area():
				_shifts.append(bounds.position.x - rect.position.x)
				_shifts.append(bounds.end.x - rect.end.x)
			for dx in _shifts:
				var cost := absf(dx) + absf(dy)
				var candidate := Rect2(rect.position + Vector2(dx, dy), rect.size)
				if bounds.has_area() and not bounds.encloses(candidate):
					continue
				if cost < best_cost and not _is_blocked(candidate, obstacles, gap):
					best = Vector2(dx, dy)
					best_cost = cost
					_fits[i] = 1
		_nudges[i] = best
		if not bounds.has_area() or _fits[i] != 0:
			_placed.append(Rect2(rect.position + best, rect.size))
	return _nudges


## 候選的橫向位移：原位，以及貼在每個已放好的提示與障礙左右兩側。
static func _collect_shifts(rect: Rect2, obstacles: Array[Rect2], gap: float) -> void:
	_shifts.clear()
	_shifts.append(0.0)
	for other in _placed:
		_shifts.append(other.end.x + gap - rect.position.x)
		_shifts.append(other.position.x - gap - rect.end.x)
	for other in obstacles:
		var padded := other.grow(OBSTACLE_MARGIN)
		_shifts.append(padded.end.x + gap - rect.position.x)
		_shifts.append(padded.position.x - gap - rect.end.x)


static func _is_blocked(rect: Rect2, obstacles: Array[Rect2], gap: float) -> bool:
	var probe := rect.grow(gap * 0.5)
	for other in _placed:
		if probe.intersects(other):
			return true
	for other in obstacles:
		if rect.intersects(other.grow(OBSTACLE_MARGIN)):
			return true
	return false


## Fresh real-world rectangles; do not reuse an earlier frame's screen-HUD position.
static func _collect_obstacles() -> void:
	collect_obstacles_except(null, _obstacle_rects)


## Bubble layout excludes its own child owners, avoiding feedback from last frame's boxes.
static func collect_obstacles_except(excluded_owner: Node, output: Array[Rect2]) -> void:
	output.clear()
	for owner in _obstacles:
		if excluded_owner != null and is_instance_valid(owner) and excluded_owner.is_ancestor_of(owner):
			continue
		if is_instance_valid(owner) and not owner.is_queued_for_deletion() and _obstacles[owner].is_valid():
			var rect: Rect2 = _obstacles[owner].call()
			if rect.has_area() and rect.position.is_finite() and rect.size.is_finite():
				output.append(rect)


## Both the reading position and its complete trajectory must remain clear.
static func can_slide(prompt: WorldPrompt, target: Vector2) -> bool:
	var start := Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size)
	var delta := target - prompt._nudge
	var bounds := TEXT_LAYOUT.world_rect(prompt.get_viewport()).grow(-SCREEN_MARGIN)
	if not bounds.encloses(start) or not bounds.encloses(Rect2(start.position + delta, start.size)):
		return false
	_collect_obstacles()
	for obstacle in _obstacle_rects:
		if _sweeps_through(start, delta, obstacle.grow(OBSTACLE_MARGIN)):
			return false
	for other in _prompts:
		if other != prompt and is_instance_valid(other) and other.visible and other._alpha > 0.0 and other._layout_allowed and not other._presentation_blocked():
			if _sweeps_through(start, delta, Rect2(other.base_rect().position + other._nudge, other.base_rect().size).grow(GAP)):
				return false
	return true


## Swept AABB: intersect the origin segment with the obstacle expanded by our size.
## Open intervals match Rect2.intersects; grazing an edge does not overlap its pixels.
static func _sweeps_through(rect: Rect2, delta: Vector2, obstacle: Rect2) -> bool:
	var low := obstacle.position - rect.size
	var high := obstacle.end
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if is_zero_approx(delta[axis]):
			if rect.position[axis] <= low[axis] or rect.position[axis] >= high[axis]:
				return false
		else:
			var first := (low[axis] - rect.position[axis]) / delta[axis]
			var last := (high[axis] - rect.position[axis]) / delta[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
		if enter >= leave:
			return false
	return true


## Caller-owned high-water output holds world endpoint pairs; returned prefix count is valid. Never move the target.
static func leader_segments(from: Vector2, to: Vector2, output: Array[Vector2], clearance := 0.0) -> int:
	_collect_obstacles()
	return clip_leader_segments(from, to, _obstacle_rects, output, clearance)


## Pure segment minus union of closed rectangles, without sorting/copying arrays.
## Every cursor advance reaches a new interval endpoint; at most N+1 visible spans.
static func clip_leader_segments(from: Vector2, to: Vector2, obstacles: Array[Rect2], output: Array[Vector2], clearance := 0.0) -> int:
	var written := 0
	if not from.is_finite() or not to.is_finite() or from == to or not is_finite(clearance) or clearance < 0.0:
		return 0
	var delta := to - from
	if not delta.is_finite():
		return 0
	var cursor := 0.0
	while cursor < 1.0:
		var covered_end := cursor
		var next_start := 1.0
		var next_end := 1.0
		for obstacle in obstacles:
			if not obstacle.has_area() or not obstacle.position.is_finite() or not obstacle.size.is_finite() or not obstacle.end.is_finite():
				continue
			var cut := segment_rect_interval(from, to, obstacle.grow(clearance))
			if cut.x >= cut.y:
				continue
			if cut.x <= cursor:
				covered_end = maxf(covered_end, cut.y)
			elif cut.x < next_start or (cut.x == next_start and cut.y > next_end):
				next_start = cut.x
				next_end = cut.y
		if covered_end > cursor:
			cursor = covered_end
			continue
		if next_start > cursor:
			if output.size() < written + 2:
				output.resize(written + 2)
			output[written] = from + delta * cursor
			output[written + 1] = from + delta * next_start
			written += 2
		cursor = next_end
	return written


## Slab interval in t=0..1; x>y means no cut. Exact-zero parallel handling.
static func segment_rect_interval(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	if not from.is_finite() or not to.is_finite() or not rect.has_area() or not rect.position.is_finite() or not rect.size.is_finite() or not rect.end.is_finite():
		return Vector2(1.0, -1.0)
	var start := 0.0
	var stop := 1.0
	var delta := to - from
	if not delta.is_finite():
		return Vector2(1.0, -1.0)
	for axis in 2:
		if delta[axis] == 0.0:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return Vector2(1.0, -1.0)
		else:
			var a := (rect.position[axis] - from[axis]) / delta[axis]
			var b := (rect.end[axis] - from[axis]) / delta[axis]
			start = maxf(start, minf(a, b))
			stop = minf(stop, maxf(a, b))
			if start > stop:
				return Vector2(1.0, -1.0)
	return Vector2(start, stop)
