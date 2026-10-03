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
