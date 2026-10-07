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
