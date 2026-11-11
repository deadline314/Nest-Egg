extends ScenarioBase
## Native replay adapted from NE-248 archived v9; no enemy HP/phase/FSM/core writes.

var logic_only := false
var side := 1
var label_mode := "current"
var boss: Enemy
var core: Hurtbox
var active := false
var stage := "damage"
var elapsed := 0.0
var next_shot := 0.0
var hits: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var captured: Array[Dictionary] = []
var capture_busy := false
var lab: Label
var last_state := ""
var phase_seen := false
var core_hit := false
var body_hit := false
var closed_hit := false
var last_boss_damage := -1
var held_aim := Vector2.INF

func _ready() -> void:
	process_physics_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--side="): side = int(arg.trim_prefix("--side="))
		elif arg.begins_with("--mode="): label_mode = arg.trim_prefix("--mode=")
		elif arg == "--logic-only": logic_only = true
	if not out_dir.is_absolute_path() or side not in [-1, 1]:
		push_error("[NE248] Requires --out=<absolute directory> and --side=1|-1")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.use_storage(out_dir.path_join("probe-settings.cfg"))
	GameState.story_autosave = false
	get_window().size = Vector2i(1280, 720)
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()

func _run() -> void:
	seed(248)
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	var arena := LevelData.new()
	arena.id = &"warden_natural_arena"
	arena.chapter = Story.DEFAULT_CHAPTER
	arena.layout_path = "res://tests/fixtures/arena_map.json"
	await open_arena("res://data/lighting/neutral.tres", 18.0 if side == 1 else 38.0, arena)
	# The shared screenshot helper disables hit invulnerability. Keep real tuning.
	player.health.setup(999, player.tuning.hurt_invulnerability)
	_check(is_equal_approx(player.health.invulnerability_time, player.tuning.hurt_invulnerability) and is_equal_approx(player.health.invulnerability_time, 1.0), "player retains authored one-second hit invulnerability")
	_check(arena.chapter == &"ch1_kasa" and not Story.chapter_info(arena.chapter).is_empty(), "arena uses the active authored first chapter")
	var canvas := CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.03, 0.05, 0.96)
	panel.position = Vector2(8, 8)
	panel.size = Vector2(624, 70)
	canvas.add_child(panel)
	lab = Label.new()
	lab.position = Vector2(16, 12)
	lab.add_theme_font_size_override("font_size", 12)
	canvas.add_child(lab)
	level.hud.visible = true
	boss = spawn_enemy("res://data/enemies/warden.tres", 30.0)
	for part: Hurtbox in boss.hurtbox.parts:
		if part.part_id == &"core": core = part
	_check(core != null, "real boss exposes the authored core hurt part")
	_check(boss.health.current == 90 and int(boss.get("_phase")) == 1, "boss starts with original 90 HP and phase 1")
	_check(player.loadout.active_weapon().id == &"pistol", "actual Player uses unchanged starting pistol")
	boss.health.damaged.connect(_on_boss_damage)
	EventBus.hit_marker.connect(_on_marker)
	active = true
	for tick in 14400:
		await get_tree().physics_frame
		if tick % 120 == 0:
			timeline.append(_snapshot("sample"))
			print("NATURAL tick=", tick, " stage=", stage, " hp=", boss.health.current, " state=", boss.fsm.current)
		if closed_hit or boss.health.is_dead or player.health.is_dead: break
	active = false
	_release()
	_check(phase_seen, "real player pistol damage naturally triggers phase 2")
	_check(core_hit, "natural exposed core receives one 2x weak hit")
	_check(body_hit, "exposed window body shot stays ordinary 1x")
	_check(closed_hit, "closed core path stays ordinary 1x")
	_check(not boss.health.is_dead and not player.health.is_dead, "both actors remain alive for the bounded verification")
	for tick in 20:
		await get_tree().process_frame
		if pending.is_empty() and not capture_busy: break
	lab.text = "LAB / %s / scripted public input; native Forward+\nphase=%d HP=%d core=%s body=%s closed=%s\nEnemy HP/phase/FSM/core never assigned by this probe" % [label_mode, boss.get("_phase"), boss.health.current, core_hit, body_hit, closed_hit]
	if not logic_only:
		await RenderingServer.frame_post_draw
		capture("summary")
	var source := {}
	for path in ["res://tools/ne248_natural_core_probe.gd", "res://game/projectiles/projectile.gd", "res://core/components/hurtbox.gd", "res://game/enemies/warden_boss.gd", "res://game/player/player.gd", "res://core/aim_input.gd", "res://data/enemies/warden.tres", "res://data/weapons/pistol.tres", "res://data/projectiles/pistol_shot.tres", "res://data/player/player_tuning.tres", "res://core/components/health_component.gd"]:
		source[path] = FileAccess.get_sha256(path)
	var result := {"mode": label_mode, "initial_side": side, "chapter": str(arena.chapter), "player_hit_invulnerability": player.health.invulnerability_time, "scope": "actual Level and Player public movement/shoot/reload/mouse input in explicitly arranged arena; player 999 HP with authored hit invulnerability; no enemy HP/phase/FSM/core writes; not full campaign or human device play", "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "hdr_2d": get_viewport().use_hdr_2d, "logic_only": logic_only, "source_sha256": source, "checks": checks, "hits": hits, "shots": shots, "timeline": timeline, "captures": captured}
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	var failures := checks.filter(func(c: Dictionary) -> bool: return not c["passed"]).size()
	print("NATURAL_CORE checks=", checks.size(), " failures=", failures)
	file.close()
	await finish()
	await AudioRelease.settle(get_tree())
	for frame in 30:
		await get_tree().process_frame
		if not logic_only:
			await RenderingServer.frame_post_draw
	get_tree().quit(0 if failures == 0 else 1)

func _physics_process(delta: float) -> void:
	if not active: return
	elapsed += delta
	var state := str(boss.fsm.current)
	if state != last_state:
		timeline.append(_snapshot("state"))
		last_state = state
	if not phase_seen and int(boss.get("_phase")) == 2:
		phase_seen = true
		stage = "wait_core"
		pending.append({"name": "phase2", "event": _snapshot("natural_phase2")})
	var is_exposed := core.damage_scale > 1.0
	if stage == "wait_core" and state == "core_recover" and is_exposed: stage = "core"
	if stage == "wait_body" and state == "core_recover" and is_exposed: stage = "body"
	if stage == "wait_closed" and not is_exposed and state not in ["leap", "phase_shift"] and is_equal_approx(boss.hurtbox.damage_scale, 1.0): stage = "closed"
	if stage in ["core", "body"] and not is_exposed:
		stage = "wait_core" if stage == "core" else "wait_body"
	var target := core.center()
	if stage in ["damage", "body"]: target = boss.global_position + Vector2(0, -25)
	if not held_aim.is_finite() or (pending.is_empty() and not capture_busy): held_aim = target
	target = held_aim
	var screen := get_viewport().get_canvas_transform() * target
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	motion.relative = Vector2(0.01, 0)
	get_viewport().push_input(motion, true)
	Input.warp_mouse(get_viewport().get_final_transform() * screen)
	var difference := boss.global_position.x - player.global_position.x
	var desired := clampf(boss.global_position.x - side * 175.0, 65.0, 890.0)
	if boss.global_position.x < 240 or boss.global_position.x > 730: desired = 480.0
	var move := 0
	if player.global_position.x < desired - 8: move = 1
	elif player.global_position.x > desired + 8: move = -1
	_set_action(&"move_left", move < 0)
	_set_action(&"move_right", move > 0)
	_set_action(&"reload", player.loadout.is_dry() and not player.loadout.is_reloading())
	var may_fire := stage in ["damage", "core", "body", "closed"] and player.is_on_floor() and absf(difference) > 80
	if stage in ["core", "body", "closed"]: may_fire = may_fire and boss.facing == -side and signi(difference) == side and is_equal_approx(boss.hurtbox.damage_scale, 1.0)
	var desired_aim := (target - player.aim_origin()).normalized()
	var aim_ready := player.aim_dir.dot(desired_aim) > cos(deg_to_rad(1.0))
	var fire := may_fire and elapsed >= next_shot and not player.loadout.is_reloading() and _flying_pistol_count() == 0 and aim_ready and pending.is_empty() and not capture_busy
	_set_action(&"shoot", fire)
	if fire:
		next_shot = elapsed + 0.26
		shots.append({"t": elapsed, "stage": stage, "target": [target.x,target.y], "muzzle": [player.muzzle_position().x,player.muzzle_position().y], "aim": [player.aim_dir.x,player.aim_dir.y]})
	_refresh_lab()

func _on_boss_damage(info: DamageInfo) -> void:
	var event := _snapshot("damage")
	event.merge({"part": info.part, "weak": info.weak_hit, "amount": info.amount, "source": info.source_id, "before_hp": boss.health.current + info.amount, "after_hp": boss.health.current, "contact": [info.contact_point.x,info.contact_point.y], "frame": Engine.get_physics_frames(), "marker": "", "contact_inside_core": core.contains_point(info.contact_point, 1.5)})
	hits.append(event)
	last_boss_damage = hits.size() - 1
	if stage == "core" and core.damage_scale > 1:
		_check(boss.facing == -side, "core shot uses the requested natural facing")
		_check(is_equal_approx(boss.hurtbox.damage_scale, 1.0), "core comparison isolates the part multiplier from leap vulnerability")
		core_hit = info.part == &"core" and info.weak_hit and info.amount == 2
		_check(core_hit, "exposed core real pistol resolves core with 2 damage and weak flag")
		_check(core.contains_point(info.contact_point, 1.5), "core hit feedback lies inside the selected authored core")
		pending.append({"name": "core_hit", "event": event})
		stage = "wait_body"
	elif stage == "body" and core.damage_scale > 1:
		body_hit = info.part == &"" and not info.weak_hit and info.amount == 1
		_check(body_hit, "body outside exposed core stays non-weak 1 damage")
		pending.append({"name": "body_hit", "event": event})
		stage = "wait_closed"
	elif stage == "closed" and is_equal_approx(core.damage_scale, 1.0) and is_equal_approx(boss.hurtbox.damage_scale, 1.0):
		closed_hit = not info.weak_hit and info.amount == 1
		_check(closed_hit, "closed core path does not receive weak multiplier")
		pending.append({"name": "closed_hit", "event": event})

func _on_marker(kind: StringName) -> void:
	if last_boss_damage < 0 or int(hits[last_boss_damage]["frame"]) != Engine.get_physics_frames(): return
	hits[last_boss_damage]["marker"] = str(kind)
	if bool(hits[last_boss_damage]["weak"]): _check(kind == &"weak", "actual weak hit marker is emitted for core hit")
	_refresh_lab()

func _process(_delta: float) -> void:
	if not pending.is_empty() and not capture_busy: _capture_pending()

func _capture_pending() -> void:
	capture_busy = true
	var entry: Dictionary = pending.pop_front()
	if not logic_only:
		await RenderingServer.frame_post_draw
		capture(str(entry["name"]))
	captured.append(entry)
	capture_busy = false

func _snapshot(kind: String) -> Dictionary:
	return {"kind": kind, "t": elapsed, "stage": stage, "state": str(boss.fsm.current), "phase": boss.get("_phase"), "hp": boss.health.current, "core_scale": core.damage_scale, "body_scale": boss.hurtbox.damage_scale, "boss_facing": boss.facing, "boss": [boss.global_position.x,boss.global_position.y], "player": [player.global_position.x,player.global_position.y], "core": [core.center().x,core.center().y]}

func _set_action(action: StringName, pressed: bool) -> void:
	if pressed: Input.action_press(action)
	else: Input.action_release(action)

func _release() -> void:
	for action in [&"move_left", &"move_right", &"shoot", &"reload"]: Input.action_release(action)

func _check(passed: bool, text: String) -> void:
	checks.append({"passed": passed, "message": text})
	print("CHECK ", passed, " ", text)


func _flying_pistol_count() -> int:
	var count := 0
	var container := ProjectilePool.container()
	if container != null:
		for child in container.get_children():
			if child is Projectile and child.active and child.team == Combat.Team.PLAYER and child.spec != null and child.spec.source_id == &"player_pistol": count += 1
	return count


func _refresh_lab() -> void:
	var last := "last hit: none"
	if not hits.is_empty():
		var event: Dictionary = hits[-1]
		last = "last hit: part=%s damage=%d weak=%s marker=%s" % [str(event["part"]) if event["part"] != "" else "body", event["amount"], event["weak"], event["marker"]]
	lab.text = "LAB / %s / public input; native Forward+ / player HP arranged\nphase=%d HP=%d state=%s goal=%s hits=%d\n%s" % [label_mode, boss.get("_phase"), boss.health.current, boss.fsm.current, stage, hits.size(), last]


func _exit_tree() -> void:
	_release()
