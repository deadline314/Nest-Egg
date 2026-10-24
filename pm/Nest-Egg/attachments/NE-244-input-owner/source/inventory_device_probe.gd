extends "res://pm/Nest-Egg/attachments/NE-254-pickup-reach/source/pickup_reach_probe.gd"
## Same new input checks, run against the real Main-owned inventory.

class InventorySuite extends TestSuite:
	var target: Level
	func run() -> void:
		await preload("res://tests/helpers/inventory_device_checks.gd").run(self)
	func start_level(_data: LevelData, _difficulty_index := 1) -> Level:
		return target
	func end_level(_level: Level) -> void:
		await runner.get_tree().process_frame

var _rows: Array[Dictionary] = []

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.story_autosave = false
	Story.auto_skip = true
	await open_arena("", 93)
	await clear_enemies()
	var suite := InventorySuite.new(self)
	suite.target = level
	await suite.run()
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":_rows,"scope":"Same helper on actual Main-owned formal-street inventory. Main route/player position arranged; NPCs/enemies/encounters and story trigger scan isolated, synthetic keyboard/mouse/pad999. No full chapter or hardware acceptance."},"  "))
	print("INVENTORY_DEVICE_RESULT checks=%d failures=%d" % [checks, failures])
	_main.call("_quit", 1 if failures else 0)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures += 1
	print("INVENTORY_CHECK %s %s" % [value, description])
	var bag: InventoryScreen = level._inventory if is_instance_valid(level) else null
	_rows.append({"pass":value,"description":description,"gamepad":InputBindings.using_gamepad,"device":InputBindings.active_device,"legend":bag._legend_label.text if bag != null else "","page":bag._current if bag != null else -1})
	var name := ""
	if description.begins_with("consumed RB immediately"): name = "controller-tab"
	elif description.begins_with("mouse motion restores"): name = "mouse-return"
	elif description.begins_with("unconsumed controller event"): name = "unconsumed-controller"
	elif description.begins_with("first controller inventory press"): name = "controller-open"
	elif description.begins_with("holding the stick repeats"): name = "stick-repeat"
	if not name.is_empty(): capture(name)
