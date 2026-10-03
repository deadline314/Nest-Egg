class_name AmmoTray
extends Control
## 動態 HUD：主角身旁的彈匣——一排排子彈圖示（與準星相反的一側，不擋瞄準）。
##   滿的是彩色圖示，用掉的是空槽輪廓；開槍時最上面一發的彈殼彈出並淡出；換彈時依序填回去；
##   不到四分之一變紅並脈動；空匣整排變輪廓並提示換彈鍵；換武器時整排翻轉成新的彈種。
##   彈匣超過 MAX_ICONS 發時一顆圖示代表多發（標示倍率）；能量武器改用電池格；備彈用小數字顯示。
## 閒置淡出，射擊、換彈、彈量變化、換武器時彈出，低彈量時常駐。所有繪製用固定大小的陣列，不每影格配置。

const ICON := Vector2(7, 9.8)
const STEP := Vector2(8, 11)
const ROW_SIZE := 10
const MAX_ICONS := 30
const MAX_ROWS := 3
## 與角色中心的水平距離（畫面像素），與垂直偏移（往上）。
const SIDE_GAP := 16.0
const LIFT := 6.0
const FOLLOW_SHARPNESS := 18.0
const SNAP_DISTANCE := 120.0
const LOW_RATIO := 0.25
const FLIP_TIME := 0.2
const EJECT_SLOTS := 10
const EJECT_TIME := 0.45
const BLIP_VOLUME := -26.0
const EMPTY_HINT := "{reload} 換彈"
## 電池格的大小。
const CELL := Vector2(5, 8)
const CELL_STEP := 6.0

var presence := HudPresence.new()
var ammo := 0
var max_ammo := 0
var reserve := 0
var weapon_color := Palette.CYAN
var is_energy := false

var _player_ref := PlayerRef.new()
var _auto_hide := true
var _icon_id: StringName = &""
var _has_mag := false
var _per_icon := 1
var _pos := Vector2.ZERO
var _has_pos := false
var _side := -1.0
var _time := 0.0
var _flip_left := 0.0
var _hint := ""
## 換彈動畫：已經顯示為滿的發數（連續值），與上一次發出的提示音所在的發數。
var _refill := 0.0
var _refill_from := 0
var _blip_at := 0
var _reloading := false
var _pop_slot := -1
var _pop_left := 0.0
## 彈殼彈出：固定數量的環形緩衝。
var _eject_pos := PackedVector2Array()
var _eject_vel := PackedVector2Array()
var _eject_age := PackedFloat32Array()
var _eject_spin := PackedFloat32Array()
var _eject_next := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_auto_hide = Settings.get_hud_auto_hide()
	Settings.display_changed.connect(func() -> void: _auto_hide = Settings.get_hud_auto_hide())
	presence.idle_alpha = 0.0
	_eject_pos.resize(EJECT_SLOTS)
	_eject_vel.resize(EJECT_SLOTS)
	_eject_age.resize(EJECT_SLOTS)
	_eject_spin.resize(EJECT_SLOTS)
	_eject_age.fill(EJECT_TIME)
	_refresh_hint()
	InputBindings.bindings_changed.connect(_refresh_hint)
	EventBus.player_loadout_changed.connect(_on_loadout_changed)
	EventBus.player_spawned.connect(func(_p: Node2D) -> void:
		_has_pos = false)


func is_showing() -> bool:
	return _has_mag and presence.alpha > 0.05


func is_low() -> bool:
	return _has_mag and float(ammo) / float(maxi(1, max_ammo)) <= LOW_RATIO


## 目前顯示的圖示數量（超過 MAX_ICONS 時是壓縮後的數量）。
func icon_count() -> int:
	return ceili(float(max_ammo) / float(_per_icon)) if _has_mag else 0


func icons_per_row() -> int:
	return ROW_SIZE


func per_icon() -> int:
	return _per_icon


func side() -> float:
	return _side


func _refresh_hint() -> void:
	_hint = InputBindings.format(EMPTY_HINT)


func _on_loadout_changed(loadout: Loadout) -> void:
	var weapon := loadout.active_weapon() if loadout != null else null
	var slot := loadout.active_slot if loadout != null else -1
	var new_icon := AmmoIcons.icon_id_for(weapon) if weapon != null else &""
	var new_ammo := loadout.mag_in(slot) if weapon != null else 0
	var switched := new_icon != _icon_id or (weapon != null and weapon.magazine_size != max_ammo)
	if switched and _icon_id != &"":
		_flip_left = FLIP_TIME
	elif new_ammo < ammo and not _reloading:
		for i in ammo - new_ammo:
			_eject(ammo - i)
	_has_mag = weapon != null and weapon.has_magazine()
	_icon_id = new_icon
	ammo = new_ammo
	if weapon != null:
		max_ammo = weapon.magazine_size
		is_energy = weapon.is_energy
		weapon_color = weapon.color
		reserve = loadout.reserve_in(slot)
		_per_icon = per_icon_for(max_ammo)
	if _has_mag:
		presence.poke()
	if not _reloading:
		_refill = float(_icons_for(ammo))


## 彈匣容量超過 MAX_ICONS 時，一顆圖示代表幾發。
static func per_icon_for(capacity: int) -> int:
	return maxi(1, ceili(float(capacity) / float(MAX_ICONS)))


func _icons_for(rounds: int) -> int:
	return ceili(float(rounds) / float(_per_icon))


func _process(delta: float) -> void:
	var cinematic := Story.is_cinematic_active()
	if get_tree().paused and not cinematic:
		return
	_time += delta
	_flip_left = maxf(0.0, _flip_left - delta)
	_pop_left = maxf(0.0, _pop_left - delta)
	var player := _player_ref.get_player(get_tree())
	var hidden := cinematic or player == null or player.is_dead() or player.mounted_vehicle != null or not _has_mag
	var low_or_empty := is_low() or (_has_mag and ammo == 0)
	presence.update(delta, low_or_empty or _reloading, _auto_hide, hidden)
	if player != null:
		_follow(player, delta)
		_track_reload(player)
	_tick_ejects(delta)
	queue_redraw()


func _follow(player: Player, delta: float) -> void:
	var to_screen := get_viewport().get_canvas_transform()
	var anchor: Vector2 = to_screen * (player.global_position + Vector2(0, -34))
	var aim: Vector2 = to_screen * player.aim_point
	# 放在與準星相反的一側；準星在角色正上方或正下方時維持原本那一側，避免左右跳動。
	if absf(aim.x - anchor.x) > 8.0:
		_side = -1.0 if aim.x > anchor.x else 1.0
	var target := anchor + Vector2(_side * SIDE_GAP, -LIFT)
	if not _has_pos or _pos.distance_to(target) > SNAP_DISTANCE:
		_pos = target
		_has_pos = true
	else:
		_pos = _pos.lerp(target, 1.0 - exp(-FOLLOW_SHARPNESS * delta))


## 換彈：依換彈進度把空槽一顆顆填回去，每填一顆響一聲。
func _track_reload(player: Player) -> void:
	var now_reloading := player.loadout.is_reloading()
	var total := _icons_for(max_ammo)
	if now_reloading and not _reloading:
		_refill_from = _icons_for(ammo)
		_blip_at = _refill_from
		presence.poke()
	_reloading = now_reloading
	if _reloading:
		var progress := player.loadout.reload_progress()
		_refill = lerpf(float(_refill_from), float(total), progress)
		var filled := int(_refill)
		if filled > _blip_at:
			_blip_at = filled
			_pop_slot = filled - 1
			_pop_left = 0.14
			Sfx.play(&"ui_move", BLIP_VOLUME, 0.0)
	else:
		_refill = float(_icons_for(ammo))


func _eject(index: int) -> void:
	if is_energy:
		return
	var slot := _eject_next
	_eject_next = (_eject_next + 1) % EJECT_SLOTS
	var rect_pos := _slot_position(clampi(_icons_for(index) - 1, 0, maxi(0, icon_count() - 1)))
	_eject_pos[slot] = rect_pos
	_eject_vel[slot] = Vector2(_side * randf_range(30.0, 70.0), randf_range(-70.0, -35.0))
	_eject_age[slot] = 0.0
	_eject_spin[slot] = randf_range(-9.0, 9.0)


func _tick_ejects(delta: float) -> void:
	for i in EJECT_SLOTS:
		if _eject_age[i] >= EJECT_TIME:
			continue
		_eject_age[i] += delta
		_eject_vel[i].y += 260.0 * delta
		_eject_pos[i] += _eject_vel[i] * delta


## 第 index 顆圖示左上角的位置：由下往上排、每排 ROW_SIZE 顆，從靠近角色的一側往外排
## （托盤在角色左邊時往左排，在右邊時往右排）。
func _slot_position(index: int) -> Vector2:
	var row := index / ROW_SIZE
	var column := index % ROW_SIZE
	var x := _pos.x - ICON.x - float(column) * STEP.x if _side < 0.0 else _pos.x + float(column) * STEP.x
	return Vector2(x, _pos.y - ICON.y - float(row) * STEP.y)


func _draw() -> void:
	var alpha := presence.alpha
	if alpha <= 0.01 or not _has_mag or not _has_pos:
		return
	# 換武器的翻轉：整排沿垂直軸壓扁再展開。
	var flip := 1.0
	if _flip_left > 0.0:
		flip = absf(1.0 - 2.0 * (_flip_left / FLIP_TIME))
	var pulse := 1.0
	var state_low := is_low() and ammo > 0
	if state_low:
		pulse = 0.65 + 0.35 * absf(sin(_time * 8.0))
	if is_energy:
		_draw_battery(alpha, pulse, state_low, flip)
	else:
		_draw_icons(alpha, pulse, state_low, flip)
	_draw_ejects(alpha)
	_draw_reserve(alpha)


func _draw_icons(alpha: float, pulse: float, state_low: bool, flip: float) -> void:
	var count := icon_count()
	var full_state := AmmoIcons.State.LOW if state_low else AmmoIcons.State.FULL
	var full_tex := AmmoIcons.texture(_icon_id, full_state)
	var empty_tex := AmmoIcons.texture(_icon_id, AmmoIcons.State.EMPTY)
	var shown := _icons_for(ammo) if not _reloading else int(_refill)
	for i in count:
		var p := _slot_position(i)
		var size := ICON
		var origin := p
		if _pop_left > 0.0 and i == _pop_slot:
			var k := 1.0 + 0.45 * (_pop_left / 0.14)
			origin -= (size * k - size) * 0.5
			size *= k
		# 沿圖示中心壓扁寬度。
		var center_x := origin.x + size.x * 0.5
		var width := size.x * flip
		var rect := Rect2(center_x - width * 0.5, origin.y, width, size.y)
		if i < shown:
			draw_texture_rect(full_tex, rect, false, Color(1, 1, 1, alpha * pulse))
		else:
			draw_texture_rect(empty_tex, rect, false, Color(1, 1, 1, alpha * 0.8))
	if _per_icon > 1:
		_text(_slot_position(count - 1) + Vector2(0, -3), "×%d" % _per_icon, Palette.UI_MUTED, alpha, 9)
	if ammo == 0 and not _reloading:
		_text(_pos + Vector2(-16 if _side < 0.0 else 0.0, 7.0), _hint, LightKit.glow(Palette.NEON_YELLOW, 1.3), alpha * (0.6 + 0.4 * sin(_time * 6.0)), 9)


## 能量武器：圖示在前、後面是分段的電池格。
func _draw_battery(alpha: float, pulse: float, state_low: bool, flip: float) -> void:
	var tex := AmmoIcons.texture(_icon_id, AmmoIcons.State.LOW if state_low else AmmoIcons.State.FULL)
	var dir := -1.0 if _side < 0.0 else 1.0
	var origin := Vector2(_pos.x - (AmmoIcons.CELL.x if _side < 0.0 else 0.0), _pos.y - AmmoIcons.CELL.y)
	var icon_rect := Rect2(origin, AmmoIcons.CELL)
	var width := icon_rect.size.x * flip
	icon_rect = Rect2(icon_rect.position.x + (icon_rect.size.x - width) * 0.5, icon_rect.position.y, width, icon_rect.size.y)
	draw_texture_rect(tex, icon_rect, false, Color(1, 1, 1, alpha * pulse))
	var shown := ammo if not _reloading else int(float(max_ammo) * (_refill / float(maxi(1, icon_count()))))
	var color := Color(LightKit.glow(Palette.DANGER if state_low or ammo == 0 else weapon_color, 1.5), alpha * pulse)
	for i in max_ammo:
		var x := origin.x + dir * (AmmoIcons.CELL.x + 3.0 + float(i) * CELL_STEP) - (CELL.x if dir < 0.0 else 0.0)
		var rect := Rect2(x, origin.y + AmmoIcons.CELL.y - CELL.y, CELL.x, CELL.y)
		if i < shown:
			draw_rect(rect, color)
		else:
			draw_rect(rect, Color(0.5, 0.62, 0.75, alpha * 0.3), false, 1.0)
	if ammo == 0 and not _reloading:
		_text(_pos + Vector2(-16 if _side < 0.0 else 0.0, 7.0), _hint, LightKit.glow(Palette.NEON_YELLOW, 1.3), alpha * (0.6 + 0.4 * sin(_time * 6.0)), 9)


func _draw_ejects(alpha: float) -> void:
	if _icon_id == &"":
		return
	var tex := AmmoIcons.texture(_icon_id, AmmoIcons.State.FULL)
	for i in EJECT_SLOTS:
		var age := _eject_age[i]
		if age >= EJECT_TIME:
			continue
		var k := age / EJECT_TIME
		var rect := Rect2(_eject_pos[i], ICON)
		draw_set_transform(rect.get_center(), _eject_spin[i] * age, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-ICON * 0.5, ICON), false, Color(1, 1, 1, alpha * (1.0 - k)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 備彈：小數字，無限備彈顯示符號。
func _draw_reserve(alpha: float) -> void:
	var text := "∞" if reserve < 0 else str(reserve)
	var dir_left := _side < 0.0
	var pos := _pos + Vector2(-2.0 if dir_left else 2.0, 9.0)
	_text(pos, text, Palette.UI_MUTED, alpha, 9, dir_left)


func _text(pos: Vector2, text: String, color: Color, alpha: float, size: int, right_aligned := false) -> void:
	var font := UiKit.font()
	var draw_pos := pos
	if right_aligned:
		draw_pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, draw_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * alpha))
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * alpha))
