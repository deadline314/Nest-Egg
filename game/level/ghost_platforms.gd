class_name GhostPlatforms
extends Node2D
## 光橋：看不見的單向平台，只有被光照到的部分才顯示出來；碰撞一直都在，所以暗處踩得到但看不到。
## 每一段光橋自己帶一盞緩慢明滅的小燈（掛在平台上方）：燈亮時路浮現，燈暗時路淡出，玩家要趁亮的時候看路、跳過去。
## 地圖用 ~ 擺放（LevelLayout.ghost_rects）。亮度每 UPDATE_INTERVAL 秒向自己的燈查一次，平台數量很少，不逐影格計算。

const UPDATE_INTERVAL := 0.1
const FADE_SPEED := 6.0
## 完全沒光時仍留下的一絲輪廓，避免玩家以為那裡什麼都沒有而不敢跳。
const MIN_ALPHA := 0.0
const EDGE_HEIGHT := 2.0
## 每段光橋的燈：掛在平台上方多高、光池半徑、亮度、明滅頻率（Hz）。
const LAMP_HEIGHT := 44.0
const LAMP_RADIUS := 84.0
const LAMP_ENERGY := 1.3
const LAMP_PULSE_HZ := 0.28

var _rects: Array[Rect2] = []
var _alpha := PackedFloat32Array()
var _target := PackedFloat32Array()
var _since_update := 0.0
var _lamps: Array[Lamp] = []


func build(layout: LevelLayout) -> void:
	var body := StaticBody2D.new()
	body.name = "Bridge"
	body.collision_layer = Layers.PLATFORM
	body.collision_mask = 0
	add_child(body)
	for cells in layout.ghost_rects:
		var rect := layout.cells_to_pixels(cells)
		_rects.append(rect)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rect.size.x, 6.0)
		var node := CollisionShape2D.new()
		node.shape = shape
		node.position = rect.position + Vector2(rect.size.x * 0.5, 3.0)
		node.one_way_collision = true
		body.add_child(node)
		var lamp := Lamp.new()
		lamp.color = Palette.CYAN
		lamp.radius = LAMP_RADIUS
		lamp.energy = LAMP_ENERGY
		lamp.flicker_chance = 0.0
		lamp.pulse_hz = LAMP_PULSE_HZ
		lamp.position = rect.position + Vector2(rect.size.x * 0.5, -LAMP_HEIGHT)
		add_child(lamp)
		_lamps.append(lamp)
	_alpha.resize(_rects.size())
	_target.resize(_rects.size())
	_alpha.fill(MIN_ALPHA)
	_target.fill(MIN_ALPHA)
	LightKit.mark_emissive(self)


## 第 index 段光橋目前被照亮的程度 0～1（測試用）。
func lit_amount(index: int) -> float:
	return _alpha[index] if index >= 0 and index < _alpha.size() else 0.0


func segment_count() -> int:
	return _rects.size()


func _process(delta: float) -> void:
	_since_update += delta
	if _since_update >= UPDATE_INTERVAL:
		_since_update = 0.0
		_sample_lights()
	var changed := false
	for i in _alpha.size():
		var next := move_toward(_alpha[i], _target[i], FADE_SPEED * delta)
		if next != _alpha[i]:
			_alpha[i] = next
			changed = true
	if changed:
		queue_redraw()


func _sample_lights() -> void:
	for i in _rects.size():
		var rect := _rects[i]
		var lit := 0.0
		# 左、中、右三點取最亮的（長平台只有一端被照到也要顯示那一端）。
		for t in [0.0, 0.5, 1.0]:
			lit = maxf(lit, _lamps[i].light_at(rect.position + Vector2(rect.size.x * t, 0.0)))
		_target[i] = clampf(lit * 1.6, MIN_ALPHA, 1.0)


func _draw() -> void:
	for i in _rects.size():
		if _alpha[i] <= 0.01:
			continue
		var rect := _rects[i]
		var body := Color(Palette.TERRAIN_TOP, 0.55 * _alpha[i])
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y)), body)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, EDGE_HEIGHT)), LightKit.glow(Palette.CYAN, 1.4 * _alpha[i]))
