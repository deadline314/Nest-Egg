extends Node

class Reference extends MeleeHeld:
	func second_grip_near(shoulder: Vector2, ideal := 0.0, near := 0.0, far := INF, shaft_side := 0) -> Vector2:
		var second := float(_spec["second"])
		var best := -SECOND_MIN if shaft_side < 0 else minf(SECOND_MIN, second)
		var best_error := INF
		var tail_end := _butt - SECOND_TAIL_MARGIN
		var s := -tail_end if tail_end >= SECOND_MIN else best
		while s <= second + 0.001:
			if (shaft_side == 0 or signf(s) == shaft_side) and (absf(s) >= SECOND_MIN - 0.001 or s == minf(SECOND_MIN, second)):
				var distance := shoulder.distance_to(_origin + _direction * s)
				var outside := maxf(near - distance, distance - far)
				var error := absf(distance - ideal) if outside <= 0.0 else OUT_OF_REACH + outside
				if outside <= 0.0 and is_finite(_second_along):
					error = absf(s - _second_along) + absf(distance - ideal) * 0.01
				if error < best_error:
					best_error = error
					best = s
			s += SECOND_STEP
		return _origin + _direction * best


const EXACT_CASES := 60000
const HOT_ROUNDS := 36000
var _before := Reference.new()
var _after := MeleeHeld.new()
var _r := RandomNumberGenerator.new()
var _err := 0
var _counts := {}


func _ready() -> void:
	_r.seed = 27522221
	for i in EXACT_CASES:
		_compare(i)
	for i in 5000:
		_step(_before, i)
		_step(_after, i)
	var pairs: Array = []
	for i in 8:
		var first := _time(_after if i % 2 else _before)
		var second := _time(_before if i % 2 else _after)
		pairs.append([second,first] if i % 2 else [first,second])
	var result := {"exact_cases":EXACT_CASES,"errors":_err,"hot_rounds":HOT_ROUNDS,"timing_us":pairs,"buckets":_counts}
	print("GRIP_REUSE_TEST ",JSON.stringify(result))
	_before.free()
	_after.free()
	get_tree().quit(0 if _err == 0 else 1)


func _compare(i: int) -> void:
	var offset := 75000.0 if i % 15 == 0 else 900.0
	var origin := Vector2(_r.randf_range(-offset,offset), _r.randf_range(-offset,offset))
	var angle := _r.randf_range(-PI,PI)
	var direction := Vector2(cos(angle),sin(angle))
	var shoulder := origin + Vector2(_r.randf_range(-45,45),_r.randf_range(-45,45))
	var second := _r.randf_range(3.0,50.0)
	var butt := _r.randf_range(0.0,55.0)
	var preferred := NAN
	var near := _r.randf_range(2.0,20.0)
	var far := near+_r.randf_range(0.0,36.0)
	if i % 7 == 0:
		far = INF
	var ideal := _r.randf_range(-2,48)
	if i % 61 == 0:
		ideal = INF
	elif i % 73 == 0:
		ideal = 150000.0
	var side := i % 3 - 1
	_setup(_before,origin,direction,second,butt,NAN)
	if i % 4 == 0:
		preferred = (_before.second_grip_near(shoulder,ideal,near,far,side)-origin).dot(direction)
	elif i % 4 == 1:
		preferred = _r.randf_range(-butt,second)
	elif i % 4 == 2:
		preferred = (_before.second_grip_near(shoulder,ideal,near,far,side)-origin).dot(direction)+_r.randf_range(-0.05001,0.05001)
	_before._second_along = preferred
	_setup(_after,origin,direction,second,butt,preferred)
	var first := _before.second_grip_near(shoulder,ideal,near,far,side)
	var next := _after.second_grip_near(shoulder,ideal,near,far,side)
	if first != next:
		_err += 1
		if _err <= 8:
			printerr("Mismatch %d: %s %s, previous %.5f, near %.4f far %.4f side %d" % [i,first,next,preferred,near,far,side])
	var k := "%d/%d" % [i%4,side]
	_counts[k]=int(_counts.get(k,0))+1


func _setup(node: MeleeHeld, origin: Vector2, direction: Vector2, second: float, butt: float, remembered: float) -> void:
	node._origin = origin
	node._direction = direction
	node._spec = {"second":second}
	node._butt = butt
	node._second_along = remembered


func _step(node: MeleeHeld, i: int) -> void:
	var n := float(i%20) * 0.002
	node.second_grip_near(Vector2(90.0+n,97.0),16.0,7.0,30.0,-1)


func _time(node: MeleeHeld) -> int:
	_setup(node, Vector2(100,100),Vector2.RIGHT,10.0,29.0,-20.0)
	var start := Time.get_ticks_usec()
	for i in HOT_ROUNDS:
		_step(node,i)
	return Time.get_ticks_usec() - start
