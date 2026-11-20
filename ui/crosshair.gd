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
const DRY_TIME := 0.18
const WEAK_MARK_END := 11.0
const BLOCK_MARK_END := 7.0

var _bound_player: WeakRef
var _reduce_motion := false
var _flash_scale := 1.0
var _kill_grows := false
var _hit_left := 0.0
var _kill_left := 0.0
var _weak_left := 0.0
var _dry_left := 0.0
var _blocked_left := 0.0
var _screen_point := Vector2.ZERO
var _bloom := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Update the actual draw bounds before world prompts lay out for this frame.
	process_priority = -1
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.hit_marker.connect(_on_hit_marker)
	EventBus.dry_fired.connect(_on_dry_fired)
	_sync_display()
	Settings.display_changed.connect(_sync_display)


func _sync_display() -> void:
	_reduce_motion = Settings.get_reduce_ui_motion()
	_flash_scale = Settings.flash_scale()
	if _reduce_motion:
		_dry_left = 0.0
		_kill_grows = false
	queue_redraw()


func _on_dry_fired() -> void:
	if not _reduce_motion:
		_dry_left = DRY_TIME


func _enter_tree() -> void:
	EventBus.player_spawned.connect(_bind_player)
	_bind_player(get_tree().get_first_node_in_group(&"player") as Player)


func _exit_tree() -> void:
	if EventBus.player_spawned.is_connected(_bind_player):
		EventBus.player_spawned.disconnect(_bind_player)
	_disconnect_player()


func _player() -> Player:
	return _bound_player.get_ref() as Player if _bound_player != null else null


func _disconnect_player() -> void:
	var player := _player()
	if player != null and player.interaction != null and player.interaction.changed.is_connected(_refresh_visibility):
		player.interaction.changed.disconnect(_refresh_visibility)
	_bound_player = null


func _bind_player(player: Player) -> void:
	if not is_inside_tree():
		return
	_disconnect_player()
	_bound_player = weakref(player) if player != null else null
	if player != null and player.interaction != null and not player.interaction.changed.is_connected(_refresh_visibility):
		player.interaction.changed.connect(_refresh_visibility)
	_refresh_visibility()


## 對話開始會同步暫停世界，因此可見性由事件同步更新。
func _refresh_visibility() -> void:
	if not is_inside_tree():
		hide()
		return
	var player := _player()
	visible = player != null and player.is_inside_tree() and not player.is_dead() and (player.interaction == null or not player.interaction.active)


func _process(delta: float) -> void:
	_hit_left = maxf(0.0, _hit_left - delta)
	_kill_left = maxf(0.0, _kill_left - delta)
	_weak_left = maxf(0.0, _weak_left - delta)
	_dry_left = maxf(0.0, _dry_left - delta)
	_blocked_left = maxf(0.0, _blocked_left - delta)
	var player := _player()
	_refresh_visibility()
	if not visible:
		return
	_bloom = player.aim_bloom
	_screen_point = get_viewport().get_canvas_transform() * player.aim_point
	queue_redraw()


## 命中標記四種：弱點是更長更黃的斜線、被擋是兩道灰色橫槓。
func _on_hit_marker(kind: StringName) -> void:
	match kind:
		&"weak":
			_weak_left = HIT_TIME * 1.6
		&"blocked":
			_blocked_left = HIT_TIME * 1.6


func _on_hit_confirmed(_world_position: Vector2, killed: bool) -> void:
	_hit_left = HIT_TIME
	if killed:
		_kill_left = KILL_TIME
		_kill_grows = not _reduce_motion


func prompt_obstacle_rect() -> Rect2:
	if not is_visible_in_tree():
		return Rect2()
	var gap := _tick_gap()
	var radius := gap + TICK_LENGTH + 1.5
	if _weak_left > 0.0:
		radius = maxf(radius, (gap + WEAK_MARK_END) * sqrt(0.5) + 1.0)
	if _blocked_left > 0.0:
		radius = maxf(radius, gap + BLOCK_MARK_END + 0.75)
	var box := Rect2(_draw_center() - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var world_box := get_viewport().get_canvas_transform().affine_inverse() * box
	return world_box if world_box.position.is_finite() and world_box.size.is_finite() else Rect2()


func _draw_center() -> Vector2:
	return _screen_point + Vector2(sin(_dry_left * 80.0) * 3.0 * (_dry_left / DRY_TIME), 0.0)


func _tick_gap() -> float:
	var kill_gap := 3.0 * (_kill_left / KILL_TIME) if _kill_grows else 0.0
	return BASE_GAP + _bloom * BLOOM_GAP + kill_gap


func _draw() -> void:
	var p := _draw_center()
	var gap := _tick_gap()
	var color := LightKit.glow(Palette.CYAN, 1.6)
	if _kill_left > 0.0:
		color = LightKit.glow(Palette.DANGER, lerpf(1.0, 2.2, _flash_scale))
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + dir * gap, p + dir * (gap + TICK_LENGTH), Color(0, 0, 0, 0.6), 3.0)
		draw_line(p + dir * gap, p + dir * (gap + TICK_LENGTH), color, 1.5)
	draw_circle(p, 1.2, color)
	if _hit_left > 0.0:
		# 命中標記：斜向四短線。
		var t := _hit_left / HIT_TIME
		# 白色在高光影下仍可能飽和，減閃光時也降低覆蓋強度。
		var mark_intensity := lerpf(1.0, 2.0, _flash_scale)
		var mark_alpha := t * lerpf(0.55, 1.0, _flash_scale)
		var mark_color := Color(LightKit.glow(Palette.WHITE, mark_intensity), mark_alpha)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := dir.normalized()
			draw_line(p + n * (gap + 2.0), p + n * (gap + 7.0), mark_color, 1.5)
	if _weak_left > 0.0:
		var tw := _weak_left / (HIT_TIME * 1.6)
		var weak_color := Color(LightKit.glow(Palette.WARNING, lerpf(1.0, 2.4, _flash_scale)), tw)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := dir.normalized()
			draw_line(p + n * (gap + 1.0), p + n * (gap + WEAK_MARK_END), weak_color, 2.0)
	if _blocked_left > 0.0:
		var tb := _blocked_left / (HIT_TIME * 1.6)
		var block_color := Color(0.7, 0.75, 0.82, tb)
		for sy: float in [-1.0, 1.0]:
			draw_line(p + Vector2(-(gap + BLOCK_MARK_END), sy * 3.0), p + Vector2(gap + BLOCK_MARK_END, sy * 3.0), block_color, 1.5)
