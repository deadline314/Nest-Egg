class_name LevelCamera
extends Camera2D
## 平台射擊遊戲鏡頭（依業界常見做法）：
##   - 前瞻：鏡頭偏向角色面向，讓玩家看得到前方敵人
##   - 垂直死區：空中小跳躍不晃鏡頭，落地或離開死區才跟隨
##   - trauma 震動：強度平方衰減 + 噪聲，比純隨機震動自然
##   - 射擊後座：方向性位移，快速回彈

## 構圖數值（倍率、前瞻、瞄準偏移、垂直偏移、死區、下落預視）在 data/feel/camera.json（CameraTuning），改數字不用改程式。
## 倍率越大視野越小，前瞻與瞄準偏移要一起調，讓面向的前方仍看得到 300 世界像素以上（敵人多半在 240～300 開始攻擊）。
const MAX_SHAKE_PX := 12.0
const SHAKE_ROTATION_PER_PX := 0.0014
const MAX_SHAKES := 8
## 震動來源超過這段距離（像素）後開始衰減，最遠剩 25%。
const SHAKE_FALLOFF_START := 240.0
const SHAKE_FALLOFF_RANGE := 640.0
const DIRECTIONAL_FREQUENCY := 16.0
const KICK_RECOVERY := 16.0
const MAX_KICK := 8.0
## 前瞻翻轉至少保有的橫移速度（世界像素／秒）：主角跑得再快，鏡頭也會慢慢轉到前方。
const MIN_OFFSET_SPEED := 40.0
## 背後威脅與高處的敵人每隔幾秒重新找一次（不每影格走訪敵人）。
const REAR_SCAN_INTERVAL := 0.15
## 邊緣往下看：站著不動的速度門檻、往面向探多遠算「在邊緣」、落差至少多深、落點下方多留的邊距（世界像素）。
const LEDGE_STILL_SPEED := 8.0
const LEDGE_REACH := 14.0
const LEDGE_MIN_DROP := 24.0
const LEDGE_MARGIN := 12.0
## 背後的敵人和主角高度差超過這個值就不算（在別層樓）。
const REAR_SCAN_HEIGHT := 160.0

## 目前用的構圖數值；換一組（例如依情境）直接指定即可，下一個物理影格生效。
var tuning: CameraTuning = CameraTuning.profile()
var _shake_reader := Callable()
var _zoom_reader := Callable()
var target: Node2D

## 進行中的震動：[峰值像素, 總秒數, 剩餘秒數, 方向]。
var _shakes: Array[Array] = []
## 縮放脈衝：[幅度, 總秒數, 剩餘秒數]。
var _pulse: Array = []
var _aim_look := Vector2.ZERO
var _kick := Vector2.ZERO
var _look := 0.0
var _fall_look := 0.0
var _anchor_y := 0.0
## 背後交戰中的敵人要留在畫面裡所需的距離（世界像素，0＝背後沒有威脅）。
var _rear_room := 0.0
## 畫面裡有敵人站在較高處時鏡頭要上抬的量（世界像素）：目標與目前值。
var _lift_goal := 0.0
var _lift := 0.0
## 站在落差邊緣時往下看的量（_peek 平滑追 _peek_goal）與已經站定多久。
var _peek_goal := 0.0
var _peek := 0.0
var _still_time := 0.0
var _ledge_ray := PhysicsRayQueryParameters2D.new()
var _rear_scan_left := 0.0
var _noise := FastNoiseLite.new()
var _noise_time := 0.0
var _presentation_owner: WeakRef
var _presentation_point := Vector2.ZERO
var _presentation_mode: ProcessMode


func _ready() -> void:
	zoom = Vector2.ONE * tuning.zoom
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	position_smoothing_speed = tuning.smoothing_speed
	limit_smoothed = true
	ignore_rotation = false
	_noise.frequency = 0.15
	EventBus.screen_shake.connect(_on_screen_shake)
	EventBus.camera_kick.connect(_on_camera_kick)
	EventBus.camera_zoom_pulse.connect(_on_zoom_pulse)
	_ledge_ray.collision_mask = Layers.SOLID
	_shake_reader = func() -> float: return snappedf(offset.length(), 0.1)
	_zoom_reader = func() -> float: return snappedf(zoom.x, 0.001)
	Feel.register_counter("camera_shake_px", _shake_reader)
	Feel.register_counter("camera_zoom", _zoom_reader)
	make_current()


func _exit_tree() -> void:
	# 診斷面板還會讀這兩個計數，鏡頭離開後不能留下指向自己的讀取函式。
	Feel.unregister_counter("camera_shake_px", _shake_reader)
	Feel.unregister_counter("camera_zoom", _zoom_reader)


func set_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


## 鎖住左界（頭目戰），鏡頭平滑推進。
func lock_left(x: float) -> void:
	limit_left = int(x)


## 立即跳到目標位置（重生時避免鏡頭從遠處滑過來）。
func snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	_anchor_y = target.global_position.y
	_scan_threats()
	_lift = _lift_goal
	_peek_goal = 0.0
	_peek = 0.0
	_still_time = 0.0
	_rear_scan_left = REAR_SCAN_INTERVAL
	_look = _facing() * _look_goal()
	_fall_look = 0.0
	global_position = _desired_position()
	reset_smoothing()
	# A resumed conversation may pause before the next physics camera callback.
	# Publish the snapped view now so its background is already the current area.
	force_update_scroll()


func _physics_process(delta: float) -> void:
	if _presentation_owner != null:
		var owner: Object = _presentation_owner.get_ref()
		if is_instance_valid(owner):
			global_position = global_position.lerp(_presentation_point, 1.0 - exp(-6.0 * maxf(0.0, delta)))
			force_update_scroll()
			return
		_release_presentation_focus()
	if is_instance_valid(target):
		# 站定才算時間；一動就收回往下看的量（邊跑邊過平台邊緣時鏡頭不會上下晃）。
		if _is_grounded() and absf(_target_velocity_x()) < LEDGE_STILL_SPEED:
			_still_time += delta
		else:
			_still_time = 0.0
			_peek_goal = 0.0
		_rear_scan_left -= delta
		if _rear_scan_left <= 0.0:
			_rear_scan_left = REAR_SCAN_INTERVAL
			_scan_threats()
			_scan_ledge()
		_lift = lerpf(_lift, _lift_goal, minf(1.0, tuning.fall_look_speed * delta))
		_peek = lerpf(_peek, _peek_goal, minf(1.0, tuning.fall_look_speed * delta))
		var y := target.global_position.y
		if _is_grounded():
			_anchor_y = y
		elif y > _anchor_y + tuning.deadzone_down:
			_anchor_y = y - tuning.deadzone_down
		elif y < _anchor_y - tuning.deadzone_up:
			_anchor_y = y + tuning.deadzone_up
		# 轉向時前瞻與瞄準偏移翻到另一邊；鏡頭跟隨目標的總橫移速度（主角移動＋偏移變化）有上限，
		# 主角邊跑邊轉身時偏移讓出跑速那部分，站著轉身仍然很快，拉近後不會一下子甩過去。
		var old_look := _look
		var old_aim_x := _aim_look.x
		var next_look := lerpf(_look, _facing() * _look_goal(), minf(1.0, tuning.look_ahead_speed * delta))
		_update_aim_look(delta)
		var change := (next_look - old_look) + (_aim_look.x - old_aim_x)
		var budget := maxf(MIN_OFFSET_SPEED, tuning.pan_max_speed - absf(_target_velocity_x())) * delta
		if absf(change) > budget:
			var k := budget / absf(change)
			next_look = old_look + (next_look - old_look) * k
			_aim_look.x = old_aim_x + (_aim_look.x - old_aim_x) * k
		_look = next_look
		_update_fall_look(delta)
		global_position = _desired_position()
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, KICK_RECOVERY * delta))
	_noise_time += delta * 60.0
	var shake_offset := _shake_offset(delta)
	# 震動與後座以 shake_reference_zoom 調過；換算成目前倍率，畫面上的晃動幅度不因拉近而變大。
	var screen_scale := tuning.shake_reference_zoom / tuning.zoom
	offset = (_kick + shake_offset) * screen_scale
	rotation = SHAKE_ROTATION_PER_PX * shake_offset.length() * _noise.get_noise_2d(_noise_time, 100.0) * 2.0
	position_smoothing_speed = tuning.smoothing_speed
	zoom = Vector2.ONE * tuning.zoom * (1.0 + _pulse_amount(delta))


## A temporary presentation owns only camera framing; gameplay, zoom and tuning
## stay with their existing owners. Another caller cannot release this scope.
func acquire_presentation_focus(owner: Object, point: Vector2) -> bool:
	if not is_instance_valid(owner) or not point.is_finite() or (_presentation_owner != null and is_instance_valid(_presentation_owner.get_ref())):
		return false
	_presentation_owner = weakref(owner)
	_presentation_point = point
	_presentation_mode = process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	return true


func release_presentation_focus(owner: Object) -> void:
	if _presentation_owner != null and _presentation_owner.get_ref() == owner:
		_release_presentation_focus()


func _release_presentation_focus() -> void:
	_presentation_owner = null
	process_mode = _presentation_mode


func _desired_position() -> Vector2:
	# 往下看的三個來源（瞄準下方、站在邊緣、下落）加起來有上限；往上瞄不受影響。
	var down := minf(maxf(_aim_look.y, 0.0) + _peek + _fall_look, tuning.down_look_max)
	return Vector2(target.global_position.x + _look + _aim_look.x, _anchor_y + tuning.vertical_offset + down + minf(_aim_look.y, 0.0) - _lift)


## 腳底下方目前看得到多少（世界像素，鏡頭停穩、沒有往下看時）。
func below_visible() -> float:
	return get_viewport_rect().size.y * 0.5 / tuning.zoom + tuning.vertical_offset


## 站在落差邊緣、面向落差停住一下：往下看到落點（NE-256）。腳前就是地面、底下沒有地面（掉出地圖的坑）都不看。
func _scan_ledge() -> void:
	_peek_goal = 0.0
	if tuning.ledge_peek_max <= 0.0 or _still_time < tuning.ledge_peek_delay or not is_instance_valid(target) or not is_inside_tree():
		return
	var seen_below := below_visible()
	_ledge_ray.from = target.global_position + Vector2(_facing() * LEDGE_REACH, -4.0)
	_ledge_ray.to = _ledge_ray.from + Vector2(0.0, seen_below + tuning.ledge_peek_max + LEDGE_MARGIN + 4.0)
	var hit := get_world_2d().direct_space_state.intersect_ray(_ledge_ray)
	if hit.is_empty():
		return
	var drop: float = (hit["position"] as Vector2).y - target.global_position.y
	if drop < LEDGE_MIN_DROP:
		return
	_peek_goal = clampf(drop + LEDGE_MARGIN - seen_below, 0.0, tuning.ledge_peek_max)


## 關卡鏡頭的基礎倍率（工具與探針用，和遊戲中的鏡頭一致）。
static func base_zoom() -> float:
	return CameraTuning.profile().zoom


## 前瞻的目標距離：平常是 look_ahead；背後有交戰中的敵人時縮小，讓牠和一點邊距留在畫面裡。
func _look_goal() -> float:
	if _rear_room <= 0.0:
		return tuning.look_ahead
	var half_width := get_viewport_rect().size.x * 0.5 / tuning.zoom
	var aim_forward := maxf(0.0, _aim_look.x * _facing())
	return clampf(half_width - _rear_room - aim_forward, 0.0, tuning.look_ahead)


## 一次走訪敵人，更新兩種構圖需求：
##   _rear_room——背後 rear_watch_range 內、同一層、正在交戰的敵人要留在畫面裡所需看到的距離；
##   _lift_goal——畫面左右範圍內、站在較高處（above_watch_range 以內）的敵人，頭頂要留在畫面裡所需的上抬量（上限 above_max_lift）。
func _scan_threats() -> void:
	_rear_room = 0.0
	_lift_goal = 0.0
	if not is_instance_valid(target) or not is_inside_tree():
		return
	var facing := _facing()
	var origin := target.global_position
	var view := get_viewport_rect().size * 0.5 / tuning.zoom
	# 鏡頭停穩時腳底上方看得到的高度。
	var above_visible := view.y - tuning.vertical_offset
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dying():
			continue
		var delta := enemy.global_position - origin
		if tuning.rear_watch_range > 0.0 and enemy.is_engaged():
			var behind := -delta.x * facing
			if behind > 0.0 and behind <= tuning.rear_watch_range and absf(delta.y) <= REAR_SCAN_HEIGHT:
				_rear_room = maxf(_rear_room, behind + tuning.rear_margin)
		var rise := -delta.y
		if tuning.above_max_lift > 0.0 and rise > 0.0 and rise <= tuning.above_watch_range and absf(delta.x) <= view.x + tuning.look_ahead:
			var height := enemy.data.body_size.y if enemy.data != null else 0.0
			_lift_goal = maxf(_lift_goal, rise + height + tuning.above_margin - above_visible)
	_lift_goal = clampf(_lift_goal, 0.0, tuning.above_max_lift)


func _target_velocity_x() -> float:
	var body := target as CharacterBody2D
	return body.velocity.x if body != null else 0.0


func _facing() -> float:
	var player := target as Player
	return float(player.facing) if player != null else 1.0


func _is_grounded() -> bool:
	var player := target as Player
	if player != null and is_instance_valid(player.mounted_vehicle):
		return player.mounted_vehicle.is_on_floor()
	var body := target as CharacterBody2D
	return body.is_on_floor() if body != null else true


## 把進行中的震動加總成鏡頭位移：每個震動從峰值像素隨剩餘時間平方衰減，持續秒數真的生效；
## 有方向的震動沿方向來回衰減（加一點雜訊），沒有方向的用雜訊；總量有上限。
func _shake_offset(delta: float) -> Vector2:
	var total := Vector2.ZERO
	var noise := Vector2(_noise.get_noise_2d(_noise_time, 0.0), _noise.get_noise_2d(0.0, _noise_time)) * 2.0
	for i in range(_shakes.size() - 1, -1, -1):
		var entry := _shakes[i]
		entry[2] = float(entry[2]) - delta
		if float(entry[2]) <= 0.0:
			_shakes.remove_at(i)
			continue
		var k := float(entry[2]) / float(entry[1])
		var amplitude := float(entry[0]) * k * k
		var direction: Vector2 = entry[3]
		if direction == Vector2.ZERO:
			total += noise * amplitude
		else:
			total += direction * sin(float(entry[2]) * TAU * DIRECTIONAL_FREQUENCY) * amplitude + noise * amplitude * 0.25
	return total.limit_length(MAX_SHAKE_PX)


func _shake_magnitude(delta: float) -> float:
	return _shake_offset(delta).length()


func _on_screen_shake(px: float, duration: float, direction: Vector2, origin: Vector2) -> void:
	if origin != Vector2.INF:
		var falloff := clampf(1.0 - (origin.distance_to(global_position) - SHAKE_FALLOFF_START) / SHAKE_FALLOFF_RANGE, 0.25, 1.0)
		px *= falloff
	if _shakes.size() >= MAX_SHAKES:
		_shakes.remove_at(0)
	_shakes.append([px, duration, duration, direction.normalized()])


func _on_zoom_pulse(amount: float, duration: float) -> void:
	if duration > 0.0:
		_pulse = [amount, duration, duration]


## 縮放脈衝：先拉近再回復（正弦一個半週期）。
func _pulse_amount(delta: float) -> float:
	if _pulse.is_empty():
		return 0.0
	_pulse[2] = float(_pulse[2]) - delta
	if float(_pulse[2]) <= 0.0:
		_pulse = []
		return 0.0
	return float(_pulse[0]) * sin(PI * (1.0 - float(_pulse[2]) / float(_pulse[1])))


## 鏡頭往準星方向偏移一點；暫時不能瞄準（講電話、死亡）時固定不動。
func _update_aim_look(delta: float) -> void:
	var player := target as Player
	var goal := Vector2.ZERO
	if player != null and not player.is_dead() and not player.is_on_phone():
		# 往上瞄維持一半的偏移；往下瞄用 aim_look_down，才看得到落差底下。
		var vertical := player.aim_dir.y * tuning.aim_look_down if player.aim_dir.y > 0.0 else player.aim_dir.y * 0.5 * tuning.aim_look
		goal = Vector2(player.aim_dir.x * tuning.aim_look, vertical)
		_aim_look = _aim_look.lerp(goal, minf(1.0, tuning.aim_look_speed * delta))


## 下落時鏡頭往下看（視野拉近後腳下的空間變少）；落地或上升時平滑回到原位。
func _update_fall_look(delta: float) -> void:
	var body := target as CharacterBody2D
	var fall_speed := body.velocity.y if body != null and not _is_grounded() else 0.0
	var goal := clampf((fall_speed - tuning.fall_look_from) * tuning.fall_look_gain, 0.0, tuning.fall_look_max)
	_fall_look = lerpf(_fall_look, goal, minf(1.0, tuning.fall_look_speed * delta))


func _on_camera_kick(kick_offset: Vector2) -> void:
	_kick = (_kick + kick_offset).limit_length(MAX_KICK)
