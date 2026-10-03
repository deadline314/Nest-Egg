class_name AmmoRing
extends Control
## 動態 HUD：準星旁的換彈進度弧與提示。彈匣本身改由主角身旁的 AmmoTray 顯示（見 ammo_tray.gd）。
## 換彈時弧形顯示進度並標示 RELOAD；彈匣與備彈都打光時顯示 EMPTY；換武器時在準星旁短暫顯示武器代號。
## 彈量、備彈等數值仍在這裡維護（測試與其他介面讀取），只是不再畫彈匣計量與數字。

const RADIUS := 14.0
const ARC_FROM := -55.0
const ARC_TO := 55.0
const ARC_WIDTH := 2.5
const LOW_RATIO := 0.25
const NAME_TIME := 1.1
const EMPTY_TIME := 0.9

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
var _name_left := 0.0
var _empty_left := 0.0
var _reload_progress := 0.0
var _reloading := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	presence.idle_alpha = 1.0
	EventBus.player_loadout_changed.connect(_on_loadout_changed)


func is_showing_ammo() -> bool:
	return _has_mag


func is_low() -> bool:
	return _has_mag and float(ammo) / float(maxi(1, max_ammo)) <= LOW_RATIO


func _process(delta: float) -> void:
	var cinematic := Story.is_cinematic_active()
	if get_tree().paused and not cinematic:
		return
	_time += delta
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


func _draw() -> void:
	var alpha := presence.alpha
	if alpha <= 0.01:
		return
	var p := _point
	var font := UiKit.font()
	if _has_mag and _reloading:
		_draw_reload_arc(p, alpha)
		var label := "RECHARGE" if is_energy else "RELOAD"
		_shadowed(p + Vector2(-16, 25), label, 8, Color(LightKit.glow(Palette.WHITE, 1.5), (0.7 + 0.3 * sin(_time * 12.0)) * alpha))
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


## 換彈進度弧：由下往上填滿。
func _draw_reload_arc(p: Vector2, alpha: float) -> void:
	var from := deg_to_rad(ARC_FROM)
	var to := deg_to_rad(ARC_TO)
	draw_arc(p, RADIUS, from, to, 24, Color(0, 0, 0, 0.5 * alpha), ARC_WIDTH + 2.0)
	draw_arc(p, RADIUS, from, to, 24, Color(0.05, 0.08, 0.12, 0.7 * alpha), ARC_WIDTH)
	if _reload_progress > 0.0:
		draw_arc(p, RADIUS, to - (to - from) * _reload_progress, to, 24, Color(LightKit.glow(Palette.WHITE, 1.6), alpha), ARC_WIDTH)
