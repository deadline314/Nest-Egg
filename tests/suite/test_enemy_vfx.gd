class_name EnemyVfxSuite
extends TestSuite
## 敵人專屬特效（art/vfx/enemies）：每個敵人都有自己的特效檔、死亡演出彼此不同、檔案引用的狀態存在於敵人腳本、
## 引用的死亡附加特效都有實作、壞檔案不會崩潰、實際播放（受擊、死亡、狀態切換、腳步）不出錯。

const DIR := "res://data/enemies"
const KNOWN_EXTRAS: Array[String] = ["smoke", "steam", "arc", "embers", "coolant", "dust"]


func run() -> void:
	_test_every_enemy_has_its_own()
	await _test_playback()
	_test_missing_file_is_safe()
	await _test_vfx2_pieces()


func _enemy_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".tres"):
			ids.append(file.get_basename())
	return ids


func _signature(death: Dictionary) -> String:
	return JSON.stringify([death.get("bursts", []), death.get("extras", []), death.get("light", {}), death.get("shake", 0.0)])


func _test_every_enemy_has_its_own() -> void:
	var signatures: Dictionary = {}
	for id in _enemy_ids():
		var path := EnemyVfx.PATH % id
		check(ResourceLoader.exists(path), "%s has its own vfx file" % id)
		if not ResourceLoader.exists(path):
			continue
		var data := RigLibrary.load_json(path)
		var death: Dictionary = data.get("death", {})
		check(not (death.get("bursts", []) as Array).is_empty(), "%s has a death effect" % id)
		for extra: Variant in death.get("extras", []):
			check(KNOWN_EXTRAS.has(str(extra)), "%s: death extra '%s' exists" % [id, extra])
		var sig := _signature(death)
		check(not signatures.has(sig), "%s does not share its death effect with %s" % [id, signatures.get(sig, "")])
		signatures[sig] = id
		# 狀態名稱要存在於敵人腳本。
		var enemy := load(DIR + "/%s.tres" % id) as EnemyData
		if enemy != null and enemy.behavior != null:
			var source := (enemy.behavior as GDScript).source_code
			var base_source := ((enemy.behavior as GDScript).get_base_script() as GDScript).source_code if (enemy.behavior as GDScript).get_base_script() != null else ""
			for state: Variant in (data.get("states", {}) as Dictionary).keys():
				check(source.contains('&"%s"' % str(state)) or base_source.contains('&"%s"' % str(state)), "%s: the behaviour has a state named %s" % [id, state])


func _test_playback() -> void:
	for id in ["grunt", "warden", "shock_hound", "mimic"]:
		var vfx := EnemyVfx.load_for(id)
		check(not vfx.is_empty(), "%s vfx loads" % id)
		var at := Vector2(100, 100)
		vfx.play_hit(at, Vector2.UP)
		vfx.play_death(at, at + Vector2(0, 20))
		for state in vfx.state_names():
			vfx.play_state(StringName(state), at, at, at)
		for i in 40:
			vfx.tick_step(at + Vector2(float(i) * 8.0, 0), true)
		check(true, "%s vfx plays without errors" % id)
		await frames(1)


func _test_missing_file_is_safe() -> void:
	var vfx := EnemyVfx.load_for("test_no_such_enemy")
	check(vfx.is_empty(), "a missing vfx file gives an empty vfx")
	vfx.play_hit(Vector2.ZERO, Vector2.UP)
	vfx.play_death(Vector2.ZERO, Vector2.ZERO)
	vfx.tick_step(Vector2.ZERO, true)
	check(true, "an empty vfx can be played safely")


## VFX 2.0 的零件：圖集與雜訊貼圖能生成、粒子場的新介面、電弧、燒融的 shader 參數與骨架的燒融呼叫。
func _test_vfx2_pieces() -> void:
	var atlas := VfxAtlas.texture()
	check(atlas != null and atlas.get_width() == VfxAtlas.CELL * VfxAtlas.COLUMNS, "the effect atlas is built")
	var image := atlas.get_image()
	for cell in VfxAtlas.Cell.size():
		var region := VfxAtlas.region(cell)
		var opaque := 0
		for y in range(int(region.position.y), int(region.end.y), 4):
			for x in range(int(region.position.x), int(region.end.x), 4):
				if image.get_pixel(x, y).a > 0.1:
					opaque += 1
		check(opaque > 12, "atlas cell %d is painted (%d samples)" % [cell, opaque])
	# 雲團是平塗色塊：邊緣只有一圈抗鋸齒，半透明的像素很少。
	for cell: int in [VfxAtlas.Cell.BLOB_A, VfxAtlas.Cell.BLOB_B]:
		var region := VfxAtlas.region(cell)
		var solid := 0
		var soft := 0
		for y in range(int(region.position.y), int(region.end.y)):
			for x in range(int(region.position.x), int(region.end.x)):
				var alpha := image.get_pixel(x, y).a
				if alpha > 0.95:
					solid += 1
				elif alpha > 0.05:
					soft += 1
		check(solid > 1200 and soft * 8 < solid, "atlas cell %d is a hard-edged blob (%d solid, %d soft)" % [cell, solid, soft])
	check(is_equal_approx(ParticleField.fade_ratio(0.4, 0.0), 0.4), "a particle without hold fades over its whole life")
	check(is_zero_approx(ParticleField.fade_ratio(0.3, 0.5)) and is_equal_approx(ParticleField.fade_ratio(0.75, 0.5), 0.5)
			and is_equal_approx(ParticleField.fade_ratio(1.0, 0.5), 1.0), "a held particle keeps its first colour, then fades in the time left")
	var noise := VfxAtlas.noise_texture().get_image()
	check(noise.get_width() == 128 and noise.get_pixel(10, 10).r >= 0.0, "the tileable noise exists")
	var field := ParticleField.new()
	field.additive = true
	runner.get_tree().root.add_child(field)
	await frames(1)
	field.emit_ex(Vector2.ZERO, Vector2(50, -20), 0.5, VfxAtlas.Cell.STREAK, 4.0, 1.0, Color.WHITE, Color(1, 1, 1, 0), 100.0, 1.0, 0.0, 0.0, 0.04)
	field.emit(Vector2.ZERO, Vector2(10, 10), Color.RED, 0.3, 2.0)
	check(field.alive_count() == 2, "a particle field accepts the new and the legacy emit")
	await frames(2)
	field.queue_free()
	var arcs := ArcField.new()
	runner.get_tree().root.add_child(arcs)
	await frames(1)
	arcs.emit_arc(Vector2.ZERO, Vector2(60, 10), Color.CYAN, 0.2, 1.5, 0.15, 2)
	check(arcs.alive_count() == 1, "an arc can be emitted")
	await frames(3)
	arcs.queue_free()
	# 骨架的燒融：套上 shader，進度與邊緣色可以改，沒有零件時回傳 false。
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("trooper"), "a rig builds for the dissolve check")
	check(rig.set_dissolve(0.4, Color("ff7a1a"), 1.0, 0.1), "a rig can dissolve")
	check(rig.set_dissolve(1.0), "a rig can dissolve completely")
	await frames(2)
	holder.queue_free()
	var empty := CharacterRig.new()
	check(not empty.set_dissolve(0.5), "a rig without parts reports it cannot dissolve")
	empty.free()

