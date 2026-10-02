class_name AmmoRing
extends Control
## 動態 HUD：準星右側的弧形彈匣計量，旁邊顯示「彈匣／備彈」。
## 換彈時弧形顯示進度並標示 RELOAD；彈匣偏低時提示換彈鍵；低彈藥變黃、最後幾發變紅；
## 彈匣與備彈都打光時顯示 EMPTY；換武器時在準星旁短暫顯示武器代號。

const RADIUS := 14.0
const ARC_FROM := -55.0
const ARC_TO := 55.0
const ARC_WIDTH := 2.5
## 彈匣超過此數時改成連續弧形，不再逐發分格。
const MAX_SEGMENTS := 36
const LOW_RATIO := 0.25
const CRITICAL_SHOTS := 2
const BUMP_TIME := 0.12
const NAME_TIME := 1.1
const EMPTY_TIME := 0.9
const RELOAD_HINT := "{reload} 換彈"

var presence := HudPresence.new()
var weapon_name := ""
var ammo := 0
var max_ammo := 0
## -1 代表無限。
var reserve := 0
var ammo_per_shot := 1
var weapon_color := Palette.CYAN
var is_energy := false

var _player_ref := PlayerRef.new()
var _weapon_id: StringName = &""
var _has_mag := false
var _point := Vector2.ZERO
var _time := 0.0
var _bump_left := 0.0
var _name_left := 0.0
var _empty_left := 0.0
var _reload_progress := 0.0
var _reloading := false
var _hint := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	presence.idle_alpha = 1.0
	_refresh_hint()
	InputBindings.bindings_changed.connect(_refresh_hint)
	EventBus.player_loadout_changed.connect(_on_loadout_changed)


func is_showing_ammo() -> bool:
	return _has_mag


func is_low() -> bool:
	return _has_mag and float(ammo) / float(maxi(1, max_ammo)) <= LOW_RATIO


func _refresh_hint() -> void:
	_hint = InputBindings.format(RELOAD_HINT)


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
	presence.update(delta, false, true, hidden or not (_has_mag or _name_left > 0.0 or _empty_left > 0.0))
	if player != null:
		_point = get_viewport().get_canvas_transform() * player.aim_point
		_reloading = player.loadout.is_reloading()
		_reload_progress = player.loadout.reload_progress()
	queue_redraw()


func _on_loadout_changed(loadout: Loadout) -> void:
	var weapon := loadout.active_weapon() if loadout != null else null
	var new_id: StringName = weapon.id if weapon != null else &""
	var slot := loadout.active_slot if loadout != null else -1
	var new_ammo := loadout.mag_in(slot) if weapon != null else 0
	if new_id != _weapon_id:
		# 有限彈藥武器打光後會自動切回主武器：顯示「EMPTY」。
		var previous_slot := loadout.find_slot(_weapon_id) if loadout != null else -1
		if _has_mag and previous_slot >= 0 and loadout.mag_in(previous_slot) == 0 and loadout.reserve_in(previous_slot) == 0:
			_empty_left = EMPTY_TIME
		if weapon != null and _weapon_id != &"":
			_name_left = NAME_TIME
		presence.poke()
	elif new_ammo < ammo:
		_bump_left = BUMP_TIME
	_weapon_id = new_id
	_has_mag = weapon != null and weapon.has_magazine()
	ammo = new_ammo
	reserve = loadout.reserve_in(slot) if weapon != null else 0
	if weapon != null:
		weapon_name = weapon.short_name if not weapon.short_name.is_empty() else weapon.display_name
		max_ammo = weapon.magazine_size
		ammo_per_shot = maxi(1, weapon.ammo_per_shot)
		weapon_color = weapon.color
		is_energy = weapon.is_energy


func _ammo_color() -> Color:
	if ammo / ammo_per_shot <= CRITICAL_SHOTS:
		return LightKit.glow(Palette.DANGER, 1.4 + 0.8 * absf(sin(_time * 9.0)))
	if is_low():
		return LightKit.glow(Palette.NEON_YELLOW, 1.3 + 0.5 * absf(sin(_time * 5.0)))
	# 平常用 HUD 青色，讓黃（低彈藥）、紅（最後幾發）的警示一眼可辨。
	return LightKit.glow(Palette.CYAN, 1.5)


func _draw() -> void:
	var alpha := presence.alpha
	if alpha <= 0.01:
		return
	var p := _point
	var font := UiKit.font()
	if _has_mag:
		_draw_arc(p, alpha)
		var bump := _bump_left / BUMP_TIME
		var text_pos := p + Vector2(RADIUS + 5.0, 4.0 - 2.0 * bump)
		var size := 9 + int(round(2.0 * bump))
		var mag_text := str(ammo)
		_shadowed(text_pos, mag_text, size, Color(_ammo_color(), alpha))
		var reserve_text := "/" + ("∞" if reserve < 0 else str(reserve))
		var reserve_x := text_pos.x + font.get_string_size(mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 1.0
		_shadowed(Vector2(reserve_x, text_pos.y), reserve_text, 7, Color(Palette.UI_MUTED, alpha))
		if _reloading:
			var label := "RECHARGE" if is_energy else "RELOAD"
			_shadowed(p + Vector2(-16, 25), label, 8, Color(LightKit.glow(Palette.WHITE, 1.5), (0.7 + 0.3 * sin(_time * 12.0)) * alpha))
		elif is_low() and reserve != 0:
			_shadowed(p + Vector2(-16, 25), _hint, 8, Color(LightKit.glow(Palette.NEON_YELLOW, 1.3), (0.6 + 0.4 * sin(_time * 6.0)) * alpha))
	if _name_left > 0.0:
		var k := minf(1.0, _name_left / 0.3)
		_shadowed(p + Vector2(RADIUS + 5.0, -10.0 + 3.0 * (1.0 - k)), weapon_name, 8, Color(LightKit.glow(weapon_color, 1.4), k * alpha))
	if _empty_left > 0.0:
		var k := _empty_left / EMPTY_TIME
		var flicker := 0.6 + 0.4 * signf(sin(_time * 30.0))
		_shadowed(p + Vector2(-14, 36), "EMPTY", 9, Color(LightKit.glow(Palette.DANGER, 1.8), k * flicker * alpha))


func _shadowed(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(UiKit.font(), pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * color.a))
	draw_string(UiKit.font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_arc(p: Vector2, alpha: float) -> void:
	var from := deg_to_rad(ARC_FROM)
	var to := deg_to_rad(ARC_TO)
	var dim := Color(0.05, 0.08, 0.12, 0.7 * alpha)
	# 底色外框，讓亮背景上也看得清楚。
	draw_arc(p, RADIUS, from, to, 24, Color(0, 0, 0, 0.5 * alpha), ARC_WIDTH + 2.0)
	if _reloading:
		# 換彈進度：由下往上填滿。
		draw_arc(p, RADIUS, from, to, 24, dim, ARC_WIDTH)
		if _reload_progress > 0.0:
			draw_arc(p, RADIUS, to - (to - from) * _reload_progress, to, 24, Color(LightKit.glow(Palette.WHITE, 1.6), alpha), ARC_WIDTH)
		return
	var color := Color(_ammo_color(), alpha)
	var count := maxi(1, max_ammo)
	if count > MAX_SEGMENTS:
		draw_arc(p, RADIUS, from, to, 24, dim, ARC_WIDTH)
		var ratio := float(ammo) / float(count)
		if ratio > 0.0:
			draw_arc(p, RADIUS, to - (to - from) * ratio, to, 24, color, ARC_WIDTH)
		return
	# 逐發分格：從上方開始消耗，剩下的集中在下方。
	var step := (to - from) / count
	var gap := minf(step * 0.4, deg_to_rad(2.5))
	for i in count:
		var a0 := to - (i + 1) * step + gap * 0.5
		var a1 := to - i * step - gap * 0.5
		draw_arc(p, RADIUS, a0, a1, 4, color if i < ammo else dim, ARC_WIDTH)
