extends "res://tools/ch4_relay_probe.gd"

const BRIEFING := "ch4_t_safety_instruction"


func _write() -> void:
	_shots[BRIEFING] = "atropos-pa"
	await super._write()
	_check(_played.has(BRIEFING) and GameState.has_flag(BRIEFED), "the original announcement plays and keeps its durable result")


func _capture(name: String) -> void:
	if name != "atropos-pa" or DisplayServer.get_name() == "headless":
		return
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image.save_jpg(_out_dir.path_join(name + ".jpg"), 0.89) == OK, "captured the captain's portrait in the live announcement")
