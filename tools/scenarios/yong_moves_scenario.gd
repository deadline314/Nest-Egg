class_name YongMovesScenario
extends ScenarioBase
## 阿勇招式與兩條路的定格（NE-265）：正式第二章二樓帳房。依序拍：戰場（三塊結帳地墊、小薇的玻璃隔間）、
## 鐵棍重擊預兆、揮空後的反擊空檔、紙頁扇形（鎖定的邊線與飛出的紙頁）、身上三層利息與亮墊、搶地墊、
## 25% 退到終端（暫停前）、主隔離箱按住中、制伏中（棍柄鎖扣橙色）、拔匣、制伏完成。
## 招式由狀態機觸發，判定與外觀都是正式程式；劇情選擇在測試設定下自動走預設（斷連）。
## 用法：godot --fixed-fps 60 res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=yong_moves

const LEVEL := "res://data/levels/ch2_ledger_office.tres"

var _yong: PatternBoss


func run() -> void:
	Enemy.activation_culling_enabled = false
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(9999, 0.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is PatternBoss and (node as PatternBoss).data.id == &"yong":
			_yong = node
	if _yong == null:
		push_error("[YongMoves] 帳房裡找不到阿勇")
		await finish()
		return
	level.hud.visible = true
	_place(30.0)
	await _frames(int(TITLE_CARD_TIME * 60))
	_yong.call(&"_wake")
	await _until(&"idle", 180)
	_hold()
	capture("NE-265-yong-arena")
	_place(_yong.global_position.x / 16.0 - 3.0)
	_move(&"slam")
	await _frames(36)
	capture("NE-265-yong-slam-windup")
	_place(_yong.global_position.x / 16.0 - 8.0)
	await _until(&"recover", 120)
	await _frames(8)
	capture("NE-265-yong-slam-whiff")
	await _until(&"idle", 200)
	_hold()
	_place(_yong.global_position.x / 16.0 - 12.0)
	_move(&"paper_fan")
	await _frames(34)
	capture("NE-265-yong-fan-locked")
	await _until(&"recover", 60)
	await _frames(22)
	capture("NE-265-yong-fan-sheets")
	await _until(&"idle", 200)
	_hold()
	for i in 3:
		var info := DamageInfo.create(1, Combat.Team.ENEMY, &"yong_baton")
		info.ignore_invulnerability = true
		info.bypass_guard = true
		player.hurtbox.receive(info)
	for i in 300:
		if _yong.mark.lit_pad() >= 0:
			break
		await get_tree().physics_frame
	var pad := _yong.mark.pad_position(_yong.mark.lit_pad())
	if pad != Vector2.INF:
		player.global_position = pad + Vector2(-40.0, 0)
		snap_camera()
	await _frames(4)
	capture("NE-265-yong-interest-pad")
	_move(&"rush_pad")
	await _frames(24)
	capture("NE-265-yong-rush-pad")
	await _until(&"idle", 200)
	_place(_yong.global_position.x / 16.0 - 6.0)
	_yong.health.take_damage(_hit(_yong.health.current))
	await _frames(40)
	capture("NE-265-yong-parley")
	for i in 600:
		if str(_yong.get("stage")) == "cut_box":
			break
		await get_tree().physics_frame
	_hold()
	var box := _yong.call(&"isolation_box") as BossHoldPoint
	if box != null:
		player.global_position = box.global_position
		snap_camera()
		Input.action_press(&"interact")
		await _frames(50)
		capture("NE-265-yong-box-hold")
		await _frames(50)
		Input.action_release(&"interact")
	await _frames(30)
	_hold()
	_place(_yong.global_position.x / 16.0 - 5.0)
	await _frames(10)
	capture("NE-265-yong-subdue-lock")
	for part in _yong.hurtbox.parts:
		if part.part_id == &"baton_lock":
			for i in 3:
				part.receive(_hit(1))
	_yong.health.take_damage(_hit(_yong.health.current))
	await _until(&"idle", 200)
	_place(_yong.global_position.x / 16.0 - 6.0)
	_move(&"jab")
	await _until(&"recover", 120)
	await _frames(4)
	var cell := _yong.call(&"power_cell") as BossHoldPoint
	if cell != null:
		player.global_position = Vector2(cell.global_position.x, _yong.global_position.y)
		snap_camera()
		Input.action_press(&"interact")
		await _frames(18)
		capture("NE-265-yong-pull-cell")
		await _frames(30)
		Input.action_release(&"interact")
	await _frames(30)
	capture("NE-265-yong-subdued")
	print("YONG_MOVES stage=%s subdued_flag=%s" % [_yong.get("stage"), GameState.get_flag(&"ch2_yong_subdued")])
	Story.auto_skip = false
	await finish()


func _hit(amount: int) -> DamageInfo:
	var info := DamageInfo.create(maxi(1, amount), Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info


## 讓他待在待機不自己出招（拍下一個定格前重設冷卻）。
func _hold() -> void:
	_yong.fsm.transition(&"idle")


func _place(x_tile: float) -> void:
	player.global_position = Vector2(x_tile * 16.0, _yong.global_position.y)
	player.velocity = Vector2.ZERO
	snap_camera()


func _move(id: StringName) -> void:
	_yong.set("_move_id", id)
	_yong.fsm.transition(&"windup")


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(state: StringName, frames_max: int) -> void:
	for i in frames_max:
		if _yong.fsm.is_in(state):
			return
		await get_tree().physics_frame
