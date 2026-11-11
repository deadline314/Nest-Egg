extends "res://tools/bg55_enemy_readability_probe.gd"
## The market entrance now has BG55's published fill profile. Both sides of
## BG48's unrelated fog change must retain that same profile, not undo BG55.


func _ready() -> void:
	super._ready()
	for node in get_children():
		if node is CanvasLayer:
			for child in node.get_children():
				if child is Label and child.text.begins_with("BG55"):
					child.text = "BG48 / RELATED PROFILE UNCHANGED / HELD WORLD / SCRIPTED AIM"


func _tour(level_id: String) -> bool:
	if level_id != "ch2_market_gate":
		printerr("[BG48] Unsupported related profile control: " + level_id)
		return false
	_reference55 = "res://data/lighting/market_gate.tres"
	return await super._tour(level_id)
