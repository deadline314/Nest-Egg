class_name HudPlacement
extends RefCounted
## 跟著主角的 HUD（彈帶、生命護盾標籤）共用的擺位規則（NE-264）。
## 平常放在主角背後；靠邊放不下時，共用依實際頭部、視窗和槍口預留的安全通道。
## 轉向時兩列可沿射線的上、下側分層繞行，避免直接穿過頭臉或瞄準方向；不強制兩者永遠一起在頭頂。
## 切換用連續的權重，由呼叫端平滑過渡，不在一格內跳位置。

## 離畫面左右邊緣至少留的距離（畫面像素）。
const EDGE_MARGIN := 4.0
## 背後至少要有這麼寬（畫面像素，從主角中心往外量）才放得下最寬的元件（間距＋十顆子彈＋備彈數字）。
const ROOM_NEEDED := 108.0
## 頭頂上方的間距（畫面像素）與兩列之間的間距。
const ABOVE_GAP := 5.0
const ROW_GAP := 3.0
## 頭頂相對於腳底的位置（世界座標）；與 VitalsTag.HEAD_OFFSET 相同。
const HEAD_OFFSET := Vector2(0, -56)
## 安全通道與背側之間的切換速度（每秒權重變化）。
## Each full above weight or side traversal takes 300ms. A reversal includes
## its approach, side traversal and return; captures retain the full stable tail.
const BLEND_SPEED := 1.0 / 0.3
const SIDE_SPEED := 2.0 / 0.3


## 背後（side：-1 左、+1 右）從主角中心 player_x 往外還有多少畫面像素。
static func room_behind(player_x: float, side: float, view_width: float) -> float:
	if side < 0.0:
		return player_x - EDGE_MARGIN
	return view_width - EDGE_MARGIN - player_x


## 目標權重：背後放得下是 0（放背後），放不下是 1（放頭上）。
## 彈帶與標籤都只用主角中心的畫面 x 與面向判斷，輸入相同、結果相同，不會一個在背後一個在頭上。
static func above_target(player_x: float, side: float, view_width: float) -> float:
	return 0.0 if room_behind(player_x, side, view_width) >= ROOM_NEEDED else 1.0


## 讓 [left, left + width] 留在畫面裡，回傳需要的水平位移。
static func clamp_shift(left: float, width: float, view_width: float) -> float:
	if width >= view_width - EDGE_MARGIN * 2.0:
		return EDGE_MARGIN - left
	if left < EDGE_MARGIN:
		return EDGE_MARGIN - left
	if left + width > view_width - EDGE_MARGIN:
		return view_width - EDGE_MARGIN - (left + width)
	return 0.0


## Only the two following HUDs use this L: rise behind the head, then centre.
## Reversing the same progress moves sideways above the head before descending.
static func routed_target(beside: Vector2, over: Vector2, above: float) -> Vector2:
	return Vector2(lerpf(beside.x, over.x, smoothstep(0.5, 1.0, above)),
		lerpf(beside.y, over.y, smoothstep(0.0, 0.5, above)))


## Keep the existing vertical follow while safely beside the head. Horizontal
## travel on the upper leg must stay at its ceiling; a 2D lerp cuts that corner.
static func follow_route(previous: Vector2, target: Vector2, above: float, delta: float, sharpness: float, safe_ceiling := INF) -> Vector2:
	var y := lerpf(previous.y, target.y, 1.0 - exp(-sharpness * delta))
	var ceiling := target.y if is_inf(safe_ceiling) else safe_ceiling
	return Vector2(target.x, minf(y, ceiling) if above >= 0.5 else y)


## Fit one complete beside envelope between the real head and viewport.
## Only AmmoTray/VitalsTag call this; an impossible side keeps their upper route.
static func beside_position(origin: Vector2, bounds: Rect2, head: Rect2, side: float, view_width: float) -> Vector2:
	var low := origin.x + EDGE_MARGIN - bounds.position.x
	var high := origin.x + view_width - EDGE_MARGIN - bounds.end.x
	if side < 0.0:
		high = minf(high, origin.x + head.position.x - ROW_GAP - bounds.end.x)
	else:
		low = maxf(low, origin.x + head.end.x + ROW_GAP - bounds.position.x)
	if low > high:
		return Vector2(INF, origin.y)
	return Vector2(clampf(origin.x, low, high), origin.y)


## Each HUD owns one cache. The existing rig API resolves registered parts;
## no find_children, image readback or per-frame temporary array is needed.
class FollowState:
	var _rig: CharacterRig
	var _head: Sprite2D
	var _skin := ""
	var _player_id := 0
	var _world := Vector2.ZERO
	var _anchor := Vector2.ZERO
	var guide_y := 0.0
	var guide_x := 0.0
	var lower_y := 0.0
	var lower_mode := false
	var _center_offset := 0.0
	var _vertical_aim := false
	var _vertical_side := 0.0
	var foot_y := 0.0
	var guide_ready := false
	var _has_guide := false

	## The existing reserve line (including shadow) is expendable headroom.
	## Both widgets use this same ammo-baseline coordinate; the tag subtracts
	## its fixed row band. No frame-distance cap or extra user setting.
	func update_guide(head: Rect2, foot: Vector2, delta: float, descent: float, text_line: float, minimum_y: float, foot_sharpness: float, view_width := 0.0, muzzle := Vector2(INF, INF)) -> void:
		var safe_ceiling := head.position.y - (9.0 + descent + 1.0)
		var target := minf(safe_ceiling, maxf(minimum_y, head.position.y - HudPlacement.ABOVE_GAP - descent - text_line))
		var lower_floor := maxf(head.end.y, muzzle.y if is_finite(muzzle.y) else head.end.y) + minimum_y - HudPlacement.EDGE_MARGIN + HudPlacement.ROW_GAP
		var lower_target := lower_floor + text_line
		var radius := HudPlacement.ROOM_NEEDED * 0.5
		var preferred := foot.x
		if view_width > radius * 2.0 + HudPlacement.EDGE_MARGIN * 2.0:
			preferred = head.end.x + HudPlacement.ROW_GAP + radius if foot.x < view_width * 0.5 else head.position.x - HudPlacement.ROW_GAP - radius
			preferred = clampf(preferred, HudPlacement.EDGE_MARGIN + radius, view_width - HudPlacement.EDGE_MARGIN - radius)
		if not _has_guide:
			guide_y = target
			guide_x = preferred
			_center_offset = preferred - foot.x
			lower_y = lower_target
			foot_y = foot.y
			guide_ready = true
			_has_guide = true
			return
		var previous := guide_y
		guide_y = HudPlacement.follow_route(Vector2(0, guide_y), Vector2(0, target), 1.0, delta, 18.0, safe_ceiling).y
		foot_y = lerpf(foot_y, foot.y, 1.0 - exp(-foot_sharpness * delta))
		# A row can cross only after real vertical clearance exists and its
		# guide is moving slower than the reserved corridor per blend time.
		var row_speed := HudPlacement.ROOM_NEEDED * HudPlacement.BLEND_SPEED
		guide_ready = guide_y <= safe_ceiling - HudPlacement.ROW_GAP and absf(guide_y - previous) <= row_speed * delta
		lower_y = maxf(lerpf(lower_y, lower_target, 1.0 - exp(-18.0 * delta)), lower_floor)
		if guide_ready:
			_center_offset = lerpf(_center_offset, preferred - foot.x, 1.0 - exp(-HudPlacement.BLEND_SPEED * delta))
		guide_x = foot.x + _center_offset


	## Both callers choose the same available side for raised aim. The choice
	## persists until that aim ends, so walking cannot suddenly cross the ray.
	func aim_side(player: Player, head: Rect2, muzzle: Vector2, view_width: float) -> float:
		var aim := player.aim_dir
		if aim.y < 0.0 and absf(aim.y) >= absf(aim.x):
			if not _vertical_aim:
				var left_room := minf(head.position.x, muzzle.x) - HudPlacement.EDGE_MARGIN
				var right_room := view_width - HudPlacement.EDGE_MARGIN - maxf(head.end.x, muzzle.x)
				var behind := -float(player.facing)
				_vertical_side = behind if (left_room if behind < 0.0 else right_room) >= HudPlacement.ROOM_NEEDED else -behind
			_vertical_aim = true
			return _vertical_side
		_vertical_aim = false
		return 0.0


	## A front-to-back reversal cannot lift through a horizontal firing line.
	## Each row uses the same L on its own side of the firing line: the upper
	## shield rises, while lower ammunition descends. They share the same phase.
	func choose_corridor(above: float, side: float, wanted_side: float, aim: Vector2, row_y: float, muzzle_y: float) -> void:
		if not is_equal_approx(side, wanted_side):
			if above < 0.01 and absf(aim.x) > absf(aim.y) and signf(side) == signf(aim.x):
				lower_mode = row_y > muzzle_y
		elif above < 0.01:
			lower_mode = false


	func corridor_y() -> float:
		return lower_y if lower_mode else guide_y



	## Relocation is measured from the actor/anchor, never from a route corner.
	func should_reset(player: Player, canvas: Transform2D, anchor: Vector2, distance: float) -> bool:
		if not is_instance_valid(player):
			_player_id = 0
			return true
		var reset := _player_id != player.get_instance_id() \
			or canvas.basis_xform(player.global_position - _world).length() > distance \
			or anchor.distance_to(_anchor) > distance
		if reset:
			_has_guide = false
			lower_mode = false
			_vertical_aim = false
		_player_id = player.get_instance_id()
		_world = player.global_position
		_anchor = anchor
		return reset

	func screen_rect(player: Player, canvas: Transform2D) -> Rect2:
		if not is_instance_valid(player):
			_rig = null
			_head = null
			return Rect2()
		var fallback := canvas * Rect2(player.global_position + HudPlacement.HEAD_OFFSET - Vector2(10, 10), Vector2(20, 20))
		if not player.is_inside_tree() or player.is_dead():
			_rig = null
			_head = null
			return fallback
		var visual := player._visual
		if not is_instance_valid(visual) or not is_instance_valid(visual.rig) or not visual.rig.is_inside_tree():
			_rig = null
			_head = null
			return fallback
		var rig := visual.rig
		if rig != _rig or rig.skin_id != _skin or not is_instance_valid(_head) or not _head.is_inside_tree() or not rig.is_ancestor_of(_head) or not _head.is_visible_in_tree() or _head.texture == null:
			_rig = rig
			_skin = rig.skin_id
			_head = rig.contact_part(&"head")
		if not is_instance_valid(_head) or _head.texture == null or not _head.is_inside_tree() or not rig.is_ancestor_of(_head) or not _head.is_visible_in_tree():
			return fallback
		# The complete texture rect includes transparent edges, so this is a
		# conservative drawable bound, not a claimed exact opaque alpha mask.
		return (canvas * _head.global_transform * _head.get_rect()).grow(1.0)
