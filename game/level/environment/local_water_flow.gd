extends Node
## Two small materials, no particles/textures/per-frame allocations. Owned by the prop.
const SHADER := preload("res://game/level/environment/local_water_flow.gdshader")
const EMISSIVE_SHADER := preload("res://game/level/environment/local_water_flow_emissive.gdshader")

var clock := 0.0
var on_screen := false
var _materials: Array[ShaderMaterial] = []


func setup(data: PropData, base: Sprite2D, glow: Sprite2D) -> void:
	for sprite in [base, glow]:
		if sprite == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = EMISSIVE_SHADER if sprite == glow else SHADER
		material.set_shader_parameter(&"flow_region", Vector4(data.flow_region.position.x, data.flow_region.position.y, data.flow_region.size.x, data.flow_region.size.y))
		material.set_shader_parameter(&"flow_surface", Vector4(data.flow_surface.position.x, data.flow_surface.position.y, data.flow_surface.size.x, data.flow_surface.size.y))
		material.set_shader_parameter(&"water_gain", data.flow_glow_gain if sprite == glow else 1.0)
		sprite.material = material
		_materials.append(material)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(Vector2.ZERO, data.size)
	notifier.screen_entered.connect(func() -> void: on_screen = true)
	notifier.screen_exited.connect(func() -> void: on_screen = false)
	get_parent().add_child(notifier)


func _process(delta: float) -> void:
	if not on_screen:
		return
	clock = fmod(clock + delta, 10.0)
	for material in _materials:
		material.set_shader_parameter(&"motion_time", clock)
