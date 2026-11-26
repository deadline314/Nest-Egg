extends RefCounted
## The replay clock and movement are local. Each route point lies on a
## tread made from the same geometry used by the presentation.

enum Segment { ARRIVAL, LOW_STREET, DRY_STAIRS, PAWNSHOP }
enum Phase { WALK, CHOOSE_ROUTE, READING, TESTIMONY }
const LIMIT_SECONDS := 600.0
const WALK_SPEED := 77.0
const LOW_WATER_AT := 18.0
const EPSILON := 0.01

const PATHS := {
	Segment.ARRIVAL: [Vector2(96, 302), Vector2(306, 302)],
	Segment.LOW_STREET: [Vector2(306, 302), Vector2(348, 318), Vector2(622, 318), Vector2(674, 302)],
	Segment.DRY_STAIRS: [
		Vector2(306, 302), Vector2(448, 302), Vector2(543, 240),
		Vector2(653, 240), Vector2(675, 244), Vector2(724, 302),
	],
	Segment.PAWNSHOP: [Vector2(724, 302), Vector2(1019, 302)],
}

# Low street ends earlier and the street behind the shop joins both routes.
const LOW_JOIN := 50.0

var segment := Segment.ARRIVAL
var phase := Phase.WALK
var checkpoint := Segment.ARRIVAL
var position := Vector2.ZERO
var remaining := LIMIT_SECONDS
var flooded := false
var facing := 1
var _distance := 0.0
var _lengths: Dictionary = {}


func _init() -> void:
	for id: int in PATHS:
		var path: Array = PATHS[id]
		var length := LOW_JOIN if id == Segment.PAWNSHOP else 0.0
		for index in range(1, path.size()):
			length += (path[index] as Vector2).distance_to(path[index - 1])
		_lengths[id] = length
	position = PATHS[segment][0]


func tick(axis: float, delta: float) -> void:
	if phase >= Phase.READING or not is_finite(delta) or delta <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		_restart()
		return
	if not flooded and LIMIT_SECONDS - remaining >= LOW_WATER_AT:
		flooded = true
		if segment == Segment.LOW_STREET:
			_return_to_fork()
			return
	if phase != Phase.WALK or not is_finite(axis) or absf(axis) <= EPSILON:
		return
	facing = 1 if axis > 0.0 else -1
	var length: float = _lengths[segment]
	_distance = clampf(_distance + clampf(axis, -1.0, 1.0) * WALK_SPEED * delta, 0.0, length)
	position = _position_at(segment, _distance)
	if axis < 0.0 and _distance <= EPSILON and segment in [Segment.LOW_STREET, Segment.DRY_STAIRS]:
		_return_to_fork()
	elif _distance >= length - EPSILON:
		_finish_path()


func choose_path(upper: bool) -> bool:
	if phase != Phase.CHOOSE_ROUTE or (flooded and not upper):
		return false
	segment = Segment.DRY_STAIRS if upper else Segment.LOW_STREET
	phase = Phase.WALK
	_distance = 0.0
	position = PATHS[segment][0]
	return true


func show_testimony() -> void:
	if phase == Phase.READING:
		phase = Phase.TESTIMONY


func _finish_path() -> void:
	match segment:
		Segment.ARRIVAL:
			checkpoint = segment
			_return_to_fork()
		Segment.LOW_STREET, Segment.DRY_STAIRS:
			checkpoint = Segment.PAWNSHOP
			# The final 50-pixel ramp follows the real joint, so the body
			# never jumps from the lower route to the upper room.
			if segment == Segment.LOW_STREET:
				segment = Segment.PAWNSHOP
				_distance = 0.0
				position = PATHS[Segment.PAWNSHOP][0] - Vector2(LOW_JOIN, 0)
			else:
				segment = Segment.PAWNSHOP
				_distance = LOW_JOIN
				position = PATHS[Segment.PAWNSHOP][0]
		Segment.PAWNSHOP:
			phase = Phase.READING


func _return_to_fork() -> void:
	segment = Segment.ARRIVAL
	phase = Phase.CHOOSE_ROUTE
	_distance = _lengths[segment]
	position = PATHS[segment][-1]


func _restart() -> void:
	remaining = LIMIT_SECONDS
	flooded = false
	if checkpoint == Segment.PAWNSHOP:
		segment = checkpoint
		phase = Phase.WALK
		_distance = LOW_JOIN
		position = PATHS[segment][0]
	elif phase == Phase.CHOOSE_ROUTE or segment in [Segment.LOW_STREET, Segment.DRY_STAIRS]:
		_return_to_fork()
	else:
		_distance = 0.0
		position = PATHS[segment][0]


func _position_at(path_id: int, distance: float) -> Vector2:
	if path_id == Segment.PAWNSHOP:
		return PATHS[path_id][0] + Vector2(distance - LOW_JOIN, 0)
	var points: Array = PATHS[path_id]
	for index in range(1, points.size()):
		var origin: Vector2 = points[index - 1]
		var end: Vector2 = points[index]
		var length := origin.distance_to(end)
		if distance <= length:
			return origin.lerp(end, distance / length)
		distance -= length
	return points[-1]
