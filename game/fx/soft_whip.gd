class_name SoftWhip
extends RefCounted
## 永遠是軟的鞭身（NE-276）：一串節點，用 Verlet 積分加距離限制模擬，從拿出來到收起來只有這一種狀態。
##
## 握把那一端釘在握把的出線口，靠近握把的一小段順著握把的方向出去；其餘的節點只受重力、阻力與「相鄰兩節距離固定」的限制。
## 出招不換模擬方式：呼叫端給一個「鞭梢的目標點」與拉力（0～1），鞭梢與它前面兩節被有限地拉過去，
## 整條鞭身由繩子自己帶動——所以看得到彎從握把往鞭梢傳，鞭梢到位後帶著慣性落下。沒有任何一格是排出來的。
## 鞭身的長度可以連續變化（單分子線從握把放出、收回）；呼叫端讓它比要打的距離長一點，到位時中段仍有弧度。
## 參考：GDNative Ropesim 的「把手」（只控制繩子的一部分，其餘照樣模擬）；Indiana Jones and the Great Circle 的鞭子
## （模擬與動畫一起用）。整理在 design/14-combat-variety/MELEE_MODULE.md。
## 節點陣列預先配置，每影格不產生新物件。

const NODES := 20
const ITERATIONS := 8
const SUBSTEPS := 2
const GRAVITY := 460.0
## 每秒保留的速度比例（空氣阻力）：越小越快靜下來。被拉著甩的時候阻力小，放開之後阻力大（收招後不會甩著繞好幾圈）。
const KEEP_PER_SECOND := 0.12
const KEEP_PER_SECOND_FREE := 0.02
## 出線口那一小段順著握把方向的程度（0～1）。
const HANDLE_STIFFNESS := 0.6
## 放線與收線的速度（像素／秒）。
const REEL_OUT := 900.0
const REEL_IN := 150.0
## 鞭梢前面幾節跟著被拉（越靠握把拉得越少）。
const PULL_FALLOFF: PackedFloat32Array = [1.0, 0.5, 0.2]
## 握把到鞭梢的直線距離最多是鞭身長度的幾成：被拉緊時線會再放出來一點，所以鞭身永遠留著弧度、不會繃成一把尺。
const MAX_TAUT := 0.965
## 線最多放到呼叫端要求長度的幾倍。
const MAX_PAYOUT := 1.2
const ROOT_WIDTH := 1.8
const TIP_WIDTH := 0.6
const INK := Color(0.05, 0.03, 0.08, 0.85)

## 節點不會低於這條線（世界座標 y）：鞭子拖在地上，不鑽進地板。
var floor_y := INF

var _pos := PackedVector2Array()
var _prev := PackedVector2Array()
var _points := PackedVector2Array()
var _length := 0.0
var _laid := false


func _init() -> void:
	_pos.resize(NODES)
	_prev.resize(NODES)
	_points.resize(NODES)


func is_laid() -> bool:
	return _laid


## 收起來（換掉武器）：下次拿出來重新垂好，不從舊位置彈過來。
func clear() -> void:
	_laid = false


func length() -> float:
	return _length


func tip() -> Vector2:
	return _pos[NODES - 1]


func node(index: int) -> Vector2:
	return _pos[clampi(index, 0, NODES - 1)]


## 握把到鞭梢的直線距離 ÷ 鞭身長度：1.0 就是一把尺。
func straightness() -> float:
	return _pos[0].distance_to(_pos[NODES - 1]) / maxf(0.001, _length)


## 每個物理影格呼叫一次。root 出線口（世界座標）、handle_dir 握把的方向、length_target 鞭身現在該多長、
## tip_target 與 pull 是鞭梢的目標點與拉力（pull 為 0 就是完全自由）。
func step(delta: float, root: Vector2, handle_dir: Vector2, length_target: float, tip_target: Vector2, pull: float) -> void:
	if not _laid:
		_lay(root, length_target)
	_length = move_toward(_length, length_target, delta * (REEL_OUT if length_target > _length else REEL_IN))
	var segment := _length / float(NODES - 1)
	var dt := delta / float(SUBSTEPS)
	var keep := pow(KEEP_PER_SECOND if pull > 0.0 else KEEP_PER_SECOND_FREE, dt)
	for sub in SUBSTEPS:
		for i in range(1, NODES):
			var here := _pos[i]
			_pos[i] = here + (here - _prev[i]) * keep + Vector2(0.0, GRAVITY * dt * dt)
			_prev[i] = here
		_prev[0] = _pos[0]
		_pos[0] = root
		# 出線口那一節順著握把出去（線是從握把裡放出來的，不會一出來就折）。
		_pos[1] = _pos[1].lerp(root + handle_dir * segment, HANDLE_STIFFNESS)
		if pull > 0.0:
			for k in PULL_FALLOFF.size():
				var index := NODES - 1 - k
				var goal := tip_target + (root - tip_target).normalized() * segment * float(k)
				_pos[index] = _pos[index].lerp(goal, clampf(pull * PULL_FALLOFF[k], 0.0, 0.9))
		for iteration in ITERATIONS:
			_pos[0] = root
			for i in range(1, NODES):
				var a := _pos[i - 1]
				var b := _pos[i]
				var gap := b - a
				var distance := gap.length()
				if distance < 0.0001:
					continue
				var fix := gap * ((distance - segment) / distance)
				if i == 1:
					_pos[i] = b - fix
				else:
					_pos[i - 1] = a + fix * 0.5
					_pos[i] = b - fix * 0.5
			for i in range(1, NODES):
				if _pos[i].y > floor_y:
					_pos[i].y = floor_y
		# 被拉緊了：線再放出來一點（放到上限還是太緊，就把鞭梢往回收），鞭身保有弧度。
		var chord := _pos[0].distance_to(_pos[NODES - 1])
		if chord > _length * MAX_TAUT:
			_length = minf(chord / MAX_TAUT, maxf(_length, length_target * MAX_PAYOUT))
			segment = _length / float(NODES - 1)
		# 有目標時先從鞭梢往握把修一遍（鞭梢盡量留在被拉到的地方），
		if pull > 0.0:
			for i in range(NODES - 2, 0, -1):
				var toward := _pos[i + 1]
				var back := _pos[i] - toward
				var span := back.length()
				if span > segment and span > 0.0001:
					_pos[i] = toward + back * (segment / span)
		# 最後從握把往鞭梢逐節把距離修到剛好一節：鞭身不會被拉長。
		for i in range(1, NODES):
			var from := _pos[i - 1]
			var gap := _pos[i] - from
			var distance := gap.length()
			if distance > segment and distance > 0.0001:
				_pos[i] = from + gap * (segment / distance)
		chord = _pos[0].distance_to(_pos[NODES - 1])
		if chord > _length * MAX_TAUT:
			_pos[NODES - 1] = _pos[0] + (_pos[NODES - 1] - _pos[0]) * (_length * MAX_TAUT / chord)


## 畫在 CanvasItem 上（節點是世界座標，to_local 把它換到畫布自己的座標）：深色描邊、武器色的鞭身由粗到細、較亮的芯。
func draw(canvas: CanvasItem, to_local: Transform2D, tint: Color, glow: float) -> void:
	if not _laid:
		return
	for i in NODES:
		_points[i] = to_local * _pos[i]
	var body := LightKit.glow(tint, glow)
	# 芯只比鞭身亮一點：鞭身會甩過頭頂，芯太白會被算成頭髮過曝。
	var core := LightKit.glow(tint.lerp(Color.WHITE, 0.3), glow)
	for i in range(1, NODES):
		var t := float(i) / float(NODES - 1)
		var width := lerpf(ROOT_WIDTH, TIP_WIDTH, t)
		canvas.draw_line(_points[i - 1], _points[i], INK, width + 1.2)
	for i in range(1, NODES):
		var t := float(i) / float(NODES - 1)
		var width := lerpf(ROOT_WIDTH, TIP_WIDTH, t)
		canvas.draw_line(_points[i - 1], _points[i], body, width)
		canvas.draw_line(_points[i - 1], _points[i], core, maxf(0.5, width * 0.35))


## 第一次拿出來：從出線口垂直垂下（太長的部分攤在地上）。
func _lay(root: Vector2, rope_length: float) -> void:
	_length = rope_length
	var segment := _length / float(NODES - 1)
	for i in NODES:
		var y := minf(root.y + segment * float(i), floor_y)
		_pos[i] = Vector2(root.x + (0.02 * float(i) if y >= floor_y else 0.0), y)
		_prev[i] = _pos[i]
	_laid = true
