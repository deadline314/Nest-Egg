extends Node
func _ready() -> void:
	print("EXTERNAL_SCENE autoload=", is_instance_valid(GameState), " story=", is_instance_valid(Story))
	get_tree().quit()
