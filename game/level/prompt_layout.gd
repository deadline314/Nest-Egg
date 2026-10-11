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

static var _prompts: Array[WorldPrompt] = []
static var _obstacles: Dictionary[Node, Callable] = {}
static var _frame := -1
# 重複使用的暫存，避免每影格配置。
static var _active: Array[WorldPrompt] = []
static var _rects: Array[Rect2] = []
static var _obstacle_rects: Array[Rect2] = []
static var _placed: Array[Rect2] = []
static var _nudges := PackedVector2Array()
static var _shifts := PackedFloat32Array()
static var _edge_shifts := PackedFloat32Array()


static func register(prompt: WorldPrompt) -> void:
	if not _prompts.has(prompt):
		_prompts.append(prompt)


static func unregister(prompt: WorldPrompt) -> void:
	_prompts.erase(prompt)
	_active.erase(prompt)
	_frame = -1


## owner 是障礙物所在的節點；rect_getter 回傳它目前在世界座標的矩形。節點離開場景樹時自動取消。
static func add_obstacle(owner: Node, rect_getter: Callable) -> void:
	_obstacles[owner] = rect_getter
	owner.tree_exiting.connect(remove_obstacle.bind(owner), CONNECT_ONE_SHOT)


static func remove_obstacle(owner: Node) -> void:
	_obstacles.erase(owner)
	_frame = -1


## 有沒有正在顯示的提示框（照目前錯開後的位置）和這個世界座標矩形重疊。HUD 元件用它判斷要不要讓位。
static func covers(rect: Rect2) -> bool:
	if not rect.has_area():
		return false
	for prompt in _prompts:
		if is_instance_valid(prompt) and prompt.is_showing() and Rect2(prompt.base_rect().position + prompt._nudge, prompt.base_rect().size).intersects(rect):
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
		if is_instance_valid(prompt) and prompt.is_showing():
			_insert_sorted(prompt)
	if _active.is_empty():
		return
	_rects.clear()
	for prompt in _active:
		_rects.append(prompt.base_rect())
	_collect_obstacles()
	# 先把靠在畫面邊外的提示推回畫面內，再錯開：錯開的結果才不會又被推回去疊在一起。
	_keep_on_screen(_active[0].get_viewport())
	solve(_rects, _obstacle_rects)
	for i in _active.size():
		_active[i].set_nudge_target(_nudges[i] + Vector2(_edge_shifts[i], 0.0))


## 超出畫面左右邊的提示往內推（鏡頭停在地圖邊上時，靠邊的看板文字才不會被切掉）；結果記在 _edge_shifts，並直接平移 _rects。
static func _keep_on_screen(viewport: Viewport) -> void:
	_edge_shifts.resize(_rects.size())
	_edge_shifts.fill(0.0)
	if viewport == null:
		return
	var view := viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var left := view.position.x + SCREEN_MARGIN
	var right := view.end.x - SCREEN_MARGIN
	for i in _rects.size():
		var rect := _rects[i]
		if rect.size.x > right - left:
			continue
		if rect.position.x < left:
			_edge_shifts[i] = left - rect.position.x
		elif rect.end.x > right:
			_edge_shifts[i] = right - rect.end.x
		_rects[i].position.x += _edge_shifts[i]


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
static func solve(rects: Array[Rect2], obstacles: Array[Rect2], gap := GAP) -> PackedVector2Array:
	_nudges.resize(rects.size())
	_placed.clear()
	for i in rects.size():
		var rect := rects[i]
		var best := Vector2(0.0, -MAX_STACK * (rect.size.y + gap))
		var best_cost := INF
		for row in MAX_STACK + 1:
			var lift := row * (rect.size.y + gap)
			if lift >= best_cost:
				break
			_collect_shifts(rect, obstacles, gap)
			for dx in _shifts:
				var cost := absf(dx) + lift
				if cost < best_cost and not _is_blocked(Rect2(rect.position + Vector2(dx, -lift), rect.size), obstacles, gap):
					best = Vector2(dx, -lift)
					best_cost = cost
		_nudges[i] = best
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
	_obstacle_rects.clear()
	for owner in _obstacles:
		if is_instance_valid(owner) and not owner.is_queued_for_deletion() and _obstacles[owner].is_valid():
			var rect: Rect2 = _obstacles[owner].call()
			if rect.has_area() and rect.position.is_finite() and rect.size.is_finite():
				_obstacle_rects.append(rect)


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
