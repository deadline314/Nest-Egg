class_name EncounterZone
extends Node2D
## 鎖場遭遇（ST-11，區域高潮）：玩家走進範圍 → 鎖上 channel 的競技場閘門 → 範圍內的敵人（加上增援）全部倒下 → 閘門升起。
## 範圍由 data.size_tiles 決定，原點是範圍底邊的中點；成員是玩家走進時範圍內還活著的敵人，所以敵人只要事先擺在範圍裡就好。
##
## 容錯：成員全部已經死了（持久世界裡先前殺光）就直接視為完成、不鎖人；鎖了超過 data.max_lock_seconds 強制解鎖並記錄；
## 玩家死亡時關卡整個重建，競技場閘門一律從打開開始，不會把人關在裡面。完成狀態存進世界狀態，之後不再觸發。

const SIDE_MARGIN := 24.0
const CHECK_INTERVAL := 0.25
const FEET_MARGIN := 8.0

## 生成增援敵人：Callable(EnemyData, Vector2 世界座標) -> Enemy（由 Level 指定）。
var spawner: Callable
var data: MechanismData
var cell := Vector2i.ZERO
## 這場遭遇的狀態：idle 尚未開始、active 進行中、cleared 已完成。
var state: StringName = &"idle"

var _tile := 16
var _zone := Rect2()
var _members: Array[WeakRef] = []
var _reinforce_index := 0
var _lock_time := 0.0
var _check_left := 0.0
var _area: Area2D


func configure(p_data: MechanismData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	_tile = tile_size


func _ready() -> void:
	if data == null:
		push_error("[EncounterZone] 未指定 MechanismData，已移除。")
		queue_free()
		return
	_zone = Rect2(Vector2(-data.size_tiles.x * _tile * 0.5, -data.size_tiles.y * _tile), Vector2(data.size_tiles) * _tile)
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = Layers.PLAYER
	_area.monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = _zone.size
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = _zone.get_center()
	_area.add_child(shape_node)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	add_to_group(WorldState.GROUP)
	set_physics_process(false)


func _on_body_entered(body: Node2D) -> void:
	if state == &"idle" and Pickup.resolve_player(body) != null:
		begin()


## 開始鎖場（玩家走進範圍時呼叫；測試也直接呼叫）。沒有成員也沒有增援就直接完成。
func begin() -> void:
	if state != &"idle":
		return
	_members.clear()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and not enemy.is_dying() and _zone_world_rect().has_point(enemy.global_position):
			_members.append(weakref(enemy))
	if _members.is_empty() and data.reinforcements.is_empty():
		state = &"cleared"
		return
	state = &"active"
	_lock_time = 0.0
	_reinforce_index = 0
	EventBus.mechanism_toggled.emit(data.channel, true)
	Sfx.play(&"gate", -3.0)
	if not data.start_text.is_empty():
		EventBus.toast_requested.emit(data.start_text)
	if data.start_scene != &"":
		Story.play(data.start_scene)
	set_physics_process(true)


## 範圍（世界座標）。底邊往下多留一點：站在地面上的敵人腳底剛好在範圍底邊，不能被算成在外面。
func _zone_world_rect() -> Rect2:
	return Rect2(global_position + _zone.position, _zone.size).grow_individual(0.0, 0.0, 0.0, FEET_MARGIN)


## 還活著的成員數（含尚未死亡動畫結束的不算）。
func living_members() -> int:
	var count := 0
	for ref in _members:
		var enemy := ref.get_ref() as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dying() and not enemy.is_queued_for_deletion():
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if state != &"active":
		return
	_lock_time += delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	if _lock_time >= data.max_lock_seconds:
		push_warning("[EncounterZone] %s（格 %s）鎖場超過 %.0f 秒，強制解鎖（還有 %d 個成員活著）" % [data.id, cell, data.max_lock_seconds, living_members()])
		_finish(true)
		return
	var living := living_members()
	if _reinforce_index < data.reinforcements.size() and living <= 1:
		_reinforce()
		living = living_members()
	if living == 0 and _reinforce_index >= data.reinforcements.size():
		_finish(false)


## 從範圍左右邊緣輪流加入下一個增援。
func _reinforce() -> void:
	var enemy_data := data.reinforcements[_reinforce_index]
	var left := _reinforce_index % 2 == 0
	_reinforce_index += 1
	if enemy_data == null or not spawner.is_valid():
		push_error("[EncounterZone] %s（格 %s）無法生成增援（沒有資料或沒有生成器）" % [data.id, cell])
		return
	var x := _zone.position.x + SIDE_MARGIN if left else _zone.end.x - SIDE_MARGIN
	var enemy: Variant = spawner.call(enemy_data, global_position + Vector2(x, -2.0))
	if enemy is Enemy:
		_members.append(weakref(enemy))


func _finish(forced: bool) -> void:
	state = &"cleared"
	set_physics_process(false)
	EventBus.mechanism_toggled.emit(data.channel, false)
	Sfx.play(&"gate", -3.0)
	if not forced and not data.clear_text.is_empty():
		EventBus.toast_requested.emit(data.clear_text)


func state_key() -> String:
	return "encounter@%d,%d" % [cell.x, cell.y]


func capture_state() -> Variant:
	return state == &"cleared"


func restore_state(saved: Variant) -> void:
	if saved == true:
		state = &"cleared"
		set_physics_process(false)
