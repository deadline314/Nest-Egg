extends ScenarioBase
## 近戰招式的逐格接點稽核（NE-277），無頭也能跑：
##   godot --headless --path . res://tools/melee_joint_audit.tscn [-- --weapon=maul] [--no-hold]
## --no-hold 不量按住招式（和還沒有按住招式的舊版本比耗時時用，兩邊量的招式才一樣）。
## 五把近戰武器的每一招（含升級尾招，以及有的話按住招式）在真的遊戲裡從頭播到尾，每個物理影格用 AnimAudit 的量法量主角的骨架：
## 骨頭拉長、手肘與膝蓋反折、軀幹與頭的傾斜、肢體網格翻面與關節變窄、單格角度跳動。
## 每一招一行 MELEE_JOINT_AUDIT {...}（每一項最糟的值與它的限制），最後一行 MELEE_JOINT_AUDIT_DONE over=N（超過限制的項目數）。
## 另外記下出招期間每個物理影格的處理耗時（Performance 的 TIME_PHYSICS_PROCESS，毫秒），印成 MELEE_JOINT_AUDIT_PHYSICS_MS（中位數與平均）；
## 只量 CPU 端、而且受機器忙不忙影響，修前修後要在同一台機器、緊接著各跑一次再比。
## 只用改版前後都有的入口（_start_melee_attack、_melee_attack、melee_pose_progress），同一支工具也能放在舊版本上量修前。

const WEAPONS: PackedStringArray = ["blade", "dagger", "glaive", "maul", "whip"]
## 和動作稽核一樣，專屬動作（揮斬本來就快）的單格跳動放寬。
const CHECKS: PackedStringArray = ["bone_stretch", "elbow_hyper", "trunk_lean", "head_turn", "mesh_fold", "limb_pinch", "angle_pop"]

var _only := ""
var _with_hold := true
var _physics_ms: Array[float] = []


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="):
			_only = argument.trim_prefix("--weapon=")
		elif argument == "--no-hold":
			_with_hold = false
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	await open_arena("", 12.0)
	var over := 0
	var worst := {}
	for weapon_id in WEAPONS:
		if not _only.is_empty() and weapon_id != _only:
			continue
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		if not set.extension_attack().is_empty():
			moves.append(set.extension_attack())
		if _with_hold and set.has_method(&"hold") and not (set.call(&"hold") as Dictionary).is_empty():
			moves.append(str((set.call(&"hold") as Dictionary)["attack"]))
		for id: Variant in moves:
			var row := await _audit(weapon, set, str(id))
			for check: String in CHECKS:
				var entry: Dictionary = row["results"].get(check, {})
				if entry.is_empty():
					continue
				var limit := float(entry["limit"]) * (AnimAudit.ACTION_POP_SCALE if check == "angle_pop" else 1.0)
				if float(entry["value"]) > limit:
					over += 1
				if not worst.has(check) or float(entry["value"]) > float(worst[check]["value"]):
					worst[check] = {"value": snappedf(float(entry["value"]), 0.001), "limit": limit, "where": "%s/%s %s" % [weapon_id, id, entry["where"]]}
			var compact := {}
			for check: String in CHECKS:
				if row["results"].has(check):
					compact[check] = snappedf(float(row["results"][check]["value"]), 0.001)
			print("MELEE_JOINT_AUDIT ", JSON.stringify({"weapon": weapon_id, "move": id, "frames": row["frames"], "worst": compact}))
	print("MELEE_JOINT_AUDIT_WORST ", JSON.stringify(worst))
	_physics_ms.sort()
	var total := 0.0
	for value in _physics_ms:
		total += value
	if not _physics_ms.is_empty():
		print("MELEE_JOINT_AUDIT_PHYSICS_MS ", JSON.stringify({"frames": _physics_ms.size(), "median": snappedf(_physics_ms[_physics_ms.size() / 2], 0.001),
				"mean": snappedf(total / _physics_ms.size(), 0.001), "p90": snappedf(_physics_ms[int(_physics_ms.size() * 0.9)], 0.001)}))
	print("MELEE_JOINT_AUDIT_DONE over=%d" % over)
	await finish()
	get_tree().quit(0)


func _audit(weapon: WeaponData, set: MeleeSet, id: String) -> Dictionary:
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
	var rig := player._visual.rig
	var ctx := {"rig": rig, "results": {}, "where": id, "frame": 0, "prev": {}, "grounded": false, "pop_scale": AnimAudit.ACTION_POP_SCALE, "skip_pop": 1}
	if not player._start_melee_attack(false):
		return {"results": {}, "frames": 0}
	player._melee_attack = set.attack(id, id == set.extension_attack())
	var frames := 0
	while player.melee_pose_progress() >= 0.0 and frames < 240:
		await get_tree().physics_frame
		frames += 1
		ctx["frame"] = frames
		AnimAudit._measure(ctx, false)
		_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	return {"results": ctx["results"], "frames": frames}
