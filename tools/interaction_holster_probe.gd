extends "res://tools/ch1_flow_probe.gd"
## NE-278：七個實際地圖互動的固定狀態修前／修後畫面；不是整章通關。
## 沿用 --out=<絕對路徑>，隔離 XDG_DATA_HOME；用 Forward+ 渲染。


func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()
	Story.auto_skip = false
	Story.set_language("zh")
	if _route == "transition":
		GameState.set_flag(&"ch1_handoff_done")
		for cycle in 3:
			await _sample("lounge", &"ch1_ali_lounge", "transition-stage-%d" % cycle)
			await _sample("pawnshop", &"ch1_label_watch", "transition-map-%d" % cycle)
		Story.reset_active_presentation(&"leave")
		print("[InteractionHolsterProbe] failures=%d" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if _route == "ali":
		_ali_fixture()
		await _sample("stall", &"ch1_ali_stall", "ali")
		get_tree().quit(0 if _failures == 0 else 1)
		return
	for name in ["watch", "guitar", "raincoat", "fare"]:
		await _sample("pawnshop", StringName("ch1_label_" + name), "label-" + name)
	GameState.set_flag(&"ch1_handoff_done")
	GameState.set_flag(&"ch1_disk_delivered")
	GameState.set_flag(&"ch1_disk_receipt_taken")
	await _sample("handoff", &"ch1_handoff_cabinet", "cabinet")
	_ali_fixture()
	await _sample("stall", &"ch1_ali_stall", "ali")
	GameState.set_flag(&"ch1_recording_heard")
	await _sample("booth_alley", &"ch1_lamp_voice", "lamp")
	if _route == "verify":
		GameState.set_flag(&"ch1_lounge_evening_done", false)
		GameState.set_flag(&"ch1_met_ali", false)
		await _sample("lounge", &"ch1_ali_lounge", "ali-stage")
		for side in [-1, 1]:
			for weapon in ["melee_blade", "melee_glaive"]:
				await _sample("pawnshop", &"ch1_label_watch", "%s-%d" % [weapon, side], "melee/" + weapon, side)
	Story.reset_active_presentation(&"leave")
	print("[InteractionHolsterProbe] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _ali_fixture() -> void:
	GameState.set_flag(&"ch1_handoff_done")
	GameState.set_flag(&"ch1_met_ali")
	GameState.set_flag(&"ch1_lounge_evening_done")
	GameState.set_flag(&"ch1_supper_done")
	GameState.set_flag(&"ch1_supper_choice", "leave")


func _sample(area: String, id: StringName, shot: String, weapon := "pistol", side := 1) -> void:
	await _enter(area)
	var npc := _object(id)
	_check(npc != null and npc.is_present(), "%s exists" % id)
	if npc == null:
		return
	_level.player.global_position = npc.global_position + Vector2(-28, 0)
	_level.player.loadout.reset(load("res://data/weapons/%s.tres" % weapon) as WeaponData)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2(side, -0.2).normalized()
	await _settle(25)
	var equipment := _level.player.loadout.snapshot()
	# 真正的 NpcActor 互動入口，保留來源 context、dispatch 與地圖對話／選擇。
	npc._talk()
	var position := _level.player.global_position
	await _settle(50)
	_check(Story.is_cinematic_active(), "%s started map presentation" % id)
	if _route == "verify" and shot != "ali-stage":
		var player := _level.player
		var crosshair: Crosshair
		for child in _level.hud.get_children():
			if child is Crosshair:
				crosshair = child
		_check(player.interaction.active and crosshair != null and not crosshair.visible, "%s hides the actual HUD crosshair" % shot)
		_check(not player._visual.rig.weapon_root().visible and not player._visual.melee_held().visible and not player._visual._blade_light.is_visible_in_tree() and not player._weapon_light.is_lit(), "%s holsters weapon and both weapon lights" % shot)
		_check(player.global_position == position and player.loadout.snapshot() == equipment, "%s leaves world position and equipment frozen" % shot)
		var rig := player._visual.rig
		_check(rig.bone(&"hand_front").global_position.y > rig.bone(&"arm_front_upper").global_position.y + 10.0, "%s front hand hangs below shoulder" % shot)
	elif _route == "verify":
		_check(not _level.player.interaction.active and _level.player._visual.rig.weapon_root().visible, "actual Ali stage leaves gameplay actor weapon state unchanged")
	await RenderingServer.frame_post_draw
	_capture(shot)
	# 擷取在 render callback 內恢復；移回一般影格再取消舞台／釋放場景，避免同時拆除繪製資源。
	await get_tree().process_frame
	Story.reset_active_presentation(&"probe")
	await _settle(5)
	if _route == "verify":
		_check(not _level.player.interaction.active and _level.player.loadout.snapshot() == equipment, "%s restores after cancellation without equipment changes" % shot)
		if shot == "label-watch":
			await RenderingServer.frame_post_draw
			_capture("restored")
			await get_tree().process_frame
