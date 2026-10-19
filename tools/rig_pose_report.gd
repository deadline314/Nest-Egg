extends Node
## 姿勢報告：用法
##   godot --headless --path . res://tools/rig_pose_report.tscn -- [--skins=rin,old_k]（預設全部骨架角色）
## 對每個骨架角色的 NPC 姿勢（站、坐、蹲）量：骨盆離腳底的高度（過場生成器的 HIP_SIT 就是坐姿的這個數字）、
## 最低的腳離地多少（正＝懸空、負＝陷地，應該接近 0）、腳掌的角度（應該接近 0＝放平）。


func _ready() -> void:
	var skins := PackedStringArray()
	var seat_sag := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seat-sag="):
			var raw_sag := arg.trim_prefix("--seat-sag=")
			if not raw_sag.is_valid_float() or not is_finite(float(raw_sag)) or float(raw_sag) < 0.0 or float(raw_sag) > 0.9:
				printerr("[rig_pose_report] --seat-sag requires a finite fraction in 0..0.9")
				get_tree().quit(2)
				return
			seat_sag = float(raw_sag)
		if arg.begins_with("--skins="):
			skins = PackedStringArray(arg.trim_prefix("--skins=").split(","))
	if skins.is_empty():
		for dir in DirAccess.get_directories_at("res://art/characters"):
			if FileAccess.file_exists("res://art/characters/%s/character.json" % dir):
				skins.append(dir)
	skins.sort()
	print("%-16s %-7s %9s %9s %9s" % ["skin", "pose", "hip(px)", "float(px)", "foot(rad)"])
	for skin in skins:
		for pose: StringName in [&"stand", &"sit", &"crouch"]:
			var holder := Node2D.new()
			add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			if not rig.setup(skin, "npc"):
				holder.queue_free()
				continue
			if seat_sag >= 0.0 and rig.animator is NpcAnimator:
				(rig.animator as NpcAnimator).seated_sag = seat_sag
			var input := RigInput.new()
			input.two_handed = false
			input.npc_pose = pose
			for i in 120:
				rig.animate(1.0 / 60.0, input)
			var a := rig.animator
			print("%-16s %-7s %9.2f %9.2f %9.2f" % [skin, pose, -a.bone_pos(&"hip").y, a.ground_level() - a._lowest_foot_y(), a.foot_angle(&"foot_front")])
			holder.queue_free()
	get_tree().quit(0)
