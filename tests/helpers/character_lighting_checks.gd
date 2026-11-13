## Caller-level lighting contracts. Pixel light/occlusion response is verified natively.
extends RefCounted


static func rig_attachments(s: TestSuite) -> void:
	var rig := CharacterRig.new()
	s.runner.add_child(rig)
	s.check(rig.setup("rin"), "lighting: Rin attachment fixture builds")
	var meshes := 0
	var rigid := 0
	for part: CanvasItem in rig._parts:
		if part is Polygon2D:
			meshes += 1
			s.check(part.get_instance_shader_parameter(&"mesh_normal_basis") == true, "lighting: real mesh opts into its deformed normal basis")
		elif part is Sprite2D:
			rigid += 1
			s.check(part.get_instance_shader_parameter(&"mesh_normal_basis") != true, "lighting: rigid sprite retains original normal basis")
	s.check(meshes > 0 and rigid > 0, "lighting: both real renderer kinds were exercised")
	var item := Sprite2D.new()
	item.texture = LitTextures.load_texture("res://art/environment/scene_props/ali_kitchen_contacts/bowl.png")
	item.offset = Vector2(3, -2)
	item.position = Vector2(4, -35)
	item.z_index = 7
	item.region_enabled = true
	item.region_rect = Rect2(1, 2, 6, 7)
	rig.add_child(item)
	var texture := item.texture
	var transform := item.transform
	var body_count := rig._parts.size()
	var tint := Color(0.4, 0.7, 0.9, 0.35)
	s.check(rig.bind_attachment(item, tint), "lighting: a reflective attachment binds")
	rig._apply_fill(2.5)
	rig._apply_light_cap(0.32)
	s.check(item.material == rig._light_material and item.texture == texture and texture is CanvasTexture,
		"lighting: held bowl retains its real CanvasTexture and uses body lighting")
	s.check(WorldPropAction._held_texture("res://art/environment/scene_props/ali_kitchen_contacts/bowl.png", texture) == texture,
		"lighting: actual place/insert texture path selects the existing bowl normal")
	var disc := load("res://art/items/world/ch1_data_disk.png") as Texture2D
	s.check(WorldPropAction._held_texture("res://art/items/world/ch1_data_disk.png", disc) == disc,
		"lighting: a legacy held disc without normal remains a valid flat-lit texture")
	s.check(item.self_modulate.is_equal_approx(Color(1.0, 1.75, 2.25, 0.35)), "lighting: attachment preserves RGB tint and alpha while applying fill once")
	s.check(item.transform == transform and item.offset == Vector2(3, -2) and item.z_index == 7 and item.region_rect == Rect2(1, 2, 6, 7),
		"lighting: binding cannot change held geometry, crop, pivot or layer")
	s.check(rig._parts.size() == body_count, "lighting: held objects do not become armor or body bounds parts")
	var material := item.material
	for tick in 120:
		rig._apply_fill(2.5)
	s.check(item.material == material and rig._attachments.size() == 1, "lighting: repeated updates reuse one binding and material")
	rig.flash()
	s.check(is_equal_approx(item.self_modulate.r, 1.4) and is_equal_approx(item.self_modulate.a, tint.a), "lighting: held objects share real flash without changing alpha")
	rig.animate(0.1, RigInput.new())
	var foreign := CanvasItemMaterial.new()
	foreign.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	item.material = foreign
	item.self_modulate = Color(0.2, 0.3, 0.4, 0.5)
	rig._apply_fill(3.0)
	s.check(item.material == foreign and item.self_modulate == Color(0.2, 0.3, 0.4, 0.5), "lighting: foreign effect owns its material and tint")
	item.material = null
	rig._apply_fill(3.0)
	s.check(item.material == material and item.self_modulate.is_equal_approx(Color(1.2, 2.1, 2.7, 0.35)), "lighting: reflective binding resumes after the effect releases it")
	rig.unbind_attachment(item)
	s.check(item.material == null and item.self_modulate == tint and rig._attachments.is_empty(), "lighting: release restores unlit-owner base tint and removes binding")
	rig.bind_attachment(item, tint)
	item.free()
	rig._apply_fill(1.0)
	s.check(rig._attachments.is_empty(), "lighting: a freed attachment cannot leave an invalid-node binding")
	var glow := Sprite2D.new()
	rig.add_child(glow)
	LightKit.mark_emissive(glow)
	s.check(not rig.bind_attachment(glow) and glow.material == LightKit.emissive_material(), "lighting: emission is never silently rebound as reflective")
	rig.free()


static func npc_context(s: TestSuite) -> void:
	var npc := NpcActor.new()
	npc.configure(load("res://data/npcs/ch1_egret.tres") as NpcData, Vector2i(3, 2))
	s.runner.add_child(npc)
	s.check(npc._actor != null and npc._actor.rig != null and npc._actor.rig.use_level_lighting,
		"lighting: real world NPC uses the level context")
	var stage := CutsceneActor.new()
	s.runner.add_child(stage)
	s.check(stage.setup(&"lighting_stage", "egret", "", 1.0, "") and not stage.rig.use_level_lighting,
		"lighting: independent stage does not inherit world fill")
	var old_fill := LightKit.character_fill
	var old_cap := LightKit.character_light_cap
	LightKit.character_fill = 3.1
	LightKit.character_light_cap = 0.43
	npc._actor.rig.animate(0.0, RigInput.new())
	stage.rig.animate(0.0, RigInput.new())
	s.check(is_equal_approx(npc._actor.rig._fill, 3.1) and is_equal_approx(npc._actor.rig._light_cap, 0.43)
		and is_equal_approx(stage.rig._fill, 1.0), "lighting: world and stage actually consume separate contexts")
	stage.rig.set_local_lighting(Color(0.25, 0.25, 0.25))
	stage.rig.animate(0.0, RigInput.new())
	s.check(is_equal_approx(stage.rig._fill, 1.0) and is_equal_approx(stage.rig._light_cap, LightKit.character_light_cap_for(0.25, 1.0))
		and is_equal_approx(LightKit.character_fill, 3.1), "lighting: a stage-local ambient changes its cap without touching level globals")
	stage.rig.set_local_lighting(Color.WHITE)
	s.check(is_equal_approx(stage.rig._light_cap, LightKit.character_light_cap_for(1.0, 1.0)), "lighting: white stage default restores the published cap")
	LightKit.character_fill = old_fill
	LightKit.character_light_cap = old_cap
	npc.free()
	stage.free()


static func debris(s: TestSuite) -> void:
	var texture := LitTextures.load_texture("res://art/characters/trooper/parts/head.png")
	var tint := Color(0.7, 1.4, 1.75, 0.6)
	var piece := RigDebris.spawn(texture, Transform2D.IDENTITY, Vector2(2, 3), Vector2.ZERO, tint, 2.5, 0.4, 3)
	s.check(piece != null, "lighting: pooled reflective debris is available")
	if piece == null:
		return
	s.check(piece._sprite.texture == texture and piece._sprite.self_modulate == tint and piece._sprite.light_mask == 3,
		"lighting: debris retains normal texture, source tint/alpha and light mask")
	var material := piece._sprite.material as ShaderMaterial
	s.check(material != null and is_equal_approx(float(material.get_shader_parameter("fill")), 2.5)
		and is_equal_approx(float(material.get_shader_parameter("light_cap")), 0.4), "lighting: detached armor keeps its capped-light response")
	piece._recycle()
	var again := RigDebris.spawn(texture, Transform2D.IDENTITY, Vector2.ZERO, Vector2.ZERO, Color(0.8, 0.8, 0.8), 1.0, -1.0)
	s.check(again == piece and again._sprite.material == null and again._sprite.self_modulate == Color(0.8, 0.8, 0.8) and again._sprite.light_mask == 1,
		"lighting: a recycled chain piece cannot inherit armor tint, material or mask")
	again.cancel()
	again.free()


static func dissolve(s: TestSuite) -> void:
	var rig := CharacterRig.new()
	s.runner.add_child(rig)
	rig.setup("trooper")
	rig._apply_fill(2.7)
	rig._apply_light_cap(0.36)
	rig.set_dissolve(0.2)
	var material := rig._dissolve_material
	s.check(is_equal_approx(float(material.get_shader_parameter("fill")), 2.7)
		and is_equal_approx(float(material.get_shader_parameter("light_cap")), 0.36), "lighting: dissolve inherits the actual base fill and cap")
	rig._apply_fill(1.4)
	rig._apply_light_cap(0.25)
	rig.set_dissolve(0.3)
	s.check(rig._dissolve_material == material and is_equal_approx(float(material.get_shader_parameter("fill")), 1.4)
		and is_equal_approx(float(material.get_shader_parameter("light_cap")), 0.25), "lighting: dissolve reuses its material and follows a region change")
	rig.free()


static func worm(s: TestSuite) -> void:
	var worm := WormCreature.new()
	s.runner.add_child(worm)
	worm.setup("cloud_serpent")
	worm.global_position = Vector2(170, 80)
	worm.reset_trail(Vector2.RIGHT)
	worm.animate(1.0 / 60.0)
	var body := worm.get_node("Body") as Polygon2D
	var head := worm.get_node("Head") as Sprite2D
	var points := body.polygon
	for value: float in [1.0, 0.6, 0.1, 0.0, 1.0]:
		worm.set_opacity(value)
		s.check(is_equal_approx(body.modulate.a, value) and is_equal_approx(worm.modulate.a * head.modulate.a, value),
			"lighting: world mesh and child head each receive opacity once at %.1f" % value)
	s.check(body.polygon == points and body.top_level and head.texture is CanvasTexture and body.texture is CanvasTexture,
		"lighting: fade preserves world mesh, body normals and head normals")
	worm.free()
