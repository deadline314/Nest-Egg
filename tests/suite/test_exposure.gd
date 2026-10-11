class_name ExposureSuite
extends TestSuite
## 主角曝光（NE-213）：每一份光影設定下，白色零件的曝光估計峰值不超過預算（亮場景玩家自己的光自動調暗、
## 單盞光對角色有亮度上限）、泛光有亮度上限、貼近玩家的閃光有能量上限、玩家的光在關卡裡確實跟著調整、
## 角色的零件與武器都用「每盞光有上限、不被補光放大」的受光材質（Forward+ 實測：頭在燈下全白的像素從約 13% 降到 0.8%）。
## 注意：真正的泛光只在 Forward+ 的 HDR 2D 下出現，無頭與 Compatibility 渲染器量不到，所以這裡檢查的是決定曝光的數字。

const LIGHTING_DIR := "res://data/lighting"
## 估計峰值允許超出預算多少（附近燈光的預留本身是估計值）。
## 本來就很亮的設定（環境光已接近全亮，例如 neutral、白色診所）也要在這個範圍內。
const TOLERANCE := 0.4
const MAX_FILL := 4.0


func run() -> void:
	_test_budget_model()
	_test_every_profile_stays_in_budget()
	_test_glow_cap()
	_test_flash_cap()
	_test_character_light_cap()
	await _test_rig_uses_the_light_material()
	await _test_player_light_follows_the_scene()
	await _test_enemy_fill_is_separate()
	await _test_weapon_light()
	_test_brightness_tiers()


func _test_budget_model() -> void:
	check(is_equal_approx(LightKit.player_light_for(0.05, 1.0), LightKit.PLAYER_LIGHT_BASE_ENERGY), "a dark scene keeps the full player light")
	check(LightKit.player_light_for(0.9, 1.0) == LightKit.PLAYER_LIGHT_MIN_ENERGY, "a bright scene dims the player light to its minimum")
	var previous := 10.0
	for ambient in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0]:
		var energy := LightKit.player_light_for(ambient, 1.0)
		check(energy <= previous + 0.0001, "the player light never grows as the scene gets brighter (%.1f: %.2f)" % [ambient, energy])
		previous = energy
	check(LightKit.player_light_for(0.3, 3.0) <= LightKit.player_light_for(0.3, 1.0), "a stronger character fill also dims the player light")
	check(LightKit.capped_flash_energy(3.0, true) == LightKit.NEAR_CHARACTER_FLASH_CAP, "a flash on top of the player is capped")
	check(LightKit.capped_flash_energy(3.0, false) == 3.0 and LightKit.capped_flash_energy(0.8, true) == 0.8, "far flashes and gentle flashes are untouched")


func _test_character_light_cap() -> void:
	check(LightKit.character_light_cap_for(0.05, 1.0) == LightKit.CHARACTER_LIGHT_CAP_MAX, "a dark scene allows the largest per-light cap")
	check(LightKit.character_light_cap_for(1.0, 1.0) == LightKit.CHARACTER_LIGHT_CAP_MIN, "a fully lit scene allows only the smallest per-light cap")
	var previous := 10.0
	for ambient in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var cap := LightKit.character_light_cap_for(ambient, 1.0)
		check(cap <= previous + 0.0001 and cap >= LightKit.CHARACTER_LIGHT_CAP_MIN and cap <= LightKit.CHARACTER_LIGHT_CAP_MAX, "the cap never grows as the scene gets brighter (%.1f: %.2f)" % [ambient, cap])
		previous = cap
	check(LightKit.character_light_cap_for(0.3, 3.0) <= LightKit.character_light_cap_for(0.3, 1.0), "a stronger fill also lowers the cap")


## 角色的每個零件與武器都掛著共用的受光材質；補光倍率與亮度上限會寫進材質。
func _test_rig_uses_the_light_material() -> void:
	var holder := Node2D.new()
	runner.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	check(rig.setup("rin"), "rin builds for the light material check")
	var material := rig._light_material
	check(material != null and material.shader != null, "the rig has a light material")
	var parts := 0
	for part in rig.find_children("*", "CanvasItem", true, false):
		var item := part as CanvasItem
		if item.name == &"Glow" or item.material is CanvasItemMaterial:
			continue  # 發光層用加法混合，不受光
		if item is Sprite2D or item is Polygon2D:
			parts += 1
			check(item.material == material, "%s uses the capped light material" % item.name)
	check(parts >= 10, "the rig's lit parts were checked (%d)" % parts)
	LightKit.character_fill = 3.0
	LightKit.character_light_cap = 0.3
	rig.animate(0.016, RigInput.new())
	check(is_equal_approx(float(material.get_shader_parameter("fill")), 3.0) and is_equal_approx(float(material.get_shader_parameter("light_cap")), 0.3), "fill and cap are written into the material")
	LightKit.character_fill = 1.0
	LightKit.character_light_cap = LightKit.CHARACTER_LIGHT_CAP_MAX
	holder.queue_free()
	await frames(1)


func _test_every_profile_stays_in_budget() -> void:
	var checked := 0
	for file in DirAccess.get_files_at(LIGHTING_DIR):
		if not file.ends_with(".tres"):
			continue
		var profile := load("%s/%s" % [LIGHTING_DIR, file]) as LightingProfile
		if profile == null:
			continue
		checked += 1
		var ambient := maxf(0.01, LightKit.luminance(profile.ambient_color))
		var fill := clampf(profile.character_floor / ambient, 1.0, MAX_FILL)
		var exposure := LightKit.character_exposure(ambient, fill)
		check(exposure <= LightKit.CHARACTER_EXPOSURE_BUDGET + TOLERANCE, "%s: white parts peak at about %.2f (budget %.2f)" % [profile.id, exposure, LightKit.CHARACTER_EXPOSURE_BUDGET + TOLERANCE])
		check(profile.glow_intensity <= 1.2, "%s: glow intensity stays modest (%.2f)" % [profile.id, profile.glow_intensity])
		# 閃電把環境光拉到全亮時也一樣：玩家的光降到最低。
		var flashed := LightKit.character_exposure(1.0, 1.0)
		check(flashed <= LightKit.CHARACTER_EXPOSURE_BUDGET + 0.4, "a full-bright lightning flash keeps the character readable (%.2f)" % flashed)
	check(checked >= 20, "all the lighting profiles were checked (%d)" % checked)


func _test_glow_cap() -> void:
	var world_env := LightKit.create_environment()
	check(world_env.environment.glow_hdr_luminance_cap == LightKit.GLOW_LUMINANCE_CAP and LightKit.GLOW_LUMINANCE_CAP <= 3.0, "bloom has a luminance cap (%.1f)" % world_env.environment.glow_hdr_luminance_cap)
	check(LightKit.glow(Color.WHITE, 99.0).r <= LightKit.HDR_PEAK_MAX, "emissive colors are clamped as before")
	world_env.free()


func _test_flash_cap() -> void:
	# Fx 的閃光：玩家身上的被夾住，遠處的維持原樣。
	var level := await start_level(NewEnemiesSuite.arena_data())
	level.player.global_position = Vector2(200, 320)
	await frames(3)
	var before_near := _lit_flash_energy()
	Fx.flash_light(level.player.global_position + Vector2(0, -24), Palette.CYAN, 160.0, 3.0, 5.0)
	var near := _lit_flash_energy()
	Fx.flash_light(level.player.global_position + Vector2(400, 0), Palette.CYAN, 60.0, 3.0, 5.0)
	var far := _lit_flash_energy()
	check(near <= LightKit.NEAR_CHARACTER_FLASH_CAP + 0.001 and near > before_near, "a flash on the player is capped at %.1f (%.2f)" % [LightKit.NEAR_CHARACTER_FLASH_CAP, near])
	check(far >= 2.9, "a flash far from the player keeps its energy (%.2f)" % far)
	await end_level(level)


## 目前最新被點亮的閃光能量（Fx 的燈池輪流使用，取能量最大的那盞也行：這裡取最近設定的）。
func _lit_flash_energy() -> float:
	var latest := 0.0
	for light: PointLight2D in Fx._lights:
		if is_instance_valid(light) and light.enabled:
			latest = maxf(latest, light.energy) if light.energy > 0.0 else latest
	return latest


func _test_player_light_follows_the_scene() -> void:
	var level := await start_level(NewEnemiesSuite.arena_data())
	var player := level.player
	await physics_frames(150)
	var target := LightKit.player_light_energy
	check(target >= LightKit.PLAYER_LIGHT_MIN_ENERGY and target <= LightKit.PLAYER_LIGHT_BASE_ENERGY, "the scene's target for the player light is in range (%.2f)" % target)
	check(absf(player._light.energy - target) < 0.02, "the player light follows the scene's target (%.2f vs %.2f)" % [player._light.energy, target])
	await end_level(level)
	check(is_equal_approx(LightKit.player_light_energy, LightKit.PLAYER_LIGHT_BASE_ENERGY), "leaving the level restores the default player light")


## 牆面是中間調的室內：敵人的補光可以比主角低（成為剪影），但不會比環境光更暗；離開關卡後還原。
func _test_enemy_fill_is_separate() -> void:
	var data := NewEnemiesSuite.arena_data()
	var zone := LightingZone.new()
	zone.start_tile = 0
	zone.profile = load("res://data/lighting/warehouse_interior.tres")
	data.lighting_zones = [zone]
	var level := await start_level(data)
	var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	enemy.position = level.player.global_position + Vector2(160, 0)
	level._entities.add_child(enemy)
	await physics_frames(150)
	var profile := zone.profile as LightingProfile
	check(profile.enemy_fill_scale < 1.0 and profile.validate().is_empty(), "the warehouse interior asks for dimmer enemies and is valid data")
	check(LightKit.character_fill > 1.0 and LightKit.enemy_fill < LightKit.character_fill and LightKit.enemy_fill >= 1.0,
			"enemies get less fill than the player but never less than the scene (%.2f vs %.2f)" % [LightKit.enemy_fill, LightKit.character_fill])
	check(enemy.rig != null and is_equal_approx(enemy.rig._fill, LightKit.enemy_fill), "an enemy's body uses the enemy fill")
	check(is_equal_approx(level.player._visual.rig._fill, LightKit.character_fill), "the player's body keeps the character fill")
	var plain := LightingProfile.new()
	plain.ambient_color = Color(0.1, 0.1, 0.1)
	plain.character_floor = 0.4
	check(is_equal_approx(plain.enemy_fill_scale, 1.0), "by default enemies are lit like the player")
	plain.enemy_fill_scale = 0.2
	check(not plain.validate().is_empty(), "an enemy fill scale below the allowed range is reported")
	await end_level(level)
	check(is_equal_approx(LightKit.enemy_fill, 1.0), "leaving the level restores the default enemy fill")


## 槍燈（NE-258）：每把槍有自己的光、跟著瞄準走、近戰與死亡時沒有、照得到的地方算進場景的光。
func _test_weapon_light() -> void:
	var guns := ["pistol", "rifle", "smg", "spread", "launcher", "laser", "railgun"]
	var seen := {}
	for id: String in guns:
		var weapon := load("res://data/weapons/%s.tres" % id) as WeaponData
		check(weapon != null and weapon.has_light() and weapon.light_range >= 120.0 and weapon.light_range <= 360.0
				and weapon.light_cone_degrees >= 6.0 and weapon.light_cone_degrees <= 90.0 and weapon.light_energy > 0.0,
				"%s has a gun light with sane reach and cone" % id)
		seen["%d/%d" % [int(weapon.light_range), int(weapon.light_cone_degrees)]] = true
	check(seen.size() == guns.size(), "every gun's light has its own reach and cone (%d distinct)" % seen.size())
	check(not (load("res://data/weapons/mech_cannon.tres") as WeaponData).has_light(), "the vehicle cannon has no gun light")
	var blade := load("res://data/weapons/melee/melee_blade.tres") as WeaponData
	check(not blade.has_light(), "melee weapons have no gun light")
	# 光錐貼圖：頂點是暗的、正前方亮、兩側與背後沒有光；同一個張角共用同一張。
	var cone := LightKit.cone_texture(40.0)
	var image := cone.get_image()
	var mid := LightKit.CONE_TEXTURE_SIZE / 2
	check(image.get_pixel(mid, mid).a < 0.05, "the cone is dark at its tip so the holder is not lit")
	check(image.get_pixel(mid + int(mid * 0.4), mid).a > 0.3, "the cone is bright straight ahead")
	check(is_zero_approx(image.get_pixel(mid, mid - int(mid * 0.5)).a) and is_zero_approx(image.get_pixel(mid - int(mid * 0.5), mid).a),
			"nothing is lit to the side of or behind the cone")
	check(LightKit.cone_texture(40.4) == cone and LightKit.cone_texture(60.0) != cone, "cones of the same angle share one texture")
	var level := await start_level(NewEnemiesSuite.arena_data())
	var player := level.player
	var light := player._weapon_light
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	await physics_frames(40)
	check(light.is_lit() and light._light.enabled, "holding a gun turns its light on")
	check(absf(angle_difference(light.global_rotation, player.aim_dir.angle())) < 0.05, "the light points where the player aims")
	check(is_equal_approx(light.reach(), 300.0), "the light uses the held gun's reach")
	var glow_radius := player._light.texture_scale * LightKit.TEXTURE_SIZE * 0.5
	check(glow_radius < Player.SELF_GLOW_RADIUS_UNARMED - 20.0, "the glow around the player shrinks while the gun light is on (%.0f)" % glow_radius)
	var ahead := LightKit.light_level_at(runner.get_tree(), light.global_position + player.aim_dir * 120.0)
	var behind := LightKit.light_level_at(runner.get_tree(), light.global_position - player.aim_dir * 120.0)
	var beyond := LightKit.light_level_at(runner.get_tree(), light.global_position + player.aim_dir * 400.0)
	check(ahead > behind + 0.2 and is_equal_approx(beyond, behind), "the gun light counts as scene light only inside its cone and reach (%.2f ahead, %.2f behind)" % [ahead, behind])
	AimInput._last_stick_dir = Vector2.UP
	await physics_frames(30)
	check(absf(angle_difference(light.global_rotation, -PI * 0.5)) < 0.2, "the light follows the aim upward")
	# 開火後變暗、可以再開火時恢復的武器。
	AimInput._last_stick_dir = Vector2.RIGHT
	var railgun := load("res://data/weapons/railgun.tres") as WeaponData
	player.loadout.equip(railgun)
	await physics_frames(40)
	var full := light._light.energy
	player._fire_cooldown_left = railgun.fire_interval
	light.fired()
	await physics_frames(2)
	check(light._light.energy < full * 0.6, "a slow gun's light dims right after firing (%.2f of %.2f)" % [light._light.energy, full])
	player._fire_cooldown_left = 0.0
	await physics_frames(4)
	check(is_equal_approx(light._light.energy, full), "and is back to full when the gun is ready again")
	# 近戰武器：沒有槍燈，身邊的微光變大。
	player.loadout.equip(blade)
	await physics_frames(60)
	check(not light.is_lit() and not light._light.enabled, "a melee weapon has no gun light")
	check(player._light.texture_scale * LightKit.TEXTURE_SIZE * 0.5 > Player.SELF_GLOW_RADIUS + 20.0, "the glow around the player grows back without a gun light")
	# 講電話、搭載具、死亡：熄掉。
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	await physics_frames(40)
	player.set_physics_process(false)
	light.set_active(false)
	for step in 20:
		light.aim(player.muzzle_position(), Vector2.RIGHT, 1.0, 0.05)
	check(not light.is_lit() and not light._light.enabled, "the gun light fades out when it is switched off (phone, vehicle)")
	light.set_active(true)
	for step in 20:
		light.aim(player.muzzle_position(), Vector2.RIGHT, 1.0, 0.05)
	check(light.is_lit(), "and comes back afterwards")
	player.set_physics_process(true)
	# 潛行者：被槍燈照到就現形，光移開又隱形。
	player.loadout.equip(load("res://data/weapons/rifle.tres") as WeaponData)
	AimInput._last_stick_dir = Vector2.UP
	var stalker := level._create_enemy(load("res://data/enemies/stalker.tres") as EnemyData) as Stalker
	stalker.data = stalker.data.duplicate()
	stalker.data.detect_range = 0.0
	stalker.data.move_speed = 0.0
	stalker.data.ability_radius = 0.0
	stalker.position = player.global_position + Vector2(200.0, 0.0)
	level._entities.add_child(stalker)
	await physics_frames(50)
	check(stalker.is_cloaked(), "a stalker stays cloaked while the gun light points elsewhere")
	AimInput._last_stick_dir = (stalker._center() - player.muzzle_position()).normalized()
	await physics_frames(50)
	check(not stalker.is_cloaked(), "a stalker caught in the gun light reveals itself")
	AimInput._last_stick_dir = Vector2.UP
	await physics_frames(60)
	check(stalker.is_cloaked(), "and cloaks again when the light moves away")
	stalker.queue_free()
	AimInput._last_stick_dir = Vector2.RIGHT
	await physics_frames(4)
	# 「減少閃光」：連射時光錐的抖動與槍口火光都變弱。
	var smg := load("res://data/weapons/smg.tres") as WeaponData
	player.loadout.equip(smg)
	await physics_frames(40)
	player.set_physics_process(false)
	var reduce_before := Settings.get_reduce_flashes()
	var sway: Array[float] = []
	var flash: Array[float] = []
	for reduced: bool in [false, true]:
		Settings.set_reduce_flashes(reduced)
		light.fired()
		var widest := 0.0
		for step in 12:
			light.aim(player.muzzle_position(), Vector2.RIGHT, 1.0, 0.01)
			widest = maxf(widest, absf(angle_difference(light.global_rotation, 0.0)))
		sway.append(widest)
		for pooled: PointLight2D in Fx._lights:
			pooled.enabled = false
		WeaponSystem.muzzle_feedback(smg, player.global_position + Vector2(300, -200), Vector2.RIGHT)
		flash.append(_lit_flash_energy())
	Settings.set_reduce_flashes(reduce_before)
	player.set_physics_process(true)
	check(sway[0] > 0.01 and sway[1] < sway[0] * 0.75, "reduce-flashes calms the gun light's shake (%.3f → %.3f rad)" % [sway[0], sway[1]])
	check(flash[0] > 0.0 and flash[1] < flash[0] * 0.75, "reduce-flashes dims the muzzle flash light (%.2f → %.2f)" % [flash[0], flash[1]])
	light.extinguish()
	check(not light.is_lit() and not light._light.enabled, "dying puts the light out at once")
	AimInput.using_gamepad = false
	await end_level(level)


## 亮度分級（BG-33）：第一章每一區用的光影設定落在它該在的那一級；敵人被光照到時比主角更容易亮起來。
func _test_brightness_tiers() -> void:
	var expected := {"market": &"normal", "freight": &"normal", "rooftop": &"normal", "alley_calm": &"normal",
		"warehouse_interior": &"dark", "pawnshop_warm": &"bright", "lounge_safe": &"bright", "mezzanine_gray": &"bright"}
	for id: String in expected:
		var profile := load("res://data/lighting/%s.tres" % id) as LightingProfile
		check(profile != null and profile.brightness_tier() == expected[id] and profile.validate().is_empty(),
				"%s is a %s lighting profile (ambient %.2f)" % [id, expected[id], LightKit.luminance(profile.ambient_color) if profile != null else -1.0])
	var by_level := {"ch1_street": [&"normal"], "ch1_rooftop": [&"normal"], "ch1_booth_alley": [&"normal"], "ch1_stall": [&"normal"],
		"ch1_warehouse": [&"dark"], "ch1_vault": [&"dark"], "ch1_lounge": [&"bright"], "ch1_pawnshop_dawn": [&"bright"], "ch1_pawnshop": [&"normal", &"bright"]}
	for level_id: String in by_level:
		var data := load("res://data/levels/%s.tres" % level_id) as LevelData
		var tiers: Array = []
		for zone: LightingZone in data.lighting_zones:
			if not tiers.has(zone.profile.brightness_tier()):
				tiers.append(zone.profile.brightness_tier())
		tiers.sort()
		var wanted: Array = by_level[level_id]
		wanted.sort()
		check(tiers == wanted, "%s uses the %s tier(s) (%s)" % [level_id, wanted, tiers])
	check(LightKit.ENEMY_LIGHT_GAIN > 1.0 and LightKit.CHARACTER_LIGHT_CAP_MAX * LightKit.ENEMY_LIGHT_GAIN <= LightKit.CHARACTER_EXPOSURE_BUDGET,
			"a light makes an enemy brighter than it makes the player, within the exposure budget")
