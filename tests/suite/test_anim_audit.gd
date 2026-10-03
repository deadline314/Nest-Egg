class_name AnimAuditSuite
extends TestSuite
## 動畫稽核（NE-107）：每個人形敵人的所有狀態與專屬動作逐格播放，量骨頭長度、關節範圍、腳底與地面、握槍、角度跳動、倒下後的躺姿，
## 都要在 AnimAudit.LIMITS 以內；超標時訊息會寫出最糟的數值、情境與格數。環境變數 ANIM_AUDIT_VERBOSE=1 會印出每個角色每一項的餘裕。

const ENEMIES: Array[String] = ["rin", "trooper", "trooper_elite", "sniper", "flamer", "grenadier", "enforcer", "heavy_gunner", "warden", "reclaimer", "slasher", "stalker"]
const WEAPONS := {"rin": "rifle", "trooper": "smg", "trooper_elite": "rifle", "sniper": "sniper", "flamer": "flamethrower", "grenadier": "launcher", "enforcer": "pistol", "heavy_gunner": "minigun", "warden": "minigun", "reclaimer": "rifle", "slasher": "", "stalker": "rifle"}


## 遊戲裡實際用到的 NPC 組合（骨架、基本姿勢、工作循環）：場景人物與過場演員。
const NPCS := [
	["old_k", &"stand", &"stir"], ["old_k", &"stand", &"wipe_hands"], ["old_k", &"lean", &"glance"],
	["wataru", &"sit", &"pull_blanket"], ["wataru", &"sit", &"cough"],
	["mei", &"sit", &"typing"], ["mei", &"stand", &""],
	["ah_po", &"stand", &"stir"], ["night_worker", &"lean", &"yawn"], ["night_worker", &"lean", &"read_note"],
	["nurse", &"stand", &"tablet"], ["nurse", &"stand", &"sort_gear"], ["repairman_chen", &"crouch", &"hammer"], ["resident", &"stand", &"hold_child"],
]


func run() -> void:
	for skin in ENEMIES:
		await _audit(skin)
	for entry: Array in NPCS:
		await _audit_npc(entry[0], entry[1], entry[2])


func _actions_of(skin: String) -> Array[String]:
	var names: Array[String] = []
	var actions: Dictionary = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	for key: String in actions.keys():
		if key.begins_with(skin + "."):
			names.append(key)
	return names


func _audit(skin: String) -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(skin), "rig builds: %s" % skin)
	rig.set_weapon(str(WEAPONS.get(skin, "")))
	var report := AnimAudit.audit(rig, skin, _actions_of(skin))
	var verbose := OS.get_environment("ANIM_AUDIT_VERBOSE") != ""
	for check_name: String in AnimAudit.LIMITS.keys():
		var entry: Dictionary = report.get(check_name, {"value": 0.0, "limit": AnimAudit.LIMITS[check_name], "where": "-"})
		if verbose:
			print("AUDIT %-14s %-18s value=%7.3f limit=%6.2f  %s" % [skin, check_name, float(entry["value"]), float(entry["limit"]), entry["where"]])
		check(float(entry["value"]) <= float(entry["limit"]), "%s: %s within limit (%.2f > %.2f at %s)" % [skin, check_name, float(entry["value"]), float(entry["limit"]), entry["where"]])
	holder.queue_free()
	await frames(1)


func _audit_npc(skin: String, pose: StringName, loop: StringName) -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	var tag := "%s/%s/%s" % [skin, pose, loop]
	check(rig.setup(skin, "npc"), "npc rig builds: %s" % tag)
	var report := AnimAudit.audit_npc(rig, pose, loop)
	var verbose := OS.get_environment("ANIM_AUDIT_VERBOSE") != ""
	for check_name: String in ["bone_stretch", "elbow_hyper", "knee_hyper", "trunk_lean", "head_turn", "angle_pop", "foot_below_ground", "foot_floating"]:
		var entry: Dictionary = report.get(check_name, {"value": 0.0, "limit": AnimAudit.LIMITS[check_name], "where": "-"})
		if verbose:
			print("AUDIT %-30s %-18s value=%7.3f limit=%6.2f  %s" % [tag, check_name, float(entry["value"]), float(entry["limit"]), entry["where"]])
		var limit := float(entry["limit"]) * (1.6 if check_name == "foot_floating" else 1.0)  # NPC 沒有落腳補償，腳底離地稍寬
		check(float(entry["value"]) <= limit, "npc %s: %s within limit (%.2f > %.2f at %s)" % [tag, check_name, float(entry["value"]), float(entry["limit"]), entry["where"]])
	holder.queue_free()
	await frames(1)
