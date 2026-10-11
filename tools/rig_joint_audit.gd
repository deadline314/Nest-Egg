extends Node
## Forward+ 相鄰部件逐格透明底取樣；其他部件、裝備與 glow 不得遮住接點。
## gpu_lock.py -- godot --path . res://tools/rig_joint_audit.tscn -- --out=<絕對目錄> --chars=enforcer,heavy_gunner,warden
## 配合 check_joint_frames.py 檢查連通與封閉透明孔；不取代全角色逐格外觀／光照檢視。

const CELL := 128
## --pair-only：只畫相接的兩片（舊的量法，用來找兩片之間本身的縫）。預設連同一根骨頭上的其他可見零件一起畫。
var _as_worn := true
const PREVIEW := preload("res://tools/rig_preview.gd")
const JOINTS := {
	"waist": [&"chest", "torso", "pelvis"],
	"hip_front": [&"leg_front_upper", "pelvis", "leg_front_upper"],
	"hip_back": [&"leg_back_upper", "pelvis", "leg_back_upper"],
	"knee_front": [&"leg_front_lower", "leg_front_upper", "leg_front_lower"],
	"knee_back": [&"leg_back_lower", "leg_back_upper", "leg_back_lower"],
	"ankle_front": [&"foot_front", "leg_front_lower", "foot_front"],
	"ankle_back": [&"foot_back", "leg_back_lower", "foot_back"],
	"shoulder_front": [&"arm_front_upper", "torso", "arm_front_upper"],
	"shoulder_back": [&"arm_back_upper", "torso", "arm_back_upper"],
	"elbow_front": [&"arm_front_lower", "arm_front_upper", "arm_front_lower"],
	"elbow_back": [&"arm_back_lower", "arm_back_upper", "arm_back_lower"],
	"wrist_front": [&"hand_front", "arm_front_lower", "hand_front"],
	"wrist_back": [&"hand_back", "arm_back_lower", "hand_back"],
	"neck": [&"head", "torso", "head"],
	"coat_shoulder_front": [&"arm_front_upper", "armor_jacket", "jacket_sleeve_front_upper"],
	# 遠側袖子掛在軀幹中間、夾克後片的後面（NE-222）：它相鄰的是軀幹與夾克前後片，不是只有夾克前片。
	"coat_shoulder_back": [&"arm_back_upper", "armor_jacket", "armor_jacket_far", "torso", "jacket_sleeve_back_upper"],
	"coat_cuff_front": [&"hand_front", "jacket_sleeve_front_upper", "jacket_sleeve_front_lower", "arm_front_upper", "arm_front_lower", "hand_front"],
	"coat_cuff_back": [&"hand_back", "jacket_sleeve_back_upper", "jacket_sleeve_back_lower", "arm_back_upper", "arm_back_lower", "hand_back"],
	"coat_elbow_front": [&"arm_front_lower", "jacket_sleeve_front_upper", "jacket_sleeve_front_lower", "arm_front_upper", "arm_front_lower"],
	"coat_elbow_back": [&"arm_back_lower", "jacket_sleeve_back_upper", "jacket_sleeve_back_lower", "arm_back_upper", "arm_back_lower"],
	"coat_hem": [&"coat_1", "armor_jacket", "jacket_hem"],
}
const ALIASES := {"torso": "armor_torso", "pelvis": "armor_pelvis", "leg_front_upper": "armor_thigh", "leg_front_lower": "armor_calf"}
const POSES := ["idle", "run", "aim_up", "crouch", "jump", "block", "stagger", "dead"]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var chars := PackedStringArray(["enforcer", "heavy_gunner", "warden"])
	var joints := PackedStringArray(JOINTS.keys().filter(func(key: String) -> bool: return not key.begins_with("coat_")))
	var frames := 120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--chars="): chars = arg.trim_prefix("--chars=").split(",", false)
		elif arg.begins_with("--joints="): joints = arg.trim_prefix("--joints=").split(",", false)
		elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
		elif arg == "--pair-only": _as_worn = false
	if out.is_empty() or frames <= 0:
		push_error("[rig_joint_audit] requires --out and positive --frames")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var metadata: Array[Dictionary] = []
	for zoom: float in [1.0, 3.4]:
		for pose: String in POSES:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(CELL * joints.size() * 2, CELL * chars.size())
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var entries: Array[Dictionary] = []
			for row in chars.size():
				for side in 2:
					for col in joints.size():
						var joint := joints[col]
						if not JOINTS.has(joint):
							push_error("[rig_joint_audit] unknown joint " + joint)
							get_tree().quit(1)
							return
						var clip := Control.new()
						clip.position = Vector2((side * joints.size() + col) * CELL, row * CELL)
						clip.size = Vector2(CELL, CELL)
						clip.clip_contents = true
						viewport.add_child(clip)
						var holder := Node2D.new()
						holder.scale = Vector2.ONE * zoom
						clip.add_child(holder)
						var rig := CharacterRig.new()
						holder.add_child(rig)
						if not rig.setup(chars[row]):
							get_tree().quit(1)
							return
						rig.set_weapon(str(PREVIEW.SHEET_WEAPONS.get(chars[row], "")))
						if rig.weapon_root() != null: rig.weapon_root().visible = false
						var pair: Array = JOINTS[joint]
						var available: Array[String] = []
						for part in rig._parts: available.append(str(part.name))
						var keep: Array[String] = []
						for key: String in pair.slice(1):
							keep.append(key if available.has(key) else str(ALIASES.get(key, key)))
						if not keep.all(func(key: String) -> bool: return available.has(key)):
							push_error("[rig_joint_audit] %s %s missing pair %s" % [chars[row], joint, keep])
							get_tree().quit(1)
							return
						var material := CanvasItemMaterial.new()
						material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
						# 同一根骨頭上、遊戲裡本來就顯示的其他零件（袖子、護腕、領子、圍裙肩帶）一起畫：玩家看到的接點是它們疊起來的樣子。
						# 只畫相接的兩片時，支點落在這些零件上的接點每一格都會被判成「中心沒蓋到」。裝甲脫落後的樣子另外用 rig_preview --damage --bare 看。
						var pair_bones: Array[Node] = []
						for part in rig._parts:
							if keep.has(str(part.name)) and not pair_bones.has(part.get_parent()):
								pair_bones.append(part.get_parent())
						for part in rig._parts:
							part.visible = keep.has(str(part.name)) or (_as_worn and part.visible and pair_bones.has(part.get_parent()))
							part.material = material
							for child in part.get_children():
								if child is CanvasItem: child.visible = false
						var input := RigInput.new()
						input.facing = 1 if side == 0 else -1
						input.aim_dir = Vector2(input.facing, -1.0 if pose == "aim_up" else 0.0).normalized()
						input.on_floor = pose != "jump"
						input.velocity = Vector2(150.0 * input.facing, -200.0 if pose == "jump" else 0.0) if pose in ["run", "jump"] else Vector2.ZERO
						input.crouching = pose == "crouch"
						input.blocking = pose == "block"
						input.staggered = pose == "stagger"
						input.dead = pose == "dead"
						input.two_handed = chars[row] != "enforcer"
						input.shield_forward = chars[row] == "enforcer"
						entries.append({"rig": rig, "input": input, "holder": holder, "clip": clip, "bone": pair[0], "char": chars[row], "joint": joint, "facing": input.facing, "radius": ceili(8.0 * zoom * rig.body_scale()), "rect": [int(clip.position.x), int(clip.position.y), CELL, CELL]})
			var samples: Array[Dictionary] = []
			for frame in frames:
				for entry in entries:
					var rig: CharacterRig = entry["rig"]
					rig.animate(1.0 / 60.0, entry["input"])
					if rig.weapon_root() != null: rig.weapon_root().visible = false
					var holder: Node2D = entry["holder"]
					holder.position += Vector2(CELL, CELL) * 0.5 - (rig.bone(entry["bone"]).global_position - (entry["clip"] as Control).global_position)
				await RenderingServer.frame_post_draw
				var file := "%s_%.1f_%03d.png" % [pose, zoom, frame]
				viewport.get_texture().get_image().save_png(out.path_join(file))
				samples.append({"file": file, "frame": frame, "seconds": float(frame + 1) / 60.0})
			var cells: Array[Dictionary] = []
			for entry in entries:
				cells.append({"char": entry["char"], "joint": entry["joint"], "facing": entry["facing"], "radius": entry["radius"], "rect": entry["rect"]})
			metadata.append({"pose": pose, "zoom": zoom, "cells": cells, "samples": samples})
			viewport.queue_free()
			await get_tree().process_frame
			print("JOINT_FRAMES ", pose, " zoom=", zoom, " frames=", frames)
	var f := FileAccess.open(out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metadata, "\t"))
	get_tree().quit()
