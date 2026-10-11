extends RefCounted
## 續玩位置正好在走過即觸發的出入口裡（NE-230 實測：金庫入口存檔、重開被送回倉庫）。
## 和穿過出入口抵達時一樣，要先離開一次才會觸發。

const VAULT := "res://data/levels/ch1_vault.tres"
const BACK := &"vault_prev"


static func run(s: TestSuite) -> void:
	var previous_skip := Story.auto_skip
	Story.auto_skip = true
	var data := load(VAULT) as LevelData
	var probe := Level.new()
	probe.configure(data)
	s.runner.get_tree().root.add_child(probe)
	await s.frames(2)
	var walk: Portal = probe._portals.get(BACK)
	s.check(walk != null and walk.data.mode == PortalData.Mode.WALK, "vault has a real walk-through portal back to the warehouse")
	if walk == null:
		probe.queue_free()
		Story.auto_skip = previous_skip
		return
	var spot := walk.position + Vector2(0, -2)
	probe.queue_free()
	await s.frames(2)
	var level := Level.new()
	level.configure(data)
	level.configure_resume({"position": [spot.x, spot.y], "health": 5, "world": {}, "loadout": {}, "area": {"consumed": {}, "damage": {}, "world": {}}})
	var requested: Array[String] = []
	level.area_requested.connect(func(path: String) -> void: requested.append(path))
	s.runner.get_tree().root.add_child(level)
	await s.frames(2)
	for i in 10:
		await s.runner.get_tree().physics_frame
	var portal: Portal = level._portals.get(BACK)
	s.check(requested.is_empty(), "restored player standing in a walk portal is not sent away on load")
	s.check(portal != null and not portal.is_armed(), "that portal waits until the player leaves it once")
	s.check(portal != null and not portal.contains_point(portal.position + Vector2(portal.data.width + 40, 0)), "points beside the portal are outside its trigger area")
	level.queue_free()
	await s.frames(2)
	Story.auto_skip = previous_skip
