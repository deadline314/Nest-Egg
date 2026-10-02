class_name AmmoRing
extends Control
## 動態 HUD：準星右側的弧形彈藥計量與剩餘發數。
## 只在手上是有限彈藥武器時出現；低彈藥變黃、最後幾發變紅；換武器時在準星旁短暫顯示武器代號。

const RADIUS := 14.0
const ARC_FROM := -55.0
const ARC_TO := 55.0
const ARC_WIDTH := 2.5
const SEGMENT_GAP := 0.25
## 彈匣超過此數時改成連續弧形，不再逐發分格。
const MAX_SEGMENTS := 24
const LOW_RATIO := 0.25
const CRITICAL_SHOTS := 3
const BUMP_TIME := 0.12
const NAME_TIME := 1.1
const EMPTY_TIME := 0.9

var presence := HudPresence.new()
var weapon_name := ""
var ammo := 0
var max_ammo := 0
var ammo_per_shot := 1
var weapon_color := Palette.CYAN

var _player_ref := PlayerRef.new()
var _weapon_id: StringName = &""
var _limited := false
var _point := Vector2.ZERO
var _time := 0.0
var _bump_left := 0.0
var _name_left := 0.0
var _empty_left := 0.0
var _shown_ratio := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	presence.idle_alpha = 1.0
	EventBus.player_loadout_changed.connect(_on_loadout_changed)


func is_showing_ammo() -> bool:
	return _limited


func _process(delta: float) -> void:
	var cinematic := Story.is_cinematic_active()
	if get_tree().paused and not cinematic:
		return
	_time += delta
	_bump_left = maxf(0.0, _bump_left - delta)
	_name_left = maxf(0.0, _name_left - delta)
	_empty_left = maxf(0.0, _empty_left - delta)
	var player := _player_ref.get_player(get_tree())
	var hidden := cinematic or player == null or player.is_dead() or player.mounted_vehicle != null
	presence.update(delta, false, true, hidden or not (_limited or _name_left > 0.0 or _empty_left > 0.0))
	if player != null:
		_point = get_viewport().get_canvas_transform() * player.aim_point
	var ratio := float(ammo) / float(maxi(1, max_ammo)) if _limited else 0.0
	_shown_ratio = move_toward(_shown_ratio, ratio, delta * 3.0)
	queue_redraw()


func _on_loadout_changed(loadout: Loadout) -> void:
	var weapon := loadout.active_weapon() if loadout != null else null
	var new_id: StringName = weapon.id if weapon != null else &""
	var new_ammo := loadout.ammo_in(loadout.active_slot) if weapon != null else 0
	var limited := weapon != null and not weapon.has_infinite_ammo()
	if new_id != _weapon_id:
		# 有限彈藥武器打空後會自動切回主武器：顯示「EMPTY」。
		var previous_slot := loadout.find_slot(_weapon_id) if loadout != null else -1
		if _limited and previous_slot >= 0 and loadout.ammo_in(previous_slot) == 0:
			_empty_left = EMPTY_TIME
		if weapon != null and _weapon_id != &"":
			_name_left = NAME_TIME
		_shown_ratio = float(new_ammo) / float(maxi(1, weapon.max_ammo)) if limited else 0.0
		presence.poke()
	elif new_ammo < ammo:
		_bump_left = BUMP_TIME
	_weapon_id = new_id
	_limited = limited
	ammo = new_ammo
	if weapon != null:
		weapon_name = weapon.short_name if not weapon.short_name.is_empty() else weapon.display_name
		max_ammo = weapon.max_ammo
		ammo_per_shot = maxi(1, weapon.ammo_per_shot)
		weapon_color = weapon.color


func _ammo_color() -> Color:
	var shots := ammo / ammo_per_shot
	if shots <= CRITICAL_SHOTS:
		return LightKit.glow(Palette.DANGER, 1.4 + 0.8 * absf(sin(_time * 9.0)))
	if float(ammo) / float(maxi(1, max_ammo)) <= LOW_RATIO:
		return LightKit.glow(Palette.NEON_YELLOW, 1.3 + 0.5 * absf(sin(_time * 5.0)))
	return LightKit.glow(weapon_color, 1.5)


func _draw() -> void:
	var alpha := presence.alpha
	if alpha <= 0.01:
		return
	var p := _point
	if _limited:
		_draw_arc(p, alpha)
		var bump := _bump_left / BUMP_TIME
		var text_pos := p + Vector2(RADIUS + 5.0, 4.0 - 2.0 * bump)
		var size := 9 + int(round(2.0 * bump))
		draw_string(UiKit.font(), text_pos + Vector2(1, 1), str(ammo), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * alpha))
		draw_string(UiKit.font(), text_pos, str(ammo), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(_ammo_color(), alpha))
	if _name_left > 0.0:
		var k := minf(1.0, _name_left / 0.3)
		var name_pos := p + Vector2(RADIUS + 5.0, -10.0 + 3.0 * (1.0 - k))
		draw_string(UiKit.font(), name_pos + Vector2(1, 1), weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, 0.7 * k * alpha))
		draw_string(UiKit.font(), name_pos, weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(LightKit.glow(weapon_color, 1.4), k * alpha))
	if _empty_left > 0.0:
		var k := _empty_left / EMPTY_TIME
		var flicker := 0.6 + 0.4 * signf(sin(_time * 30.0))
		draw_string(UiKit.font(), p + Vector2(-14, 26), "EMPTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(LightKit.glow(Palette.DANGER, 1.8), k * flicker * alpha))


func _draw_arc(p: Vector2, alpha: float) -> void:
	var from := deg_to_rad(ARC_FROM)
	var to := deg_to_rad(ARC_TO)
	var dim := Color(0.05, 0.08, 0.12, 0.7 * alpha)
	var color := Color(_ammo_color(), alpha)
	# 底色外框，讓亮背景上也看得清楚。
	draw_arc(p, RADIUS, from, to, 24, Color(0, 0, 0, 0.5 * alpha), ARC_WIDTH + 2.0)
	if max_ammo > MAX_SEGMENTS:
		draw_arc(p, RADIUS, from, to, 24, dim, ARC_WIDTH)
		if _shown_ratio > 0.0:
			draw_arc(p, RADIUS, to - (to - from) * _shown_ratio, to, 24, color, ARC_WIDTH)
		return
	# 逐發分格：從上方開始消耗，剩下的集中在下方。
	var count := maxi(1, max_ammo)
	var step := (to - from) / count
	var gap := minf(step * 0.4, deg_to_rad(SEGMENT_GAP * 10.0))
	for i in count:
		var a0 := to - (i + 1) * step + gap * 0.5
		var a1 := to - i * step - gap * 0.5
		draw_arc(p, RADIUS, a0, a1, 4, color if i < ammo else dim, ARC_WIDTH)
