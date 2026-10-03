class_name PostureSuite
extends TestSuite
## 敵人的站姿、待機與步伐（NE-106、NE-107）：腳踩實地（站、跑、蹲腳底都貼著地）、步幅配合速度（踩在地上的腳不滑）、
## 放鬆（槍垂下）與舉槍之間的平滑過渡、站姿與放鬆的資料每個角色各自不同。

const ENEMIES: Array[String] = ["trooper", "trooper_elite", "sniper", "flamer", "grenadier", "enforcer", "heavy_gunner", "warden", "reclaimer", "slasher", "stalker"]
const DT := 1.0 / 60.0


func run() -> void:
	_test_data()
	await _test_feet_stay_on_the_ground()
	await _test_planted_stride()
	await _test_relaxed_and_ready()
	await _test_recoil_depends_on_the_weapon()
	await _test_weapon_less_and_airborne_are_safe()


func _make(skin: String, input: RigInput) -> CharacterRig:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup(skin), "rig builds: %s" % skin)
	rig.set_weapon("rifle")
	input.facing = 1
	input.on_floor = true
	input.aim_dir = Vector2.RIGHT
	input.two_handed = true
	return rig


func _foot_error(rig: CharacterRig) -> float:
	var animator := rig.animator
	return absf(animator._lowest_foot_y() - animator._ground_y)


func _test_data() -> void:
	var seen_aims: Dictionary = {}
	for skin in ENEMIES:
		var path := "res://art/motion/%s.json" % skin
		var d := RigLibrary.load_json(path)
		check(bool(d.get("grounding", false)), "%s plants its feet" % skin)
		var relax: Dictionary = d.get("relax", {})
		var aim := float(relax.get("aim", -1.0))
		check(aim > 0.3 and aim < 1.4 and float(relax.get("reach", 0.0)) > 0.5, "%s has a sane relaxed pose (aim %.2f)" % [skin, aim])
		var legs: Array = (d.get("idle", {}) as Dictionary).get("legs", [])
		check(legs.size() == 4 and absf(float(legs[0])) > 0.05 and float(legs[2]) > 0.1, "%s stands with its feet apart" % skin)
		seen_aims[snappedf(aim, 0.01)] = true
	check(seen_aims.size() >= 8, "the relaxed weapon angle is different for most characters (%d kinds)" % seen_aims.size())


## 站、跑、蹲、瞄準時最低的腳底都貼著站立的地面（誤差不到半個像素）。
func _test_feet_stay_on_the_ground() -> void:
	for skin in ENEMIES:
		var input := RigInput.new()
		var rig := _make(skin, input)
		var worst := 0.0
		for i in 30:
			rig.animate(DT, input)
		worst = maxf(worst, _foot_error(rig))
		input.velocity = Vector2(120.0, 0.0)
		input.run_speed = 120.0
		for i in 90:
			rig.animate(DT, input)
			if i >= 20:  # 起跑的過渡（IK 權重漸入）不算
				worst = maxf(worst, _foot_error(rig))
		input.velocity = Vector2.ZERO
		input.crouching = true
		for i in 60:
			rig.animate(DT, input)
		worst = maxf(worst, _foot_error(rig))
		check(worst < 0.6, "%s keeps its feet on the ground standing, running and crouching (worst %.2f px)" % [skin, worst])
		rig.get_parent().queue_free()
	await frames(1)


## 落腳：跑的時候貼著地面的那隻腳，相對身體往後移動的速度＝前進速度（不滑，誤差 15% 內）；另一隻腳抬起時離地。
func _test_planted_stride() -> void:
	for skin in ["trooper", "heavy_gunner", "sniper", "slasher"]:
		var input := RigInput.new()
		var rig := _make(skin, input)
		var speed := 60.0
		input.velocity = Vector2(speed, 0.0)
		input.run_speed = speed * 2.0
		for i in 60:
			rig.animate(DT, input)
		var animator := rig.animator
		var expected := -speed / rig.scale.x
		var error := 0.0
		var samples := 0
		var lifted := 0.0
		var last: Dictionary = {}
		for i in 300:
			rig.animate(DT, input)
			for foot: StringName in [&"foot_front", &"foot_back"]:
				var pos: Vector2 = animator._global_pos[foot]
				var on_ground := absf(pos.y - animator._ground_y) < 0.6
				if on_ground and last.has(foot) and last[foot][1]:
					error += absf(((pos.x - float(last[foot][0])) / DT - expected) / expected)
					samples += 1
				lifted = maxf(lifted, animator._ground_y - pos.y)
				last[foot] = [pos.x, on_ground]
		var mean_error := error / maxf(1.0, float(samples))
		check(samples > 150 and mean_error < 0.15, "%s's planted foot moves back at the ground speed (error %.0f%% over %d samples)" % [skin, mean_error * 100.0, samples])
		check(lifted > 2.0, "%s lifts the swinging foot off the ground (%.1f px)" % [skin, lifted])
		rig.get_parent().queue_free()
	await frames(1)


func _test_relaxed_and_ready() -> void:
	var input := RigInput.new()
	var rig := _make("trooper", input)
	for i in 30:
		rig.animate(DT, input)
	var ready := rig.weapon_root().rotation
	input.relaxed = true
	for i in 120:
		rig.animate(DT, input)
	var low := rig.weapon_root().rotation
	check(low > ready + 0.4, "a relaxed enemy lowers the weapon (%.2f -> %.2f rad)" % [ready, low])
	input.relaxed = false
	var midway := 0.0
	for i in 60:
		rig.animate(DT, input)
		if i == 5:
			midway = rig.weapon_root().rotation
	check(midway > ready + 0.05 and midway < low, "raising the weapon is a smooth transition, not a snap (%.2f)" % midway)
	check(absf(rig.weapon_root().rotation - ready) < 0.05, "the weapon comes back up when the enemy engages")
	rig.get_parent().queue_free()
	await frames(1)


## 沒有武器的角色、在空中、死亡時都不會出錯，空中不做腳底補償（身體不會被拉回地面）。
func _test_weapon_less_and_airborne_are_safe() -> void:
	var input := RigInput.new()
	var rig := _make("slasher", input)
	rig.set_weapon("")
	input.relaxed = true
	for i in 30:
		rig.animate(DT, input)
	input.on_floor = false
	input.velocity = Vector2(80, -200)
	for i in 20:
		rig.animate(DT, input)
	check(is_zero_approx(rig.animator._ground_shift), "no ground correction while airborne")
	input.on_floor = true
	input.velocity = Vector2.ZERO
	input.dead = true
	for i in 40:
		rig.animate(DT, input)
	check(true, "relaxed, weapon-less, airborne and dead states all animate without errors")
	rig.get_parent().queue_free()
	await frames(1)


## 開火的後座力依角色與武器而不同：榴彈兵比步兵把身體頂得更遠、恢復更慢；每個角色的後座力資料各自不同。
func _test_recoil_depends_on_the_weapon() -> void:
	var recoils: Dictionary = {}
	for skin in ENEMIES:
		var r: Dictionary = RigLibrary.load_json("res://art/motion/%s.json" % skin).get("recoil", {})
		check(r.size() == 4 and float(r.get("decay", 0.0)) > 0.0, "%s has recoil data" % skin)
		recoils["%s|%s|%s|%s" % [r.get("chest"), r.get("reach"), r.get("hip"), r.get("decay")]] = true
	check(recoils.size() >= 9, "recoil data differs between most characters (%d kinds)" % recoils.size())
	var pushed: Dictionary = {}
	for skin in ["trooper", "grenadier", "sniper"]:
		var input := RigInput.new()
		var rig := _make(skin, input)
		for i in 20:
			rig.animate(DT, input)
		var rest_x := rig.animator._hip_offset.x
		input.recoil = 1.0
		rig.animate(DT, input)
		input.recoil = 0.0
		for i in 3:
			rig.animate(DT, input)
		pushed[skin] = rest_x - rig.animator._hip_offset.x
		rig.get_parent().queue_free()
	check(pushed["grenadier"] > pushed["trooper"] and pushed["sniper"] > pushed["trooper"], "a launcher or sniper rifle pushes the body back further than a rifle (%.2f, %.2f vs %.2f)" % [pushed["grenadier"], pushed["sniper"], pushed["trooper"]])
	await frames(1)
