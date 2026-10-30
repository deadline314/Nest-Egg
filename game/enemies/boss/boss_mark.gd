class_name BossMark
extends Node2D
## 頭目給玩家的疊層標記與清除地墊（資料 data/bosses/<id>.json 的 mark；第二章阿勇的「利息」與「結帳」地墊）。
## 規則：頭目醒著時，玩家每受擊一次疊一層（最多 max 層），每層讓下一擊多 per_stack 的傷害；
## 踩上亮著的地墊、或 decay 秒沒有受擊，就全部清除。地墊一次只亮一塊，被踩掉（玩家或頭目）後暗 dark_time 秒，再換一塊亮。
## 畫面：玩家頭上一排小格顯示層數；每塊地墊的白框分成 max 段，亮起的段數就是目前層數（踩下去會清掉幾層）。
## 只改玩家受擊框的傷害倍率，不另外記貨幣或存檔；頭目離開場景時一定還原倍率。

signal stacks_changed(stacks: int)
signal pad_used(index: int, by_player: bool)

const PAD_WIDTH := 26.0
const PAD_REACH := 14.0
## 玩家頭上的層數格高度：在彈帶與護盾標籤（NE-264）上面，不和它們重疊。
const HEAD_OFFSET := 104.0
const PIP := 4.0
const PIP_GAP := 2.0

var label := "標記"
## 亮著的地墊上寫的字（空白就不寫）。
var pad_label := ""
var max_stacks := 5
var per_stack := 0.1
var decay := 6.0
var lit_time := 6.0
var dark_time := 2.0
## 第一次疊層時的提示（一句講重點）與劇情的短通訊（可空白）。
var first_hint := ""
var first_scene: StringName = &""
var stacks := 0
var active := false

var _boss: Enemy
var _player: Player
## 每塊地墊：{tile, row, pos（世界座標，地面上）, lit, timer}
var _pads: Array[Dictionary] = []
var _lit := -1
var _dark_left := 0.0
var _since_hit := 0.0
var _hinted := false
var _font: Font
var _floor_ray := PhysicsRayQueryParameters2D.new()


## 讀資料（欄位錯誤時記錄頭目 id 與欄位，退回預設值）。
func configure(boss: Enemy, config: Dictionary, where: String) -> void:
	_boss = boss
	label = str(config.get("label", label))
	pad_label = str(config.get("pad_label", ""))
	max_stacks = clampi(int(config.get("max", max_stacks)), 1, 9)
	per_stack = clampf(float(config.get("per_stack", per_stack)), 0.0, 0.5)
	decay = maxf(1.0, float(config.get("decay", decay)))
	lit_time = maxf(1.0, float(config.get("lit_time", lit_time)))
	dark_time = maxf(0.0, float(config.get("dark_time", dark_time)))
	first_hint = str(config.get("first_hint", ""))
	first_scene = StringName(str(config.get("first_scene", "")))
	var pads: Variant = config.get("pads", [])
	if pads is Array:
		for entry: Variant in pads:
			if entry is Dictionary and (entry as Dictionary).has("tile"):
				_pads.append({"tile": float((entry as Dictionary)["tile"]), "row": int((entry as Dictionary).get("row", -1)),
						"pos": Vector2.INF, "lit": false})
			else:
				push_error("[BossMark] %s：mark.pads 的項目要有 tile（欄），略過 %s" % [where, entry])
	top_level = true
	z_index = 2
	set_physics_process(false)


func _ready() -> void:
	_font = UiKit.font()


## 頭目醒來：找出地墊在地上的位置、亮第一塊、開始聽玩家受擊。
func start() -> void:
	if active:
		return
	active = true
	global_position = Vector2.ZERO
	for pad in _pads:
		pad["pos"] = _ground_at(pad)
	_dark_left = 0.0
	_bind_player()
	set_physics_process(true)


## 停止（制伏、擊敗、離開場景）：清掉層數並還原玩家的傷害倍率。
func stop() -> void:
	active = false
	_set_stacks(0)
	for pad in _pads:
		pad["lit"] = false
	_lit = -1
	set_physics_process(false)
	queue_redraw()


func _exit_tree() -> void:
	stop()


func lit_pad() -> int:
	return _lit


func pad_position(index: int) -> Vector2:
	return _pads[index]["pos"] if index >= 0 and index < _pads.size() else Vector2.INF


func pad_count() -> int:
	return _pads.size()


## 下一擊的傷害倍率。
func damage_scale() -> float:
	return 1.0 + per_stack * stacks


## 頭目要搶的地墊 x：亮著、而且和頭目在同一層地面附近；沒有就是 INF。
func rush_target_x(from: Vector2) -> float:
	if _lit < 0:
		return INF
	var pos: Vector2 = _pads[_lit]["pos"]
	return pos.x if absf(pos.y - from.y) < 24.0 else INF


## 玩家帶著標記往亮著的地墊走（或已經很近）：頭目的「搶地墊」習慣用。
func player_heading_to_lit_pad() -> bool:
	if _lit < 0 or not is_instance_valid(_player):
		return false
	var pos: Vector2 = _pads[_lit]["pos"]
	var dx := pos.x - _player.global_position.x
	if absf(dx) < 48.0:
		return true
	return absf(dx) < 180.0 and signf(_player.velocity.x) == signf(dx) and absf(_player.velocity.x) > 10.0


## 頭目衝到地墊上：踩掉（暗掉），玩家這次清不到。
func boss_arrived(at: Vector2) -> void:
	if _lit < 0:
		return
	var pos: Vector2 = _pads[_lit]["pos"]
	if absf(pos.x - at.x) <= PAD_REACH + 6.0 and absf(pos.y - at.y) < 24.0:
		_use_pad(_lit, false)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(_player):
		_bind_player()
	_since_hit += delta
	if stacks > 0 and _since_hit >= decay:
		_set_stacks(0)
	_tick_pads(delta)
	if stacks > 0 and _lit >= 0 and _player_on(_lit):
		_use_pad(_lit, true)
	queue_redraw()


func _tick_pads(delta: float) -> void:
	if _pads.is_empty():
		return
	if _lit >= 0:
		_pads[_lit]["timer"] = float(_pads[_lit].get("timer", 0.0)) - delta
		if float(_pads[_lit]["timer"]) <= 0.0:
			_pads[_lit]["lit"] = false
			_lit = -1
			_dark_left = dark_time
		return
	_dark_left -= delta
	if _dark_left <= 0.0:
		_light(_farthest_from_boss())


func _light(index: int) -> void:
	if index < 0:
		return
	_lit = index
	_pads[index]["lit"] = true
	_pads[index]["timer"] = lit_time
	Fx.flash_light(_pads[index]["pos"] + Vector2(0, -4), Palette.WHITE, 48.0, 0.8, 0.2)


## 下一塊亮的地墊：離頭目最遠的那塊（玩家要繞開他才清得到）。
func _farthest_from_boss() -> int:
	var best := -1
	var best_distance := -1.0
	for i in _pads.size():
		var pos: Vector2 = _pads[i]["pos"]
		if pos == Vector2.INF:
			continue
		var distance := absf(pos.x - _boss.global_position.x) if is_instance_valid(_boss) else float(i)
		if distance > best_distance:
			best_distance = distance
			best = i
	return best


func _use_pad(index: int, by_player: bool) -> void:
	_pads[index]["lit"] = false
	_lit = -1
	_dark_left = dark_time
	var pos: Vector2 = _pads[index]["pos"]
	if by_player:
		_set_stacks(0)
		Fx.burst(pos + Vector2(0, -6), Palette.WHITE, 12, 120.0, 0.3)
		Sfx.play(&"switch", -2.0)
	else:
		Fx.dust(pos, 8, 90.0)
		Sfx.play(&"block", -6.0)
	pad_used.emit(index, by_player)


func _player_on(index: int) -> bool:
	var pos: Vector2 = _pads[index]["pos"]
	return _player.is_on_floor() and absf(_player.global_position.x - pos.x) <= PAD_REACH and absf(_player.global_position.y - pos.y) < 8.0


func _bind_player() -> void:
	var target := get_tree().get_first_node_in_group(&"player") as Player
	if target == _player:
		return
	if is_instance_valid(_player) and _player.health.damaged.is_connected(_on_player_damaged):
		_player.health.damaged.disconnect(_on_player_damaged)
	_player = target
	if _player != null:
		_player.health.damaged.connect(_on_player_damaged)
		_apply_scale()


func _on_player_damaged(_info: DamageInfo) -> void:
	if not active:
		return
	_since_hit = 0.0
	if stacks == 0 and not _hinted:
		_hinted = true
		if not first_hint.is_empty():
			EventBus.toast_requested.emit(first_hint)
		if first_scene != &"":
			Story.play(first_scene)
	_set_stacks(mini(max_stacks, stacks + 1))


func _set_stacks(value: int) -> void:
	if value == stacks:
		return
	stacks = value
	_apply_scale()
	stacks_changed.emit(stacks)


func _apply_scale() -> void:
	if is_instance_valid(_player) and _player.hurtbox != null:
		_player.hurtbox.damage_scale = damage_scale() if active else 1.0


## 地墊站的地面：指定列就從那一列往下找（平台上的地墊），否則從頭目的高度往下找。
func _ground_at(pad: Dictionary) -> Vector2:
	var x := float(pad["tile"]) * 16.0 + 8.0
	var from_y := float(pad["row"]) * 16.0 - 8.0 if int(pad["row"]) >= 0 else (_boss.global_position.y - 24.0 if is_instance_valid(_boss) else 0.0)
	_floor_ray.from = Vector2(x, from_y)
	_floor_ray.to = Vector2(x, from_y + 320.0)
	_floor_ray.collision_mask = Layers.SOLID
	_floor_ray.hit_from_inside = false
	var hit := get_world_2d().direct_space_state.intersect_ray(_floor_ray)
	if hit.is_empty():
		# A cold near-boss entry can wake before new collision bodies are synced.
		# Use only its original map's bounded floor; never invent a missing surface.
		var ancestor: Node = _boss if is_instance_valid(_boss) else get_parent()
		while ancestor != null:
			if ancestor.has_method("authored_floor_below"):
				var surface: Variant = ancestor.call("authored_floor_below", _floor_ray.from, 320.0)
				if surface is Vector2 and surface.is_finite(): return surface
				break
			ancestor = ancestor.get_parent()
		push_error("[BossMark] 第 %s 欄的地墊下面找不到地面，改放在頭目的高度" % pad["tile"])
		return Vector2(x, _boss.global_position.y if is_instance_valid(_boss) else from_y)
	return hit["position"]


# ---------------------------------------------------------------------------
# 畫面
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not active:
		return
	for i in _pads.size():
		_draw_pad(_pads[i])
	if stacks > 0 and is_instance_valid(_player):
		_draw_pips(_player.global_position + Vector2(0, -HEAD_OFFSET))


## 地墊：亮著是白色光面，暗著是灰色；白框分成 max 段，亮起的段數＝目前層數（踩下去清掉幾層）。
func _draw_pad(pad: Dictionary) -> void:
	var pos: Vector2 = pad["pos"]
	if pos == Vector2.INF:
		return
	var lit := bool(pad["lit"])
	var left := pos.x - PAD_WIDTH * 0.5
	var fill := LightKit.glow(Palette.WHITE, 1.6) if lit else Color(0.32, 0.33, 0.36, 0.9)
	draw_rect(Rect2(Vector2(left, pos.y - 3.0), Vector2(PAD_WIDTH, 3.0)), Color(fill, 0.85 if lit else 0.6))
	var segment := PAD_WIDTH / float(max_stacks)
	for s in max_stacks:
		var on := lit and s < stacks
		var color := LightKit.glow(Palette.WHITE, 2.2) if on else Color(0.85, 0.85, 0.85, 0.35 if lit else 0.15)
		draw_line(Vector2(left + s * segment + 0.5, pos.y - 5.0), Vector2(left + (s + 1) * segment - 0.5, pos.y - 5.0), color, 1.0)
	if lit and _font != null and not pad_label.is_empty():
		var size := _font.get_string_size(pad_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		draw_string(_font, Vector2(pos.x - size.x * 0.5, pos.y - 8.0), pad_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(LightKit.glow(Palette.WHITE, 1.4), 0.9))


## 玩家頭上：max 格小方塊，疊幾層亮幾格（紅橙＝下一擊會更痛），旁邊寫標記名稱。
func _draw_pips(at: Vector2) -> void:
	var width := max_stacks * PIP + (max_stacks - 1) * PIP_GAP
	var left := at.x - width * 0.5
	var warn := LightKit.glow(Palette.DANGER, 1.8)
	for s in max_stacks:
		var rect := Rect2(Vector2(left + s * (PIP + PIP_GAP), at.y - PIP), Vector2(PIP, PIP))
		if s < stacks:
			draw_rect(rect, warn)
		else:
			draw_rect(rect, Color(0.8, 0.8, 0.8, 0.35), false, 1.0)
	if _font != null:
		var text := "%s ×%d" % [label, stacks]
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		draw_string(_font, Vector2(at.x - size.x * 0.5, at.y - PIP - 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(warn, 0.95))
