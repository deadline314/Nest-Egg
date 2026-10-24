extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var source_path := ""
	var output_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="): source_path = arg.trim_prefix("--src=")
		if arg.begins_with("--out="): output_path = arg.trim_prefix("--out=")
	var source := Image.load_from_file(source_path)
	if source == null or output_path.is_empty():
		push_error("normal probe requires a valid source and output")
		get_tree().quit(1)
		return
	var result := NormalMapMaker.make(source)
	var error := result.save_png(output_path)
	print("NORMAL_PROBE ", JSON.stringify({"source":source_path,"output":output_path,"error":error,"size":[result.get_width(),result.get_height()]}))
	get_tree().quit(0 if error == OK else 1)
