class_name CharactersSuite
extends TestSuite
## 新增的角色骨架外觀（NE-44）：老 K、芽、航、回收員，以及狙擊手、火焰兵、重裝機槍手。
## 驗收重點：外觀定義與規格一致（尺寸、支點）、零件圖／發光層／法線都在且尺寸正確、
## 肢體確實畫到下一個關節（對位）、動畫與裝甲脫落正常、髮色與服裝和頭像一致。

const NEW_CHARACTERS: Array[String] = ["old_k", "mei", "wataru", "reclaimer", "sniper", "flamer", "heavy_gunner"]
## 會上場戰鬥的外觀：必須有可破壞裝甲。
const COMBATANTS: Array[String] = ["reclaimer", "sniper", "flamer", "heavy_gunner"]
const NEW_WEAPONS: Array[String] = ["sniper", "flamethrower"]
## 規格基準（Q 版人形骨架的零件尺寸與支點）；凜已改用 7.5 頭身的專屬骨架，不再是基準。
const REFERENCE := "old_k"
const REQUIRED_PARTS: Array[String] = ["head", "torso", "pelvis", "arm_upper", "arm_lower", "hand", "leg_upper", "leg_lower", "foot"]
## 肢體零件要畫到下一個關節（規格書的「子關節」）：貼圖 → 從畫布左上角算起的位置。
const LIMB_ENDS := {
	"arm_upper": Vector2(12, 42), "arm_lower": Vector2(11, 37), "leg_upper": Vector2(14, 50), "leg_lower": Vector2(12, 48),
}
## 各角色預設的手持武器（空字串＝空手）。
const WEAPONS := {
	"old_k": "pistol", "mei": "smg", "wataru": "", "reclaimer": "rifle", "sniper": "sniper", "flamer": "flamethrower", "heavy_gunner": "minigun",
}
## 頭像取樣點（128×128）：{ 角色: [頭髮或頭盔處, 衣服處] }，與 painter_style 的 hair／armor 與 coat 比對。
const PORTRAIT_SAMPLES := {
	"old_k": [Vector2(60, 20), Vector2(60, 110)],
	"mei": [Vector2(50, 26), Vector2(60, 110)],
	"wataru": [Vector2(50, 26), Vector2(60, 110)],
	"reclaimer": [Vector2(70, 30), Vector2(60, 110)],
}
const HUE_TOLERANCE := 0.07
const VALUE_TOLERANCE := 0.3
const POSES: Array[String] = ["idle", "run", "aim", "crouch", "jump", "block", "stagger", "dead"]


func run() -> void:
	_test_definitions()
	_test_alignment()
	_test_portraits()
	_test_weapons()
	await _test_rigs()


func _texture_image(path: String) -> Image:
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	return tex.get_image() if tex != null else null


func _test_definitions() -> void:
	var reference := RigLibrary.character(REFERENCE)
	for id in NEW_CHARACTERS:
		var skin := RigLibrary.character(id)
		check(not skin.is_empty() and str(skin.get("id")) == id, "character definition loads and id matches its folder: %s" % id)
		check(not str(skin.get("display_name", "")).is_empty(), "character has a display name: %s" % id)
		var textures: Dictionary = skin.get("textures", {})
		var dir := RigLibrary.character_dir(id)
		for part_name in REQUIRED_PARTS:
			check(textures.has(part_name), "%s defines the required part %s" % [id, part_name])
		for tex_name: String in textures.keys():
			var def: Dictionary = textures[tex_name]
			var spec: Dictionary = reference.get("textures", {}).get(tex_name, {})
			check(not spec.is_empty(), "%s.%s is a part the rig spec knows" % [id, tex_name])
			check(def.get("size") == spec.get("size") and def.get("pivot") == spec.get("pivot"), "%s.%s keeps the spec size and pivot" % [id, tex_name])
			var size := RigLibrary.vec2(def.get("size"))
			var file_path := dir.path_join(str(def.get("file")))
			var image := _texture_image(file_path)
			check(image != null and Vector2(image.get_size()) == size, "%s.%s image matches the declared canvas" % [id, tex_name])
			var normal := _texture_image(file_path.get_basename() + "_n.png")
			check(normal != null and Vector2(normal.get_size()) == size, "%s.%s has a normal map of the same size" % [id, tex_name])
			if def.has("glow"):
				var glow := _texture_image(dir.path_join(str(def["glow"])))
				check(glow != null and Vector2(glow.get_size()) == size, "%s.%s has a glow layer of the same size" % [id, tex_name])
		check(float(skin.get("texture_scale", 0.0)) == 0.25, "%s is drawn at 4x resolution" % id)
		var armor_orders: Array[int] = []
		for part: Dictionary in skin.get("parts", []):
			if int(part.get("armor_order", 0)) > 0:
				armor_orders.append(int(part["armor_order"]))
		if COMBATANTS.has(id):
			check(armor_orders.size() >= 4, "%s has breakable armor (%d pieces)" % [id, armor_orders.size()])
	check(float(RigLibrary.character("wataru").get("scale", 1.0)) <= 0.8, "wataru is drawn smaller (a child)")
	for id in ["old_k", "mei", "reclaimer", "sniper"]:
		check(float(RigLibrary.character(id).get("scale", 1.0)) > float(RigLibrary.character("wataru").get("scale", 1.0)), "%s is taller than wataru" % id)
	check(float(RigLibrary.character("heavy_gunner").get("scale", 1.0)) > float(RigLibrary.character("enforcer").get("scale", 1.0)), "the heavy gunner is bigger than an enforcer")


## 對位檢查：肢體零件的支點與下一個關節都有畫到東西（沒畫到就會在關節處出現縫隙），主要零件不是空圖。
func _test_alignment() -> void:
	for id in NEW_CHARACTERS:
		var skin := RigLibrary.character(id)
		var dir := RigLibrary.character_dir(id)
		var textures: Dictionary = skin.get("textures", {})
		for tex_name: String in LIMB_ENDS.keys():
			if not textures.has(tex_name):
				continue
			var def: Dictionary = textures[tex_name]
			var image := _texture_image(dir.path_join(str(def["file"])))
			if image == null:
				check(false, "%s.%s image readable for the alignment check" % [id, tex_name])
				continue
			var pivot := RigLibrary.vec2(def.get("pivot"))
			var end: Vector2 = LIMB_ENDS[tex_name]
			check(image.get_pixelv(Vector2i(pivot)).a > 0.5, "%s.%s is painted at its pivot" % [id, tex_name])
			check(image.get_pixelv(Vector2i(end)).a > 0.5, "%s.%s reaches the next joint" % [id, tex_name])
		for tex_name in ["head", "torso", "pelvis", "foot", "hand"]:
			var image := _texture_image(dir.path_join(str(textures[tex_name]["file"])))
			var opaque := 0
			if image != null:
				for y in image.get_height():
					for x in image.get_width():
						if image.get_pixel(x, y).a > 0.5:
							opaque += 1
			var ratio := float(opaque) / maxf(1.0, float(image.get_width() * image.get_height())) if image != null else 0.0
			check(ratio > 0.12, "%s.%s is not an empty image (%.0f%% opaque)" % [id, tex_name, ratio * 100.0])


## 髮色與服裝以頭像為準：頭像取樣點的色相與亮度要和外觀的 painter_style 接近。
func _test_portraits() -> void:
	for id: String in PORTRAIT_SAMPLES.keys():
		var style: Dictionary = RigLibrary.character(id).get("painter_style", {})
		var portrait := _texture_image("res://art/portraits/%s.png" % id)
		check(portrait != null, "portrait exists for %s" % id)
		if portrait == null:
			continue
		var samples: Array = PORTRAIT_SAMPLES[id]
		var keys: Array[String] = ["hair" if style.has("hair") else "armor", "coat"]
		for i in 2:
			var from_portrait := portrait.get_pixelv(Vector2i(samples[i] as Vector2))
			var from_style := Color(str(style.get(keys[i], "#ff00ff")))
			var close := absf(from_portrait.v - from_style.v) <= VALUE_TOLERANCE
			if from_portrait.s > 0.2 and from_style.s > 0.2:
				var hue_gap := absf(from_portrait.h - from_style.h)
				close = close and minf(hue_gap, 1.0 - hue_gap) <= HUE_TOLERANCE
			check(close, "%s %s matches its portrait (portrait %s, style %s)" % [id, keys[i], from_portrait.to_html(false), from_style.to_html(false)])


func _test_weapons() -> void:
	var base_dir := RigLibrary.WEAPONS_PATH.get_base_dir()
	for id in NEW_WEAPONS:
		var def := RigLibrary.weapon(id)
		check(not def.is_empty(), "weapon visual exists: %s" % id)
		var size := RigLibrary.vec2(def.get("size"))
		for key in ["file", "glow"]:
			var image := _texture_image(base_dir.path_join(str(def.get(key, ""))))
			check(image != null and Vector2(image.get_size()) == size, "weapon %s %s image matches its canvas" % [id, key])
		var normal := _texture_image(base_dir.path_join(str(def.get("file", ""))).get_basename() + "_n.png")
		check(normal != null, "weapon %s has a normal map" % id)
		var muzzle := RigLibrary.vec2(def.get("muzzle"))
		check(Rect2(Vector2.ZERO, size).has_point(muzzle) and muzzle.x > size.x * 0.8, "weapon %s muzzle is inside the canvas, at the front" % id)


func _test_rigs() -> void:
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	for id in NEW_CHARACTERS:
		var rig := CharacterRig.new()
		holder.add_child(rig)
		check(rig.setup(id) and rig.is_valid(), "rig builds: %s" % id)
		rig.set_weapon(str(WEAPONS[id]))
		var input := RigInput.new()
		for pose in POSES:
			input.facing = 1
			input.aim_dir = Vector2(1, -0.6).normalized() if pose == "aim" else Vector2.RIGHT
			input.on_floor = pose != "jump"
			input.velocity = Vector2(150, 0) if pose == "run" else (Vector2(80, -200) if pose == "jump" else Vector2.ZERO)
			input.crouching = pose == "crouch"
			input.blocking = pose == "block"
			input.staggered = pose == "stagger"
			input.dead = pose == "dead"
			for i in 20:
				rig.animate(1.0 / 60.0, input)
		input.dead = false
		input.staggered = false
		input.aim_dir = Vector2.RIGHT
		input.velocity = Vector2.ZERO
		for i in 30:
			rig.animate(1.0 / 60.0, input)
		await frames(1)
		if not str(WEAPONS[id]).is_empty():
			var hand := rig.bone(&"hand_front").global_position
			check(hand.distance_to(rig.weapon_root().global_position) < 2.0, "%s: front hand holds the weapon" % id)
			check(rig.muzzle_global().x > rig.global_position.x + 6.0, "%s: muzzle is in front of the character" % id)
		var armor := rig.armor_count()
		if COMBATANTS.has(id):
			rig.set_armor_ratio(0.0, false)
			var visible := 0
			for node in rig.find_children("armor_*", "Sprite2D", true, false):
				visible += 1 if (node as Sprite2D).visible else 0
			check(visible == 0, "%s: all armor falls off at zero health" % id)
			rig.set_armor_ratio(1.0, false)
			visible = 0
			for node in rig.find_children("armor_*", "Sprite2D", true, false):
				visible += 1 if (node as Sprite2D).visible else 0
			check(visible == armor, "%s: armor is restored at full health" % id)
		else:
			check(armor == 0, "%s: civilians have no breakable armor" % id)
		rig.queue_free()
	holder.queue_free()
	await frames(2)
