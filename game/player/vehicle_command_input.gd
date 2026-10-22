extends Node
## Local hitstop suspends actor simulation, but a nearby vehicle interaction
## still accepts one input edge. Normal, paused and locked routes stay unchanged.
var player: Player
var _held := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released(&"interact"):
		_held = false
	elif event.is_action_pressed(&"interact") and not event.is_echo() and not _held:
		# Leave the normal event to the actor; capture only a suspended owner.
		if _dispatch_frozen():
			_held = true


func _physics_process(_delta: float) -> void:
	var pressed := Input.is_action_pressed(&"interact")
	if pressed and not _held:
		_dispatch_frozen()
	_held = pressed


func _dispatch_frozen() -> bool:
	if not is_instance_valid(player) or get_tree().paused or GameplayLock.is_locked():
		return false
	if player.state == Player.State.NORMAL and Fx.is_frozen(player):
		player._try_mount()
		return true
	if player.state == Player.State.MOUNTED and is_instance_valid(player.mounted_vehicle) and Fx.is_frozen(player.mounted_vehicle):
		player.mounted_vehicle.request_dismount()
		return true
	return false
