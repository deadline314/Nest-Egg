extends ScenarioBase
## 近戰招式的逐格對照表（NE-277），要原生視窗（Forward+ 或軟體 Vulkan）：
##   godot --path . res://tools/melee_move_film.tscn -- --out=<絕對資料夾> [--tag=before|after] [--weapon=maul] [--facing=-1]
## 每把近戰武器的每一招（含升級尾招與按住招式）從頭播到尾，在固定的招式進度各拍一格（預兆、出手、跟隨、收招都有），
## 拼成 <標籤>-<武器>.png：一列一招、一欄一個進度。只用改版前後都有的入口（_start_melee_attack、_melee_attack、
## melee_pose_progress），所以同一支工具也能放在舊版本上拍修前的畫面。

const WEAPONS: PackedStringArray = ["blade", "dagger", "glaive", "maul", "whip"]
## 拍攝的招式進度：0～0.4 前搖（預兆）、0.4～0.7 出招、0.7～1 收招（前段是跟隨）。
const SAMPLES: Array[float] = [0.0, 0.2, 0.38, 0.48, 0.58, 0.7, 0.82, 0.95]
const ZOOM := 2.6
const CELL := Vector2i(240, 200)
## 每一格拍的範圍（世界像素，以招式開始時的腳底為原點、朝右）：留後面與上面的空間給舉起的武器。
const BOX := Rect2(-46.0, -78.0, 96.0, 80.0)

var _tag := "film"
var _only := ""
var _facing := 1


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--weapon="):
			_only = argument.trim_prefix("--weapon=")
		elif argument.begins_with("--facing="):
			_facing = -1 if argument.trim_prefix("--facing=") == "-1" else 1
	if not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[MeleeMoveFilm] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	await open_arena("res://data/lighting/warehouse_interior.tres", 12.0)
	var camera := get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * ZOOM
	level.hud.visible = false
	# 軟體算圖每秒只有幾格，引擎會在一格畫面裡補跑好幾個物理步，快的招式（匕首整招只有 11 個物理步）拍到的會是後面幾步。
	# 一格畫面只跑一個物理步（慢動作；每一步的邏輯不變），拍到的才是想拍的那一刻。
	var steps_before := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	for weapon_id in WEAPONS:
		if not _only.is_empty() and weapon_id != _only:
			continue
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		if not set.extension_attack().is_empty():
			moves.append(set.extension_attack())
		# 按住招式（NE-277 之後才有）：一樣從頭播到尾拍（蓄力與持續在這裡不按住，看的是招式本身的四段）。
		if set.has_method(&"hold") and not (set.call(&"hold") as Dictionary).is_empty():
			moves.append(str((set.call(&"hold") as Dictionary)["attack"]))
		var sheet := Image.create(CELL.x * SAMPLES.size(), CELL.y * moves.size(), false, Image.FORMAT_RGBA8)
		for row in moves.size():
			await _film_move(weapon, set, str(moves[row]), camera, sheet, row)
		var path := out_dir.path_join("%s-%s.png" % [_tag, weapon_id])
		print("saved %s (%s)" % [path, error_string(sheet.save_png(path))])
	Engine.max_physics_steps_per_frame = steps_before
	await finish()
	get_tree().quit(0)


func _film_move(weapon: WeaponData, set: MeleeSet, id: String, camera: Camera2D, sheet: Image, row: int) -> void:
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	place_player(12.0)
	player.facing = _facing
	player.aim_dir = Vector2(_facing, 0.0)
	# 跟著準星的招式（戰戟刺擊、鞭）要朝正前方：用手把的準星鎖住，不受視窗裡滑鼠游標的位置影響。
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2(_facing, 0.0)
	camera.global_position = player.global_position + Vector2(_facing * 30.0, -24.0)
	await settle(30)
	if not player._start_melee_attack(false):
		push_error("[MeleeMoveFilm] %s %s 出不了招" % [weapon.id, id])
		return
	player._melee_attack = set.attack(id, id == set.extension_attack())
	for column in SAMPLES.size():
		while player.melee_pose_progress() >= 0.0 and player.melee_pose_progress() < SAMPLES[column]:
			await get_tree().physics_frame
		# 衝刺與前衝會把人帶走：鏡頭不動，主角在格子裡的位置就看得出身體的位移。
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
		image.convert(Image.FORMAT_RGBA8)
		var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
		var feet := Vector2(12.0 * 16.0, FLOOR_Y)
		# 打得遠的武器（鞭）格子往前放寬，看得到鞭梢；格子的長寬比不變，所以人會比較小。
		var reach := maxf(BOX.end.x, set.max_range() + 12.0)
		var wide := Rect2(BOX.position.x * reach / BOX.end.x, BOX.position.y * reach / BOX.end.x, BOX.size.x * reach / BOX.end.x, BOX.size.y * reach / BOX.end.x)
		var box := wide if _facing > 0 else Rect2(-wide.end.x, wide.position.y, wide.size.x, wide.size.y)
		var a := to_screen * (feet + box.position)
		var b := to_screen * (feet + box.end)
		var region := Rect2i(Vector2i(a), Vector2i(b - a)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var cell := image.get_region(region)
		cell.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))
	while player.melee_pose_progress() >= 0.0:
		await get_tree().physics_frame
