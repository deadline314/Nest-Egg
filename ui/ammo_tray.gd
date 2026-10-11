class_name AmmoTray
extends Control
## 動態 HUD：主角身旁的彈帶——常駐的一排子彈圖示（與準星相反的一側，不擋瞄準）。
##   固定最多 MAX_ICONS（10）顆圖示：彈匣更大的槍一顆圖示代表多發，長度不變；離主角最近的是下一發。
##   開槍時最靠近主角的那一顆彈出並淡出，其餘子彈用緩動往主角的方向滑過去補位（連續開槍時累積、不打結）；
##   換彈時從遠端依序補回；不到四分之一變紅並脈動；空匣整排變輪廓並提示換彈鍵；換武器時整排翻轉成新的彈種。
##   能量武器改用電池格；備彈用小數字顯示在近端。
## 常駐顯示（不受 HUD 自動淡出影響），只有死亡、過場、乘坐載具、沒有彈匣的武器時隱藏。所有繪製用固定大小的陣列，不每影格配置。

const ICON := Vector2(6, 8.4)
const STEP := Vector2(7, 0)
## 一排最多幾顆圖示（彈匣更大時一顆代表多發）。
const MAX_ICONS := 10
## 補位滑動：每打掉一顆圖示，剩下的子彈從「遠一格」滑回來；累積上限（格）與回復的快慢（越大越快到位）。
const SLIDE_MAX_STEPS := 3.0
const SLIDE_SHARPNESS := 20.0
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
var _icon_id: StringName = &""
var _has_mag := false
## 一顆圖示代表幾發（容量不超過 MAX_ICONS 時是 1，更大時是容量 / MAX_ICONS，可以不是整數）。
var _per_icon := 1.0
## 補位滑動的剩餘距離（像素，往遠離主角的方向為正）。
var _slide := 0.0
var _pos := Vector2.ZERO
var _has_pos := false
var _side := -1.0
## 畫面上實際的方向（-1～1 連續值）：轉身時整排先收攏到主角身旁再往另一側展開，不在一格內跳到另一邊。
var _draw_side := -1.0
## 移到頭頂的權重（0 在背後、1 在頭上）；主角靠近畫面邊緣、背後放不下時才往上移（NE-264）。
var _above := 0.0
var _time := 0.0
var _flip_left := 0.0
var _hint := ""
var _obstacle_reserve_width := 0.0
var _obstacle_hint_width := 0.0
var _obstacle_icon_label_width := 0.0
var _obstacle_ascent := 0.0
var _obstacle_descent := 0.0
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
	presence.idle_alpha = 1.0
	_eject_pos.resize(EJECT_SLOTS)
	_eject_vel.resize(EJECT_SLOTS)
	_eject_age.resize(EJECT_SLOTS)
	_eject_spin.resize(EJECT_SLOTS)
	_eject_age.fill(EJECT_TIME)
	_refresh_hint()
	Settings.display_changed.connect(_refresh_obstacle_text_metrics)
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	InputBindings.bindings_changed.connect(_refresh_hint)
	EventBus.player_loadout_changed.connect(_on_loadout_changed)
	EventBus.player_spawned.connect(func(_p: Node2D) -> void:
		_has_pos = false)


func is_showing() -> bool:
	return _has_mag and presence.alpha > 0.05


func is_low() -> bool:
	return _has_mag and float(ammo) / float(maxi(1, max_ammo)) <= LOW_RATIO


## 目前顯示的圖示數量（最多 MAX_ICONS）。
func icon_count() -> int:
	return _icons_for(max_ammo) if _has_mag else 0


func per_icon() -> float:
	return _per_icon


## 補位滑動剩下的距離（像素）；測試與稽核用。
func slide() -> float:
	return _slide


func side() -> float:
	return _side


func _refresh_hint() -> void:
	_hint = InputBindings.format(EMPTY_HINT)
	_refresh_obstacle_text_metrics()


func _on_loadout_changed(loadout: Loadout) -> void:
	var weapon := loadout.active_weapon() if loadout != null else null
	var slot := loadout.active_slot if loadout != null else -1
	var new_icon := AmmoIcons.icon_id_for(weapon) if weapon != null else &""
	var new_ammo := loadout.mag_in(slot) if weapon != null else 0
	var switched := new_icon != _icon_id or (weapon != null and weapon.magazine_size != max_ammo)
	if switched and _icon_id != &"":
		_flip_left = FLIP_TIME
	elif new_ammo < ammo and not _reloading and _per_icon > 0.0:
		# 每一發離主角最近的那一顆彈出；打掉整顆圖示時，剩下的往主角方向補位。
		for i in mini(ammo - new_ammo, EJECT_SLOTS):
			_eject()
		var lost := maxi(0, _icons_for(ammo) - _icons_for(new_ammo))
		_slide = minf(_slide + float(lost) * STEP.x, SLIDE_MAX_STEPS * STEP.x)
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
	_refresh_obstacle_text_metrics()


## 彈匣容量超過 MAX_ICONS 時，一顆圖示代表幾發（容量 / MAX_ICONS，不到時一發一顆）。
static func per_icon_for(capacity: int) -> float:
	return maxf(1.0, float(capacity) / float(MAX_ICONS))


func _icons_for(rounds: int) -> int:
	return mini(MAX_ICONS, ceili(float(rounds) / _per_icon - 0.0001))


func _process(delta: float) -> void:
	var cinematic := Story.is_cinematic_active()
	if get_tree().paused and not cinematic:
		return
	_time += delta
	_flip_left = maxf(0.0, _flip_left - delta)
	_pop_left = maxf(0.0, _pop_left - delta)
	var player := _player_ref.get_player(get_tree())
	var hidden := cinematic or player == null or player.is_dead() or player.mounted_vehicle != null or not _has_mag
	presence.update(delta, true, false, hidden)  # 常駐：不受自動淡出影響
	_slide = lerpf(_slide, 0.0, 1.0 - exp(-SLIDE_SHARPNESS * delta))
	if _slide < 0.02:
		_slide = 0.0
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
	var view_width := get_viewport_rect().size.x
	# 用面向判斷（與生命護盾標籤相同）；準星方向只決定背後是哪一側的顯示。
	var wanted_above := HudPlacement.above_target(anchor.x, -float(player.facing), view_width)
	if not _has_pos:
		_draw_side = _side
		_above = wanted_above
	else:
		_draw_side = move_toward(_draw_side, _side, delta * 2.0 / FLIP_TIME)
		_above = move_toward(_above, wanted_above, delta * HudPlacement.BLEND_SPEED)
	var width := _row_width()
	var beside := anchor + Vector2(_draw_side * SIDE_GAP, -LIFT)
	var head: Vector2 = to_screen * (player.global_position + HudPlacement.HEAD_OFFSET)
	var over := Vector2(anchor.x - _draw_side * width * 0.5, head.y - HudPlacement.ABOVE_GAP)
	var target := beside.lerp(over, smoothstep(0.0, 1.0, _above))
	# 整排（含收攏中的寬度）留在畫面左右邊緣之內。
	var span := absf(_draw_side) * width
	target.x += HudPlacement.clamp_shift(target.x if _draw_side >= 0.0 else target.x - span, span, view_width)
	if not _has_pos or _pos.distance_to(target) > SNAP_DISTANCE:
		_pos = target
		_has_pos = true
	else:
		_pos = _pos.lerp(target, 1.0 - exp(-FOLLOW_SHARPNESS * delta))


## 整排在畫面上的寬度（子彈圖示或電池格，不含備彈數字）。
func _row_width() -> float:
	if is_energy:
		return AmmoIcons.CELL.x + 3.0 + float(maxi(0, max_ammo)) * CELL_STEP
	return float(maxi(0, icon_count() - 1)) * STEP.x + ICON.x


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


## 離主角最近的那一顆彈出（彈帶的第 0 格）。
func _eject() -> void:
	if is_energy:
		return
	var slot := _eject_next
	_eject_next = (_eject_next + 1) % EJECT_SLOTS
	_eject_pos[slot] = _slot_position(0)
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


## 第 index 顆圖示左上角的位置：從靠近角色的一側往外排成一排
## （彈帶在角色左邊時往左排，在右邊時往右排）；index 0 是下一發。
func _slot_position(index: int) -> Vector2:
	# 以圖示中心沿方向排列：方向是連續值，轉身時各顆圖示平滑收攏再展開。
	var center := _pos.x + _draw_side * (float(index) * STEP.x + ICON.x * 0.5)
	return Vector2(center - ICON.x * 0.5, _pos.y - ICON.y)


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
		var rect := _icon_draw_rect(i, shown, flip)
		if i < shown:
			draw_texture_rect(full_tex, rect, false, Color(1, 1, 1, alpha * pulse))
		else:
			draw_texture_rect(empty_tex, rect, false, Color(1, 1, 1, alpha * 0.8))
	if _per_icon >= 2.0:
		_text(_slot_position(count - 1) + Vector2(0, -3), "×%d" % roundi(_per_icon), Palette.UI_MUTED, alpha, 9)
	if ammo == 0 and not _reloading:
		_text(_pos + Vector2(-16 if _draw_side < 0.0 else 0.0, 7.0), _hint, LightKit.glow(Palette.NEON_YELLOW, 1.3), alpha * (0.6 + 0.4 * sin(_time * 6.0)), 9)


## Pure geometry shared by drawing and prompt obstruction; preserves current slide/pop/flip animation.
func _icon_draw_rect(index: int, shown: int, flip: float) -> Rect2:
	var origin := _slot_position(index)
	if index < shown:
		origin.x += _draw_side * _slide
	var size := ICON
	if _pop_left > 0.0 and index == _pop_slot:
		var scale := 1.0 + 0.45 * (_pop_left / 0.14)
		origin -= (size * scale - size) * 0.5
		size *= scale
	var width := size.x * flip
	return Rect2(origin.x + (size.x - width) * 0.5, origin.y, width, size.y)


## 能量武器：圖示在前、後面是分段的電池格。
func _draw_battery(alpha: float, pulse: float, state_low: bool, flip: float) -> void:
	var tex := AmmoIcons.texture(_icon_id, AmmoIcons.State.LOW if state_low else AmmoIcons.State.FULL)
	draw_texture_rect(tex, _battery_icon_rect(flip), false, Color(1, 1, 1, alpha * pulse))
	var shown := ammo if not _reloading else int(float(max_ammo) * (_refill / float(maxi(1, icon_count()))))
	var color := Color(LightKit.glow(Palette.DANGER if state_low or ammo == 0 else weapon_color, 1.5), alpha * pulse)
	for i in max_ammo:
		var rect := _battery_cell_rect(i)
		if i < shown:
			draw_rect(rect, color)
		else:
			draw_rect(rect, Color(0.5, 0.62, 0.75, alpha * 0.3), false, 1.0)
	if ammo == 0 and not _reloading:
		_text(_pos + Vector2(-16 if _draw_side < 0.0 else 0.0, 7.0), _hint, LightKit.glow(Palette.NEON_YELLOW, 1.3), alpha * (0.6 + 0.4 * sin(_time * 6.0)), 9)


## 電池圖示與第 i 格電池的位置：和子彈一樣以中心沿連續方向排列，轉身時平滑收攏再展開。
func _battery_icon_rect(flip: float) -> Rect2:
	var center := Vector2(_pos.x + _draw_side * AmmoIcons.CELL.x * 0.5, _pos.y - AmmoIcons.CELL.y * 0.5)
	var width := AmmoIcons.CELL.x * flip
	return Rect2(center.x - width * 0.5, center.y - AmmoIcons.CELL.y * 0.5, width, AmmoIcons.CELL.y)


func _battery_cell_rect(index: int) -> Rect2:
	var center := _pos.x + _draw_side * (AmmoIcons.CELL.x + 3.0 + float(index) * CELL_STEP + CELL.x * 0.5)
	return Rect2(center - CELL.x * 0.5, _pos.y - CELL.y, CELL.x, CELL.y)


## Actual visible AmmoTray drawing bounds in world space, including transient pooled shells.
func prompt_obstacle_rect() -> Rect2:
	if not is_visible_in_tree() or presence.alpha <= 0.01 or modulate.a <= 0.01 \
				or self_modulate.a <= 0.01 or not _has_mag or not _has_pos:
		return Rect2()
	var bounds := Rect2()
	var flip := 1.0
	if _flip_left > 0.0:
		flip = absf(1.0 - 2.0 * (_flip_left / FLIP_TIME))
	if is_energy:
		bounds = _merge_prompt_rect(bounds, _battery_icon_rect(flip))
		for i in max_ammo:
			bounds = _merge_prompt_rect(bounds, _battery_cell_rect(i))
	else:
		var count := icon_count()
		var shown := _icons_for(ammo) if not _reloading else int(_refill)
		for i in count:
			bounds = _merge_prompt_rect(bounds, _icon_draw_rect(i, shown, flip))
		if _per_icon >= 2.0 and count > 0:
			bounds = _merge_prompt_rect(bounds, _baseline_rect(_slot_position(count - 1) + Vector2(0, -3), _obstacle_icon_label_width, false))
	if ammo == 0 and not _reloading:
		var hint_anchor := _pos + Vector2(-16.0 if _draw_side < 0.0 else 0.0, 7.0)
		# Both draw paths call _text without right_aligned, so the hint begins at this anchor.
		bounds = _merge_prompt_rect(bounds, _baseline_rect(hint_anchor, _obstacle_hint_width, false))
	# _draw_ejects checks only icon identity; pooled shells remain drawable after energy switch.
	if _icon_id != &"":
		var radius := Vector2(ICON.x * 0.5, ICON.y * 0.5).length()
		for i in EJECT_SLOTS:
			if _eject_age[i] < EJECT_TIME:
				var center := _eject_pos[i] + ICON * 0.5
				bounds = _merge_prompt_rect(bounds, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	bounds = _merge_prompt_rect(bounds, _baseline_rect(_reserve_anchor(), _obstacle_reserve_width, _reserve_right_aligned()))
	if not bounds.has_area():
		return Rect2()
	var canvas := get_viewport().get_canvas_transform()
	if not is_finite(canvas.determinant()) or is_zero_approx(canvas.determinant()):
		return Rect2()
	return canvas.affine_inverse() * (get_global_transform() * bounds)


func _baseline_rect(anchor: Vector2, text_width: float, right_aligned: bool) -> Rect2:
	if text_width <= 0.0:
		return Rect2()
	var left := anchor.x - text_width if right_aligned else anchor.x
	return Rect2(left - 1.0, anchor.y - _obstacle_ascent - 1.0, text_width + 2.0, _obstacle_ascent + _obstacle_descent + 2.0)


func _merge_prompt_rect(bounds: Rect2, next: Rect2) -> Rect2:
	if not next.has_area():
		return bounds
	return next if not bounds.has_area() else bounds.merge(next)


func _refresh_obstacle_text_metrics() -> void:
	var font := UiKit.font()
	_obstacle_ascent = font.get_ascent(9)
	_obstacle_descent = font.get_descent(9)
	_obstacle_reserve_width = font.get_string_size("∞" if reserve < 0 else str(reserve), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_obstacle_hint_width = font.get_string_size(_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_obstacle_icon_label_width = font.get_string_size("×%d" % roundi(_per_icon), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x if _per_icon >= 2.0 else 0.0


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
	_text(_reserve_anchor(), text, Palette.UI_MUTED, alpha, 9, _reserve_right_aligned())


## 備彈數字：在背後時寫在彈帶下方靠主角；移到頭頂時改寫在整排靠畫面內側的那一端（外側可能就是畫面邊緣），不壓到頭髮。
func _reserve_anchor() -> Vector2:
	var below := _pos + Vector2(-2.0 if _draw_side < 0.0 else 2.0, 9.0)
	var inner := Vector2(_pos.x - _draw_side * 3.0, _pos.y - 1.0)
	return below.lerp(inner, smoothstep(0.0, 1.0, _above))


func _reserve_right_aligned() -> bool:
	return (_draw_side < 0.0) != (_above > 0.5)


func _text(pos: Vector2, text: String, color: Color, alpha: float, size: int, right_aligned := false) -> void:
	var font := UiKit.font()
	var draw_pos := pos
	if right_aligned:
		draw_pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, draw_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * alpha))
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * alpha))
