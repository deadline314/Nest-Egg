extends Node
## Read the first real player step, after its control logic and before idle visuals.
var player: Player
var _sample: Dictionary = {}
var _pending := false

func _ready() -> void:
	process_physics_priority = player.process_physics_priority + 1

func capture() -> Dictionary:
	if _pending or not is_inside_tree() or not is_instance_valid(player): return {}
	_pending = true
	_sample = {}
	var tree := get_tree()
	for i in 120:
		if not _sample.is_empty() or not is_inside_tree(): break
		await tree.physics_frame
	_pending = false
	return _sample

func _physics_process(_delta: float) -> void:
	if _pending and _sample.is_empty() and is_instance_valid(player):
		_sample = {"blocking": player.is_blocking, "parry": player.is_parry_window(),
			"window": player.parry_window_length(), "extension": player._visual._shield.extension,
			"block_time": player._block_time, "physics_frame": Engine.get_physics_frames(),
			"process_frame": Engine.get_process_frames()}
