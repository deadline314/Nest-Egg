class_name CharacterRig
extends Node2D
## 骨架角色：依外觀定義（character.json）與骨架定義（humanoid.json）建立
## Skeleton2D／Bone2D，並把零件圖片掛到骨頭上；動作由 HumanoidAnimator 程式驅動。
##
## 美術替換：只要依 character.json 的 textures 尺寸與支點畫好同名 PNG 覆蓋即可。
## 原點在腳底；面向由 facing 控制（整個骨架水平翻轉）。

signal armor_broken(part_name: StringName)

const GLOW_INTENSITY := 2.4
const FLASH_TIME := 0.06
## 受擊閃白亮度（> 1 會帶泛光；太高在連續命中時會整隻變白）。
const FLASH_BRIGHTNESS := 1.4
const BREAK_IMPULSE := Vector2(80, -170)
const DISSOLVE_SHADER := preload("res://art/shaders/dissolve.gdshader")
## 動畫器登記表：名稱 → 類別（需要繼承 HumanoidAnimator，建構時收到骨架）。外觀定義的 animator 欄位或 setup 的 animator_kind 用這些名稱；
## 特殊角色（專屬骨架、專屬攻擊動作）在這裡加一行即可，不需要動其他角色。
static var ANIMATORS: Dictionary = {"humanoid": HumanoidAnimator, "npc": NpcAnimator}

var skin_id := ""
var animator: HumanoidAnimator  # 或它的子類別（NpcAnimator）
var facing := 1:
	set(value):
		facing = 1 if value >= 0 else -1
		scale = Vector2(_base_scale * facing, _base_scale)

var _base_scale := 1.0
var _texture_scale := 0.25
var _skeleton: Skeleton2D
var _bones: Dictionary[StringName, Bone2D] = {}
var _rest: Dictionary[StringName, Vector2] = {}
var _parent: Dictionary[StringName, StringName] = {}
var _order: Array[StringName] = []
var _springs: Array[Dictionary] = []
## 會脫落的零件，依脫落順序（先掉在前）；同一個 armor_order 的零件算同一步，一起脫落（例如夾克的四片、前後腿的同一段絲襪）。
var _armor: Array[Array] = []
## 衣物底下的破損層（character.json 零件的 under）：完整衣物都在時被蓋住，不需要畫，第一片脫落後才顯示。
var _under: Array[Sprite2D] = []
## 零件與它們的原始明暗（補光倍率套用在 self_modulate 上，發光層不受影響）。
var _part_sprites: Array[Sprite2D] = []
var _part_tints: PackedFloat32Array = PackedFloat32Array()
var _dissolve_material: ShaderMaterial
var _fill := 1.0
var _armor_visible := 0
var _weapon_root: Node2D
var _weapon_sprite: Sprite2D
var _weapon_glow: Sprite2D
var _weapon_def: Dictionary = {}
var _weapon_scale := 0.25
var _anchor_bone: StringName = &"chest"
var _anchor_pos := Vector2.ZERO
var _anchor_reach := 8.0
var _flash_left := 0.0
var _valid := false


## 建立骨架與零件。回傳 false 代表定義缺失（會記錄錯誤，節點仍可安全存在）。
## animator_kind：空字串＝依外觀定義（character.json 的 animator，沒寫就是人形）；"npc"＝NPC 動畫器（場景人物與過場演員用）。
func setup(p_skin_id: String, animator_kind := "") -> bool:
	skin_id = p_skin_id
	var skin := RigLibrary.character(skin_id)
	if skin.is_empty():
		return false
	var skeleton_def := RigLibrary.load_json(str(skin.get("rig", "")))
	if skeleton_def.is_empty():
		return false
	_base_scale = float(skin.get("scale", 1.0))
	_texture_scale = float(skin.get("texture_scale", 0.25))
	facing = facing
	_build_skeleton(skeleton_def)
	_build_parts(skin)
	var kind := animator_kind if animator_kind != "" else str(skin.get("animator", "humanoid"))
	if not ANIMATORS.has(kind):
		push_warning("[CharacterRig] %s 的 animator「%s」沒有登記（有：%s），改用人形動畫器。" % [skin_id, kind, ", ".join(ANIMATORS.keys())])
		kind = "humanoid"
	animator = (ANIMATORS[kind] as GDScript).new(self)
	_valid = true
	return true


func is_valid() -> bool:
	return _valid


# ---------------------------------------------------------------------------
# 骨頭存取（動畫器使用）
# ---------------------------------------------------------------------------

func bone(name: StringName) -> Bone2D:
	return _bones.get(name)


func has_bone(name: StringName) -> bool:
	return _bones.has(name)


func rest(name: StringName) -> Vector2:
	return _rest.get(name, Vector2.ZERO)


func parent_of(name: StringName) -> StringName:
	return _parent.get(name, &"")


func bone_order() -> Array[StringName]:
	return _order


## 站立時持槍基準點（武器掛點）離腳底的高度（世界像素）；瞄準的起點用它，準星才和手上的槍同高。
func anchor_height() -> float:
	var y := _anchor_pos.y
	var bone_name := _anchor_bone
	while bone_name != &"":
		y += _rest.get(bone_name, Vector2.ZERO).y
		bone_name = _parent.get(bone_name, &"")
	return -y * _base_scale


## 骨架整體縮放（不含面向的正負號）。
func body_scale() -> float:
	return _base_scale


## 骨架定義的次級動態（彈簧）設定；沒有定義時為空陣列（動畫器改用預設）。
func springs() -> Array[Dictionary]:
	return _springs


func weapon_anchor() -> Array:
	return [_anchor_bone, _anchor_pos, _anchor_reach]


func weapon_def() -> Dictionary:
	return _weapon_def


func weapon_scale() -> float:
	return _weapon_scale


func weapon_root() -> Node2D:
	return _weapon_root


## 骨架空間（未翻轉、未縮放）→ 世界座標。
func skeleton_to_global(point: Vector2) -> Vector2:
	return _skeleton.to_global(point) if _skeleton != null else global_position


# ---------------------------------------------------------------------------
# 動畫與外觀
# ---------------------------------------------------------------------------

func animate(delta: float, input: RigInput) -> void:
	if not _valid:
		return
	facing = input.facing
	_apply_fill(LightKit.character_fill)
	animator.update(delta, input)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_skeleton.modulate = Color.WHITE


## 套用補光倍率（環境光很暗時把角色零件補亮，見 LightKit.character_fill）。
func _apply_fill(fill: float) -> void:
	if is_equal_approx(fill, _fill):
		return
	_fill = fill
	for i in _part_sprites.size():
		var tint := _part_tints[i] * fill
		_part_sprites[i].self_modulate = Color(tint, tint, tint, 1.0)
	if _weapon_sprite != null:
		_weapon_sprite.self_modulate = Color(fill, fill, fill, 1.0)


## 燒融：零件依世界座標的雜訊逐塊燒掉，邊緣發出炭火的光（art/shaders/dissolve.gdshader）。progress 0→1；
## rise＞0 火從腳往上燒、＜0 從頭往下燒、0 沒有方向。發光層與武器隨進度淡出。回傳 false 代表沒有可以燒的零件。
func set_dissolve(progress: float, edge_color := Color("ff7a1a"), rise := 0.0, edge_width := 0.1) -> bool:
	if _part_sprites.is_empty():
		return false
	if _dissolve_material == null:
		_dissolve_material = ShaderMaterial.new()
		_dissolve_material.shader = DISSOLVE_SHADER
		_dissolve_material.set_shader_parameter("noise_tex", VfxAtlas.noise_texture())
		_dissolve_material.set_shader_parameter("foot_y", global_position.y)
		_dissolve_material.set_shader_parameter("body_height", maxf(20.0, RigLibrary.standing_height(skin_id)))
		for sprite in _part_sprites:
			sprite.material = _dissolve_material
	_dissolve_material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	_dissolve_material.set_shader_parameter("edge_color", edge_color)
	_dissolve_material.set_shader_parameter("rise", rise)
	_dissolve_material.set_shader_parameter("edge_width", edge_width)
	var fade := clampf(1.0 - progress * 2.2, 0.0, 1.0)
	for sprite in _part_sprites:
		for child in sprite.get_children():
			if child is Sprite2D:
				(child as Sprite2D).modulate.a = fade
	if _weapon_root != null:
		_weapon_root.modulate.a = clampf(1.0 - progress * 1.6, 0.0, 1.0)
	return true


## 世界座標的一個點落在這個角色身體的哪裡（燒融時沿著身體噴餘燼用）：以腳底為準，高度 0~1。
func body_point(height01: float, spread := 6.0) -> Vector2:
	var h := RigLibrary.standing_height(skin_id)
	return global_position + Vector2(randf_range(-spread, spread), -h * clampf(height01, 0.0, 1.0))


## 受擊閃白（HDR，會帶一點泛光）。strength 0~1：輕擊用較弱的閃白。
func flash(strength := 1.0) -> void:
	if _skeleton == null:
		return
	_flash_left = FLASH_TIME
	var level := lerpf(1.0, FLASH_BRIGHTNESS, clampf(strength, 0.0, 1.0))
	_skeleton.modulate = Color(level, level, level, 1)


## 設定手持武器外觀（weapons.json 的 id）；空字串代表空手。
func set_weapon(visual_id: String) -> void:
	_weapon_def = RigLibrary.weapon(visual_id) if not visual_id.is_empty() else {}
	if _weapon_root == null:
		return
	_weapon_root.visible = not _weapon_def.is_empty()
	if _weapon_def.is_empty():
		return
	var base_dir := RigLibrary.WEAPONS_PATH.get_base_dir()
	var size := RigLibrary.vec2(_weapon_def.get("size"), Vector2(64, 24))
	_weapon_scale = float(RigLibrary.weapons().get("texture_scale", 0.25))
	_weapon_sprite.texture = LitTextures.load_texture(base_dir.path_join(str(_weapon_def.get("file", ""))), Vector2i(size))
	_weapon_sprite.offset = -RigLibrary.vec2(_weapon_def.get("grip"))
	_weapon_sprite.scale = Vector2.ONE * _weapon_scale
	var glow := RigLibrary.optional_texture(base_dir.path_join(str(_weapon_def.get("glow", ""))))
	_weapon_glow.texture = glow
	_weapon_glow.visible = glow != null
	_weapon_glow.offset = _weapon_sprite.offset
	_weapon_glow.scale = _weapon_sprite.scale


## 槍口的世界座標（沒有武器時回傳胸口位置）。
func muzzle_global() -> Vector2:
	if _weapon_def.is_empty() or _weapon_sprite == null:
		return skeleton_to_global(rest(&"hip") + rest(&"chest"))
	return _weapon_sprite.to_global(RigLibrary.vec2(_weapon_def.get("muzzle")) + _weapon_sprite.offset)


## 依剩餘生命比例顯示裝甲；減少時脫落的裝甲會噴飛。
## _armor 依 armor_order 由小到大排列：order 越小越先脫落，顯示中的是最後 _armor_visible 步。
func set_armor_ratio(ratio: float, burst := true) -> void:
	var target := ceili(clampf(ratio, 0.0, 1.0) * _armor.size())
	while _armor_visible > target:
		var step := _armor[_armor.size() - _armor_visible]
		_armor_visible -= 1
		var broke := false
		for part: Sprite2D in step:
			if part.visible:
				part.visible = false
				broke = true
				if burst:
					_spawn_debris(part)
		if broke:
			armor_broken.emit(StringName((step[0] as Sprite2D).name))
	while _armor_visible < target:
		_armor_visible += 1
		for part: Sprite2D in _armor[_armor.size() - _armor_visible]:
			part.visible = true
	var broken := _armor_visible < _armor.size()
	for part in _under:
		part.visible = broken


func armor_count() -> int:
	return _armor.size()


# ---------------------------------------------------------------------------
# 建立
# ---------------------------------------------------------------------------

func _build_skeleton(definition: Dictionary) -> void:
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	var bones: Variant = definition.get("bones", [])
	if typeof(bones) != TYPE_ARRAY:
		push_error("[CharacterRig] 骨架定義缺少 bones：%s" % skin_id)
		return
	for entry: Variant in bones:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var bone_name := StringName(str(entry.get("name", "")))
		var parent_name := StringName(str(entry.get("parent", "")))
		if bone_name == &"" or _bones.has(bone_name):
			push_warning("[CharacterRig] 骨頭名稱無效或重複：%s" % bone_name)
			continue
		var parent_node: Node = _skeleton if parent_name == &"" else _bones.get(parent_name)
		if parent_node == null:
			push_error("[CharacterRig] 骨頭 %s 的父骨頭 %s 不存在（父骨頭需先定義）" % [bone_name, parent_name])
			continue
		var pos := RigLibrary.vec2(entry.get("pos"))
		var b := Bone2D.new()
		b.name = String(bone_name)
		b.position = pos
		b.rest = Transform2D(0.0, pos)
		b.set_autocalculate_length_and_angle(false)
		b.set_length(4.0)
		b.set_bone_angle(PI * 0.5)
		parent_node.add_child(b)
		_bones[bone_name] = b
		_rest[bone_name] = pos
		_parent[bone_name] = parent_name
		_order.append(bone_name)
	var springs: Variant = definition.get("springs", [])
	if typeof(springs) == TYPE_ARRAY:
		for entry: Variant in springs:
			if typeof(entry) == TYPE_DICTIONARY and _bones.has(StringName(str(entry.get("bone", "")))):
				_springs.append(entry)
			else:
				push_warning("[CharacterRig] %s 的 springs 有無效項目（需要存在的 bone）：%s" % [skin_id, entry])
	var anchor: Variant = definition.get("weapon_anchor", {})
	if typeof(anchor) == TYPE_DICTIONARY:
		_anchor_bone = StringName(str(anchor.get("bone", "chest")))
		_anchor_pos = RigLibrary.vec2(anchor.get("pos"))
		_anchor_reach = float(anchor.get("reach", 8.0))
	_weapon_root = Node2D.new()
	_weapon_root.name = "Weapon"
	_weapon_root.z_index = 7
	_skeleton.add_child(_weapon_root)
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.centered = false
	_weapon_root.add_child(_weapon_sprite)
	_weapon_glow = _make_glow_sprite()
	_weapon_root.add_child(_weapon_glow)
	_weapon_root.visible = false


func _build_parts(skin: Dictionary) -> void:
	var textures: Dictionary = skin.get("textures", {})
	var base_dir := RigLibrary.character_dir(skin_id)
	var parts: Variant = skin.get("parts", [])
	if typeof(parts) != TYPE_ARRAY:
		push_error("[CharacterRig] %s 缺少 parts" % skin_id)
		return
	var armor_entries: Array = []
	for entry: Variant in parts:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tex_name := str(entry.get("texture", ""))
		var bone_name := StringName(str(entry.get("bone", "")))
		var target_bone := _bones.get(bone_name) as Bone2D
		if not textures.has(tex_name) or target_bone == null:
			push_error("[CharacterRig] %s 的零件 %s 參照不存在的貼圖或骨頭（%s / %s）" % [skin_id, entry.get("name"), tex_name, bone_name])
			continue
		var tex_def: Dictionary = textures[tex_name]
		var size := RigLibrary.vec2(tex_def.get("size"), Vector2(16, 16))
		var sprite := Sprite2D.new()
		sprite.name = str(entry.get("name", tex_name))
		sprite.centered = false
		sprite.texture = LitTextures.load_texture(base_dir.path_join(str(tex_def.get("file", ""))), Vector2i(size))
		sprite.offset = -RigLibrary.vec2(tex_def.get("pivot"))
		sprite.scale = Vector2.ONE * _texture_scale
		sprite.position = RigLibrary.vec2(entry.get("offset"))
		sprite.rotation = float(entry.get("rotation", 0.0))
		sprite.z_index = int(entry.get("z", 0))
		var tint := float(entry.get("tint", 1.0))
		sprite.self_modulate = Color(tint, tint, tint, 1.0)
		_part_sprites.append(sprite)
		_part_tints.append(tint)
		target_bone.add_child(sprite)
		var glow := RigLibrary.optional_texture(base_dir.path_join(str(tex_def.get("glow", ""))))
		if glow != null:
			var glow_sprite := _make_glow_sprite()
			glow_sprite.texture = glow
			glow_sprite.offset = sprite.offset
			glow_sprite.self_modulate = Color(GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, 1.0)
			sprite.add_child(glow_sprite)
		if int(entry.get("armor_order", 0)) > 0:
			armor_entries.append([int(entry["armor_order"]), sprite])
		if bool(entry.get("under", false)):
			sprite.visible = false
			_under.append(sprite)
	# 依脫落順序排序：order 小的先掉，同一個 order 的零件放在同一步。_armor 由先掉到後掉。
	armor_entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var last_order := -1
	for pair in armor_entries:
		if int(pair[0]) != last_order:
			_armor.append([])
			last_order = int(pair[0])
		_armor[_armor.size() - 1].append(pair[1])
	_armor_visible = _armor.size()


## 發光層：加法混合、不受場景光源影響、HDR 增亮產生泛光。
func _make_glow_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.light_mask = 0
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	sprite.material = material
	return sprite


func _spawn_debris(part: Sprite2D) -> void:
	var debris := RigDebris.spawn(part.texture, part.global_transform, part.offset, Vector2(BREAK_IMPULSE.x * -facing * randf_range(0.6, 1.2), BREAK_IMPULSE.y * randf_range(0.8, 1.2)))
	if debris != null and not Fx.add_world_node(debris):
		debris.cancel()
	Fx.burst(part.global_position, Palette.ARMOR, 6, 120.0, 0.3)
