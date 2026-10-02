class_name Crosshair
extends Control
## 準星：跟隨滑鼠（手把時顯示在角色瞄準方向），本身就是射擊回饋——
##   連射時四角向外擴散、命中時出現白色命中標記、擊殺時變紅並放大。
## 只讀取玩家公開的瞄準資料，玩家不存在時自動隱藏。

const BASE_GAP := 4.0
const BLOOM_GAP := 9.0
const TICK_LENGTH := 5.0
const HIT_TIME := 0.12
const KILL_TIME := 0.28

var _player_ref: WeakRef
var _hit_left := 0.0
var _kill_left := 0.0
var _screen_point := Vector2.ZERO
var _bloom := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


func _process(delta: float) -> void:
	_hit_left = maxf(0.0, _hit_left - delta)
	_kill_left = maxf(0.0, _kill_left - delta)
	var player := _player()
	visible = player != null and not player.is_dead()
	if not visible:
		return
	_bloom = player.aim_bloom
	_screen_point = get_viewport().get_canvas_transform() * player.aim_point
	queue_redraw()


func _player() -> Player:
	var player: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
		_player_ref = weakref(player) if player != null else null
	return player


func _on_hit_confirmed(_world_position: Vector2, killed: bool) -> void:
	_hit_left = HIT_TIME
	if killed:
		_kill_left = KILL_TIME


func _draw() -> void:
	var p := _screen_point
	var gap := BASE_GAP + _bloom * BLOOM_GAP
	var color := LightKit.glow(Palette.CYAN, 1.6)
	if _kill_left > 0.0:
		color = LightKit.glow(Palette.DANGER, 2.2)
		gap += 3.0 * (_kill_left / KILL_TIME)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + dir * gap, p + dir * (gap + TICK_LENGTH), Color(0, 0, 0, 0.6), 3.0)
		draw_line(p + dir * gap, p + dir * (gap + TICK_LENGTH), color, 1.5)
	draw_circle(p, 1.2, color)
	if _hit_left > 0.0:
		# 命中標記：斜向四短線。
		var t := _hit_left / HIT_TIME
		var mark_color := Color(LightKit.glow(Palette.WHITE, 2.0), t)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := dir.normalized()
			draw_line(p + n * (gap + 2.0), p + n * (gap + 7.0), mark_color, 1.5)
