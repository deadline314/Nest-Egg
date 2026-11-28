extends ScenarioBase
## 演出總檢（PRESENTATION_AUDIT.md）：用第一章的真實資料，把玩家會看到的時刻各拍一張或幾張。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=presentation_audit
## 主選單、難度、設定、圖鑑、暫停、背包、死亡、結算另由 --scenario=screens 拍；地點標示與章末畫面由 --scenario=presentation 拍。

const PROLOGUE := "res://data/levels/ch1_prologue.tres"
const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const STREET := "res://data/levels/ch1_street.tres"
const STALL := "res://data/levels/ch1_stall.tres"
const SLOW := 0.15


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	Settings.set_ui_text_scale(1.0)
	GameState.start_new_run(GameState.difficulties[1])
	for arg in OS.get_cmdline_user_args():
		if arg == "--part=hurt":
			Story.auto_skip = true
			for spot: Array in [[STREET, &"street_home", "street"], [PAWNSHOP, &"", "pawnshop"]]:
				GameState.pending_portal = spot[1]
				await _open(spot[0])
				await wait(5.5)
				await _hurt_frames(spot[2])
			await finish()
			return
		if arg == "--part=death":
			Story.auto_skip = true
			await _open(PAWNSHOP)
			await wait(5.5)
			await _death_frames()
			await finish()
			return
		if arg.begins_with("--part=street-text"):
			Story.auto_skip = false
			GameState.pending_portal = &"street_home"
			await _open(STREET)
			await wait(4.0)
			await _street_text(arg.get_slice("@", 1) if arg.contains("@") else "before")
			await finish()
			return
		if arg == "--part=bubble-styles":
			Story.auto_skip = true
			GameState.pending_portal = &"street_home"
			await _open(STREET)
			await wait(5.0)
			await _bubble_styles()
			await finish()
			return
		if arg.begins_with("--part=world-text"):
			Story.auto_skip = true
			await _world_text(arg.get_slice("@", 1) if arg.contains("@") else "after")
			await finish()
			return
		if arg.begins_with("--part=booth"):
			Story.auto_skip = true
			GameState.clear_checkpoint()
			GameState.pending_portal = &""
			await _open("res://data/levels/ch1_booth_alley.tres")
			await wait(5.0)
			await _booth(arg.get_slice("@", 1) if arg.contains("@") else "after")
			await finish()
			return
		if arg == "--part=contrast":
			Story.auto_skip = true
			await _world_text_contrast()
			await finish()
			return
		if arg.begins_with("--part=choice"):
			Story.auto_skip = false
			await _open(STALL)
			await wait(2.0)
			var choice_tag := arg.get_slice("@", 1) if arg.contains("@") else "after"
			for scene_id: StringName in [&"ch1_t_supper_host_prompt", &"ch2_t_s22_tea"]:
				await _choice_frame(scene_id, "%s-%s" % [choice_tag, scene_id])
			await finish()
			return
		if arg == "--part=transitions":
			Story.auto_skip = true
			await _open(PAWNSHOP)
			await wait(5.5)
			await _purpose_transitions()
			await finish()
			return
	await _prologue()
	await _story_moments()
	await _feedback()
	await _transitions()
	await _street_bubbles()
	await _boss()
	await _death()
	await finish()


func _open(path: String) -> void:
	if is_instance_valid(level):
		level.queue_free()
		await settle(3)
	level = Level.new()
	level.configure(load(path))
	add_child(level)
	await settle(4)
	player = level.player


## 序章：進場的過場（開門），拍開頭、中段。
func _prologue() -> void:
	Story.auto_skip = false
	await _open(PROLOGUE)
	await wait(1.2)
	capture("audit-prologue-a")
	await wait(2.5)
	capture("audit-prologue-b")
	await wait(2.5)
	capture("audit-prologue-c")
	Story.skip_cinematic()
	await wait(1.5)
	capture("audit-prologue-after")


## 對話、地圖上的氣泡、通訊。
func _story_moments() -> void:
	player.health.setup(999, 0.0)
	Story.play(&"ch1_p02_talk", false)
	await wait(1.6)
	capture("audit-dialogue")
	Story.skip_cinematic()
	await wait(0.8)
	Story.play(&"ch1_p03_range", false)
	await wait(1.4)
	capture("audit-street-entry")
	await wait(4.0)
	Story.play(&"ch1_p04_dash", false)
	await wait(1.8)
	capture("audit-radio")
	await wait(5.0)


## 拾取、檢查點、受傷、瀕死。
func _feedback() -> void:
	Story.auto_skip = true
	await _open(PAWNSHOP)
	await wait(5.5)
	player.health.setup(10, 0.0)
	StoryItems.acquire(&"old_k_order")
	await wait(0.35)
	capture("audit-pickup")
	await wait(2.0)
	EventBus.toast_requested.emit(Level.REGISTERED_TOAST)
	await wait(0.35)
	capture("audit-checkpoint")
	await wait(3.0)
	player.hurtbox.receive(DamageInfo.create(3, Combat.Team.ENEMY, &"presentation_audit"))
	await settle(2)
	capture("audit-hurt")
	await wait(1.0)
	player.hurtbox.receive(DamageInfo.create(5, Combat.Team.ENEMY, &"presentation_audit"))
	await wait(0.8)
	capture("audit-near-death")


## 轉場：區域之間（FADE）、主選單進遊戲（SCAN）、章節之間（ELEVATOR）、死亡重來（GLITCH）、讀取（IRIS），各拍蓋住一半。
func _transitions() -> void:
	for kind_name: String in ["FADE", "SCAN", "ELEVATOR", "GLITCH", "IRIS"]:
		var kind: int = Transition.Kind[kind_name]
		Engine.time_scale = SLOW
		var done := [false]
		var job := func() -> void:
			await Transition.play(kind, func() -> void: await get_tree().create_timer(0.3, true, false, true).timeout)
			done[0] = true
		job.call()
		await get_tree().create_timer(Transition.DEFAULT_TIME[kind] * 0.5, true, false, false).timeout
		capture("audit-transition-%s" % kind_name.to_lower())
		Engine.time_scale = 1.0
		for i in 600:
			if done[0]:
				break
			await get_tree().process_frame
		await settle(4)


## 受傷與瀕死（NE-428）：被打中的峰值一格、瀕死時脈動的高低兩格。主角停住，避免移動造成差異。
func _hurt_frames(tag: String) -> void:
	player.health.setup(10, 0.0)
	await wait(0.3)
	capture("hurt-%s-0-calm" % tag)
	player.hurtbox.receive(DamageInfo.create(2, Combat.Team.ENEMY, &"presentation_audit"))
	await settle(2)
	capture("hurt-%s-1-hit" % tag)
	await wait(1.2)
	player.hurtbox.receive(DamageInfo.create(6, Combat.Team.ENEMY, &"presentation_audit"))
	await wait(1.6)
	for i in 2:
		capture("hurt-%s-%d-danger" % [tag, 2 + i])
		await wait(PI / PostProcess.DANGER_PULSE_SPEED)
	player.health.setup(999, 0.0)
	await wait(1.5)


## 死亡與重來（NE-472）：倒地、死亡畫面以回溯進場（一半）、死亡畫面、重來的回溯（蓋住一半、蓋住、揭開一半）。
func _death_frames() -> void:
	# 第一章第一次死亡是劇情的診間場景；拍一般的死亡流程。
	GameState.deaths = 3
	player.health.setup(1, 0.0)
	player.hurtbox.receive(DamageInfo.create(5, Combat.Team.ENEMY, &"presentation_audit"))
	await wait(0.4)
	capture("death-0-fall")
	var screen: DeathScreen = null
	for i in 240:
		for node in level.find_children("*", "", true, false):
			if node is DeathScreen:
				screen = node
		if screen != null:
			break
		await get_tree().process_frame
	if screen == null:
		# 這一章的死亡會先播劇情的死亡場景；照關卡建立死亡畫面的方式直接建立一個，拍一般死亡的進場。
		print("AUDIT death scene played instead of the death screen; building the ordinary screen")
		screen = DeathScreen.new()
		screen.setup(DefeatCodex.unlock(&"grunt_shot", Story.language), true)
		level.add_child(screen)
		await settle(1)
	Engine.time_scale = SLOW
	await get_tree().create_timer(DeathScreen.NOISE_TIME * 0.35).timeout
	capture("death-1-screen-in")
	Engine.time_scale = 1.0
	await wait(1.6)
	capture("death-2-screen")
	var kind: int = Transition.RETRY
	var half: float = Transition.DEFAULT_TIME[kind]
	Engine.time_scale = SLOW
	var done := [false]
	var job := func() -> void:
		await Transition.play(kind, func() -> void: await get_tree().create_timer(0.6, true, false, true).timeout, -1.0, Vector2(0.5, 0.5), DeathScreen.record_title(GameState.deaths), 0.0)
		done[0] = true
	job.call()
	await get_tree().create_timer(half * 0.5).timeout
	capture("death-3-retry-cover")
	await get_tree().create_timer(half * 0.5 + 0.03).timeout
	capture("death-4-retry-covered")
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.6, true, false, true).timeout
	Engine.time_scale = SLOW
	await get_tree().create_timer(half * 0.5).timeout
	capture("death-5-retry-reveal")
	Engine.time_scale = 1.0
	for i in 600:
		if done[0]:
			break
		await get_tree().process_frame


## 文字的交通管制（NE-491）：港區街道，主角從入口慢慢走過 x27 一帶，讓街坊聊天、互動提示、教學看板自然出現；
## 每走一小段停一下拍一格（共 16 格），看得出文字依序出現而不是同時擠上來。
func _street_text(tag: String) -> void:
	player.health.setup(999, 0.0)
	for i in 16:
		Input.action_press(&"move_right")
		await wait(0.25)
		Input.action_release(&"move_right")
		await wait(0.35)
		capture("street-text-%s-%02d" % [tag, i])


## 氣泡的兩種樣子（NE-491）：路人自己的閒聊（小、淡）與對凜說的話（左邊講者顏色的細軌）。
func _bubble_styles() -> void:
	player.health.setup(999, 0.0)
	var npcs: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is Node2D:
			npcs.append(node)
	npcs.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.x < b.global_position.x)
	if npcs.is_empty():
		print("AUDIT no npc in street")
		return
	var vendor: Node2D = npcs[0]
	player.global_position = vendor.global_position + Vector2(-150.0, 0.0)
	snap_camera()
	await wait(1.0)
	var host: MapBubbles = null
	for node in level.find_children("*", "", true, false):
		if node is MapBubbles:
			host = node
	host.anchor_resolver = func(id: String) -> Node2D: return player if id == "rin" else vendor
	var chatter: Array[Dictionary] = [{"speaker": "street_vendor", "text": "市集那頭被收帳的封了，菜車只好繞去碼頭。", "color": Palette.UI_TEXT}]
	host.show_lines(&"style_ambient", chatter)
	await wait(1.0)
	capture("bubble-ambient")
	await wait(4.5)
	var talk: Array[Dictionary] = [{"speaker": "street_vendor", "text": "妳也是來找收帳的人？他早上往碼頭走了。", "color": Palette.NEON_YELLOW}, {"speaker": "rin", "text": "謝了，我自己去看看。", "color": Palette.MAGENTA}]
	host.show_lines(&"style_addressed", talk)
	await wait(1.0)
	capture("bubble-addressed")


## 檢查點（NE-494）：電話亭巷的電話亭，第一次撥（通話中、登記中、勾號、結束）與再撥一次（更短），各拍幾格。
func _booth(tag: String) -> void:
	player.health.setup(999, 0.0)
	var booth: Checkpoint = null
	for node in level.find_children("*", "", true, false):
		if node is Checkpoint and (booth == null or absf(node.global_position.x - player.global_position.x) < absf(booth.global_position.x - player.global_position.x)):
			booth = node
	if booth == null:
		print("AUDIT no booth in booth alley")
		return
	# 第一章第一個亭子會播一段劇情錄音（故事線的內容）；這裡只拍亭子自己的演出，先當作聽過。
	Story._seen[&"ch1_t_booth_recording"] = true
	player.global_position = booth.global_position + Vector2(-Checkpoint.STAND_DISTANCE, 0.0)
	player.facing = 1
	snap_camera()
	await wait(1.2)
	_booth_shot(booth, "booth-%s-0-near" % tag)
	booth.start_call(player)
	await wait(0.75)
	_booth_shot(booth, "booth-%s-1-call" % tag)
	while booth.is_calling():
		await get_tree().process_frame
	for step: Array in [[0.2, "2-filling"], [0.55, "3-check"], [0.35, "4-settle"]]:
		await wait(step[0])
		_booth_shot(booth, "booth-%s-%s" % [tag, step[1]])
	await wait(1.5)
	_booth_shot(booth, "booth-%s-5-done" % tag)
	booth.start_call(player)
	while booth.is_calling():
		await get_tree().process_frame
	await wait(0.2)
	_booth_shot(booth, "booth-%s-6-again" % tag)
	await wait(1.4)
	_booth_shot(booth, "booth-%s-7-again-done" % tag)


## 世界文字的對比（NE-494 併入）：最不利的三個場景（第一章街道的霓虹、第四章紅光舊廠、第三章冷白辦公大廳），
## 拾取說明放在畫面左、中、右三處，對凜說的話在凜頭上；每處拍「有字」與「沒字」兩格，並印出文字框在畫面上的位置（640×360）。
func _world_text_contrast() -> void:
	for area: Array in [["street", STREET, &"street_home"], ["factory", "res://data/levels/ch4_factory_approach.tres", &""], ["office", "res://data/levels/ch3_office_hall.tres", &""]]:
		GameState.pending_portal = area[2]
		await _open(area[1])
		await wait(4.0)
		player.health.setup(999, 0.0)
		var host: MapBubbles = null
		for node in level.find_children("*", "", true, false):
			if node is MapBubbles:
				host = node
		host.anchor_resolver = func(_id: String) -> Node2D: return player
		var view := MapBubbles.TEXT_LAYOUT.world_rect(get_viewport())
		for i in 3:
			var pickup := WorldPrompt.new()
			pickup.text = "止痛貼片：撐過下一場就好，別當成治療。"
			pickup.set("text_kind", &"pickup")
			pickup.reach_check = func() -> bool: return true
			level.add_child(pickup)
			pickup.global_position = Vector2(view.position.x + view.size.x * (0.2 + 0.3 * float(i)), view.position.y + view.size.y * (0.3 + 0.12 * float(i)))
			var talk: Array[Dictionary] = [{"speaker": "rin", "text": "先把這裡的貨單抄下來，再去碼頭找他。", "color": Palette.MAGENTA}]
			host.show_lines(StringName("contrast_%s_%d" % [area[0], i]), talk)
			for k in 20:
				await wait(0.1)
				if host._active.any(func(b: Dictionary) -> bool: return (b.get("rect", Rect2()) as Rect2).has_area()):
					break
			await wait(0.6)
			var canvas := get_viewport().get_canvas_transform()
			var pickup_rect := canvas * Rect2(pickup.base_rect().position + pickup._nudge, pickup.base_rect().size)
			var bubble_rect := Rect2()
			for b: Dictionary in host._active:
				bubble_rect = canvas * (b.get("rect", Rect2()) as Rect2)
			var name := "contrast-%s-%d" % [area[0], i]
			capture(name + "-text")
			print("AUDIT contrast %s pickup=%s bubble=%s" % [name, pickup_rect, bubble_rect])
			pickup.visible = false
			host.visible = false
			await get_tree().process_frame
			capture(name + "-bare")
			host.visible = true
			pickup.queue_free()
			while host.is_busy():
				await wait(0.2)


## 拍一格電話亭，並印出亭子在畫面上的位置（640×360 畫布），方便裁出近拍。
func _booth_shot(booth: Checkpoint, name: String) -> void:
	capture(name)
	print("AUDIT booth %s at %s" % [name, get_viewport().get_canvas_transform() * booth.global_position])


## 世界裡的文字在螢幕上的大小（NE-493）：取景最緊的第一章街道（靠近人物時 21:9 遮幅）與最鬆的倉庫（沒有遮幅），
## 各放一段對凜說的話、一個互動提示與一個拾取說明拍一張；同一類文字在兩張裡應該一樣大。
func _world_text(tag: String) -> void:
	for area: Array in [["street", STREET, &"street_home"], ["warehouse", WAREHOUSE, &""]]:
		GameState.pending_portal = area[2]
		await _open(area[1])
		await wait(5.0)
		player.health.setup(999, 0.0)
		var speaker: Node2D = player
		if area[0] == "street":
			var npcs: Array[Node2D] = []
			for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
				if node is Node2D:
					npcs.append(node)
			npcs.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.x < b.global_position.x)
			if not npcs.is_empty():
				speaker = npcs[0]
				player.global_position = speaker.global_position + Vector2(-70.0, 0.0)
		snap_camera()
		await wait(1.0)
		var host: MapBubbles = null
		for node in level.find_children("*", "", true, false):
			if node is MapBubbles:
				host = node
		host.anchor_resolver = func(id: String) -> Node2D: return player if id == "rin" else speaker
		# 街道上有真的拾取物（傳單）；倉庫這一段沒有，放一個同類的拾取說明。
		if area[0] == "warehouse":
			var pickup := WorldPrompt.new()
			pickup.text = "止痛貼片：撐過下一場就好，別當成治療。"
			pickup.set("text_kind", &"pickup")
			pickup.reach_check = func() -> bool: return true
			level.add_child(pickup)
			pickup.global_position = player.global_position + Vector2(110.0, -30.0)
		var talk: Array[Dictionary] = [{"speaker": "rin", "text": "先把這裡的貨單抄下來，再去碼頭找他。", "color": Palette.MAGENTA}]
		host.show_lines(&"world_text_fixture", talk)
		for i in 20:
			await wait(0.15)
			if host._active.any(func(b: Dictionary) -> bool: return (b.get("rect", Rect2()) as Rect2).has_area()):
				break
		await wait(0.3)
		capture("world-text-%s-%s" % [tag, area[0]])
		while host.is_busy():
			await wait(0.2)


## 過場的選擇框不蓋住講者（NE-492）：播麵攤的招待選擇，台詞自動往下，選擇框出現後拍一張。
func _choice_frame(scene_id: StringName, tag: String) -> void:
	Story.skip_cinematic()
	await wait(0.5)
	# 直接用播放器播（和圖鑑的回看一樣），不受劇情旗標限制。
	var cutscene := CutscenePlayer.new()
	add_child(cutscene)
	cutscene.play(scene_id, Story._scenes[String(scene_id)])
	for i in 1200:
		if is_instance_valid(cutscene):
			if is_instance_valid(cutscene._choice):
				break
			if cutscene._dialogue.is_complete():
				cutscene._advance_requested = true
		await get_tree().process_frame
	await wait(1.0)
	capture("choice-%s" % tag)
	if is_instance_valid(cutscene):
		cutscene.skip()
		await wait(1.0)


## 遊戲流程的三種轉場用途（NE-427）：各拍蓋住一半、完全蓋住、揭開一半。
func _purpose_transitions() -> void:
	for purpose: Array in [["world", Transition.WORLD, ""], ["system", Transition.SYSTEM, ""], ["retry", Transition.RETRY, DeathScreen.record_title(4)]]:
		var kind: int = purpose[1]
		var half: float = Transition.DEFAULT_TIME[kind]
		Engine.time_scale = SLOW
		var done := [false]
		var job := func() -> void:
			await Transition.play(kind, func() -> void: await get_tree().create_timer(0.6, true, false, true).timeout, -1.0, Vector2(0.5, 0.5), purpose[2], 0.0)
			done[0] = true
		job.call()
		await get_tree().create_timer(half * 0.5).timeout
		capture("flow-%s-0-cover" % purpose[0])
		await get_tree().create_timer(half * 0.5 + 0.03).timeout
		capture("flow-%s-1-covered" % purpose[0])
		Engine.time_scale = 1.0
		await get_tree().create_timer(0.6, true, false, true).timeout
		Engine.time_scale = SLOW
		await get_tree().create_timer(half * 0.5).timeout
		capture("flow-%s-2-reveal" % purpose[0])
		Engine.time_scale = 1.0
		for i in 600:
			if done[0]:
				break
			await get_tree().process_frame
		await settle(4)


## 頭目：碼頭倉庫的看門狗（區域裡的頭目敵人）。主角走到牠前面，拍血條出現、交戰、擊敗。
func _boss() -> void:
	Story.auto_skip = true
	GameState.pending_portal = &"wh_street"
	await _open(WAREHOUSE)
	await wait(5.5)
	player.health.setup(999, 0.0)
	var boss: Enemy = null
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data != null and enemy.data.is_boss:
			boss = enemy
			break
	if boss == null:
		print("AUDIT warehouse has no boss enemy")
		return
	player.global_position = Vector2(boss.global_position.x - 120.0, boss.global_position.y)
	snap_camera()
	await wait(1.5)
	capture("audit-boss-intro-a")
	await wait(2.0)
	capture("audit-boss-intro-b")
	boss.hurtbox.receive(DamageInfo.create(99999, Combat.Team.PLAYER, &"presentation_audit"))
	await wait(0.3)
	capture("audit-boss-defeat-a")
	await wait(1.5)
	capture("audit-boss-defeat-b")
	await wait(3.0)
	capture("audit-boss-after")


## 港區街道入口：教學看板與路人的氣泡（氣泡要等講者在畫面裡才會出現，這一格主要拍到教學看板）。
func _street_bubbles() -> void:
	Story.auto_skip = true
	GameState.pending_portal = &"street_home"
	await _open(STREET)
	await wait(5.5)
	Story.play(&"ch1_b_street_in", false)
	await wait(1.4)
	capture("audit-street-entry")

## 死亡：倒下的瞬間、中段、死亡畫面。
func _death() -> void:
	Story.auto_skip = true
	await _open(PAWNSHOP)
	await wait(5.5)
	player.health.setup(1, 0.0)
	player.hurtbox.receive(DamageInfo.create(5, Combat.Team.ENEMY, &"presentation_audit"))
	await wait(0.25)
	capture("audit-death-a")
	await wait(1.0)
	capture("audit-death-b")
	await wait(2.5)
	capture("audit-death-c")
