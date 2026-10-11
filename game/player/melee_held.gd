class_name MeleeHeld
extends Node2D
## 手上的近戰武器（NE-275）：握在拳頭裡、有自己的重量。
##
## 握：握把對在掌心（骨架的握點），這個節點排在前手的後面、手臂的前面，所以握拳的手指會蓋在握把上。
## 拿：不出招時每把武器有自己的拿法（朝哪裡、跟著手臂晃多少），不是筆直沿著前臂垂下來；
##     尖端與握把尾端都不會低於腳下的地面，太低就把武器抬起來，鞭子的細線只畫到地面為止。
## 揮：出招時武器的方向以前臂為準，但不是和前臂綁死——武器的角度用一個有阻尼的彈簧去追目標：
##     手臂突然加速時刀尖落在後面（拖曳），手臂停下時多甩過去一點再回來（跟隨）。重的武器彈簧軟、拖得多。
## 每把武器的數字在 data/weapon_art/melee.json 的 hold（見 MeleeArt.hold_spec）；沒寫的武器用下面的預設。
##
## 只管看得到的樣子：招式打得到的距離、判定與時間照招式資料，和這裡無關。

## 預設拿法（朝右時的角度，弧度；0 是水平朝前、正的是往下）。second 是另一隻手握在離握把多遠的地方（世界像素，0＝單手）。
const DEFAULT := {"carry": 0.5, "couple": 0.3, "freq": 8.0, "damp": 0.6, "lag": 0.5, "swing": 0.0, "second": 0.0}
## 尖端離地面至少留這麼多（世界像素）。
const FLOOR_MARGIN := 1.5
## 彈簧每一小步最多走多少相位（弧度）。
const SPRING_STEP := 0.25
## 進出招式時「拿法」與「跟著前臂」之間的過渡速度（每秒）。
const BLEND_SPEED := 14.0
## 武器本體的明暗：最暗的環境剩幾成亮度、環境光每 1.0 增加多少。
const SHADE_FLOOR := 0.42
const SHADE_GAIN := 1.5

var _visual: PlayerVisual
var _weapon: WeaponData
var _spec: Dictionary = DEFAULT
var _tip := 0.0
var _butt := 0.0
## 武器最粗的地方的一半（錘頭很厚：中心線在地面以上不夠，整個錘頭都要在地面以上）。
var _half_width := 0.0
## 朝右空間裡武器現在的角度與角速度。
var _angle := 0.0
var _speed := 0.0
var _swing_blend := 0.0
var _facing := 0
var _settled := false
var _origin := Vector2.ZERO
var _direction := Vector2.RIGHT
var _reach := -1.0
var _shown := false


func setup(visual: PlayerVisual) -> void:
	_visual = visual
	LightKit.mark_emissive(self)


## 每個物理影格在骨架動完之後呼叫：更新握點、武器的角度與要不要畫。
func update(delta: float) -> void:
	_shown = _visual.shows_melee_weapon()
	visible = _shown
	if not _shown:
		_settled = false
		return
	var player := _visual.player
	var rig := _visual.rig
	var weapon := player.loadout.active_weapon()
	if weapon != _weapon:
		_adopt(weapon)
	var hand := rig.bone(&"hand_front")
	var forearm := rig.bone(&"arm_front_lower")
	_origin = hand.global_transform * rig.hand_grip_offset(&"hand_front")
	var facing := 1 if player.facing >= 0 else -1
	var along := hand.global_position - forearm.global_position
	# 一律換到「朝右」的空間裡算角度，朝左時左右對調。
	var arm_angle := Vector2(along.x * facing, along.y).angle()
	var in_move := not player.melee_pose().is_empty()
	_swing_blend = move_toward(_swing_blend, 1.0 if in_move else 0.0, delta * BLEND_SPEED)
	var carry := float(_spec["carry"]) + float(_spec["couple"]) * angle_difference(PI * 0.5, arm_angle)
	var target := lerp_angle(carry, arm_angle + float(_spec["swing"]), smoothstep(0.0, 1.0, _swing_blend))
	if not _settled or facing != _facing:
		# 剛拿出來、或轉身：直接到位，不要掃過半圈。
		_angle = target
		_speed = 0.0
		_settled = true
		_facing = facing
	else:
		_follow(target, delta)
	_reach = -1.0
	if _swing_blend < 1.0:
		_keep_above_floor(player.global_position.y - FLOOR_MARGIN)
	_direction = Vector2(cos(_angle) * facing, sin(_angle))
	queue_redraw()


## 雙手武器另一隻手要握的地方（世界座標）；單手武器或現在沒有在畫時回傳 false。
func has_second_grip() -> bool:
	return _shown and _settled and float(_spec["second"]) > 0.0


func second_grip() -> Vector2:
	return _origin + _direction * float(_spec["second"])


## 握把的位置與刃尖的方向（世界座標）：origin 是掌心，x 軸指向刃尖。
func hold() -> Transform2D:
	return Transform2D(_direction, _direction.orthogonal(), _origin)


## 武器現在比「該在的方向」落後多少（弧度，朝右空間；量測與測試用）。
func lag_from(target_angle: float) -> float:
	return angle_difference(target_angle, _angle)


func angle() -> float:
	return _angle


func _adopt(weapon: WeaponData) -> void:
	_weapon = weapon
	_spec = DEFAULT.duplicate()
	_spec.merge(MeleeArt.hold_spec(weapon), true)
	var entry := MeleeArt.art(weapon)
	if entry.is_empty():
		_tip = weapon.melee_length
		_butt = 5.0
		_half_width = 1.5
	else:
		_tip = float((entry["size"] as Vector2).x) - float((entry["grip"] as Vector2).x)
		_butt = float((entry["grip"] as Vector2).x)
		_half_width = float((entry["size"] as Vector2).y) * 0.5
	_settled = false


## 有阻尼的彈簧：角度追目標；落後超過上限就拉住（不讓刀甩到身體後面去）。
func _follow(target: float, delta: float) -> void:
	var omega := TAU * float(_spec["freq"])
	# 彈簧硬（匕首 14 Hz）時一個物理影格一步會算到發散、每一格左右跳：切成小步，每步不超過 0.25 弧度的相位。
	var steps := maxi(1, ceili(omega * delta / SPRING_STEP))
	var step := delta / float(steps)
	for i in steps:
		var error := angle_difference(_angle, target)
		_speed += (omega * omega * error - 2.0 * float(_spec["damp"]) * omega * _speed) * step
		_angle = wrapf(_angle + _speed * step, -PI, PI)
	var limit := float(_spec["lag"])
	var behind := angle_difference(target, _angle)
	if absf(behind) > limit:
		_angle = wrapf(target + signf(behind) * limit, -PI, PI)
		_speed = 0.0


## 不出招時武器的兩端都要在地面以上：太低就往水平的方向抬；鞭子的細線另外只畫到地面。
func _keep_above_floor(floor_y: float) -> void:
	var room := floor_y - _origin.y - _half_width
	if room <= 0.0:
		return
	var rise := sin(_angle)
	if _tip > 0.0 and rise * _tip > room:
		var limit := asin(clampf(room / _tip, -1.0, 1.0))
		_angle = limit if cos(_angle) >= 0.0 else PI - limit
		_speed = minf(_speed, 0.0) if cos(_angle) >= 0.0 else maxf(_speed, 0.0)
	elif _butt > 0.0 and -rise * _butt > room:
		var limit := -asin(clampf(room / _butt, -1.0, 1.0))
		_angle = limit if cos(_angle) >= 0.0 else -PI - limit
		_speed = 0.0
	if _weapon != null and _weapon.melee_shape == "whip" and sin(_angle) > 0.05:
		_reach = clampf((floor_y - _origin.y - 1.0) / sin(_angle), _tip, _weapon.melee_length)


func _draw() -> void:
	if not _shown or _weapon == null:
		return
	var player := _visual.player
	var glow := PlayerVisual.MELEE_GLOW_SWING if player.is_melee_swinging() else PlayerVisual.MELEE_GLOW
	# 武器不受場景光影響：本體的明暗跟著環境光走，暗的區域裡只有發光的刃口是亮的。
	var shade := clampf(SHADE_FLOOR + LightKit.ambient_luma * SHADE_GAIN, SHADE_FLOOR, 1.0)
	var inverse := global_transform.affine_inverse()
	MeleeArt.draw(self, inverse * _origin, inverse.basis_xform(_direction).normalized(), _weapon, glow, shade, _reach)
