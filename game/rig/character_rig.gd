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
const LIGHT_SHADER := preload("res://art/shaders/character_light.gdshader")
## 動畫器登記表：名稱 → 類別（需要繼承 HumanoidAnimator，建構時收到骨架）。外觀定義的 animator 欄位或 setup 的 animator_kind 用這些名稱；
## 特殊角色（專屬骨架、專屬攻擊動作）在這裡加一行即可，不需要動其他角色。
static var ANIMATORS: Dictionary = {"humanoid": HumanoidAnimator, "npc": NpcAnimator}

static var _glow_shared: CanvasItemMaterial
## 開發工具與測試用：true 時新建的角色全部維持剛體零件（不做關節網格），用來並排比較修正前後。
static var force_rigid_limbs := false

var skin_id := ""
var animator: HumanoidAnimator  # 或它的子類別（NpcAnimator）
var facing := 1:
	set(value):
		facing = 1 if value >= 0 else -1
		scale = Vector2(_base_scale * facing, _base_scale)

var _base_scale := 1.0
var _texture_scale := 0.25
var _limb_zone := 0.3
var _skeleton: Skeleton2D
var _bones: Dictionary[StringName, Bone2D] = {}
var _rest: Dictionary[StringName, Vector2] = {}
var _parent: Dictionary[StringName, StringName] = {}
var _order: Array[StringName] = []
var _springs: Array[Dictionary] = []
## 會脫落的零件，依脫落順序（先掉在前）；同一個 armor_order 的零件算同一步，一起脫落（例如夾克的四片、前後腿的同一段絲襪）。
var _armor: Array[Array] = []
## 衣物底下的破損層（character.json 零件的 under）：完整衣物都在時被蓋住，不需要畫，第一片脫落後才顯示。
var _under: Array[CanvasItem] = []
## 零件與它們的原始明暗（補光倍率套用在 self_modulate 上，發光層不受影響）。
var _parts: Array[CanvasItem] = []
## 做成可彎曲網格的肢體零件（RigPartMesh；也在 _parts 裡）：每格動畫之後依骨頭姿勢重算關節附近的頂點。
var _meshes: Array[RigPartMesh] = []
var _part_tints: PackedFloat32Array = PackedFloat32Array()
var _dissolve_material: ShaderMaterial
## 零件與武器共用的受光材質（每盞光有亮度上限、不被補光倍率放大；NE-213）。
var _light_material: ShaderMaterial
var _light_cap := LightKit.CHARACTER_LIGHT_CAP_MAX
var _fill := 1.0
var _armor_visible := 0
var _armor_debris := true
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
	var debris_setting = skin.get("armor_debris", true)
	_armor_debris = true
	if typeof(debris_setting) == TYPE_BOOL:
		_armor_debris = debris_setting
	else:
		push_warning("[CharacterRig] %s/armor_debris must be a boolean; using true" % skin_id)
	var skeleton_def := RigLibrary.load_json(str(skin.get("rig", "")))
	if skeleton_def.is_empty():
		return false
	_base_scale = float(skin.get("scale", 1.0))
	_texture_scale = float(skin.get("texture_scale", 0.25))
	_limb_zone = clampf(float(skeleton_def.get("limb_zone", skin.get("limb_zone", 0.3))), 0.05, 0.6)
	facing = facing
	_light_material = ShaderMaterial.new()
	_light_material.shader = LIGHT_SHADER
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
	_apply_light_cap(LightKit.character_light_cap)
	animator.update(delta, input)
	refresh_limbs()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_skeleton.modulate = Color.WHITE


## 依骨頭現在的姿勢重算肢體網格（動畫器改過骨頭之後呼叫；animate() 已經會做）。
func refresh_limbs() -> void:
	for mesh in _meshes:
		mesh.refresh()


## 肢體網格（測試與稽核用）。
func limb_meshes() -> Array[RigPartMesh]:
	return _meshes


## 所有看得見的零件（不含手持武器）合起來的世界座標範圍；沒有零件時回傳空的 Rect2。
func visual_bounds() -> Rect2:
	var total := Rect2()
	var first := true
	for part in _parts:
		if part == null or not part.is_visible_in_tree():
			continue
		var xf := part.get_global_transform()
		var corners: Array[Vector2] = []
		if part is RigPartMesh:
			for vertex in (part as RigPartMesh).deformed_vertices():
				corners.append(vertex)
		elif part is Sprite2D and (part as Sprite2D).texture != null:
			var r := (part as Sprite2D).get_rect()
			corners = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		if corners.is_empty():
			continue
		var rect := Rect2(xf * corners[0], Vector2.ZERO)
		for corner in corners:
			rect = rect.expand(xf * corner)
		total = rect if first else total.merge(rect)
		first = false
	return total


## 套用補光倍率（環境光很暗時把角色零件補亮，見 LightKit.character_fill）。
func _apply_fill(fill: float) -> void:
	if is_equal_approx(fill, _fill):
		return
	_fill = fill
	_light_material.set_shader_parameter("fill", fill)
	for i in _parts.size():
		var tint := _part_tints[i] * fill
		_parts[i].self_modulate = Color(tint, tint, tint, 1.0)
	if _weapon_sprite != null:
		_weapon_sprite.self_modulate = Color(fill, fill, fill, 1.0)


## 套用單盞光的亮度上限（亮場景小、暗場景大，見 LightKit.character_light_cap_for）。
func _apply_light_cap(cap: float) -> void:
	if is_equal_approx(cap, _light_cap):
		return
	_light_cap = cap
	_light_material.set_shader_parameter("light_cap", cap)


## 燒融：零件依世界座標的雜訊逐塊燒掉，邊緣發出炭火的光（art/shaders/dissolve.gdshader）。progress 0→1；
## rise＞0 火從腳往上燒、＜0 從頭往下燒、0 沒有方向。發光層與武器隨進度淡出。回傳 false 代表沒有可以燒的零件。
func set_dissolve(progress: float, edge_color := Color("ff7a1a"), rise := 0.0, edge_width := 0.1) -> bool:
	if _parts.is_empty():
		return false
	if _dissolve_material == null:
		_dissolve_material = ShaderMaterial.new()
		_dissolve_material.shader = DISSOLVE_SHADER
		_dissolve_material.set_shader_parameter("noise_tex", VfxAtlas.noise_texture())
		_dissolve_material.set_shader_parameter("foot_y", global_position.y)
		_dissolve_material.set_shader_parameter("body_height", maxf(20.0, RigLibrary.standing_height(skin_id)))
		for sprite in _parts:
			sprite.material = _dissolve_material
	_dissolve_material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	_dissolve_material.set_shader_parameter("edge_color", edge_color)
	_dissolve_material.set_shader_parameter("rise", rise)
	_dissolve_material.set_shader_parameter("edge_width", edge_width)
	var fade := clampf(1.0 - progress * 2.2, 0.0, 1.0)
	for sprite in _parts:
		for child in sprite.get_children():
			if child is CanvasItem:
				(child as CanvasItem).modulate.a = fade
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
		for part: CanvasItem in step:
			if part.visible:
				part.visible = false
				broke = true
				if burst:
					_spawn_debris(part)
		if broke:
			armor_broken.emit(StringName((step[0] as Node).name))
	while _armor_visible < target:
		_armor_visible += 1
		for part: CanvasItem in _armor[_armor.size() - _armor_visible]:
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
	_weapon_sprite.material = _light_material
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
	var bend_limbs := bool(skin.get("limb_bend", true)) and not force_rigid_limbs
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
		var pivot := RigLibrary.vec2(tex_def.get("pivot"))
		var texture := LitTextures.load_texture(base_dir.path_join(str(tex_def.get("file", ""))), Vector2i(size))
		var glow_texture := RigLibrary.optional_texture(base_dir.path_join(str(tex_def.get("glow", ""))))
		var tint := float(entry.get("tint", 1.0))
		var part_name := str(entry.get("name", tex_name))
		var part_pos := RigLibrary.vec2(entry.get("offset"))
		var part_rot := float(entry.get("rotation", 0.0))
		var part: CanvasItem = null
		if bend_limbs and is_zero_approx(part_rot) and not (bone_name in [&"hip", &"chest"] and tex_name.begins_with("armor_")):
			part = _make_limb_mesh(bone_name, texture, glow_texture, size, pivot, part_pos, tint, bool(entry.get("root_attach", false)), StringName(str(entry.get("bend_partner", ""))))
		if part == null:
			part = _make_sprite(texture, glow_texture, pivot, part_pos, part_rot, tint)
		part.name = part_name
		part.material = _light_material
		part.z_index = int(entry.get("z", 0))
		part.self_modulate = Color(tint, tint, tint, 1.0)
		_parts.append(part)
		_part_tints.append(tint)
		target_bone.add_child(part)
		if int(entry.get("armor_order", 0)) > 0:
			armor_entries.append([int(entry["armor_order"]), part])
		if bool(entry.get("under", false)):
			part.visible = false
			_under.append(part)
	# 依脫落順序排序：order 小的先掉，同一個 order 的零件放在同一步。_armor 由先掉到後掉。
	armor_entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var last_order := -1
	for pair in armor_entries:
		if int(pair[0]) != last_order:
			_armor.append([])
			last_order = int(pair[0])
		_armor[_armor.size() - 1].append(pair[1])
	_armor_visible = _armor.size()


func _make_sprite(texture: Texture2D, glow_texture: Texture2D, pivot: Vector2, part_pos: Vector2, part_rot: float, tint: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	sprite.offset = -pivot
	sprite.scale = Vector2.ONE * _texture_scale
	sprite.position = part_pos
	sprite.rotation = part_rot
	if glow_texture != null:
		var glow_sprite := _make_glow_sprite()
		glow_sprite.texture = glow_texture
		glow_sprite.offset = sprite.offset
		glow_sprite.self_modulate = Color(GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, 1.0)
		sprite.add_child(glow_sprite)
	return sprite


## 肢體零件（上臂、前臂、大腿、小腿）靠近關節時做成可彎曲的網格，回傳 null＝這個零件維持剛體（不是肢體、碰不到關節、骨架沒有成對的上下段）。
func _make_limb_mesh(bone_name: StringName, texture: Texture2D, glow_texture: Texture2D, size: Vector2, pivot: Vector2, part_pos: Vector2, tint: float, attach_root := false, bend_partner: StringName = &"") -> RigPartMesh:
	var limb := _limb_of(bone_name)
	if bend_partner != &"":
		if not _bones.has(bend_partner) or _parent.get(bend_partner, &"") != bone_name:
			push_warning("[CharacterRig] %s/%s bend_partner must be an immediate child bone: %s; using rigid part" % [skin_id, bone_name, bend_partner])
			return null
		limb = {"upper": true, "partner": bend_partner, "zone": _rest[bend_partner].length() * _limb_zone}
	if limb.is_empty():
		return null
	var partner_name: StringName = limb["partner"]
	var is_upper: bool = limb["upper"]
	var joint_y: float = _rest[partner_name].y if is_upper else 0.0
	var zone: float = float(limb["zone"])
	var direction: int = int(limb.get("direction", 1 if is_upper else -1))
	var node_transform := Transform2D(0.0, Vector2.ONE * _texture_scale, 0.0, part_pos)
	if not RigPartMesh.reaches_joint(RigPartMesh.vertical_span(size, pivot, node_transform), joint_y, zone, direction > 0):
		return null
	var mesh := RigPartMesh.new()
	mesh.position = part_pos
	mesh.scale = Vector2.ONE * _texture_scale
	var root_partner: Bone2D = _bones.get(_parent.get(bone_name, &"")) if is_upper and (String(bone_name).begins_with("leg_") or attach_root) else null
	# Both thigh textures were cut around the same illustrated hip.
	# A far-side copy offset must not pull that root away from the pelvis.
	var root_origin: Vector2 = Vector2(0.0, _rest[bone_name].y) if String(bone_name).begins_with("leg_") else _rest[bone_name]
	if not mesh.setup(texture, size, pivot, _bones[bone_name], _bones[partner_name], is_upper, _rest[bone_name], _rest[partner_name], zone, direction, root_partner, zone, root_origin):
		mesh.free()
		return null
	if glow_texture != null:
		mesh.set_glow(glow_texture, _glow_material(), Color(GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, GLOW_INTENSITY * tint, 1.0))
	_meshes.append(mesh)
	return mesh


## 骨頭 bone_name 若是肢體的上段（xxx_upper，子骨頭 xxx_lower）或下段，回傳 {upper, lower, partner, zone}；否則空字典。
## 混合半徑 zone ＝ 下段骨頭長度 × limb_zone（骨架定義可用 "limb_zone" 調整，預設 0.3）。
func _limb_of(bone_name: StringName) -> Dictionary:
	if bone_name in [&"hip", &"chest"] and _bones.has(&"chest") and _parent.get(&"chest", &"") == &"hip":
		var is_pelvis := bone_name == &"hip"
		# Chest extends upward: both sides must blend toward the same waist, not away from it.
		return {"upper": is_pelvis, "partner": &"chest" if is_pelvis else &"hip", "zone": _rest[&"chest"].length() * _limb_zone, "direction": -1 if is_pelvis else 1}
	var text := String(bone_name)
	var upper_name := bone_name
	var lower_name := bone_name
	var is_upper := text.ends_with("_upper")
	if is_upper:
		lower_name = StringName(text.trim_suffix("_upper") + "_lower")
	elif text.ends_with("_lower"):
		upper_name = StringName(text.trim_suffix("_lower") + "_upper")
	else:
		return {}
	if not (_bones.has(upper_name) and _bones.has(lower_name)) or _parent.get(lower_name, &"") != upper_name:
		return {}
	var fraction := float(_limb_zone)
	return {"upper": is_upper, "lower": lower_name, "partner": lower_name if is_upper else upper_name, "zone": _rest[lower_name].length() * fraction}


## 發光層：加法混合、不受場景光源影響、HDR 增亮產生泛光。
func _make_glow_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.light_mask = 0
	sprite.material = _glow_material()
	return sprite


## 發光層共用的材質（加法混合、不受場景光源影響）。
static func _glow_material() -> CanvasItemMaterial:
	if _glow_shared == null:
		_glow_shared = CanvasItemMaterial.new()
		_glow_shared.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow_shared.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _glow_shared


func _spawn_debris(part: CanvasItem) -> void:
	if _armor_debris:
		var offset: Vector2 = (part as RigPartMesh).pivot_offset if part is RigPartMesh else (part as Sprite2D).offset
		var texture: Texture2D = (part as RigPartMesh).texture if part is RigPartMesh else (part as Sprite2D).texture
		var debris := RigDebris.spawn(texture, part.global_transform, offset, Vector2(BREAK_IMPULSE.x * -facing * randf_range(0.6, 1.2), BREAK_IMPULSE.y * randf_range(0.8, 1.2)))
		if debris != null and not Fx.add_world_node(debris):
			debris.cancel()
	Fx.burst(part.global_position, Palette.ARMOR, 6, 120.0, 0.3)
