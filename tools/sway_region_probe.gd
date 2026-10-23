extends Node2D
## 開發工具（NE-257）：只動一個區域擺動，量它在畫面上實際移動多少，並輸出並排對照圖。
## 用法：godot --path . res://tools/sway_region_probe.tscn -- --out=/絕對路徑/檔名.png [--skin=rin] [--region=chest_follow]
##   [--angles=-0.08,0,0.08] [--zoom=1.92] [--left]
## 其他擺動全部固定在 0，所以差異只來自這一個區域；--zoom 是關卡鏡頭倍率（畫面再被 640×360 → 1280×720 放大兩倍）。
## 結果：PNG（每個角度一格＋與 0 度的差異放大圖）與同名 .json（每個角度改變的像素數、改變範圍）。
## 這是固定角度的靜態量測，不是自然動態驗收；自然動態看 tools/rig_preview.tscn 的 --seq。
## --curves：不截圖，改用真實輸入序列（站→走→跑→急停、起跳→落地、衝刺、轉身）在 30 與 60 更新率下模擬，
##   輸出每個擺動（頭髮、衣襬、胸口）在每段的峰值角度與停下所需時間到 --out 指定的 .json（可無頭執行）。
## --strip=stop|jump|land|dash|turn：真實輸入序列的連續影格（角色固定在畫面中央、空手，--weapon=外觀 可換）。
##   上排是實際畫面，中排是同一輸入但這個區域固定在 0 的對照，下排是兩者差異放大；--left 朝左、--zoom 換倍率。

var _out := ""
var _skin := "rin"
var _region := "chest_follow"
var _angles: PackedFloat32Array = [-0.08, 0.0, 0.08]
var _zoom := 1.92
var _left := false
var _rigs: Array[CharacterRig] = []
var _cell := 640
var _curves := false
var _strip := ""
var _weapon := ""
var _base_facing := 1
## --strip 的取樣時間（事件後幾秒）。
const STRIP_TIMES := [0.0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.45, 0.8]
## --curves 的序列：每段是 [名稱, 秒數, 水平速度, 事件]；事件在該段第一格送出。
const CURVE_SEGMENTS := [
	["stand", 2.0, 0.0, ""], ["walk", 2.0, 70.0, ""], ["run", 2.0, 150.0, ""], ["stop", 2.0, 0.0, ""],
	["jump", 0.84, 150.0, "jump"], ["land", 2.0, 0.0, "land"], ["dash", 0.4, 360.0, "dash"], ["after_dash", 2.0, 0.0, ""],
	["run_again", 1.0, 150.0, ""], ["turn", 2.0, -150.0, ""], ["settle", 2.0, 0.0, ""],
]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--skin="):
			_skin = arg.trim_prefix("--skin=")
		elif arg.begins_with("--region="):
			_region = arg.trim_prefix("--region=")
		elif arg.begins_with("--angles="):
			_angles = PackedFloat32Array(Array(arg.trim_prefix("--angles=").split(",")).map(func(v: String) -> float: return float(v)))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--left":
			_left = true
		elif arg == "--curves":
			_curves = true
		elif arg.begins_with("--strip="):
			_strip = arg.trim_prefix("--strip=")
		elif arg.begins_with("--weapon="):
			_weapon = arg.trim_prefix("--weapon=")
	if _out.is_empty():
		push_error("[sway_region_probe] 需要 --out=")
		get_tree().quit(1)
		return
	if _curves:
		_run_curves.call_deferred()
		return
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.2))
	if not _strip.is_empty():
		_run_strip.call_deferred()
		return
	var light := DirectionalLight2D.new()
	light.energy = 0.0
	add_child(light)
	# 每格寬度取整數畫布像素，角色放在格子正中的整數位置：各格只差在擺動角度，不會因小數位置取樣不同。
	_cell = floori(640.0 / maxf(1, _angles.size()))
	for i in _angles.size():
		var holder := Node2D.new()
		holder.position = Vector2(_cell * i + _cell / 2, 300)
		holder.scale = Vector2.ONE * _zoom
		add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		if not rig.setup(_skin):
			push_error("[sway_region_probe] 角色 %s 建不起來" % _skin)
			get_tree().quit(1)
			return
		rig.set_weapon("")
		_rigs.append(rig)
	_capture.call_deferred()


func _capture() -> void:
	var input := RigInput.new()
	input.facing = -1 if _left else 1
	input.aim_dir = Vector2.LEFT if _left else Vector2.RIGHT
	input.two_handed = false
	for tick in 90:
		for rig in _rigs:
			rig.animate(1.0 / 60.0, input)
	var known := false
	for i in _rigs.size():
		var rig := _rigs[i]
		for spring: Dictionary in rig.springs():
			if spring.has("warp"):
				rig.set_sway(StringName(str(spring["id"])), 0.0)
		known = rig._sway_targets.has(StringName(_region))
		rig.set_sway(StringName(_region), _angles[i])
	if not known:
		push_error("[sway_region_probe] %s 沒有擺動區域 %s" % [_skin, _region])
		get_tree().quit(1)
		return
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	var cell := _cell * image.get_width() / 640
	var zero := _angles.find(0.0)
	var rows: Array[Dictionary] = []
	var sheet := Image.create(image.get_width(), image.get_height() * 2, false, Image.FORMAT_RGBA8)
	sheet.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	for i in _angles.size():
		var changed := 0
		var bounds := Rect2i()
		if zero >= 0:
			for y in image.get_height():
				for x in cell:
					var a := image.get_pixel(i * cell + x, y)
					var b := image.get_pixel(zero * cell + x, y)
					var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
					var v := clampf(d * 6.0, 0.0, 1.0)
					sheet.set_pixel(i * cell + x, image.get_height() + y, Color(v, v, v))
					if d > 0.06:
						changed += 1
						bounds = Rect2i(x, y, 1, 1) if bounds.size == Vector2i.ZERO else bounds.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
		rows.append({"angle": _angles[i], "changed_pixels": changed, "changed_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
	sheet.save_png(_out)
	var file := FileAccess.open(_out + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"kind": "fixed region angle, other sway regions at 0; not a motion test", "skin": _skin, "region": _region,
			"zoom": _zoom, "window": [image.get_width(), image.get_height()], "facing": -1 if _left else 1,
			"adapter": RenderingServer.get_video_adapter_name(), "rows": rows}, "\t") + "\n")
	print("saved ", _out)
	get_tree().quit()


func _run_curves() -> void:
	var result := {"kind": "natural input sequence through HumanoidAnimator; spring angles only, no rendering", "skin": _skin, "fps": {}}
	for fps: int in [60, 30]:
		var holder := Node2D.new()
		add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		if not rig.setup(_skin):
			push_error("[sway_region_probe] 角色 %s 建不起來" % _skin)
			get_tree().quit(1)
			return
		var animator: HumanoidAnimator = rig.animator
		var input := RigInput.new()
		input.run_speed = 150.0
		input.aim_dir = Vector2.RIGHT
		var dt := 1.0 / fps
		var segments: Array[Dictionary] = []
		for segment: Array in CURVE_SEGMENTS:
			var speed := float(segment[2])
			input.facing = -1 if speed < 0.0 else 1
			input.aim_dir = Vector2(input.facing, 0)
			input.velocity = Vector2(speed, 0.0)
			input.on_floor = segment[0] != "jump"
			input.dashing = segment[0] == "dash"
			var peaks := {}
			var peak_at := {}
			var settled := {}
			var ticks := roundi(float(segment[1]) * fps)
			for tick in ticks:
				input.jumped = tick == 0 and segment[3] == "jump"
				input.landed = 0.75 if tick == 0 and segment[3] == "land" else 0.0
				input.dash_started = tick == 0 and segment[3] == "dash"
				if segment[0] == "jump":
					input.velocity.y = -420.0 + 1000.0 * tick * dt
				else:
					input.velocity.y = 0.0
				rig.animate(dt, input)
				for spring: Dictionary in animator._springs:
					var key := animator._spring_key(spring)
					var offset := absf(float(animator._spring_angle[key]) - float(spring.get("rest", 0.0)))
					if offset > float(peaks.get(key, 0.0)):
						peaks[key] = offset
						peak_at[key] = snappedf((tick + 1) * dt, 0.001)
					var still := offset < 0.002 and absf(float(animator._spring_velocity[key])) < 0.05
					if not still:
						settled.erase(key)
					elif not settled.has(key):
						settled[key] = snappedf((tick + 1) * dt, 0.001)
			var row := {"segment": segment[0], "seconds": segment[1], "peak": {}, "peak_at": {}, "still_after": {}}
			for key: Variant in peaks.keys():
				row["peak"][str(key)] = snappedf(float(peaks[key]), 0.0001)
				row["peak_at"][str(key)] = peak_at.get(key, null)
				row["still_after"][str(key)] = settled.get(key, null)
			segments.append(row)
		result["fps"][str(fps)] = segments
		holder.queue_free()
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("[sway_region_probe] 寫不進 %s" % _out)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("saved ", _out)
	get_tree().quit()


## 依序列設定這一格的輸入；t 是事件後的秒數（負的＝事件前）。
func _strip_input(input: RigInput, t: float, previous: float) -> void:
	input.on_floor = true
	input.dashing = false
	input.velocity = Vector2.ZERO
	input.jumped = false
	input.landed = 0.0
	input.dash_started = false
	match _strip:
		"stop":
			input.velocity.x = 150.0 if t < 0.0 else 0.0
		"jump":
			input.velocity.x = 0.0
			if t >= 0.0 and t < 0.84:
				input.on_floor = false
				input.velocity.y = -420.0 + 1000.0 * t
			input.jumped = previous < 0.0 and t >= 0.0
		"land":
			if t < 0.0:
				input.on_floor = false
				input.velocity.y = 420.0
			input.landed = 0.75 if previous < 0.0 and t >= 0.0 else 0.0
		"dash":
			input.velocity.x = 360.0 if t >= 0.0 and t < 0.17 else 0.0
			input.dashing = t >= 0.0 and t < 0.17
			input.dash_started = previous < 0.0 and t >= 0.0
		"turn":  # 朝原方向跑，時間 0 轉身往回跑（面向跟著翻）
			input.velocity.x = 150.0 if t < 0.0 else -150.0
	input.velocity.x *= _base_facing
	if _strip == "turn":
		input.facing = _base_facing * (1 if t < 0.0 else -1)
		input.aim_dir = Vector2(input.facing, 0.6).normalized()


func _run_strip() -> void:
	if not _strip in ["stop", "jump", "land", "dash", "turn"]:
		push_error("[sway_region_probe] --strip=%s 不存在（stop、jump、land、dash、turn）" % _strip)
		get_tree().quit(1)
		return
	var pair: Array[CharacterRig] = []
	for i in 2:
		var holder := Node2D.new()
		holder.position = Vector2(160 + 320 * i, 300)
		holder.scale = Vector2.ONE * _zoom
		add_child(holder)
		var rig := CharacterRig.new()
		holder.add_child(rig)
		if not rig.setup(_skin):
			push_error("[sway_region_probe] 角色 %s 建不起來" % _skin)
			get_tree().quit(1)
			return
		rig.set_weapon(_weapon)
		pair.append(rig)
	if not pair[0]._sway_targets.has(StringName(_region)):
		push_error("[sway_region_probe] %s 沒有擺動區域 %s" % [_skin, _region])
		get_tree().quit(1)
		return
	var input := RigInput.new()
	_base_facing = -1 if _left else 1
	input.facing = _base_facing
	input.aim_dir = Vector2(input.facing, 0.6).normalized()
	input.two_handed = not _weapon.is_empty()
	input.run_speed = 150.0
	input.relaxed = true
	var dt := 1.0 / 60.0
	var t := -2.0
	var frames: Array[Image] = []
	var angles: Array[float] = []
	var facings: Array[int] = []
	var centers: Array = []
	for at: float in STRIP_TIMES:
		while t < at - 0.0001:
			var previous := t
			t += dt
			_strip_input(input, t, previous)
			for rig in pair:
				rig.animate(dt, input)
			pair[1].set_sway(StringName(_region), 0.0)
		angles.append(float(pair[0].animator._spring_angle[StringName(_region)]))
		facings.append(input.facing)
		centers.append([pair[0].bone(&"chest").global_position, pair[1].bone(&"chest").global_position])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		frames.append(preload("res://tools/viewport_capture.gd").image(get_viewport()))
	# 裁切：以胸骨在畫面上的位置為中心（兩隻角色同一相對位置）。
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var crop := Vector2i(220, 260)
	var sheet := Image.create(crop.x * frames.size(), crop.y * 3, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		for row in 2:
			# 胸骨在背側上方；往前、往下挪到胸口中央（依面向與倍率）。
			var center := to_screen * ((centers[i][row] as Vector2) + Vector2(4.0 * facings[i], -6.0) * _zoom)
			var origin := Vector2i(center) - crop / 2
			var cell := frames[i].get_region(Rect2i(origin, crop))
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, crop), Vector2i(i * crop.x, row * crop.y))
		for y in crop.y:
			for x in crop.x:
				var a := sheet.get_pixel(i * crop.x + x, y)
				var b := sheet.get_pixel(i * crop.x + x, crop.y + y)
				var v := clampf(maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 6.0, 0.0, 1.0)
				sheet.set_pixel(i * crop.x + x, crop.y * 2 + y, Color(v, v, v))
	sheet.save_png(_out)
	var file := FileAccess.open(_out + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"kind": "natural input sequence; row 1 actual, row 2 same input with this region held at 0, row 3 difference x6",
			"skin": _skin, "region": _region, "sequence": _strip, "zoom": _zoom, "facing": input.facing, "weapon": _weapon,
			"times": STRIP_TIMES, "region_angle": angles, "adapter": RenderingServer.get_video_adapter_name()}, "\t") + "\n")
	print("saved ", _out)
	get_tree().quit()
