extends "res://tools/bg55_enemy_readability_probe.gd"
## Recheck the original fog counterfactual with real support and owner updates.


func _ready() -> void:
	var original := FileAccess.get_file_as_string("res://data/lighting/market.tres")
	var authored := FileAccess.get_file_as_string("res://data/lighting/lounge_front.tres")
	var expected := original.replace("id = &\"market\"", "id = &\"lounge_front\"").replace("fog_density = 1.0", "fog_density = 0.5")
	if expected != authored:
		push_error("[BG48] Original fog reference differs beyond profile id/fog; review data/lighting/market.tres and lounge_front.tres")
		get_tree().quit(2)
		return
	_reference55 = "res://data/lighting/market.tres"
	super._ready()
	for node in get_children():
		if node is CanvasLayer:
			for child in node.get_children():
				if child is Label:
					child.text = child.text.replace("BG55", "BG48 / GROUNDED FOG CONTROL")


func _measure(level: Level, world: Rect2) -> Dictionary:
	var result := await super._measure(level, world)
	result["bg48"] = {"kind": "same live geometry and simulation; original fog 1.0 versus authored fog 0.5; not historical checkout",
		"source_sha256": FileAccess.get_sha256("res://tools/bg48_grounded_readability_probe.gd")}
	return result


func _tour(level_id: String) -> bool:
	if level_id != "ch2_lounge_front":
		printerr("[BG48] Unsupported fog comparison level: " + level_id)
		return false
	return await super._tour(level_id)
