extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	var level := Level.new()
	level.configure(load("res://data/levels/ch1_pawnshop.tres"))
	add_child(level)
	for tick in 15: await get_tree().physics_frame
	Input.action_press(&"move_right")
	var logged := false
	for tick in 600:
		await get_tree().physics_frame
		var p := level.player
		if p.is_on_floor() and p.position.x > 1100 and absf(p.velocity.x) < 0.1 and not logged:
			logged = true
			print("BLOCK ",p.position," input ",Input.get_axis(&"move_left", &"move_right"))
			for i in p.get_slide_collision_count():
				var collision := p.get_slide_collision(i)
				var body := collision.get_collider() as Node
				print("COLLIDER ",body.name," class ",body.get_class()," script ",body.get_script()," point ",collision.get_position()," normal ",collision.get_normal())
				for child in body.get_children():
					if child is CollisionShape2D: print("SHAPE ",child.shape," rect ",child.shape.get_rect()," pos ",child.global_position)
			Input.action_press(&"jump")
			for frame in 35:
				await get_tree().physics_frame
				if frame % 5 == 0: print("JUMP ",frame," pos ",p.position," velocity ",p.velocity," input ",Input.get_axis(&"move_left", &"move_right"))
			Input.action_release(&"jump")
		if logged and p.position.x > 1250: break
	Input.action_release(&"move_right")
	print("END ",level.player.position)
	level.queue_free()
	for tick in 6: await get_tree().process_frame
	await AudioRelease.settle(get_tree())
	get_tree().quit()
