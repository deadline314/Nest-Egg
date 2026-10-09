extends Node
## 開發工具：把角色擺成參考姿勢、放大輸出，供 AI 生成「與骨架對齊」的全身立繪，再依零件切回零件圖。
## 用法：godot --path . res://tools/comfyui/rig_reference.tscn -- --skin=rin --out=/絕對路徑/資料夾 [--zoom=24]
## 輸出：body.png（不含裝甲）、armor.png（含裝甲），以及同名 .json：每個零件的貼圖、繪製順序、
##       與「零件貼圖像素 → 輸出圖像素」的仿射轉換（切零件時反轉回零件畫布用）。
## 後側手腳隱藏（前後共用同一張貼圖，只需要前側）。

## 預設輸出尺寸與腳底位置；用 --zoom=倍率 放大時等比放大。
const BASE_SIZE := Vector2i(832, 1216)
## 世界座標 → 輸出圖的倍率（零件貼圖 1px = 世界 0.25px，所以 16 倍時貼圖 1px = 輸出 4px）。
const BASE_ZOOM := 16.0
const BASE_FEET := Vector2(400, 1140)
## 參考姿勢（弧度，相對於靜止姿勢）：前手往前抬、前腳跨出，盡量減少零件互相遮擋。
const POSE := {
	&"arm_front_upper": -0.75, &"arm_front_lower": -0.45, &"hand_front": -0.2,
	&"leg_front_upper": -0.32, &"leg_front_lower": 0.22, &"foot_front": 0.1,
}
const HIDDEN_PREFIXES := ["arm_back", "leg_back", "foot_back", "hand_back", "armor_shoulder_back", "armor_knee_back"]

var _skin := "rin"
var _out := ""
var _zoom := BASE_ZOOM
var _pose := "reference"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skin="):
			_skin = arg.trim_prefix("--skin=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = maxf(1.0, float(arg.trim_prefix("--zoom=")))
		elif arg.begins_with("--pose="):
			_pose = arg.trim_prefix("--pose=")
	if _pose not in ["reference", "stand", "sit", "crouch", "lean"]:
		push_error("[rig_reference] unsupported pose: %s" % _pose)
		get_tree().quit(1)
		return
	if _out.is_empty():
		push_error("[rig_reference] 需要 --out=資料夾")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await _render_pass("body", false)
	await _render_pass("armor", true)
	get_tree().quit()


func _render_pass(pass_name: String, with_armor: bool) -> void:
	var viewport := SubViewport.new()
	var ratio := _zoom / BASE_ZOOM
	viewport.size = Vector2i(roundi(BASE_SIZE.x * ratio), roundi(BASE_SIZE.y * ratio))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var holder := Node2D.new()
	holder.position = BASE_FEET * ratio
	holder.scale = Vector2.ONE * _zoom
	viewport.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	if not rig.setup(_skin, "npc" if _pose != "reference" else ""):
		push_error("[rig_reference] 無法建立角色：%s" % _skin)
		return
	rig.weapon_root().visible = false
	if _pose == "reference":
		for bone_name: StringName in POSE:
			if rig.has_bone(bone_name):
				rig.bone(bone_name).rotation = POSE[bone_name]
	else:
		var input := RigInput.new()
		input.two_handed = false
		input.npc_pose = StringName(_pose)
		for frame in 180:
			rig.animate(1.0 / 60.0, input)
		assert((rig.animator as NpcAnimator)._use_npc, "requested NPC pose must actually be active")
	for bone_name in rig.bone_order():
		if bone_name != &"hip":
			assert(rig.bone(bone_name).position.distance_to(rig.rest(bone_name)) < 0.001, "pose reference cannot change bone lengths")
	rig.refresh_limbs()
	var sprites: Array[CanvasItem] = []
	_collect(rig, sprites)
	assert(sprites.size() == rig._parts.size(), "reference must include every body part")
	var parts: Array[Dictionary] = []
	for i in sprites.size():
		var sprite := sprites[i]
		for child in sprite.get_children():
			if child is CanvasItem:
				(child as CanvasItem).visible = false
		var parent_name := str(sprite.get_parent().name)
		var hidden := _pose == "reference" and HIDDEN_PREFIXES.any(func(p: String) -> bool: return sprite.name.begins_with(p) or parent_name.begins_with(p))
		if sprite.name.begins_with("armor_") and not with_armor:
			hidden = true
		if rig._under.has(sprite) and with_armor:
			hidden = true
		sprite.visible = not hidden
		if hidden:
			continue
		parts.append({"name": String(sprite.name), "tree_index": i, "z": sprite.z_index,
				"bone": parent_name})
	rig.refresh_limbs()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for part in parts:
		var sprite := sprites[part["tree_index"]]
		part.merge(geometry(sprite))
	var bones: Array[Dictionary] = []
	for bone_name in rig.bone_order():
		var bone := rig.bone(bone_name)
		var xf := bone.get_global_transform()
		bones.append({"name": str(bone_name), "parent": str(rig.parent_of(bone_name)),
			"position": [bone.global_position.x, bone.global_position.y],
			"rotation": bone.global_rotation, "rest": [rig.rest(bone_name).x, rig.rest(bone_name).y],
			"xform": [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y]})
	var image := viewport.get_texture().get_image()
	assert(image.save_png(_out.path_join(pass_name + ".png")) == OK)
	var file := FileAccess.open(_out.path_join(pass_name + ".json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"version": 2, "skin": _skin, "pose": _pose, "size": [viewport.size.x, viewport.size.y], "zoom": _zoom, "texture_scale": rig._texture_scale, "body_scale": rig.body_scale(), "bones": bones, "parts": parts}, "  "))
	file.close()
	print("rig_reference: %s (%d parts)" % [pass_name, parts.size()])
	viewport.queue_free()


static func geometry(part: CanvasItem) -> Dictionary:
	var texture: Texture2D
	var result: Dictionary = {}
	if part is RigPartMesh:
		var mesh := part as RigPartMesh
		texture = mesh.texture
		result["kind"] = "mesh"
		result["vertices"] = []
		result["uv"] = []
		result["triangles"] = []
		for vertex in mesh.deformed_vertices():
			var point: Vector2 = mesh.get_global_transform() * vertex
			result["vertices"].append([point.x, point.y])
		for uv in mesh.uv:
			result["uv"].append([uv.x, uv.y])
		for triangle in mesh.polygons:
			result["triangles"].append(Array(triangle))
	else:
		var sprite := part as Sprite2D
		texture = sprite.texture
		result["kind"] = "sprite"
		var xf := sprite.get_global_transform() * Transform2D(0.0, sprite.offset)
		result["xform"] = [xf.x.x, xf.x.y, xf.y.x, xf.y.y, xf.origin.x, xf.origin.y]
	assert(texture != null)
	var diffuse := (texture as CanvasTexture).diffuse_texture if texture is CanvasTexture else texture
	result["file"] = diffuse.resource_path
	result["tex_size"] = [texture.get_width(), texture.get_height()]
	return result


func _collect(node: Node, out: Array[CanvasItem]) -> void:
	for child in node.get_children():
		if (child is Sprite2D or child is RigPartMesh) and child.get_parent() is Bone2D:
			out.append(child)
		_collect(child, out)
