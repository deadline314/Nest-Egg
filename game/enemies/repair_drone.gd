extends Enemy
## 維修機（支援）
## 行為：飛在其他敵人附近尋找沒有護盾的同伴；找到後伸出綠色光束連結（預兆），充能完成就給對方一層護盾並修復一點生命。
##       遇到玩家靠近會拉開距離。護盾每層擋一次攻擊，爆炸與終結技無視護盾。
## 應對：優先擊落維修機（脆弱、會飛）；光束連著時打斷（擊落或暈眩）護盾就不會生效。
## 數值：ability_time = 充能秒數，ability_radius = 能支援的距離，ability_damage = 給幾層護盾。

const FOLLOW_HEIGHT := 46.0
const FLEE_DISTANCE := 110.0
const FOLLOW_SPEED_SCALE := 1.0
const SCAN_INTERVAL := 0.4
const HEAL_AMOUNT := 1
const BEAM_COLOR := Color("3dffa0")

var _ally_ref: WeakRef
var _cooldown := 1.0
var _scan_left := 0.0
var _beam_time := 0.0


func _setup_states() -> void:
	fsm.add(&"idle", _idle_tick)
	fsm.add(&"follow", _follow_tick)
	fsm.add(&"channel", _channel_tick, _channel_enter)
	fsm.start(&"idle")


func _on_stunned() -> void:
	_ally_ref = null
	fsm.transition(&"idle")


func _ally() -> Enemy:
	var ally: Enemy = _ally_ref.get_ref() as Enemy if _ally_ref != null else null
	if ally == null or not is_instance_valid(ally) or ally.is_dying():
		return null
	return ally


## 最近的、還沒有護盾的同伴（不含自己、其他維修機與頭目）。
func _find_ally() -> Enemy:
	var best: Enemy = null
	var best_distance := data.ability_radius
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var candidate := node as Enemy
		if candidate == null or candidate == self or candidate.is_dying() or candidate.data.is_boss:
			continue
		if candidate.data.id == data.id or candidate.shield >= Enemy.MAX_SHIELD:
			continue
		var distance := candidate.global_position.distance_to(global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _idle_tick(delta: float) -> void:
	_hover(_home + Vector2(0, sin(_anim_time * 2.0) * 5.0), delta, 0.6)
	_cooldown = maxf(0.0, _cooldown - delta)
	_scan_left -= delta
	if _scan_left <= 0.0 and _cooldown <= 0.0:
		_scan_left = SCAN_INTERVAL
		var ally := _find_ally()
		if ally != null:
			_ally_ref = weakref(ally)
			fsm.transition(&"follow")


func _follow_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var ally := _ally()
	if ally == null or ally.shield >= Enemy.MAX_SHIELD:
		fsm.transition(&"idle")
		return
	var desired := ally.global_position + Vector2(0, -ally.data.body_size.y - FOLLOW_HEIGHT * 0.5)
	desired += _flee_offset()
	_hover(desired, delta, FOLLOW_SPEED_SCALE)
	if _cooldown <= 0.0 and global_position.distance_to(desired) < 40.0:
		fsm.transition(&"channel")


## 玩家太近時往反方向退。
func _flee_offset() -> Vector2:
	var target := _target()
	if target == null:
		return Vector2.ZERO
	var away := global_position - target.global_position
	if away.length() > FLEE_DISTANCE:
		return Vector2.ZERO
	return Vector2(signf(away.x) if away.x != 0.0 else 1.0, -0.4) * 60.0


func _channel_enter() -> void:
	velocity = velocity * 0.3
	_beam_time = 0.0
	_start_telegraph(data.ability_time)


func _channel_tick(delta: float) -> void:
	var ally := _ally()
	if ally == null or ally.global_position.distance_to(global_position) > data.ability_radius * 1.4:
		fsm.transition(&"idle")
		return
	velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_beam_time += delta
	if not is_telegraphing():
		_apply(ally)
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"idle")


func _apply(ally: Enemy) -> void:
	ally.add_shield(data.ability_damage)
	ally.health.heal(HEAL_AMOUNT)
	Fx.burst(ally._center(), BEAM_COLOR, 10, 100.0, 0.4)
	Fx.flash_light(ally._center(), BEAM_COLOR, 80.0, 1.2, 0.25)
	Sfx.play(&"pickup", -8.0)


func _hover(desired: Vector2, delta: float, speed_scale: float) -> void:
	var toward := (desired - global_position).limit_length(data.move_speed * speed_scale)
	velocity = velocity.move_toward(toward, 400.0 * delta)
	_face_target()


func _draw_overlay() -> void:
	var ally := _ally()
	if ally == null:
		return
	if fsm.is_in(&"channel"):
		var t := clampf(1.0 - _telegraph_left / maxf(0.01, data.ability_time), 0.0, 1.0)
		var color := LightKit.glow(BEAM_COLOR, 1.0 + 1.5 * t)
		color.a = 0.3 + 0.6 * t
		var from := to_local(_center())
		var to := to_local(ally._center())
		draw_line(from, to, color, 1.0 + 1.5 * t)
		draw_circle(to, 2.0 + 3.0 * t, Color(color, 0.5))


func _draw_body(color: Color) -> void:
	# 維修機：扁圓機身、綠色十字燈與兩隻小旋翼。
	var h := data.body_size.y
	var w := data.body_size.x
	var c := Vector2(0, -h * 0.5)
	var chrome := Color("a7b3a9")
	draw_circle(c, w * 0.42, chrome.darkened(0.35) if color != Palette.WHITE else Palette.WHITE)
	draw_arc(c, w * 0.42, 0.0, TAU, 14, Color("07080d"), 1.0)
	var spin := absf(sin(_anim_time * 36.0)) * w * 0.6
	for side: float in [-1.0, 1.0]:
		var hub := c + Vector2(side * w * 0.42, -h * 0.4)
		draw_line(hub + Vector2(-spin * 0.5, 0), hub + Vector2(spin * 0.5, 0), Color(BEAM_COLOR, 0.7), 1.0)
	var glow := LightKit.glow(BEAM_COLOR, 3.0 if fsm.is_in(&"channel") else 1.6)
	draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), glow, 2.0)
	draw_line(c + Vector2(0, -3), c + Vector2(0, 3), glow, 2.0)
	draw_circle(c + Vector2(facing * w * 0.25, 4), 1.2, LightKit.glow(Palette.DANGER, 1.4))
