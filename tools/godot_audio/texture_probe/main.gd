extends Node
## No game autoloads, imported textures or background scene loading.
const BATCHES := 8
const PER_BATCH := 1024
var workers_count := 0
var output := ""
var mode := ""
var checks := 0
var failures: Array[String] = []
var created := 0
var released := 0

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	workers_count = 1 if mode == "single" else 4 if mode == "four" else 0
	if workers_count == 0 or not output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Texture control requires single|four and an absolute owned output directory")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value and failures.size() < 32:
		failures.append(label)
		print("FAIL ", label)

func _allocate(image: Image, count: int) -> Array[RID]:
	var rids: Array[RID] = []
	for i in count:
		rids.append(RenderingServer.texture_2d_create(image))
	return rids

func _color(index: int) -> Color:
	return Color8(32 + index * 48, 64, 128)

func _run() -> void:
	for batch in BATCHES:
		var workers: Array[Thread] = []
		for i in workers_count:
			var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
			image.fill(_color(i))
			var worker := Thread.new()
			var status := worker.start(_allocate.bind(image, PER_BATCH / workers_count))
			_check(status == OK, "bounded texture worker starts")
			if status == OK:
				workers.append(worker)
		var all := {}
		for i in workers.size():
			var rids: Array = workers[i].wait_to_finish()
			for rid: RID in rids:
				created += 1
				_check(rid.is_valid() and not all.has(rid), "concurrent original texture allocation has a unique valid RID")
				if rid.is_valid():
					all[rid] = _color(i)
		# Worker calls queue initialization on the main rendering server.
		await get_tree().process_frame
		await get_tree().process_frame
		for rid: RID in all:
			var actual := RenderingServer.texture_2d_get(rid)
			_check(actual != null and actual.get_size() == Vector2i(2, 2) and actual.get_pixel(0, 0).is_equal_approx(all[rid]), "actual texture readback retains its own worker's pixels")
			RenderingServer.free_rid(rid)
			released += 1
		await get_tree().process_frame
		await get_tree().process_frame
		print("TEXTURE_BATCH ", batch, " unique=", all.size(), " failures=", failures.size())
		if not failures.is_empty():
			break
	_check(created == BATCHES * PER_BATCH and released == created, "every bounded original texture allocation is released")
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write owned texture result: " + error_string(FileAccess.get_open_error()))
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify({"mode":mode,"workers":workers_count,"created":created,"released":released,"checks":checks,"failures":failures}, "  "))
	file.close()
	print("TEXTURE_RESULT ", mode, " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
