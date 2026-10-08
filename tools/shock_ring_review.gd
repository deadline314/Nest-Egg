extends Node
## NE-95: legacy placeholder (left) versus production ring (right), same shader and centered geometry.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for index in 2:
		var sprite: Sprite2D = Sprite2D.new() if index == 0 else ShockRing.new()
		if index == 0:
			var placeholder := PlaceholderTexture2D.new()
			placeholder.size = Vector2(2, 2)
			sprite.texture = placeholder
		var material := ShaderMaterial.new()
		material.shader = load("res://art/shaders/shock_ring.gdshader")
		material.set_shader_parameter("progress", 0.3)
		material.set_shader_parameter("strength", 0.0)
		material.set_shader_parameter("tint", Color.CYAN)
		sprite.scale = Vector2(80, 80)
		sprite.position = Vector2(160 + index * 320, 180)
		add_child(sprite)  # ShockRing._ready supplies the shared production carrier.
		sprite.visible = true
		sprite.material = material
		print("RING type=%s center=%s rect=%s" % [sprite.texture.get_class(), sprite.position, sprite.get_rect()])
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://pm/Nest-Egg/images/NE-95-ring-surface-before-after.png")
	get_tree().quit()
