extends ScenarioBase
## NE-224：在正式關卡場地與光影下（Forward+ 實機），用正式的 CharacterRig.animate 連續播放 30 秒，
## 檢查眨眼與衣襬。不指定眼睛狀態、不改彈簧設定；有衣襬骨頭的角色來回走動，其餘站著待機與說話輪替。
## 用法：godot --path . res://pm/Nest-Egg/attachments/NE-224-scene-check/capture.tscn -- --out=<絕對目錄> [--empty] [--skins=a,b,c] [--lighting=res://data/lighting/x.tres]
## 量每格耗時時加引擎參數 --disable-vsync；--empty 不放角色，同一個場景當對照。

var SKINS: PackedStringArray = ["rin", "old_k", "nurse", "night_worker", "repairman_chen", "resident", "ah_po", "wataru", "mei", "egret", "ali"]
const SECONDS := 30.0
const SHOTS: Array[float] = [4.0, 13.0, 22.0]

var rigs: Array[CharacterRig] = []
var inputs: Array[RigInput] = []
var rows: Array[Dictionary] = []
var elapsed := 0.0
var frames := 0
var running := false
var empty := false
var lighting := "res://data/lighting/alley_calm.tres"
var frame_ms: PackedFloat32Array = []
var last_usec := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--empty":
			empty = true
		elif arg.begins_with("--lighting="):
			lighting = arg.trim_prefix("--lighting=")
		elif arg.begins_with("--skins="):
			SKINS = arg.trim_prefix("--skins=").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await run()
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	frame_ms.sort()
	var total := 0.0
	for ms in frame_ms:
		total += ms
	file.store_string(JSON.stringify({"seconds": elapsed, "frames": frames, "frame_ms": {"average": total / maxf(1.0, frame_ms.size()),
		"p95": frame_ms[int(frame_ms.size() * 0.95)], "p99": frame_ms[int(frame_ms.size() * 0.99)], "max": frame_ms[frame_ms.size() - 1]}, "hdr_2d": get_viewport().use_hdr_2d, "lighting": lighting,
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "adapter": RenderingServer.get_video_adapter_name(), "rows": rows}, "\t"))
	file.close()
	await finish()
	get_tree().quit()


func run() -> void:
	seed(22401)
	await open_arena(lighting, 3.0)
	player.set_physics_process(false)
	level.camera.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	level.camera.limit_left = -100000
	level.camera.limit_right = 100000
	level.camera.zoom = Vector2.ONE * 1.6
	level.camera.global_position = Vector2((7.0 + (SKINS.size() - 1) * 1.1) * 16.0, FLOOR_Y - 50.0)
	for i in (0 if empty else SKINS.size()):
		var rig := CharacterRig.new()
		level.add_child(rig)
		rig.position = Vector2((7.0 + i * 2.2) * 16.0, FLOOR_Y)
		var ok := rig.setup(SKINS[i], "npc")
		var input := RigInput.new()
		input.two_handed = false
		rigs.append(rig)
		inputs.append(input)
		rows.append({"skin": SKINS[i], "loaded": ok, "has_hem": rig.has_bone(&"coat_1"), "eye": "open", "blinks": 0, "closed_frames": 0,
			"hem_min": 0.0, "hem_max": 0.0, "home_x": rig.position.x})
	running = true
	last_usec = Time.get_ticks_usec()
	for t in SHOTS:
		await wait(t - elapsed)
		capture("scene_%02ds" % int(t))
	await wait(SECONDS - elapsed)
	running = false


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	frames += 1
	var now := Time.get_ticks_usec()
	frame_ms.append((now - last_usec) / 1000.0)
	last_usec = now
	for i in rigs.size():
		var rig := rigs[i]
		var input := inputs[i]
		var row := rows[i]
		input.on_floor = true
		input.talking = fmod(elapsed + i, 10.0) > 6.0
		if row["has_hem"]:  # 走 0.5 秒、停 1.5 秒，每兩秒換方向
			var phase := fmod(elapsed, 4.0)
			var dir := 1.0 if phase < 2.0 else -1.0
			var speed := 55.0 if fmod(phase, 2.0) < 0.5 else 0.0
			input.facing = int(dir)
			input.velocity = Vector2(dir * speed, 0.0)
			input.talking = false
			rig.position.x += dir * speed * delta
		rig.animate(delta, input)
		var eye := str(rig._eye_state)
		if eye != row["eye"] and eye == "closed":
			row["blinks"] = int(row["blinks"]) + 1
		if eye == "closed":
			row["closed_frames"] = int(row["closed_frames"]) + 1
		row["eye"] = eye
		if row["has_hem"]:
			var spring: float = rig.animator._spring_angle.get(&"coat_1", 0.0)
			row["hem_min"] = minf(row["hem_min"], spring)
			row["hem_max"] = maxf(row["hem_max"], spring)
