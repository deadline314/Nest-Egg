extends SceneTree
func _initialize() -> void:
	print("EXTERNAL_PROBE autoload=", root.get_node_or_null("GameState") != null, " project=", ProjectSettings.globalize_path("res://"))
	quit()
