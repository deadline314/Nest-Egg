extends Node
## Actual SettingsScreen with the same new public-event checks; no hardware claim.

class SettingsSuite extends TestSuite:
	func run() -> void:
		await preload("res://tests/helpers/settings_device_checks.gd").run(self)

var _out := ""
var _checks := 0
var _failures := 0
var _rows: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _out = argument.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(LightKit.create_environment())
	await SettingsSuite.new(self).run()
	var file := FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"rows":_rows,"scope":"Actual isolated SettingsScreen; same final helper as UI suite. Capture target/tab/focus arranged, real keyboard/mouse/synthetic999 events. Not Main routing, a full chapter, physical controller or hardware vibration acceptance."},"  "))
	print("SETTINGS_DEVICE_RESULT checks=%d failures=%d" % [_checks,_failures])
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if _failures else 0)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value: _failures += 1
	print("SETTINGS_CHECK %s %s" % [value,description])
	var settings: SettingsScreen
	for child in get_children():
		if child is SettingsScreen: settings = child
	if settings == null: return
	_rows.append({"pass":value,"description":description,"gamepad":InputBindings.using_gamepad,"device":InputBindings.active_device,"tab":settings._tabs.current_tab,"rules":settings._hold_rule_labels[0].text,"controller_note":settings._controller_note.text,"jump_key":InputBindings.get_code(&"jump",0),"jump_joy":InputBindings.get_joy_button(&"jump"),"capturing":settings._capturing,"status":settings._status.text})
	var name := ""
	if description.begins_with("controller page note follows"): name = "controller-page"
	elif description.begins_with("mouse restores keyboard"): name = "keyboard-page"
	elif description.begins_with("short B retains"): name = "short-b-bound"
	elif description.begins_with("long B cancels"): name = "long-b-cancelled"
	elif description.begins_with("consumed new keyboard binding"): name = "keyboard-bound"
	elif description.begins_with("capture instructions identify"): name = "capture-prompt-%d" % _checks
	if not name.is_empty():
		var captured := preload("res://tools/viewport_capture.gd").image(get_viewport())
		print("saved %s %s" % [name,error_string(captured.save_png(_out.path_join(name+".png")))])
