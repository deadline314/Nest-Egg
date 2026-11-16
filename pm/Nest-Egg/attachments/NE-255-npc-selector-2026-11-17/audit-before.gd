extends Node
## Forward+ 相鄰部件逐格透明底取樣；其他部件、裝備與 glow 不得遮住接點。
## gpu_lock.py -- godot --path . res://tools/rig_joint_audit.tscn -- --out=<絕對目錄> --chars=enforcer,heavy_gunner,warden
## 配合 check_joint_frames.py 檢查連通與封閉透明孔；不取代全角色逐格外觀／光照檢視。

const CELL := 128
## --pair-only：只畫相接的兩片（舊的量法，用來找兩片之間本身的縫）。預設連同一根骨頭上的其他可見零件一起畫。
var _as_worn := true
## Explicit NPC stand→sit and sit→stand timelines; the original combat audit stays the default.
var _npc_transitions := false
## Independent NPC performance coverage; does not change the combat audit or transition timelines.
var _npc_performance := false
const NPC_PERFORMANCES := ["stand", "sit", "sit_talk", "sit_listen", "wave"]
## An explicit source-unchanged failure control for the same rendered joint checker.
var _displace_part := ""
var _seat_sag := -1.0
var _zooms: Array[float] = [1.0, 3.4]
var _trace_joint := ""
var _trace_frame := 0
var _only_npc_pose := ""
## Single-factor diagnostic only: show one named neighbouring material.
var _diagnostic_include_part := ""
var _diagnostic_whole_rig := false
var _alpha_only := false
var _diagnostic_part_texture := ""
var _joint_context := false
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
		elif arg == "--npc-transitions": _npc_transitions = true
		elif arg == "--npc-performance": _npc_performance = true
		elif arg.begins_with("--displace-part="): _displace_part = arg.trim_prefix("--displace-part=")
		elif arg.begins_with("--trace-joint="): _trace_joint = arg.trim_prefix("--trace-joint=")
		elif arg.begins_with("--trace-frame="): _trace_frame = int(arg.trim_prefix("--trace-frame="))
		elif arg.begins_with("--npc-pose="): _only_npc_pose = arg.trim_prefix("--npc-pose=")
		elif arg.begins_with("--diagnostic-include-part="): _diagnostic_include_part = arg.trim_prefix("--diagnostic-include-part=")
		elif arg == "--diagnostic-whole-rig": _diagnostic_whole_rig = true
		elif arg == "--alpha-only": _alpha_only = true
		elif arg.begins_with("--diagnostic-part-texture="): _diagnostic_part_texture = arg.trim_prefix("--diagnostic-part-texture=")
		elif arg == "--joint-context": _joint_context = true
		elif arg.begins_with("--seat-sag="):
			var raw_sag := arg.trim_prefix("--seat-sag=")
			if not raw_sag.is_valid_float():
				push_error("[rig_joint_audit] --seat-sag requires a finite numeric value")
				get_tree().quit(1)
				return
			_seat_sag = float(raw_sag)
		elif arg.begins_with("--zooms="):
			_zooms.clear()
			for value in arg.trim_prefix("--zooms=").split(",", false):
				if not value.is_valid_float() or not is_finite(float(value)) or float(value) <= 0.0 or float(value) > 6.0:
					push_error("[rig_joint_audit] --zooms requires finite values in (0,6]")
					get_tree().quit(1)
					return
				_zooms.append(float(value))
	if _npc_transitions and _npc_performance:
		push_error("[rig_joint_audit] select either --npc-transitions or --npc-performance")
		get_tree().quit(1)
		return
	if not _only_npc_pose.is_empty() and (not _npc_performance or not _only_npc_pose in NPC_PERFORMANCES):
		push_error("[rig_joint_audit] --npc-pose requires one existing --npc-performance state")
		get_tree().quit(1)
		return
	if _joint_context and not (_npc_performance or _npc_transitions):
		push_error("[rig_joint_audit] --joint-context requires an explicit NPC timeline")
		get_tree().quit(1)
		return
	if out.is_empty() or frames <= 0 or _zooms.is_empty():
		push_error("[rig_joint_audit] requires --out and positive --frames")
		get_tree().quit(1)
		return
	if _trace_frame < 0 or _trace_frame >= frames:
		push_error("[rig_joint_audit] --trace-frame must be inside the captured timeline")
		get_tree().quit(1)
		return
	if not _trace_joint.is_empty() and (not JOINTS.has(_trace_joint) or not joints.has(_trace_joint)):
		push_error("[rig_joint_audit] --trace-joint must name one of the selected joints")
		get_tree().quit(1)
		return
	var zoom_labels := {}
	for zoom in _zooms:
		var label := "%.1f" % zoom
		if zoom_labels.has(label):
			push_error("[rig_joint_audit] zoom output names collide; select distinct labels or separate runs")
			get_tree().quit(1)
			return
		zoom_labels[label] = true
	if not is_finite(_seat_sag) or _seat_sag > 0.9 or (_seat_sag < 0.0 and _seat_sag != -1.0):
		push_error("[rig_joint_audit] --seat-sag must be 0..0.9 or omitted")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var override_part := ""
	var override_image: Image
	if not _diagnostic_part_texture.is_empty():
		var fields := _diagnostic_part_texture.split(":", true, 1)
		if fields.size() != 2 or not fields[1].is_absolute_path():
			push_error("[rig_joint_audit] diagnostic texture requires part:absolute-PNG")
			get_tree().quit(1)
			return
		override_part = fields[0]
		override_image = Image.load_from_file(fields[1])
		if override_image == null or override_image.get_format() != Image.FORMAT_RGBA8:
			push_error("[rig_joint_audit] diagnostic texture requires native RGBA8")
			get_tree().quit(1)
			return
	var alpha_material: ShaderMaterial
	if _alpha_only:
		var alpha_shader := Shader.new()
		# Fragment COLOR already contains texture * vertex/modulate alpha:
		# https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html
		# Assign RGB only. Native A/A must prove every alpha pixel before adoption.
		alpha_shader.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR.rgb = vec3(1.0); }"
		alpha_material = ShaderMaterial.new()
		alpha_material.shader = alpha_shader
	var metadata: Array[Dictionary] = []
	for zoom: float in _zooms:
		for pose: String in ([_only_npc_pose] if not _only_npc_pose.is_empty() else NPC_PERFORMANCES if _npc_performance else ["sit_down", "stand_up"] if _npc_transitions else POSES):
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
						if not rig.setup(chars[row], "npc" if _npc_transitions or _npc_performance else ""):
							get_tree().quit(1)
							return
						if _seat_sag >= 0.0 and (_npc_transitions or _npc_performance):
							(rig.animator as NpcAnimator).seated_sag = _seat_sag
						rig.set_weapon(str(PREVIEW.SHEET_WEAPONS.get(chars[row], "")))
						if not override_part.is_empty():
							var found := false
							for part in rig._parts:
								if str(part.name) != override_part:
									continue
								var current := part.get("texture") as CanvasTexture
								if current == null or current.diffuse_texture == null or current.diffuse_texture.get_size() != Vector2(override_image.get_size()):
									push_error("[rig_joint_audit] diagnostic texture must preserve current native canvas/pivot")
									get_tree().quit(1)
									return
								var replacement := current.duplicate() as CanvasTexture
								replacement.diffuse_texture = ImageTexture.create_from_image(override_image)
								part.set("texture", replacement)
								found = true
							if not found:
								push_error("[rig_joint_audit] diagnostic texture part not found: " + override_part)
								get_tree().quit(1)
								return
						if rig.weapon_root() != null: rig.weapon_root().visible = false
						var pair: Array = JOINTS[joint]
						var available: Array[String] = []
						for part in rig._parts: available.append(str(part.name))
						var keep: Array[String] = []
						for key: String in pair.slice(1):
							keep.append(key if available.has(key) else str(ALIASES.get(key, key)))
						if not _diagnostic_include_part.is_empty():
							keep.append(_diagnostic_include_part)
						if _diagnostic_whole_rig:
							keep.assign(available)
						if not keep.all(func(key: String) -> bool: return available.has(key)):
							push_error("[rig_joint_audit] %s %s missing pair %s" % [chars[row], joint, keep])
							get_tree().quit(1)
							return
						var material: Material = alpha_material
						if not _alpha_only:
							var regular := CanvasItemMaterial.new()
							regular.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
							material = regular
						# 同一根骨頭上、遊戲裡本來就顯示的其他零件（袖子、護腕、領子、圍裙肩帶）一起畫：玩家看到的接點是它們疊起來的樣子。
						# 只畫相接的兩片時，支點落在這些零件上的接點每一格都會被判成「中心沒蓋到」。裝甲脫落後的樣子另外用 rig_preview --damage --bare 看。
						var pair_bones: Array[Node] = []
						for part in rig._parts:
							if keep.has(str(part.name)) and not pair_bones.has(part.get_parent()):
								pair_bones.append(part.get_parent())
						for part in rig._parts:
							part.material = material
							for child in part.get_children():
								if child is CanvasItem: child.visible = false
							# 姿勢專屬零件（跪姿的前大腿）跟著它取代的那個位置顯示或隱藏，由骨架決定；直接改 visible 的話，
							# 骨架換上專屬零件時會把它畫進每一個接點的格子裡，變成假的游離碎片。
							if str(part.name).begins_with("Pose_"):
								continue
							rig._set_base_part_visible(part, keep.has(str(part.name)) or (_as_worn and rig._base_part_is_visible(part) and pair_bones.has(part.get_parent())))
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
						if _npc_transitions:
							input.two_handed = false
							input.npc_pose = &"stand" if pose == "sit_down" else &"sit"
							for tick in 180:
								rig.animate(1.0 / 60.0, input)
							assert((rig.animator as NpcAnimator)._use_npc)
							input.npc_pose = &"sit" if pose == "sit_down" else &"stand"
						elif _npc_performance:
							input.two_handed = false
							input.npc_pose = &"sit" if pose.begins_with("sit") else &"stand"
							# Warm the actual resting posture before starting the full performance.
							for tick in 180:
								rig.animate(1.0 / 60.0, input)
							assert((rig.animator as NpcAnimator)._use_npc)
							input.talking = pose == "sit_talk"
							input.listening = pose == "sit_listen"
							input.waving = pose == "wave"
						var displaced: Node2D = null
						if not _displace_part.is_empty():
							for part in rig._parts:
								if str(part.name) == _displace_part:
									displaced = part as Node2D
							if displaced == null:
								push_error("[rig_joint_audit] negative-control part unavailable: " + _displace_part)
								get_tree().quit(1)
								return
						entries.append({"rig": rig, "input": input, "holder": holder, "clip": clip, "bone": pair[0], "char": chars[row], "joint": joint, "facing": input.facing, "radius": ceili(8.0 * zoom * rig.body_scale()), "rect": [int(clip.position.x), int(clip.position.y), CELL, CELL], "displaced": displaced, "original_position": displaced.position if displaced != null else Vector2.ZERO})
			var samples: Array[Dictionary] = []
			for frame in frames:
				var joint_contexts := {}
				for entry in entries:
					var rig: CharacterRig = entry["rig"]
					rig.animate(1.0 / 60.0, entry["input"])
					if entry["displaced"] != null:
						(entry["displaced"] as Node2D).position = entry["original_position"] + Vector2(6.0, 0.0)
					if rig.weapon_root() != null: rig.weapon_root().visible = false
					var holder: Node2D = entry["holder"]
					holder.position += Vector2(CELL, CELL) * 0.5 - (rig.bone(entry["bone"]).global_position - (entry["clip"] as Control).global_position)
					if frame == _trace_frame and entry["joint"] == _trace_joint:
						entry["geometry_sample"] = _material_geometry(rig, entry["clip"])
						if frame == 0:
							entry["geometry_first"] = entry["geometry_sample"]
					if _joint_context:
						var source_key := "%s/%s" % [entry["char"], entry["facing"]]
						var points := {}
						var origin := rig.bone(&"hip").global_position
						for name: String in JOINTS:
							if name.begins_with("coat_"):
								continue
							var point := rig.bone(JOINTS[name][0]).global_position - origin
							points[name] = [point.x, point.y]
						if joint_contexts.has(source_key):
							for name: String in points:
								var prior: Array = joint_contexts[source_key][name]
								if Vector2(prior[0], prior[1]).distance_to(Vector2(points[name][0], points[name][1])) > .001:
									push_error("[rig_joint_audit] isolated rigs disagree on actual native bone positions")
									get_tree().quit(1)
									return
						else:
							joint_contexts[source_key] = points
				await RenderingServer.frame_post_draw
				var file := "%s_%.1f_%03d.png" % [pose, zoom, frame]
				viewport.get_texture().get_image().save_png(out.path_join(file))
				var sample := {"file": file, "frame": frame, "seconds": float(frame + 1) / 60.0}
				if _joint_context:
					sample["joint_anchors_relative_hip_native_pixels"] = joint_contexts
				samples.append(sample)
			var cells: Array[Dictionary] = []
			for entry in entries:
				var cell := {"char": entry["char"], "joint": entry["joint"], "facing": entry["facing"], "radius": entry["radius"], "rect": entry["rect"]}
				if entry.has("geometry_first"):
					cell["geometry_first"] = entry["geometry_first"]
				if entry.has("geometry_sample"):
					cell["geometry_sample"] = entry["geometry_sample"]
					cell["geometry_frame"] = _trace_frame
				cell["diagnostic_whole_rig"] = _diagnostic_whole_rig
				cell["alpha_only_rgb"] = _alpha_only
				cell["diagnostic_part_texture"] = _diagnostic_part_texture
				cells.append(cell)
			metadata.append({"pose": pose, "zoom": zoom, "npc_transitions": _npc_transitions, "npc_performance": _npc_performance, "seat_sag": _seat_sag, "diagnostic_include_part": _diagnostic_include_part, "negative_control_part": _displace_part, "negative_control_offset": [6.0, 0.0] if not _displace_part.is_empty() else [], "fixed_step": 1.0 / 60.0, "prewarm_frames": 180 if _npc_transitions or _npc_performance else 0, "godot": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "cells": cells, "samples": samples})
			viewport.queue_free()
			await get_tree().process_frame
			print("JOINT_FRAMES ", pose, " zoom=", zoom, " frames=", frames)
	var f := FileAccess.open(out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metadata, "\t"))
	get_tree().quit()


## Read-only first-frame material mapping to locate a measured hole in source pixels.
## It never changes the render, alpha threshold, sampling band or checker verdict.
func _material_geometry(rig: CharacterRig, clip: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part in rig._parts:
		if not part.visible:
			continue
		var texture: Texture2D
		if part is Sprite2D:
			texture = (part as Sprite2D).texture
		elif part is Polygon2D:
			texture = (part as Polygon2D).texture
		if texture is CanvasTexture:
			texture = (texture as CanvasTexture).diffuse_texture
		if texture == null:
			continue
		var transform := clip.get_global_transform().affine_inverse() * (part as Node2D).global_transform
		var data := {"part": str(part.name), "texture": texture.resource_path,
			"size": [texture.get_width(), texture.get_height()],
			"to_cell": [[transform.x.x, transform.y.x, transform.origin.x], [transform.x.y, transform.y.y, transform.origin.y]]}
		if part is Sprite2D:
			var origin := (part as Sprite2D).get_rect().position
			data["rect_origin"] = [origin.x, origin.y]
		elif part is Polygon2D:
			var polygon := part as Polygon2D
			data["uv"] = _points(polygon.uv)
			data["vertices"] = _points(polygon.polygon)
			var triangles: Array = []
			for indices: PackedInt32Array in polygon.polygons:
				triangles.append(Array(indices))
			data["triangles"] = triangles
		result.append(data)
	return result


func _points(points: PackedVector2Array) -> Array:
	var values: Array = []
	for point in points:
		values.append([point.x, point.y])
	return values
