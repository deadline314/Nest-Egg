extends Node
## 走路姿勢總表（NE-480）：art/motion 裡每個角色以自己實際走路的速度量一次，印出骨盆高度、支撐中段膝角、
## 兩腳前後分開的距離與上身後仰，標出超過 LocomotionSuite 門檻的項目。
## 用法：godot --headless --path . res://tools/gait_survey.tscn [-- --skins=stalker,sniper]

func _ready() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skins="):
			only = arg.trim_prefix("--skins=").split(",", false)
	var speeds := GaitLimits.walk_speeds()
	var holder := Node2D.new()
	add_child(holder)
	print("skin                    walk/run   hip_L  knee°  spread_L  lean°  flags")
	var bad := 0
	for file in DirAccess.get_files_at("res://art/motion"):
		if not file.ends_with(".json"):
			continue
		var skin := file.get_basename()
		if not only.is_empty() and not only.has(skin):
			continue
		var rig := CharacterRig.new()
		holder.add_child(rig)
		if not rig.setup(skin):
			rig.queue_free()
			continue
		var pace: Array = GaitLimits.pace_for(skin, speeds)
		var r := LocomotionAudit.measure(rig, float(pace[0]), float(pace[1]))
		var flags := GaitLimits.problems(r, skin)
		if not flags.is_empty():
			bad += 1
		print("%-23s %3.0f/%-3.0f    %.2f   %5.1f  %.2f      %5.1f  %s" % [skin, pace[0], pace[1], r["hip_height_l"], r["stance_knee"], r["foot_spread_l"], r["back_lean"], ", ".join(flags)])
		rig.queue_free()
		await get_tree().process_frame
	print("GAIT_SURVEY flagged: %d" % bad)
	get_tree().quit(0)
