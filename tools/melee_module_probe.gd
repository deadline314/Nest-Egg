extends ScenarioBase
## 近戰模組的逐格量測（NE-277），無頭也能跑：
##   godot --headless --path . res://tools/melee_module_probe.tscn [-- --weapon=maul] [--out=<絕對資料夾>]
## 五把近戰武器的每一招（含升級尾招）各從頭播到尾，每個物理影格量：
##   palm  前手掌心離「武器路徑要的握點」多遠（世界像素；手臂搆不到時才會大於 0）
##   second 雙手招式時，後手的握點離桿上那一點多遠（世界像素）；搆不到、沒握上的影格數
##   body  骨盆離站姿的最大前後、上下位移（世界像素），看身體有沒有參與
##   visual_reach  出招段武器最遠的一點（刃尖、錘頭、鞭梢）離胸口多遠，和招式的 range（實際打得到的距離）對照
## 另外印出骨架縮放與手臂長度（寫武器路徑的 reach 要用的骨架單位）。
## 結果：每一招一行 MELEE_MODULE_PROBE {...}，最後一行 MELEE_MODULE_PROBE_DONE failures=N；--out 時另存 melee-module-probe.json。
## --verbose 另外印出雙手招式每一個沒握上的影格（招式進度、後肩到桿上握點的距離）。
## 門檻：palm ≤ 1.0、second ≤ 1.5 且雙手招式沒有握不到的影格；超過算失敗。

const WEAPONS: PackedStringArray = ["blade", "dagger", "glaive", "maul", "whip"]
const PALM_LIMIT := 1.0
const SECOND_LIMIT := 1.5

var _only := ""
var _failures := 0
var _verbose := false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="):
			_only = argument.trim_prefix("--weapon=")
		elif argument == "--verbose":
			_verbose = true
		elif argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	await open_arena("", 12.0)
	var rig := player._visual.rig
	var upper := rig.rest(&"arm_front_lower").length()
	var lower := rig.rest(&"hand_front").length()
	print("MELEE_MODULE_PROBE_RIG ", JSON.stringify({"scale": rig.global_transform.get_scale().abs().x, "arm_length": snappedf(upper + lower, 0.01),
			"upper": snappedf(upper, 0.01), "lower": snappedf(lower, 0.01)}))
	var report := []
	for weapon_id in WEAPONS:
		if not _only.is_empty() and weapon_id != _only:
			continue
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		if not set.extension_attack().is_empty():
			moves.append(set.extension_attack())
		for id: Variant in moves:
			var row := await _measure(weapon, set, str(id))
			report.append(row)
			print("MELEE_MODULE_PROBE ", JSON.stringify(row))
	if out_dir.is_absolute_path():
		DirAccess.make_dir_recursive_absolute(out_dir)
		var file := FileAccess.open(out_dir.path_join("melee-module-probe.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	print("MELEE_MODULE_PROBE_DONE failures=%d" % _failures)
	await finish()
	get_tree().quit(1 if _failures > 0 else 0)


func _measure(weapon: WeaponData, set: MeleeSet, id: String) -> Dictionary:
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	place_player(12.0)
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	await settle(30)
	var def := set.attack(id, id == set.extension_attack())
	var row := {"weapon": weapon.id, "move": id, "frames": 0, "palm_max": 0.0, "second_max": 0.0, "second_missed": 0, "two_handed": MeleeMove.hands(def) == 2,
			"body_dx": 0.0, "body_dy": 0.0, "path": def.has("path"), "visual_reach": 0.0, "range": float(def["range"])}
	if not player.melee.start_attack(false):
		row["error"] = "could not start"
		_failures += 1
		return row
	# 量的是這一招本身：換成指定的招式（連段順序與付費尾招由別的測試負責）。
	player.melee.attack = def
	player.melee.swing_direction = player.melee.aim_direction(def)
	var rig := player._visual.rig
	var held := player._visual.melee_held()
	var rest_hip := rig.bone(&"hip").global_position - player.global_position if rig.has_bone(&"hip") else Vector2.ZERO
	while player.melee.is_active():
		await get_tree().physics_frame
		if not player.melee.is_active():
			break
		row["frames"] = int(row["frames"]) + 1
		var path := player.melee.path_now()
		if not path.is_empty() and player._visual._input.melee_path_w >= 0.999:
			var shoulder_local := rig.to_local(rig.bone(&"arm_front_upper").global_position)
			var want := rig.to_global(shoulder_local + Vector2.from_angle(path[0]) * path[1])
			row["palm_max"] = maxf(float(row["palm_max"]), held.hold().origin.distance_to(want))
		if _verbose and not path.is_empty():
			print("  frame p=%.2f path_weapon=%.2f held=%.2f" % [player.melee.pose_progress(), path[0] + path[2], held.angle()])
		if row["two_handed"] and player._visual._input.melee_path_w >= 0.999:
			if not rig.second_hand_on_weapon:
				row["second_missed"] = int(row["second_missed"]) + 1
				if _verbose:
					var shoulder := rig.bone(&"arm_back_upper").global_position
					var near := player._visual.second_grip(shoulder)
					var along := (shoulder - held.hold().origin).dot(held.hold().x)
					print("  miss p=%.2f dist=%.1f along=%.1f perp=%.1f" % [player.melee.pose_progress(), shoulder.distance_to(near), along,
							absf((shoulder - held.hold().origin).dot(held.hold().y))])
			else:
				var hand := rig.bone(&"hand_back")
				var grip := hand.global_transform * rig.hand_grip_offset(&"hand_back")
				var on_shaft := player._visual.second_grip(rig.bone(&"arm_back_upper").global_position)
				row["second_max"] = maxf(float(row["second_max"]), grip.distance_to(on_shaft))
		if player.melee.phase == MeleeModule.Phase.ACTIVE:
			var chest := player.global_position + Vector2(0.0, -Player.BODY_SIZE.y * 0.55)
			row["visual_reach"] = maxf(float(row["visual_reach"]), chest.distance_to(held.tip_point()))
		if rig.has_bone(&"hip"):
			var hip := rig.bone(&"hip").global_position - player.global_position - rest_hip
			row["body_dx"] = maxf(float(row["body_dx"]), absf(hip.x))
			row["body_dy"] = maxf(float(row["body_dy"]), absf(hip.y))
	for key in ["palm_max", "second_max", "body_dx", "body_dy", "visual_reach"]:
		row[key] = snappedf(float(row[key]), 0.01)
	if float(row["palm_max"]) > PALM_LIMIT or float(row["second_max"]) > SECOND_LIMIT or int(row["second_missed"]) > 0:
		_failures += 1
		row["fail"] = true
	return row
