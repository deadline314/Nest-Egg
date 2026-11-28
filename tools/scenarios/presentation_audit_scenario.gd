extends ScenarioBase
## 演出總檢（PRESENTATION_AUDIT.md）：用第一章的真實資料，把玩家會看到的時刻各拍一張或幾張。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=presentation_audit
## 主選單、難度、設定、圖鑑、暫停、背包、死亡、結算另由 --scenario=screens 拍；地點標示與章末畫面由 --scenario=presentation 拍。

const PROLOGUE := "res://data/levels/ch1_prologue.tres"
const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const STREET := "res://data/levels/ch1_street.tres"
const SLOW := 0.15


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_reduce_flashes(false)
	Settings.set_ui_text_scale(1.0)
	GameState.start_new_run(GameState.difficulties[1])
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
