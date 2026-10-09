extends Node2D
## Actual NE218 borrowed EnemyData appearance; evidence of failure, not a replacement.
func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[1])
	var bg := ColorRect.new()
	bg.color = Color(0.38,0.38,0.38,1)
	bg.size = Vector2(640,360)
	add_child(bg)
	var label := Label.new()
	label.position = Vector2(8,8)
	label.text = "watchdog / actual EnemyData / rig_skin=warden / FAIL NE218 quadruped"
	label.scale = Vector2(0.7,0.7)
	add_child(label)
	var data := load("res://data/enemies/watchdog.tres") as EnemyData
	for face: int in [-1,1]:
		var dog := data.behavior.new() as Enemy
		dog.configure(data)
		dog.position = Vector2(320,280)
		dog.facing = face
		add_child(dog)
		dog.set_physics_process(false)
		for frame in 120:
			dog._drive_rig(1.0/60.0)
		for wait_frame in 4:
			await get_tree().process_frame
		var path := "res://pm/Nest-Egg/images/NE-90-cloud-creatures/watchdog-borrowed-warden-dormant-frame119-face%d-zoom1.png" % face
		var image := get_viewport().get_texture().get_image()
		image.save_png(path)
		print("WATCHDOG_FAIL native_size=",image.get_size()," face=",face," state=",dog.fsm.current," rig=",dog.rig != null," PartCreature=",dog.creature != null," data=",data.resource_path)
		dog.free()
	get_tree().quit()
