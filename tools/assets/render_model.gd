extends Node
## 開發工具：把免費 3D 模型（glTF）以正交鏡頭渲染成 2D 道具貼圖 + 法線貼圖（NE-57）。
## 用法：godot --path . res://tools/assets/render_model.tscn -- --batch=<json 路徑，相對專案根目錄或絕對路徑>
## batch 是陣列，每筆：{ "src": gltf 路徑, "out": 輸出前綴（不含副檔名）, "width": 輸出寬度（像素，預設 512）,
##   "yaw": 繞 Y 軸旋轉角度（預設 0）, "pitch": 俯仰角度（預設 0）, "light": 光源方向角度（預設 [-40, 30]）,
##   "glow": 材質名稱的正規表示式清單（符合的材質會輸出到自發光層，例如 ["glass", "bulb"]；沒有就不輸出自發光層）,
##   "glow_through": true 時發光面不做深度測試（燈泡包在玻璃裡時用；預設 false，立面窗戶要被窗框擋住）,
##   "glow_color": 自發光層的顏色 [r, g, b]（預設白色；寫實模型的燈泡多半靠發光屬性而不是貼圖顏色，所以用單色） }
## 輸出：<out>.png（反照率，已含柔和環境光與方向光的起伏）、<out>_n.png（鏡頭空間法線，Y+ 向上，與 LitTextures 相同慣例）、
##   <out>_glow.png（只有符合的材質，其餘為黑；有 glow 才輸出）、
##   <out>.json（模型尺寸，單位公尺，用來決定遊戲內大小）。壞掉的項目只記錄錯誤並略過。
## 需要可渲染的環境（有 GPU）。

const RENDER_SIZE := 2048
const MARGIN := 0.04
const NORMAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 n = normalize(NORMAL) * 0.5 + 0.5;
	// 輸出會經過線性轉 sRGB，先反轉才能得到原值。
	ALBEDO = pow(n, vec3(2.2));
}
"""

var _viewport: SubViewport
var _camera: Camera3D
var _light: DirectionalLight3D
var _environment: Environment


func _ready() -> void:
	var batch_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--batch="):
			batch_path = arg.trim_prefix("--batch=")
	_run.call_deferred(batch_path)


func _run(batch_path: String) -> void:
	var jobs = JSON.parse_string(FileAccess.get_file_as_string(_abs(batch_path)))
	if not jobs is Array:
		push_error("[render_model] batch 不是陣列或讀不到：%s" % batch_path)
		get_tree().quit(1)
		return
	_build_stage()
	var failed := 0
	for job: Dictionary in jobs:
		if not await _render(job):
			failed += 1
	get_tree().quit(1 if failed > 0 else 0)


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.85, 0.88, 1.0)
	_environment.ambient_light_energy = 0.55
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	_viewport.add_child(world_env)
	_light = DirectionalLight3D.new()
	_light.light_energy = 1.0
	_light.shadow_enabled = true
	_viewport.add_child(_light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)


func _render(job: Dictionary) -> bool:
	var src := _abs(String(job.get("src", "")))
	var out := _abs(String(job.get("out", "")))
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(src, state) != OK:
		push_error("[render_model] 讀不到模型：%s" % src)
		return false
	var model := doc.generate_scene(state) as Node3D
	if model == null:
		push_error("[render_model] 模型沒有場景：%s" % src)
		return false
	model.rotation_degrees = Vector3(float(job.get("pitch", 0.0)), float(job.get("yaw", 0.0)), 0.0)
	_viewport.add_child(model)
	var bounds := _bounds(model)
	if bounds.size == Vector3.ZERO:
		push_error("[render_model] 模型沒有網格：%s" % src)
		model.queue_free()
		return false
	var center := bounds.get_center()
	_camera.size = maxf(bounds.size.x, bounds.size.y) * (1.0 + MARGIN * 2.0)
	_camera.position = center + Vector3(0, 0, bounds.size.z + 10.0)
	_camera.far = bounds.size.z + 40.0
	var light_angle: Array = job.get("light", [-40.0, 30.0])
	_light.rotation_degrees = Vector3(float(light_angle[0]), float(light_angle[1]), 0.0)

	var color := await _capture()
	_apply_normal_pass(model)
	_environment.ambient_light_energy = 0.0
	_light.visible = false
	var normal := await _capture()
	var glow: Image = null
	var glow_patterns: Array = job.get("glow", [])
	if not glow_patterns.is_empty():
		var color_list: Array = job.get("glow_color", [1.0, 1.0, 1.0])
		_apply_glow_pass(model, glow_patterns, Color(float(color_list[0]), float(color_list[1]), float(color_list[2])), bool(job.get("glow_through", false)))
		glow = await _capture()
	_environment.ambient_light_energy = 0.55
	_light.visible = true
	model.queue_free()

	var rect := color.get_used_rect()
	if rect.size == Vector2i.ZERO:
		push_error("[render_model] 渲染結果是空的：%s" % src)
		return false
	var width := int(job.get("width", 512))
	var height := maxi(1, int(round(float(width) * rect.size.y / rect.size.x)))
	var passes: Array = [[color, ""], [normal, "_n"]]
	if glow != null:
		passes.append([glow, "_glow"])
	for pair: Array in passes:
		var image: Image = (pair[0] as Image).get_region(rect)
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
		image.fix_alpha_edges()
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		image.save_png("%s%s.png" % [out, pair[1]])
	var info := {"size_m": [bounds.size.x, bounds.size.y, bounds.size.z], "pixels": [width, height], "src": String(job.get("src", ""))}
	FileAccess.open(out + ".json", FileAccess.WRITE).store_string(JSON.stringify(info, "\t"))
	print("rendered %s (%dx%d)" % [out.get_file(), width, height])
	return true


func _capture() -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var box := mesh_node.global_transform * mesh_node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _apply_normal_pass(root: Node3D) -> void:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = NORMAL_SHADER
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material


## 自發光遮罩：符合名稱的材質用單色（不受光）輸出，其他材質塗黑。
func _apply_glow_pass(root: Node3D, patterns: Array, glow_color: Color, through: bool) -> void:
	var regexes: Array[RegEx] = []
	for pattern: String in patterns:
		var regex := RegEx.new()
		if regex.compile("(?i)" + pattern) == OK:
			regexes.append(regex)
		else:
			push_error("[render_model] glow 的正規表示式無效：%s" % pattern)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = glow_color
	# 燈泡常包在玻璃裡：through 時發光面不做深度測試、最後畫，才不會被塗黑的玻璃蓋住。
	flat.no_depth_test = through
	flat.render_priority = 10 if through else 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = null
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface)
			var matched := false
			if source != null:
				for regex in regexes:
					matched = matched or regex.search(source.resource_name) != null
			if matched:
				mesh_node.set_surface_override_material(surface, flat)
			else:
				mesh_node.set_surface_override_material(surface, black)


func _abs(path: String) -> String:
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path)
