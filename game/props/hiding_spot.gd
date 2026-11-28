class_name HidingSpot
extends Node2D
## 可躲藏的位置：掛著塑膠條門簾的凹室。玩家蹲在簾子後面（腳在凹室範圍內、蹲著）時，還沒進入戰鬥的敵人看不到他，
## 從面前走過去也一樣；已經在戰鬥或被警報引來的敵人照常看得到。站起來、走出去或開槍打到人就不再藏得住。
## 簾子畫在角色前面：人走過時條簾會晃，蹲在裡面時簾子變得比較密，看得出「藏好了」。
## 原點在凹室最左那一格的地面上（關卡把生成物放在格子中央，這裡往左挪半格）。不存進檢查點，沒有狀態要還原。

const GROUP := &"hiding_spots"
## 腳要在凹室裡面多深才算藏好（像素，左右各留這麼多）。
const EDGE_MARGIN := 4.0
## 腳底離地面多近才算蹲在地上。
const FLOOR_BAND := 4.0
const STRIP_WIDTH := 3.0
const STRIP_GAP := 2.0
## 條簾晃動：人穿過時依速度給一個擺幅，之後慢慢停下（像素、每秒衰減、擺動頻率）。
const SWAY_MAX := 3.0
const SWAY_DECAY := 2.5
const SWAY_RATE := 9.0
const PROMPT_MARGIN := 40.0

const RECESS_TOP := Color("07090d")
const RECESS_BOTTOM := Color("141a22")
const FRAME_COLOR := Color("39434f")
const FRAME_LIT := Color("6d7d8e")
const STRIP_COLOR := Color(0.62, 0.72, 0.8, 0.22)
const STRIP_HIDDEN := Color(0.5, 0.58, 0.66, 0.7)
## 藏好時蓋在凹室上的陰影：簾子後面的人變暗，一眼看得出「藏住了」。
const HIDDEN_SHADE := Color(0.02, 0.03, 0.05, 0.45)
const STRIP_EDGE := Color(0.82, 0.9, 1.0, 0.28)
const RAIL_COLOR := Color("2a3038")

static var _spots: Array[HidingSpot] = []

var data: HidingSpotData
var cell := Vector2i.ZERO
var width := 32.0
var height := 48.0

var _half_tile := 8.0
var _sway := 0.0
var _sway_time := 0.0
var _hidden := false
var _curtain: _Curtain
var _prompt: WorldPrompt
var _player_ref := PlayerRef.new()


## 目標（玩家）是不是正蹲在任何一處簾子後面。敵人判斷看不看得到玩家時用（只對還沒進入戰鬥的敵人有效）。
static func conceals(target: Node2D) -> bool:
	var player := target as Player
	if player == null or not player.is_crouching or _spots.is_empty():
		return false
	for spot in _spots:
		if spot.contains_feet(player.global_position):
			return true
	return false


func configure(p_data: HidingSpotData, p_cell: Vector2i, tile_size: int) -> void:
	data = p_data
	cell = p_cell
	width = float(data.width_tiles * tile_size)
	height = float(data.height_tiles * tile_size)
	_half_tile = tile_size * 0.5


func _ready() -> void:
	if data == null:
		push_error("[HidingSpot] 未指定 HidingSpotData（格 %s），已移除。" % cell)
		queue_free()
		return
	add_to_group(GROUP)
	position.x -= _half_tile
	_curtain = _Curtain.new()
	_curtain.host = self
	add_child(_curtain)
	var hint := data.hint_for(Story.language)
	if not hint.is_empty():
		_prompt = WorldPrompt.new()
		_prompt.text = hint
		_prompt.reach_check = _prompt_in_reach
		_prompt.position = Vector2(width * 0.5, -height)
		_prompt.offset = Vector2(0.0, -14.0)
		add_child(_prompt)


func _enter_tree() -> void:
	if not _spots.has(self):
		_spots.append(self)


func _exit_tree() -> void:
	_spots.erase(self)


## 腳底（世界座標）是不是在凹室裡、貼著地面。
func contains_feet(feet: Vector2) -> bool:
	var at := feet - global_position
	return at.x >= EDGE_MARGIN and at.x <= width - EDGE_MARGIN and absf(at.y) <= FLOOR_BAND


func is_hiding_player() -> bool:
	return _hidden


func _prompt_in_reach() -> bool:
	var player := _player_ref.get_player(get_tree())
	if player == null or _hidden:
		return false
	var at := player.global_position - global_position
	return at.x > -PROMPT_MARGIN and at.x < width + PROMPT_MARGIN and absf(at.y) <= FLOOR_BAND + 2.0


func _physics_process(delta: float) -> void:
	var player := _player_ref.get_player(get_tree())
	var hidden := player != null and player.is_crouching and contains_feet(player.global_position)
	var changed := hidden != _hidden
	_hidden = hidden
	# 人穿過簾子時條簾跟著晃；「減少介面動態」時不晃。
	if player != null and not Settings.get_reduce_ui_motion():
		var at := player.global_position - global_position
		if at.x > -4.0 and at.x < width + 4.0 and absf(at.y) <= height and absf(player.velocity.x) > 20.0:
			_sway = clampf(maxf(absf(_sway), absf(player.velocity.x) / 60.0) * signf(player.velocity.x), -SWAY_MAX, SWAY_MAX)
	if not is_zero_approx(_sway):
		_sway_time += delta
		_sway = move_toward(_sway, 0.0, SWAY_DECAY * delta)
		changed = true
	if changed:
		_curtain.queue_redraw()


## 某一條簾在底部偏移多少（像素）：越靠近中間擺得越大，相鄰兩條不同步。
func strip_offset(index: int) -> float:
	if is_zero_approx(_sway) or Settings.get_reduce_ui_motion():
		return 0.0
	return _sway * sin(_sway_time * SWAY_RATE + float(index) * 0.9)


# ---------------------------------------------------------------------------
# 外觀：凹室在角色後面（門框、往裡變暗的凹洞、頂上的橫樑）；條簾在角色前面。
# ---------------------------------------------------------------------------

func _draw() -> void:
	if data == null:
		return
	var top := -height
	# 凹洞：上暗下略亮的漸層，四角往內收一點，不是一個方塊。
	var inset := 2.0
	var recess := PackedVector2Array([Vector2(inset, 0.0), Vector2(inset, top + 4.0), Vector2(inset + 3.0, top + 1.0),
			Vector2(width - inset - 3.0, top + 1.0), Vector2(width - inset, top + 4.0), Vector2(width - inset, 0.0)])
	var colors := PackedColorArray([RECESS_BOTTOM, RECESS_TOP, RECESS_TOP, RECESS_TOP, RECESS_TOP, RECESS_BOTTOM])
	draw_polygon(recess, colors)
	# 門框：兩側的柱子與頂上的橫樑，受光的一側亮一點。
	draw_line(Vector2(1.0, 0.0), Vector2(1.0, top + 2.0), FRAME_COLOR, 2.0)
	draw_line(Vector2(width - 1.0, 0.0), Vector2(width - 1.0, top + 2.0), FRAME_COLOR, 2.0)
	draw_line(Vector2(0.0, top + 0.5), Vector2(width, top + 0.5), FRAME_LIT, 1.0)
	draw_line(Vector2(0.0, top + 2.0), Vector2(width, top + 2.0), FRAME_COLOR, 2.0)


class _Curtain:
	extends Node2D

	var host: HidingSpot

	func _init() -> void:
		z_as_relative = false
		z_index = WorldLayers.ABOVE_CHARACTERS

	func _draw() -> void:
		if host == null or host.data == null:
			return
		var top := -host.height + 3.0
		var bottom := -1.0
		draw_line(Vector2(0.0, top), Vector2(host.width, top), HidingSpot.RAIL_COLOR, 2.0)
		if host._hidden:
			var shade := PackedVector2Array([Vector2(1.0, top), Vector2(host.width - 1.0, top), Vector2(host.width - 1.0, bottom), Vector2(1.0, bottom)])
			var clear := Color(HidingSpot.HIDDEN_SHADE, 0.0)
			draw_polygon(shade, PackedColorArray([HidingSpot.HIDDEN_SHADE, HidingSpot.HIDDEN_SHADE, clear, clear]))
		var fill := HidingSpot.STRIP_HIDDEN if host._hidden else HidingSpot.STRIP_COLOR
		var step := HidingSpot.STRIP_WIDTH + HidingSpot.STRIP_GAP
		var x := 2.0
		var index := 0
		while x + HidingSpot.STRIP_WIDTH <= host.width - 1.0:
			var drift := host.strip_offset(index)
			var strip := PackedVector2Array([Vector2(x, top + 1.0), Vector2(x + HidingSpot.STRIP_WIDTH, top + 1.0),
					Vector2(x + HidingSpot.STRIP_WIDTH + drift, bottom), Vector2(x + drift, bottom)])
			draw_colored_polygon(strip, fill)
			draw_line(Vector2(x, top + 1.0), Vector2(x + drift, bottom), HidingSpot.STRIP_EDGE, 1.0)
			x += step
			index += 1
