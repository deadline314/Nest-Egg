extends Node
const Capture := preload("res://tools/viewport_capture.gd")
var out := ""
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var progression: Node
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print("NE301_NATIVE_CHECK ", value, " ", label)
	if not value: failures.append(label)
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func pickup_ids(level: Level) -> Array[int]:
	var ids: Array[int] = []
	for child in level._entities.get_children():
		if child is Pickup: ids.append(child.get_instance_id())
	return ids
func fresh(level: Level, old: Array[int]) -> Array[Pickup]:
	var result: Array[Pickup] = []
	for child in level._entities.get_children():
		if child is Pickup and not old.has(child.get_instance_id()): result.append(child)
	return result
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	check(Capture.image(get_viewport()).save_png(path) == OK, "native screenshot saved: " + name)
	shots.append(path)
func enemy(level: Level, at: Vector2, credits: int) -> Enemy:
	var data := (load("res://data/enemies/grunt.tres") as EnemyData).duplicate() as EnemyData
	data.credit_value = credits
	data.health_drop_chance = 1.0
	var actor := level._create_enemy(data)
	actor.position = at
	level._entities.add_child(actor)
	actor.set_physics_process(false)
	return actor
func _run() -> void:
	if not out.is_absolute_path() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("NE301 witness requires native Forward+ and absolute --out")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	add_child(LightKit.create_environment())
	var story: Node = get_tree().root.get_node("Story")
	story.auto_skip = true
	var game_state: Node = get_tree().root.get_node("GameState")
	game_state.start_new_run(game_state.difficulties[1])
	progression = get_tree().root.get_node("Progression")
	var level := Level.new()
	level.configure(load("res://data/levels/ch1_street.tres"))
	get_tree().root.add_child(level)
	for actor in get_tree().get_nodes_in_group(&"enemies"): actor.set_physics_process(false)
	await frames(30)
	var player := level.player
	player.set_physics_process(false)
	player.health.setup(10, 0.0)
	player.health.current = 5
	player.health.health_changed.emit(5, 10)
	player.consumables.restore({})
	var origin := player.position
	var initial := pickup_ids(level)
	var credits_before: int = progression.credits
	var credit_actor := enemy(level, origin + Vector2(60, 0), 17)
	var health_actor := enemy(level, origin + Vector2(100, 0), 0)
	credit_actor._drop_credits()
	health_actor._try_drop(false)
	await frames(3)
	var drops := fresh(level, initial)
	check(drops.size() == 2, "actual enemy methods yield one credit and one health reward")
	await shot("NE-301-enemy-drops")
	var box_data := BreakableData.new()
	box_data.id = &"ne301_witness_box"
	box_data.drop_chance = 1.0
	box_data.drops = [ConsumableBag.find(&"med_injector")]
	var box := level._create_prop({"resource": box_data, "cell": Vector2i((origin + Vector2(140, 0)) / 16.0)}) as Breakable
	box.position = origin + Vector2(140, 0)
	level._entities.add_child(box)
	box._on_died(null)
	await frames(5)
	drops = fresh(level, initial)
	check(drops.size() == 3, "actual box broken signal yields its configured consumable once")
	var refs: Array[WeakRef] = []
	for drop in drops: refs.append(weakref(drop))
	await shot("NE-301-box-drop")
	credit_actor.free()
	health_actor.free()
	player.set_physics_process(true)
	Input.action_press(&"move_right")
	for i in 240:
		if player.position.x >= origin.x + 153: break
		if Input.get_action_strength(&"move_right") < 0.5: Input.action_press(&"move_right")
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	await frames(12)
	player.set_physics_process(false)
	check(progression.credits == credits_before + 17, "real movement/body overlap applies credit once")
	check(player.health.current == 7, "real movement/body overlap applies health once")
	check(player.consumables.count(&"med_injector") == 1, "real movement/body overlap applies configured box item once")
	check(refs.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null), "all three actually collected pickup IDs are released")
	await shot("NE-301-collected")
	var source := {}
	for path: String in ["game/pickups/pickup.gd", "game/enemies/enemy.gd", "game/level/level.gd"]:
		source[path] = FileAccess.get_sha256("res://" + path)
	var summary := {"checks": checks, "failures": failures, "shots": shots, "source_shas": source,
		"tool_sha256": FileAccess.get_sha256(get_script().resource_path), "user_data_dir": OS.get_user_data_dir(), "appdata": OS.get_environment("APPDATA"),
		"scope": "Controlled actual ch1_street Level, cloned production grunt data, real source methods and physical movement; not full Main/human play/performance proof",
		"origin": [origin.x,origin.y], "final_position": [player.position.x,player.position.y], "credits_before": credits_before,
		"credits_after": progression.credits, "health": player.health.current, "med_count": player.consumables.count(&"med_injector"),
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "hdr_2d": get_viewport().use_hdr_2d}
	var file := FileAccess.open(out.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"  "))
	file.close()
	level.free()
	await frames(3)
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures.is_empty() else 1)
