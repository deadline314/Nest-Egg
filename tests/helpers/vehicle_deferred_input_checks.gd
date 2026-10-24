extends RefCounted
## Public polling pulse, with combat stop deferred to the step boundary.

class DeferredStop extends Node:
	var actors: Array = []
	var stopped := false

	func _ready() -> void:
		process_physics_priority = -50

	func _physics_process(_delta: float) -> void:
		if not stopped and Input.is_action_pressed(&"interact"):
			stopped = true
			Fx.freeze.call_deferred(actors, 0.08)


static func run(s: TestSuite) -> void:
	var level := await s.start_level(load("res://data/levels/level_01.tres") as LevelData)
	for node in level.find_children("*", "", true, false):
		if node is Enemy:
			node.set_physics_process(false)
	var player := level.player
	var vehicle: Vehicle
	for node in s.runner.get_tree().get_nodes_in_group(&"vehicles"):
		if level.is_ancestor_of(node):
			vehicle = node
			break
	s.check(vehicle != null, "deferred-step stop uses the authored vehicle")
	if vehicle == null:
		await s.end_level(level)
		return
	Fx.thaw_all()
	player.global_position = vehicle.global_position + Vector2(-8, -2)
	player.velocity = Vector2.ZERO
	await s.frames(2)
	var stop := DeferredStop.new()
	stop.actors = [player, vehicle]
	level.add_child(stop)
	Input.action_press(&"interact")
	await s.frames(1)
	Input.action_release(&"interact")
	await s.frames(2)
	s.check(stop.stopped and Fx.is_frozen(player) and Fx.is_frozen(vehicle), "deferred-step command keeps both actual actors stopped")
	s.check(player.state == Player.State.MOUNTED and vehicle.driver == player, "interaction survives a stop at the physics-step boundary before the actor receives its input edge")
	stop.queue_free()
	Fx.thaw_all()
	if player.state != Player.State.MOUNTED:
		player.mount_vehicle(vehicle)  # The independent exit case retains the failed mount above.
	await s.frames(24)
	stop = DeferredStop.new()
	stop.actors = [player, vehicle]
	level.add_child(stop)
	Input.action_press(&"interact")
	await s.frames(1)
	Input.action_release(&"interact")
	await s.frames(2)
	s.check(stop.stopped and Fx.is_frozen(player) and Fx.is_frozen(vehicle), "deferred-step exit preserves both actor stops")
	s.check(player.state == Player.State.NORMAL and vehicle.driver == null, "exit survives a stop at the physics-step boundary before the vehicle receives its input edge")
	stop.queue_free()
	Fx.thaw_all()
	Input.action_release(&"interact")
	if player.state == Player.State.MOUNTED:
		player.dismount_vehicle(false) # Independent hold setup; the failed exit remains failed.
	await s.frames(24)
	player.global_position = vehicle.global_position + Vector2(-8, -2)
	player.velocity = Vector2.ZERO
	Input.action_press(&"interact")
	await s.frames(24)
	Fx.freeze([player, vehicle], 0.5)
	await s.frames(3)
	s.check(player.state == Player.State.MOUNTED and vehicle.driver == player, "holding an already consumed normal mount never exits during a later stop")
	Input.action_release(&"interact")
	Fx.thaw_all()
	if player.state == Player.State.MOUNTED:
		player.dismount_vehicle(false) # Independent expired-edge setup after the hold assertion.
	await s.frames(24)
	player.global_position = vehicle.global_position + Vector2(-100, -2)
	player.velocity = Vector2.ZERO
	Input.action_press(&"interact")
	await s.frames(1)
	Input.action_release(&"interact")
	await s.frames(4)
	Fx.freeze([player, vehicle], 0.5)
	player.global_position = vehicle.global_position + Vector2(-8, -2)
	await s.frames(2)
	s.check(player.state == Player.State.NORMAL and vehicle.driver == null, "an expired normal interaction never replays when a later stop begins in mount range")
	Fx.thaw_all()
	await s.end_level(level)
