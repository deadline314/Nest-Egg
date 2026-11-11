extends "res://tools/ch1_readability_check.gd"
## Corrected ContrastProbe remeasurement, controlled native fixture only.
func _ready() -> void:
	Settings.use_storage("user://bg53_ch1_settings.cfg")
	Settings.set_brightness(0.5)
	seed(531111)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "NATIVE FORWARD+ / STATIONARY READABILITY LAB / SCRIPTED AIM RIGHT"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)
	super._ready()

func _process(delta: float) -> void:
	super._process(delta)
	for node in get_tree().get_nodes_in_group(&"player"):
		if node is Player:
			AimInput.set_virtual_gamepad(node, true)

func _check_level(path: String, spots: Array, enemy_path := "res://data/enemies/grunt.tres") -> void:
	await super._check_level(path, spots, enemy_path)
