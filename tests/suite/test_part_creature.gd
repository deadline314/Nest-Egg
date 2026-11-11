class_name PartCreatureSuite
extends TestSuite
## 零件式生物（PartCreature，NE-99／NE-100）：每份資料都建得起來、各狀態外觀不同且沒有 NaN、每格移動量有限、
## 壞資料不會崩潰（缺貼圖、缺父零件、不存在的狀態）、有 show 的狀態只顯示指定零件、瞄準與槍口跟著轉。

const CREATURES: Array[String] = ["drone", "searchlight_drone", "repair_drone", "bomber", "shock_hound", "turret", "mimic", "watchdog"]
const DT := 1.0 / 60.0
const MAX_STEP := 6.0


func run() -> void:
	_test_all_build_and_states()
	_test_smooth_motion()
	_test_show_and_aim()
	_test_optional_lighting()
	_test_bad_data_is_safe()


func _test_optional_lighting() -> void:
	var source := LightingProfile.new()
	var enabled := LightingProfile.new()
	enabled.creature_floor = 0.6
	var mixed := LightingProfile.new()
	check(source.creature_floor == 0.0, "old profiles leave creature lighting disabled")
	LightingProfile.blend_into(mixed, source, enabled, 0.5)
	check(is_equal_approx(mixed.creature_floor, 0.3), "optional creature floor follows real zone interpolation")
	var creature := _make("drone")
	var originals: Array[Dictionary] = []
	for part in creature._parts:
		var sprite: Sprite2D = part.sprite
		originals.append({"material": sprite.material, "tint": sprite.self_modulate, "texture": sprite.texture})
	creature.set_lighting(0.0, 0.5)
	check(creature._light_material == null, "default zero allocates no material")
	for i in creature._parts.size():
		var sprite: Sprite2D = creature._parts[i].sprite
		check(sprite.material == originals[i].material and sprite.self_modulate == originals[i].tint,
			"default zero preserves material and authored tint: %d" % i)
	creature.set_lighting(2.4, 0.608)
	var cached := creature._light_material
	check(cached != null and cached.shader == PartCreature.LIGHT_SHADER, "enabled creatures use existing normal-aware capped lighting")
	for tick in 120: creature.set_lighting(2.4, 0.608)
	check(creature._light_material == cached, "unchanged frames retain one instance material")
	creature.flash()
	var flash := creature.modulate
	creature.set_lighting(3.0, 0.4)
	check(creature.modulate == flash and creature._flash_left > 0.0, "lighting keeps the authored flash and parent tint")
	var sprite: Sprite2D = creature._parts[0].sprite
	var foreign := ShaderMaterial.new()
	foreign.shader = preload("res://art/shaders/dissolve.gdshader")
	var effect_tint := Color(1, 0.2, 0.1, 0.6)
	sprite.material = foreign
	sprite.self_modulate = effect_tint
	creature.set_lighting(4.0, 0.32)
	check(sprite.material == foreign and sprite.self_modulate == effect_tint, "foreign dissolve and tint keep ownership")
	sprite.material = originals[0].material
	sprite.self_modulate = originals[0].tint
	creature.set_lighting(4.0, 0.32)
	check(sprite.material == cached and sprite.self_modulate.r > effect_tint.r, "effect release resumes lighting without a zone change")
	var last_lit := sprite.self_modulate
	sprite.material = foreign
	creature.set_lighting(0.0, 0.5)
	check(sprite.material == foreign and sprite.self_modulate == last_lit, "area exit leaves active dissolve untouched")
	sprite.material = originals[0].material
	creature.set_lighting(0.0, 0.5)
	check(not creature._lighting_pending, "deferred area-exit restoration finishes after dissolve")
	for i in creature._parts.size():
		var part: Sprite2D = creature._parts[i].sprite
		check(part.material == originals[i].material and part.self_modulate == originals[i].tint and part.texture == originals[i].texture,
			"area round trip restores exact material, tint and normal texture: %d" % i)
	creature.queue_free()


func _make(id: String) -> PartCreature:
	var creature := PartCreature.new()
	runner.get_tree().root.add_child(creature)
	check(creature.setup(id), "part creature builds: %s" % id)
	return creature


func _snapshot(creature: PartCreature) -> PackedVector2Array:
	var points := PackedVector2Array()
	for part_name in creature.part_names():
		points.append(creature.joint_of(part_name).global_position)
		points.append(Vector2(creature.joint_of(part_name).global_rotation, creature.joint_of(part_name).visible as float))
	return points


func _test_all_build_and_states() -> void:
	for id in CREATURES:
		var data := RigLibrary.load_json(PartCreature.PATH % id)
		var states: Array = (data.get("states", {}) as Dictionary).keys()
		check(states.size() >= 2, "%s has states" % id)
		var creature := _make(id)
		var looks: Dictionary = {}
		for state in states:
			for i in 90:
				creature.animate(DT, StringName(state), Vector2(60.0, 0.0), 1, 0.0)
			var snap := _snapshot(creature)
			var finite := true
			for p in snap:
				finite = finite and is_finite(p.x) and is_finite(p.y)
			check(finite, "%s/%s finite" % [id, state])
			looks[str(snap)] = true
		check(looks.size() >= maxi(2, states.size() - 2), "%s states look different (%d of %d)" % [id, looks.size(), states.size()])
		creature.queue_free()


func _test_smooth_motion() -> void:
	for id in CREATURES:
		var data := RigLibrary.load_json(PartCreature.PATH % id)
		var states: Array = (data.get("states", {}) as Dictionary).keys()
		var creature := _make(id)
		var last := _snapshot(creature)
		var worst := 0.0
		for n in 240:
			creature.animate(DT, StringName(states[(n / 20) % states.size()]), Vector2(70.0, 0.0), 1, 0.0)
			var now := _snapshot(creature)
			for i in range(0, now.size(), 2):
				worst = maxf(worst, now[i].distance_to(last[i]))
			last = now
		check(worst <= MAX_STEP, "%s moves smoothly (max step %.2f px)" % [id, worst])
		creature.queue_free()


func _test_show_and_aim() -> void:
	var mimic := _make("mimic")
	for i in 60:
		mimic.animate(DT, &"idle")
	check(mimic.joint_of("closed").visible and not mimic.joint_of("open").visible, "mimic idle shows only the closed crate")
	for i in 60:
		mimic.animate(DT, &"exposed")
	check(not mimic.joint_of("closed").visible and mimic.joint_of("open").visible, "mimic exposed shows only the open crate")
	mimic.queue_free()
	var turret := _make("turret")
	for i in 5:
		turret.animate(DT, &"track", Vector2.ZERO, 1, 0.0)
	var level := turret.muzzle_global("barrel")
	for i in 5:
		turret.animate(DT, &"track", Vector2.ZERO, 1, -0.6)
	var raised := turret.muzzle_global("barrel")
	check(raised.y < level.y - 4.0, "turret muzzle rises with aim")
	turret.kick()
	turret.animate(DT, &"track", Vector2.ZERO, 1, 0.0)
	check(turret.muzzle_global("barrel").distance_to(level) > 0.5, "turret barrel recoils when kicked")
	turret.queue_free()


func _test_bad_data_is_safe() -> void:
	var missing := PartCreature.new()
	runner.get_tree().root.add_child(missing)
	check(not missing.setup("no_such_creature"), "missing creature data returns false")
	missing.animate(DT, &"idle")
	missing.queue_free()
	var drone := _make("drone")
	for i in 10:
		drone.animate(DT, &"no_such_state", Vector2.ZERO, -1, 0.0)
	check(is_finite(drone.joint_of("body").position.x), "unknown state falls back safely")
	drone.queue_free()
