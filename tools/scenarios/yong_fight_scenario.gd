class_name YongFightScenario
extends ScenarioBase
## 阿勇實戰模擬（NE-265）：正式第二章二樓帳房，用真正的輸入動作（左右、跳、衝刺、射擊、互動）由規則型機器人打完一整場，
## 記錄各難度的完成時間、受到的傷害、換算的死亡次數、清掉幾次利息，並可定時截圖（Forward+ 連續畫面）。
## 機器人的打法就是設計文件寫的應對：保持中距離射擊；看到舉棍就往後退（太近就衝刺穿過）；紙頁來了就跳；
## 身上兩層以上利息就去踩亮著的地墊；25% 暫停後依路線操作隔離箱（斷連）或繼續打（保留）；
## 制伏時先打橙色的棍柄鎖扣，進度打完後等短拳撲空，繞到背後按住互動拔出儲能匣。
## 這不是實體手把或真人驗收；用法：
##   godot --headless --fixed-fps 60 res://tools/screenshot.tscn -- --out=<資料夾> --scenario=yong_fight --difficulty=1 [--route=keep] [--pad] [--capture=2]

const LEVEL := "res://data/levels/ch2_ledger_office.tres"
const TIME_LIMIT := 420.0
const KEEP_DISTANCE := 110.0
const BACK_OFF := 70.0

var _yong: PatternBoss
var _difficulty := 1
var _route := "cut"
var _use_pad := false
var _capture_every := 0.0
var _next_capture := 0.0
var _elapsed := 0.0
var _damage_taken := 0
var _hits_taken := 0
var _cleared := 0
var _events: PackedStringArray = []
var _dash_cooldown := 0.0
var _last_stage := ""


func run() -> void:
	_read_args()
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[_difficulty])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	if _route == "keep":
		GameState.set_flag(&"yong_link_choice", "keep", false)  # 自動略過時選擇走預設（斷連）；保留路先寫好選擇
	player = level.player
	var max_hp := player.health.max_health
	player.health.setup(9999, 0.0)
	player.health.damaged.connect(_on_player_damaged)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is PatternBoss and (node as PatternBoss).data.id == &"yong":
			_yong = node
	if _yong == null:
		push_error("[YongFight] 帳房裡找不到阿勇")
		await finish()
		return
	_yong.mark.stacks_changed.connect(func(stacks: int) -> void:
		if stacks == 0:
			_cleared += 1)
	AimInput.set_virtual_gamepad(player, _use_pad)
	while _elapsed < TIME_LIMIT and is_instance_valid(_yong) and not _yong.call(&"is_subdued"):
		await get_tree().physics_frame
		if GameplayLock.is_locked():
			continue
		_elapsed += get_physics_process_delta_time()
		_drive()
		var stage := str(_yong.get("stage"))
		if stage != _last_stage:
			_last_stage = stage
			_log("stage %s" % stage)
			_capture_now("stage-%s" % stage)
		if _capture_every > 0.0 and _elapsed >= _next_capture:
			_next_capture += _capture_every
			_capture_now("t%03d" % int(_elapsed))
	_release_all()
	AimInput.set_virtual_gamepad(player, false)
	var won: bool = is_instance_valid(_yong) and _yong.call(&"is_subdued")
	print("YONG_FIGHT difficulty=%s route=%s input=%s result=%s time=%.1fs damage_taken=%d hits=%d deaths_equiv=%d interest_cleared=%d subdued_flag=%s" % [
			GameState.difficulty.id, _route, "pad" if _use_pad else "mouse", "subdued" if won else "timeout", _elapsed, _damage_taken, _hits_taken,
			_damage_taken / maxi(1, max_hp), _cleared, GameState.get_flag(&"ch2_yong_subdued")])
	print("YONG_FIGHT events: %s" % " | ".join(_events))
	if is_instance_valid(_yong):
		print("YONG_FIGHT end: hp=%d disarmed=%s set=%s state=%s yx=%.0f px=%.0f lock_open=%s" % [_yong.health.current, _yong.call(&"is_disarmed"), _yong.phase_set,
				_yong.fsm.current, _yong.global_position.x, player.global_position.x, _yong.is_part_open(&"baton_lock")])
	Story.auto_skip = false
	await settle(30)
	await finish()


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--difficulty="):
			_difficulty = clampi(int(arg.trim_prefix("--difficulty=")), 0, GameState.difficulties.size() - 1)
		elif arg.begins_with("--capture="):
			_capture_every = maxf(0.0, float(arg.trim_prefix("--capture=")))
		elif arg.begins_with("--route="):
			_route = arg.trim_prefix("--route=")
		elif arg == "--pad":
			_use_pad = true


# ---------------------------------------------------------------------------
# 機器人
# ---------------------------------------------------------------------------

func _drive() -> void:
	_dash_cooldown = maxf(0.0, _dash_cooldown - get_physics_process_delta_time())
	var px := player.global_position.x
	var yx := _yong.global_position.x
	var side := -1.0 if px <= yx else 1.0
	var gap := absf(px - yx)
	var stage := str(_yong.get("stage"))
	var move := _yong.current_move()
	var kind := StringName(_yong.pattern.moves.get(move, {}).get("kind", &""))
	var winding := _yong.fsm.is_in(&"windup")
	var acting := _yong.fsm.is_in(&"act")
	var goal := yx + side * KEEP_DISTANCE
	var jump := false
	var dash := false
	var interact := false
	var box := _yong.call(&"isolation_box") as BossHoldPoint
	var cell := _yong.call(&"power_cell") as BossHoldPoint
	var minion := _nearest_minion()
	if minion != null and absf(minion.global_position.x - px) < 200.0:
		goal = minion.global_position.x + signf(px - minion.global_position.x) * KEEP_DISTANCE * 0.8  # 先清掉小弟
	elif stage == "cut_box" and box != null and box.enabled:
		goal = box.global_position.x
		interact = absf(px - goal) < 10.0
	elif cell != null and cell.enabled:
		goal = cell.global_position.x
		interact = absf(px - goal) < 12.0
	elif _yong.mark.stacks >= 2 and _yong.mark.lit_pad() >= 0 and absf(_yong.mark.pad_position(_yong.mark.lit_pad()).y - player.global_position.y) < 24.0:
		goal = _yong.mark.pad_position(_yong.mark.lit_pad()).x
	if (winding or acting) and kind == &"slam" and gap < 90.0:
		interact = false  # 按住到一半也先退開，躲完再回來重按（受擊本來就會中斷）
		goal = yx + side * (gap + BACK_OFF)
		if gap < 34.0 and _dash_cooldown <= 0.0:
			dash = true
			_dash_cooldown = 0.8
	if stage == "subdue" and bool(_yong.call(&"is_disarmed")) and _yong.health.current <= 1 and not (cell != null and cell.enabled):
		goal = yx + side * 40.0  # 站在短拳外一點，引他撲空
	goal = clampf(goal, 24.0, 1120.0)
	# 要去的地方在阿勇另一側：用衝刺（無敵）穿過他，不硬擠過去。
	var crossing := signf(goal - px) == signf(yx - px) and absf(goal - px) > absf(yx - px)
	if crossing and gap < 50.0 and _dash_cooldown <= 0.0:
		dash = true
		_dash_cooldown = 0.8
	jump = _sheet_close() or _blocked_ahead(goal - px)
	_press_move(goal - px, dash, interact)
	_set_action(&"jump", jump)
	_set_action(&"interact", interact)
	_aim_and_fire(interact)


func _sheet_close() -> bool:
	for child: Node in ProjectilePool.container().get_children():
		var shot := child as Projectile
		if shot == null or not shot.active or shot.team != Combat.Team.ENEMY:
			continue
		var gap := shot.global_position.x - player.global_position.x
		if absf(gap) < 40.0 and signf(-gap) == signf(shot.velocity.x) and absf(shot.global_position.y - (player.global_position.y - 20.0)) < 26.0:
			return true
	return false


func _blocked_ahead(offset: float) -> bool:
	if absf(offset) < 8.0:
		return false
	var probe := PhysicsRayQueryParameters2D.create(player.global_position + Vector2(0, -8), player.global_position + Vector2(signf(offset) * 14.0, -8), Layers.WORLD)
	return not player.get_world_2d().direct_space_state.intersect_ray(probe).is_empty()


func _press_move(offset: float, dash: bool, hold_still: bool) -> void:
	var dir := 0.0 if absf(offset) < 4.0 or hold_still else signf(offset)
	_set_action(&"move_left", dir < 0.0)
	_set_action(&"move_right", dir > 0.0)
	if dash:
		Input.action_press(&"move_left" if _yong.global_position.x < player.global_position.x else &"move_right")
		Input.action_press(&"dash")
	else:
		Input.action_release(&"dash")


func _nearest_minion() -> Enemy:
	var best: Enemy = null
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy == _yong or enemy.is_dying() or not enemy.hurtbox.enabled:
			continue
		if best == null or absf(enemy.global_position.x - player.global_position.x) < absf(best.global_position.x - player.global_position.x):
			best = enemy
	return best


## 瞄準：附近有小弟先打小弟；制伏時先打打開的棍柄鎖扣，其他時候打頭（1.5 倍），按住互動時不開槍。
func _aim_and_fire(holding: bool) -> void:
	var target := Vector2.INF
	var minion := _nearest_minion()
	if minion != null and absf(minion.global_position.x - player.global_position.x) < 200.0:
		target = minion.hurtbox.center()
	for id: StringName in [&"baton_lock", &"head"]:
		if target != Vector2.INF or not _yong.is_part_open(id):
			continue
		for part in _yong.hurtbox.parts:
			if part.part_id == id and part.enabled:
				target = part.center()
	if target == Vector2.INF:
		target = _yong.hurtbox.center()
	var direction := (target - player.muzzle_position()).normalized()
	if _use_pad:
		_set_stick(direction)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = get_viewport().get_final_transform() * player.get_canvas_transform() * target
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		if DisplayServer.get_name() != "headless":
			Input.warp_mouse(motion.position)  # 有視窗時真實游標會蓋過事件，一起移過去
	_set_action(&"shoot", not holding and absf(target.x - player.global_position.x) < 320.0)


func _set_stick(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])


func _set_action(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"dash", &"shoot", &"interact", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(action)


func _on_player_damaged(info: DamageInfo) -> void:
	_damage_taken += info.amount
	_hits_taken += 1
	_log("hit by %s (%d) px=%.0f yx=%.0f %s" % [info.source_id, info.amount, player.global_position.x, _yong.global_position.x, _yong.fsm.current])


func _log(text: String) -> void:
	_events.append("%.1fs %s" % [_elapsed, text])


func _capture_now(label: String) -> void:
	if out_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	capture("NE-265-yong-fight-d%d-%s-%s" % [_difficulty, _route, label])
