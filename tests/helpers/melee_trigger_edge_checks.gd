extends RefCounted
## Public analog input, inspecting only the command latch; not physical-pad verification.
static func run(s: EnemySuiteBase) -> void:
	await s.open_level(10.0)
	var player := s.level.player
	player.loadout.equip(load("res://data/weapons/melee/melee_blade.tres"))
	var commands := player.melee.commands
	# Hold the actor still so no attack consumes the command between events.
	var mode := player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_axis(0.0)
	commands.clear()
	_axis(0.9)
	s.check(commands.remaining() > 0.0, "trigger threshold crossing queues one melee command")
	commands.consume()
	var repeated := false
	for value: float in [0.92, 0.8, 1.0, 0.85]:
		_axis(value)
		repeated = repeated or commands.remaining() > 0.0
		commands.consume()
	s.check(not repeated, "held analog trigger motion never requeues an already consumed melee press")
	_axis(0.0)
	_axis(0.95)
	s.check(commands.remaining() > 0.0, "releasing and pressing the trigger queues the next melee command")
	commands.consume()
	s.runner.get_tree().paused = true
	_axis(0.0)
	s.runner.get_tree().paused = false
	_axis(0.95)
	s.check(commands.remaining() > 0.0, "a trigger released during pause accepts its next real press")
	_axis(0.0)
	commands.clear()
	InputBindings.clear_held_inputs()
	player.process_mode = mode
	await s.end_level(s.level)

static func _axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
