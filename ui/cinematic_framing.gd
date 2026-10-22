class_name CinematicFraming
extends CanvasLayer
## Story 持有的畫幅服務。只改遮幅；不縮放世界、不取得 GameplayLock、不寫故事狀態。
## 正式演出以 owner/token 管理，可巢狀；預告只讀人物／入口當下的可用性。

signal safe_rect_changed(rect: Rect2)
signal preview_target_changed(target: Node2D)

const ASPECT := 21.0 / 9.0
const ENTER_DISTANCE := 80.0
const EXIT_DISTANCE := 100.0
const SWITCH_ADVANTAGE := 16.0
const VERTICAL_RANGE := 56.0
const CHECK_INTERVAL := 0.1
const EASE_SECONDS := 0.28

var amount := 0.0:
	set(value):
		amount = clampf(value, 0.0, 1.0)
		_layout()
var _top: ColorRect
var _bottom: ColorRect
var _scopes: Dictionary[int, Dictionary] = {}
var _next_token := 0
var _targets: Array[Node2D] = []
var _consumed_targets: Dictionary[int, bool] = {}
var _selected: Node2D
var _player: Player
var _check_left := 0.0
var _goal := 0.0
var _tween: Tween


func _ready() -> void:
	layer = UiLayers.FRAMING
	process_mode = Node.PROCESS_MODE_ALWAYS
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		if top:
			_top = bar
		else:
			_bottom = bar
	get_viewport().size_changed.connect(_layout)
	Settings.display_changed.connect(_settings_changed)
	EventBus.player_spawned.connect(_player_spawned)
	EventBus.player_died.connect(func(_cause: StringName) -> void: reset())
	_layout()
	set_physics_process(false)


static func rect_for(view_size: Vector2, ratio := 1.0) -> Rect2:
	var inset := maxf(0.0, (view_size.y - view_size.x / ASPECT) * 0.5) * clampf(ratio, 0.0, 1.0)
	return Rect2(Vector2(0, inset), Vector2(maxf(0, view_size.x), maxf(0, view_size.y - 2.0 * inset)))


func safe_rect() -> Rect2:
	return rect_for(get_viewport().get_visible_rect().size, amount)


func _layout() -> void:
	if not is_instance_valid(_top):
		return
	var view_size := get_viewport().get_visible_rect().size
	var rect := rect_for(view_size, amount)
	_top.position = Vector2.ZERO
	_top.size = Vector2(view_size.x, rect.position.y)
	_bottom.position = Vector2(0, rect.end.y)
	_bottom.size = _top.size
	_top.visible = rect.position.y > 0.0
	_bottom.visible = _top.visible
	safe_rect_changed.emit(rect)


func acquire(owner: Node) -> int:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
		push_error("[CinematicFraming] 演出來源必須位於場景樹中且未等待刪除。")
		return 0
	_next_token += 1
	var token := _next_token
	var cleanup := release.bind(token)
	_scopes[token] = {"owner": weakref(owner), "cleanup": cleanup}
	owner.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	_select(null)
	_set_goal(1.0)
	return token


func release(token: int) -> void:
	if not _scopes.has(token):
		return
	var entry := _scopes[token]
	_scopes.erase(token)
	var owner := (entry.owner as WeakRef).get_ref() as Node
	if is_instance_valid(owner) and owner.tree_exiting.is_connected(entry.cleanup):
		owner.tree_exiting.disconnect(entry.cleanup)
	_set_goal(0.0 if _scopes.is_empty() else 1.0)
	_check_left = 0.0


func scope_count() -> int:
	return _scopes.size()


func register_target(target: Node2D) -> void:
	if not is_instance_valid(target) or _targets.has(target):
		return
	_targets.append(target)
	target.tree_exiting.connect(unregister_target.bind(target), CONNECT_ONE_SHOT)
	set_physics_process(true)


func unregister_target(target: Node2D) -> void:
	_targets.erase(target)
	_consumed_targets.erase(target.get_instance_id())
	if _selected == target:
		_select(null)
		if _scopes.is_empty():
			_set_goal(0.0)
	set_physics_process(not _targets.is_empty())


func selected_target() -> Node2D:
	return _selected if is_instance_valid(_selected) else null


## 開始過的來源須退出距離後才再預告，避免播完站原地又把黑邊收起／展開。
func interaction_started(target: Node2D) -> void:
	_consumed_targets[target.get_instance_id()] = true


## 只在確認輸入時選擇互動來源；戰鬥抑制預告不會取消既有交談能力。
func is_interaction_target(target: Node2D) -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return false
	var closest: Node2D
	var distance := NpcActor.INTERACT_RANGE + 0.01
	for candidate in _targets:
		if not is_instance_valid(candidate) or not bool(candidate.call("interaction_available")):
			continue
		var offset := candidate.global_position - player.global_position
		if absf(offset.y) <= VERTICAL_RANGE and absf(offset.x) < distance:
			closest = candidate
			distance = absf(offset.x)
	return closest == target


func _player_spawned(player: Node2D) -> void:
	_player = player as Player
	_check_left = 0.0


func _physics_process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or not _scopes.is_empty():
		return
	_check_left = CHECK_INTERVAL
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
	if not is_instance_valid(_player) or _player.is_dead() or _player.state == Player.State.MOUNTED \
			or get_tree().paused or GameplayLock.is_locked() or Music.engaged_enemies() > 0:
		_select(null)
		_set_goal(0.0, true)
		return
	var best: Node2D
	var best_distance := ENTER_DISTANCE
	var current_distance := INF
	for target in _targets:
		if not is_instance_valid(target) or not target.is_inside_tree():
			continue
		var offset := target.global_position - _player.global_position
		var id := target.get_instance_id()
		if _consumed_targets.has(id):
			if absf(offset.x) > EXIT_DISTANCE or absf(offset.y) > VERTICAL_RANGE:
				_consumed_targets.erase(id)
			else:
				continue
		if not bool(target.call("preview_available")):
			continue
		if absf(offset.y) > VERTICAL_RANGE:
			continue
		var distance := absf(offset.x)
		if target == _selected and distance <= EXIT_DISTANCE:
			current_distance = distance
		if distance < best_distance:
			best = target
			best_distance = distance
	if current_distance < INF and (best == null or best_distance + SWITCH_ADVANTAGE >= current_distance):
		best = _selected
		best_distance = current_distance
	_select(best)
	_set_goal(clampf((EXIT_DISTANCE - best_distance) / (EXIT_DISTANCE - NpcActor.INTERACT_RANGE), 0.0, 1.0) if best != null else 0.0)


func _select(target: Node2D) -> void:
	if _selected == target:
		return
	_selected = target
	preview_target_changed.emit(target)


func _set_goal(goal: float, immediate := false) -> void:
	if is_equal_approx(_goal, goal) and not immediate:
		return
	_goal = goal
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if immediate or Settings.get_reduce_ui_motion():
		amount = goal
		return
	# 來源在物理影格切換；遮幅也用同一階段推進，避免低幀率時頁首多等idle影格。
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_ignore_time_scale(true)
	_tween.tween_property(self, "amount", goal, EASE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _settings_changed() -> void:
	if Settings.get_reduce_ui_motion():
		_set_goal(_goal, true)
	_layout()


func reset() -> void:
	for token in _scopes.keys():
		release(token)
	_select(null)
	_set_goal(0.0, true)
	_check_left = 0.0


func clear_preview() -> void:
	_select(null)
	_set_goal(0.0 if _scopes.is_empty() else 1.0, true)
