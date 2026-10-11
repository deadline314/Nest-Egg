class_name WatchdogFightScenario
extends ScenarioBase
## 看門狗實戰模擬（NE-253）：正式第一章碼頭倉庫，用真正的輸入動作（左右、跳、蹲、衝刺、射擊）由規則型機器人打一整場，
## 記錄各難度的擊敗時間、受到的傷害與換算的死亡次數，並可定時截圖（Forward+ 連續畫面）。
## 機器人的打法就是設計文件寫的應對：站在黃黑線內引撲咬→撲咬時退出線外→被扯回時打背部電源；
## 吠叫跳過震波、點射時蹲下、飛彈離開紅圈、跳壓離開陰影、第三階段拉開距離並用衝刺穿過撲咬。
## 這不是實體手把或真人驗收；用法：
##   godot --headless --fixed-fps 60 res://tools/screenshot.tscn -- --out=<資料夾> --scenario=watchdog_fight --difficulty=1
##   加 --capture=2 每 2 秒截一張；--pad 用手把的瞄準搖桿代替滑鼠方向。

const LEVEL := "res://data/levels/ch1_warehouse.tres"
const TIME_LIMIT := 300.0
const START_TILE := 40.0
## 站在鍊子盡頭內側幾像素引牠撲咬；撲咬預兆時退到線外多遠。
const BAIT_INSIDE := 6.0
const BAIT_OUTSIDE := 34.0
const KITE_DISTANCE := 120.0
## 第三階段拉開距離時留在前廳的開闊地板（貨櫃右側到隔牆前）。
const KITE_MIN_X := 816.0
const KITE_MAX_X := 1150.0

var _dog: PatternBoss
var _difficulty := 1
var _capture_every := 0.0
var _use_pad := false
var _elapsed := 0.0
var _next_capture := 0.0
var _damage_taken := 0
var _hits_taken := 0
var _yanks := 0
var _back_hits := 0
var _shots_blocked := 0
var _events: PackedStringArray = []
var _side := -1.0
var _dash_cooldown := 0.0


func run() -> void:
	_read_args()
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[_difficulty])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	var max_hp := player.health.max_health
	player.health.setup(9999, 0.0)
	player.health.damaged.connect(_on_player_damaged)
	player.global_position.x = START_TILE * 16.0
	snap_camera()
	for node in level._entities.get_children():
		if node is PatternBoss and (node as PatternBoss).data.id == &"watchdog":
			_dog = node
	if _dog == null:
		push_error("[WatchdogFight] 倉庫裡找不到看門狗")
		await finish()
		return
	# 只量頭目戰：前廳的一般敵人先移除（實際遊玩時玩家會先處理或繞過）。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != _dog:
			node.queue_free()
	AimInput.set_virtual_gamepad(player, _use_pad)
	_dog.health.damaged.connect(_on_dog_damaged)
	_dog.hurtbox.hit_blocked.connect(func(_info: DamageInfo) -> void: _shots_blocked += 1)
	var last_phase := 0
	var last_state := &""
	while _elapsed < TIME_LIMIT and is_instance_valid(_dog) and not _dog.is_dying():
		await get_tree().physics_frame
		_elapsed += get_physics_process_delta_time()
		_drive()
		if _dog.phase != last_phase:
			last_phase = _dog.phase
			_log("phase %d" % (last_phase + 1))
			_capture_now("phase%d" % (last_phase + 1))
		if _dog.fsm.current != last_state:
			last_state = _dog.fsm.current
			if last_state == &"yanked" and _dog.get("_yanked_recently"):
				_yanks += 1
				_capture_now("yank%d" % _yanks)
			elif last_state == &"windup" and _yanks + 1 < 4 and str(_dog.current_move()) in ["missiles", "pounce", "bark"]:
				_capture_now("windup_%s_%d" % [_dog.current_move(), int(_elapsed)])
		if _capture_every > 0.0 and _elapsed >= _next_capture:
			_next_capture += _capture_every
			_capture_now("t%03d" % int(_elapsed))
	_release_all()
	AimInput.set_virtual_gamepad(player, false)
	var won := not is_instance_valid(_dog) or _dog.is_dying()
	print("WATCHDOG_FIGHT difficulty=%s result=%s time=%.1fs damage_taken=%d hits=%d deaths_equiv=%d yanks=%d back_hits=%d blocked_shots=%d" % [
			GameState.difficulty.id, "win" if won else "timeout", _elapsed, _damage_taken, _hits_taken, _damage_taken / maxi(1, max_hp),
			_yanks, _back_hits, _shots_blocked])
	print("WATCHDOG_FIGHT events: %s" % " | ".join(_events))
	await settle(30)
	await finish()


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--difficulty="):
			_difficulty = clampi(int(arg.trim_prefix("--difficulty=")), 0, GameState.difficulties.size() - 1)
		elif arg.begins_with("--capture="):
			_capture_every = maxf(0.0, float(arg.trim_prefix("--capture=")))
		elif arg == "--pad":
			_use_pad = true


# ---------------------------------------------------------------------------
# 機器人：每個物理影格決定移動、跳、蹲、衝刺與瞄準
# ---------------------------------------------------------------------------

func _drive() -> void:
	_dash_cooldown = maxf(0.0, _dash_cooldown - get_physics_process_delta_time())
	var px := player.global_position.x
	var dx := _dog.global_position.x
	_side = -1.0 if px <= dx else 1.0
	var goal := px
	var jump := false
	var crouch := false
	var dash := false
	var move := _dog.current_move()
	var kind := StringName(_dog.pattern.moves.get(move, {}).get("kind", &""))
	var winding := _dog.fsm.is_in(&"windup")
	var acting := _dog.fsm.is_in(&"act")
	if _dog.is_leashed():
		var line := _dog.anchor().x + _side * _dog.pattern.leash_length
		goal = line - _side * BAIT_INSIDE
		if (winding or acting) and kind == &"lunge":
			goal = line + _side * BAIT_OUTSIDE
		if _dog.fsm.is_in(&"yanked"):
			goal = line - _side * BAIT_INSIDE
	else:
		goal = dx + _side * KITE_DISTANCE
		if goal < KITE_MIN_X or goal > KITE_MAX_X:
			goal = dx - _side * KITE_DISTANCE  # 繞到另一側，不躲到貨櫃後面（子彈會打在貨櫃上）
		goal = clampf(goal, KITE_MIN_X, KITE_MAX_X)
		# 要繞到另一側時，用衝刺（無敵）穿過牠，不直接撞上去。
		var crossing := signf(goal - px) == signf(dx - px) and absf(goal - px) > absf(dx - px)
		if crossing and absf(dx - px) < 60.0 and _dash_cooldown <= 0.0:
			dash = true
			_dash_cooldown = 0.8
		if acting and kind == &"lunge" and absf(dx - px) < 70.0 and _dash_cooldown <= 0.0:
			dash = true
			_dash_cooldown = 0.8
	if (winding or acting) and kind == &"missiles":
		goal = _safe_from_marks(goal)
	if (winding or acting) and kind == &"pounce":
		var shadow: float = _dog.get("_pounce_x")
		if absf(goal - shadow) < 60.0:
			goal = shadow + _side * 70.0
	var dodge_burst := (acting and kind == &"burst") or _dog.is_aim_locked()
	jump = _wave_close() or _blocked_ahead(goal - px) or dodge_burst
	_press_move(goal - px, dash)
	_set_action(&"jump", jump)
	_set_action(&"move_down", crouch and not jump)
	_aim_and_fire()


## 地上有朝自己來的震波就跳。
func _wave_close() -> bool:
	for child: Node in ProjectilePool.container().get_children():
		var shot := child as Projectile
		if shot == null or not shot.active or shot.team != Combat.Team.ENEMY or shot.spec.visual_style != "wave":
			continue
		var gap := shot.global_position.x - player.global_position.x
		if absf(gap) < 34.0 and signf(-gap) == signf(shot.velocity.x) and absf(shot.global_position.y - player.global_position.y) < 24.0:
			return true
	return false


## 往目標走卻被牆（貨櫃）擋住：按住跳翻過去。
func _blocked_ahead(offset: float) -> bool:
	if absf(offset) < 8.0:
		return false
	var probe := PhysicsRayQueryParameters2D.create(player.global_position + Vector2(0, -8), player.global_position + Vector2(signf(offset) * 14.0, -8), Layers.WORLD)
	return not player.get_world_2d().direct_space_state.intersect_ray(probe).is_empty() or not player.is_on_floor() and player.velocity.y < 0.0


func _safe_from_marks(goal: float) -> float:
	var marks: PackedVector2Array = _dog.get("_marks")
	var radius := float(_dog.pattern.moves[&"missiles"]["params"].get("radius", 22.0)) + 14.0
	var x := goal
	for i in 6:
		var inside := false
		for mark in marks:
			if absf(mark.x - x) < radius:
				inside = true
				x = mark.x + (radius + 2.0) * (-1.0 if x < mark.x else 1.0) * (1.0 if i % 2 == 0 else 1.0)
		if not inside:
			break
	return x


func _press_move(offset: float, dash: bool) -> void:
	var dir := 0.0 if absf(offset) < 4.0 else signf(offset)
	_set_action(&"move_left", dir < 0.0)
	_set_action(&"move_right", dir > 0.0)
	if dash:
		Input.action_press(&"move_left" if _dog.global_position.x < player.global_position.x else &"move_right")
		Input.action_press(&"dash")
	else:
		Input.action_release(&"dash")


## 瞄準：只打現在打開（橙色）的部位，優先背部電源、頭、槍臂；都關著時不浪費子彈。
func _aim_and_fire() -> void:
	var target := Vector2.INF
	for id: StringName in [&"back_power", &"head", &"gun_arm"]:
		if target != Vector2.INF or not _dog.is_part_open(id):
			continue
		for part in _dog.hurtbox.parts:
			if part.part_id == id:
				target = part.center()
	if target == Vector2.INF and not _dog.current_phase()["armored"]:
		target = _dog.hurtbox.center()
	if target == Vector2.INF:
		_set_action(&"shoot", false)
		return
	var direction := (target - player.muzzle_position()).normalized()
	if _use_pad:
		_set_stick(direction)
	else:
		# 滑鼠：送出真正的滑鼠移動事件，游標放在目標的螢幕位置。
		var motion := InputEventMouseMotion.new()
		motion.position = get_viewport().get_final_transform() * player.get_canvas_transform() * target
		motion.global_position = motion.position
		Input.parse_input_event(motion)
	_set_action(&"shoot", absf(target.x - player.global_position.x) < 320.0)


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
	for action: StringName in [&"move_left", &"move_right", &"jump", &"move_down", &"dash", &"shoot", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(action)


# ---------------------------------------------------------------------------
# 紀錄
# ---------------------------------------------------------------------------

func _on_player_damaged(info: DamageInfo) -> void:
	_damage_taken += info.amount
	_hits_taken += 1
	_log("hit by %s (%d)" % [info.source_id, info.amount])


func _on_dog_damaged(info: DamageInfo) -> void:
	if info.part == &"back_power":
		_back_hits += 1


func _log(text: String) -> void:
	_events.append("%.1fs %s" % [_elapsed, text])


func _capture_now(label: String) -> void:
	if out_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	capture("NE-253-watchdog-d%d-%s" % [_difficulty, label])
