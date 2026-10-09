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
const EYE_BLINK_SCRIPT := preload("res://game/rig/eye_blink.gd")
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
## Validated pose alternatives keyed by the logical parts[].name (not the texture alias).
## A slot keeps the armor-controlled base visibility separately from the currently selected node.
var _pose_slots: Dictionary[StringName, Dictionary] = {}
var _pose_slot_by_base_id: Dictionary[int, StringName] = {}
var _pose_sets: Dictionary[StringName, bool] = {}
var _active_pose_set: StringName = &""
## 做成可彎曲網格的肢體零件（RigPartMesh；也在 _parts 裡）：每格動畫之後依骨頭姿勢重算關節附近的頂點。
var _meshes: Array[RigPartMesh] = []
var _hand_grips: Array[Dictionary] = []
## Optional head-only eye state. All textures are resolved once during setup; animation only swaps cached references.
var _eye_blink: RefCounted
var _eye_part: Sprite2D
var _eye_glow: Sprite2D
var _eye_open_texture: Texture2D
var _eye_half_texture: Texture2D
var _eye_closed_texture: Texture2D
var _eye_open_glow: Texture2D
var _eye_half_glow: Texture2D
var _eye_closed_glow: Texture2D
var _eye_state: StringName = &"open"
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
	_pose_slots.clear()
	_pose_slot_by_base_id.clear()
	_pose_sets.clear()
	_active_pose_set = &""
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
	_build_pose_parts(skin)
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


## 握點相對手腕（骨架單位）；沒有握持變體的角色保持原有 IK。
func hand_grip_offset(hand: StringName) -> Vector2:
	for entry in _hand_grips:
		if entry["bone"] == hand and entry["closed"]:
			return entry["offset"]
	return Vector2.ZERO


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
	_update_hand_grips(input)
	animator.update(delta, input)
	var scene_tree := get_tree()
	if scene_tree == null or not scene_tree.paused:
		_update_eye_states(delta, input)
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
		for base_part: CanvasItem in step:
			if _base_part_is_visible(base_part):
				var visible_part := _active_part_for_base(base_part)
				_set_base_part_visible(base_part, false)
				broke = true
				if burst:
					_spawn_debris(visible_part)
		if broke:
			armor_broken.emit(StringName((step[0] as Node).name))
	while _armor_visible < target:
		_armor_visible += 1
		for base_part: CanvasItem in _armor[_armor.size() - _armor_visible]:
			_set_base_part_visible(base_part, true)
	var broken := _armor_visible < _armor.size()
	for base_part in _under:
		_set_base_part_visible(base_part, broken)


func armor_count() -> int:
	return _armor.size()


## Select one prevalidated attachment set. Empty clears alternatives and restores the current armor/damage visibility.
## Selection is explicit; animate() performs no pose-set dictionary work per frame.
func set_pose_parts(pose_key: StringName) -> bool:
	if pose_key != &"" and not _pose_sets.has(pose_key):
		push_warning("[CharacterRig] %s.pose_parts.%s is unavailable; keeping pose set '%s'" % [skin_id, pose_key, _active_pose_set])
		return false
	if pose_key == _active_pose_set:
		return true
	_active_pose_set = pose_key
	_apply_pose_part_visibility()
	return true


func active_pose_parts() -> StringName:
	return _active_pose_set


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
		if entry.has("grip_texture"):
			var grip_def: Dictionary = textures.get(str(entry["grip_texture"]), {})
			var grip_path := base_dir.path_join(str(grip_def.get("file", "")))
			var offset := RigLibrary.vec2(entry.get("grip_offset"))
			if not part is Sprite2D or bone_name not in [&"hand_front", &"hand_back"] or grip_def.is_empty() or not ResourceLoader.exists(grip_path) or not offset.is_finite():
				push_warning("[CharacterRig] %s/%s invalid gripping attachment %s; keeping resting hand" % [skin_id, part_name, entry["grip_texture"]])
			else:
				_hand_grips.append({"sprite": part, "bone": bone_name, "open_texture": texture, "open_pivot": pivot,
					"grip_texture": LitTextures.load_texture(grip_path, Vector2i(RigLibrary.vec2(grip_def.get("size")))),
					"grip_pivot": RigLibrary.vec2(grip_def.get("pivot")), "offset": offset, "closed": false})
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
	_setup_eye_states(skin)


## Pose assets are optional. Validate each whole set before adding any of its nodes so a bad file
## cannot leave a partially selectable pose. Runtime selection only switches cached CanvasItems.
func _build_pose_parts(skin: Dictionary) -> void:
	if not skin.has("pose_parts"):
		return
	var pose_parts_value: Variant = skin.get("pose_parts")
	if typeof(pose_parts_value) != TYPE_DICTIONARY:
		_pose_warning("pose_parts", "expected a dictionary keyed by pose name; ignoring all pose sets")
		return
	var textures_value: Variant = skin.get("textures", {})
	var parts_value: Variant = skin.get("parts", [])
	if typeof(textures_value) != TYPE_DICTIONARY or typeof(parts_value) != TYPE_ARRAY:
		_pose_warning("pose_parts", "textures and parts must be dictionaries/arrays; ignoring all pose sets")
		return
	var textures: Dictionary = textures_value
	var base_entries: Dictionary[StringName, Dictionary] = {}
	var duplicate_base_slots: Dictionary[StringName, bool] = {}
	for entry: Variant in parts_value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var part_def: Dictionary = entry
		var slot_name := StringName(str(part_def.get("name", part_def.get("texture", ""))))
		if slot_name == &"":
			continue
		if base_entries.has(slot_name):
			duplicate_base_slots[slot_name] = true
		else:
			base_entries[slot_name] = part_def
	var base_nodes: Dictionary[StringName, CanvasItem] = {}
	for part in _parts:
		var slot_name := StringName(str(part.name))
		if base_nodes.has(slot_name):
			duplicate_base_slots[slot_name] = true
		else:
			base_nodes[slot_name] = part

	var base_dir := RigLibrary.character_dir(skin_id)
	for raw_pose_key: Variant in pose_parts_value.keys():
		var pose_key := StringName(str(raw_pose_key))
		var field := "pose_parts.%s" % pose_key
		var pose_def_value: Variant = pose_parts_value[raw_pose_key]
		if pose_key == &"" or typeof(pose_def_value) != TYPE_DICTIONARY:
			_pose_warning(field, "each named pose must be a dictionary; rejecting this set")
			continue
		var pose_def: Dictionary = pose_def_value
		var pose_entries_value: Variant = pose_def.get("parts", [])
		var pose_texture_scale := _texture_scale
		if pose_def.has("texture_scale"):
			var raw_scale: Variant = pose_def["texture_scale"]
			if typeof(raw_scale) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_scale)) or float(raw_scale) <= 0.0:
				_pose_warning(field, "texture_scale must be a finite positive number; rejecting this set")
				continue
			pose_texture_scale = float(raw_scale)
		if typeof(pose_entries_value) != TYPE_ARRAY or (pose_entries_value as Array).is_empty():
			_pose_warning(field, "each named pose must contain a non-empty parts array; rejecting this set")
			continue
		var seen_slots: Dictionary[StringName, bool] = {}
		var pending: Array[Dictionary] = []
		var failure := ""
		for entry: Variant in pose_entries_value:
			if typeof(entry) != TYPE_DICTIONARY:
				failure = "entries must be dictionaries"
				break
			var alternative: Dictionary = entry
			var slot_name := StringName(str(alternative.get("slot", "")))
			if slot_name == &"":
				failure = "every entry requires a logical slot name"
				break
			if seen_slots.has(slot_name):
				failure = "duplicate logical slot '%s'" % slot_name
				break
			seen_slots[slot_name] = true
			if duplicate_base_slots.has(slot_name) or not base_entries.has(slot_name) or not base_nodes.has(slot_name):
				failure = "slot '%s' must resolve to exactly one existing base part" % slot_name
				break
			var base_part := base_nodes[slot_name] as CanvasItem
			var base_def: Dictionary = base_entries[slot_name]
			if base_part == _eye_part and _eye_part != null:
				failure = "slot '%s' is controlled by eye_states blink and cannot be replaced by pose_parts" % slot_name
				break
			var base_bone := StringName(str(base_def.get("bone", "")))
			var alternative_bone := StringName(str(alternative.get("bone", "")))
			if base_bone == &"" or alternative_bone != base_bone or base_part.get_parent() != _bones.get(base_bone):
				failure = "slot '%s' must keep its existing bone '%s'" % [slot_name, base_bone]
				break
			var texture_key := str(alternative.get("texture", ""))
			if texture_key.is_empty() or typeof(textures.get(texture_key)) != TYPE_DICTIONARY:
				failure = "slot '%s' references a missing texture definition" % slot_name
				break
			var texture_def: Dictionary = textures[texture_key]
			var file_value: Variant = texture_def.get("file", "")
			var size_value: Variant = texture_def.get("size")
			var pivot_value: Variant = texture_def.get("pivot")
			if typeof(file_value) != TYPE_STRING or str(file_value).is_empty():
				failure = "texture '%s' requires a non-empty file path" % texture_key
				break
			if not _pose_numeric_pair(size_value, true) or not _pose_numeric_pair(pivot_value, false):
				failure = "texture '%s' requires finite [width,height] and [pivot_x,pivot_y] pairs" % texture_key
				break
			if float(size_value[0]) > 2147483647.0 or float(size_value[1]) > 2147483647.0:
				failure = "texture '%s' native size exceeds Vector2i limits" % texture_key
				break
			var size := Vector2i(int(size_value[0]), int(size_value[1]))
			var pivot := Vector2(float(pivot_value[0]), float(pivot_value[1]))
			if size.x <= 0 or size.y <= 0 or pivot.x < 0.0 or pivot.y < 0.0 or pivot.x > float(size.x) or pivot.y > float(size.y):
				failure = "texture '%s' has an invalid native size or out-of-canvas pivot" % texture_key
				break
			var offset := (base_part as Node2D).position
			if alternative.has("offset"):
				if not _pose_numeric_pair(alternative["offset"], false):
					failure = "slot '%s' offset must be a finite pair" % slot_name
					break
				offset = Vector2(float(alternative["offset"][0]), float(alternative["offset"][1]))
			var rotation := (base_part as Node2D).rotation
			if alternative.has("rotation"):
				if typeof(alternative["rotation"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(alternative["rotation"])):
					failure = "slot '%s' rotation must be finite" % slot_name
					break
				rotation = float(alternative["rotation"])
			var texture_path := base_dir.path_join(str(file_value))
			if not ResourceLoader.exists(texture_path):
				failure = "texture '%s' file is missing: %s" % [texture_key, texture_path]
				break
			var raw_texture := load(texture_path) as Texture2D
			if raw_texture == null or raw_texture.get_size() != Vector2(size):
				failure = "texture '%s' native size does not match metadata %s: %s" % [texture_key, size, texture_path]
				break
			var base_texture_key := str(base_def.get("texture", ""))
			var base_texture_def: Dictionary = textures.get(base_texture_key, {})
			var base_path := base_dir.path_join(str(base_texture_def.get("file", "")))
			var base_normal_path := _normal_path(base_path)
			var normal_required := ResourceLoader.exists(base_normal_path)
			var normal_path := _normal_path(texture_path)
			var normal_exists := ResourceLoader.exists(normal_path)
			if normal_required and not normal_exists:
				failure = "texture '%s' requires a matching normal map: %s" % [texture_key, normal_path]
				break
			if normal_exists:
				var normal_texture := load(normal_path) as Texture2D
				if normal_texture == null or normal_texture.get_size() != Vector2(size):
					failure = "texture '%s' normal map must match native size %s: %s" % [texture_key, size, normal_path]
					break
			var glow_value: Variant = texture_def.get("glow", "")
			if typeof(glow_value) != TYPE_STRING:
				failure = "texture '%s' glow path must be a string" % texture_key
				break
			var glow_path := base_dir.path_join(str(glow_value)) if not str(glow_value).is_empty() else ""
			var base_has_glow := _part_has_glow(base_part)
			if base_has_glow and glow_path.is_empty():
				failure = "slot '%s' requires a glow companion like its base part" % slot_name
				break
			var glow_texture := RigLibrary.optional_texture(glow_path)
			if not glow_path.is_empty() and (glow_texture == null or glow_texture.get_size() != Vector2(size)):
				failure = "texture '%s' glow must exist and match native size %s: %s" % [texture_key, size, glow_path]
				break
			var lit_texture := LitTextures.load_texture(texture_path, size)
			if lit_texture == null:
				failure = "texture '%s' could not be loaded by LitTextures" % texture_key
				break
			if normal_exists and LitTextures.is_enabled():
				if not lit_texture is CanvasTexture or (lit_texture as CanvasTexture).normal_texture == null:
					failure = "texture '%s' did not retain its CanvasTexture normal channel" % texture_key
					break
			pending.append({"slot": slot_name, "base": base_part, "texture": lit_texture, "glow": glow_texture,
				"size": size, "pivot": pivot, "offset": offset, "rotation": rotation, "texture_scale": pose_texture_scale})
		if not failure.is_empty():
			_pose_warning(field, "%s; rejecting this set" % failure)
			continue
		failure = _pose_layer_counterpart_error(seen_slots, base_entries)
		if not failure.is_empty():
			_pose_warning(field, "%s; rejecting this set" % failure)
			continue
		for item: Dictionary in pending:
			var slot_name: StringName = item["slot"]
			var base_part: CanvasItem = item["base"]
			if not _pose_slots.has(slot_name):
				_pose_slots[slot_name] = {"base": base_part, "base_visible": base_part.visible, "alternatives": {}}
			_pose_slot_by_base_id[base_part.get_instance_id()] = slot_name
			var alternate := _make_sprite(item["texture"], item["glow"], item["pivot"], item["offset"], item["rotation"], base_part.self_modulate.r)
			alternate.scale = Vector2.ONE * float(item["texture_scale"])
			alternate.name = "Pose_%s__%s" % [pose_key, slot_name]
			alternate.material = _light_material
			alternate.z_index = base_part.z_index
			alternate.self_modulate = base_part.self_modulate
			alternate.visible = false
			(base_part.get_parent() as Node).add_child(alternate)
			(_pose_slots[slot_name]["alternatives"] as Dictionary)[pose_key] = alternate
			_parts.append(alternate)
			_part_tints.append(base_part.self_modulate.r)
		_pose_sets[pose_key] = true
	_active_pose_set = &""
	_apply_pose_part_visibility()


## Keep pose art coherent across intact armor and the same-bone underlayers it reveals.
func _pose_layer_counterpart_error(selected_slots: Dictionary[StringName, bool], base_entries: Dictionary[StringName, Dictionary]) -> String:
	for slot_name: StringName in selected_slots:
		var part_def: Dictionary = base_entries[slot_name]
		var part_bone := str(part_def.get("bone", ""))
		var is_armor := int(part_def.get("armor_order", 0)) > 0
		var is_under := bool(part_def.get("under", false))
		if not is_armor and not is_under:
			continue
		for counterpart_slot: StringName in base_entries:
			var counterpart: Dictionary = base_entries[counterpart_slot]
			if str(counterpart.get("bone", "")) != part_bone:
				continue
			var counterpart_required := (is_armor and bool(counterpart.get("under", false))) or (is_under and int(counterpart.get("armor_order", 0)) > 0)
			if counterpart_required and not selected_slots.has(counterpart_slot):
				return "slot '%s' must include same-bone armor/damage counterpart '%s'" % [slot_name, counterpart_slot]
	return ""


func _pose_numeric_pair(value: Variant, integral: bool) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return false
	for component: Variant in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
		if integral and not is_equal_approx(float(component), roundf(float(component))):
			return false
	return true


func _normal_path(texture_path: String) -> String:
	return texture_path.get_basename() + "_n." + texture_path.get_extension()


func _part_has_glow(part: CanvasItem) -> bool:
	for child in part.get_children():
		if child is Sprite2D and (child as Sprite2D).material == _glow_material() and (child as Sprite2D).texture != null:
			return true
		if child is Polygon2D and (child as Polygon2D).material == _glow_material() and (child as Polygon2D).texture != null:
			return true
	return false


func _pose_warning(field: String, reason: String) -> void:
	push_warning("[CharacterRig] %s.%s invalid; %s" % [skin_id, field, reason])


func _apply_pose_part_visibility() -> void:
	for slot_name: StringName in _pose_slots:
		var slot: Dictionary = _pose_slots[slot_name]
		var base_part: CanvasItem = slot["base"]
		var selected: CanvasItem = base_part
		var alternatives: Dictionary = slot["alternatives"]
		if _active_pose_set != &"" and alternatives.has(_active_pose_set):
			selected = alternatives[_active_pose_set]
		var eligible := bool(slot["base_visible"])
		base_part.visible = eligible and selected == base_part
		for alternative: CanvasItem in alternatives.values():
			alternative.visible = eligible and alternative == selected


func _base_part_is_visible(base_part: CanvasItem) -> bool:
	var slot_name: StringName = _pose_slot_by_base_id.get(base_part.get_instance_id(), &"")
	if slot_name != &"" and _pose_slots.has(slot_name):
		return bool(_pose_slots[slot_name]["base_visible"])
	return base_part.visible


func _active_part_for_base(base_part: CanvasItem) -> CanvasItem:
	var slot_name: StringName = _pose_slot_by_base_id.get(base_part.get_instance_id(), &"")
	if slot_name == &"" or not _pose_slots.has(slot_name):
		return base_part
	var alternatives: Dictionary = _pose_slots[slot_name]["alternatives"]
	return alternatives.get(_active_pose_set, base_part) if _active_pose_set != &"" else base_part


func _set_base_part_visible(base_part: CanvasItem, visible: bool) -> void:
	var slot_name: StringName = _pose_slot_by_base_id.get(base_part.get_instance_id(), &"")
	if slot_name == &"" or not _pose_slots.has(slot_name):
		base_part.visible = visible
		return
	_pose_slots[slot_name]["base_visible"] = visible
	_apply_pose_part_visibility()


## Optional top-level eye_states are intentionally separate from portrait.blink, which describes portrait paint-over data.
## A bad or incomplete state set leaves the original head texture and its glow untouched.
func _setup_eye_states(skin: Dictionary) -> void:
	_eye_blink = null
	_eye_part = null
	_eye_glow = null
	_eye_open_texture = null
	_eye_half_texture = null
	_eye_closed_texture = null
	_eye_open_glow = null
	_eye_half_glow = null
	_eye_closed_glow = null
	_eye_state = &"open"
	if not skin.has("eye_states"):
		return
	var config: Variant = skin["eye_states"]
	if typeof(config) != TYPE_DICTIONARY:
		_eye_warning("eye_states", "expected a dictionary; keeping the original head")
		return
	var part_name := str(config.get("part", ""))
	if part_name.is_empty():
		_eye_warning("eye_states.part", "expected the name of an existing head Sprite2D")
		return
	var head_sprite: Sprite2D
	for candidate in _parts:
		if str(candidate.name) != part_name:
			continue
		if not candidate is Sprite2D or head_sprite != null:
			_eye_warning("eye_states.part", "must identify exactly one Sprite2D; keeping the original head")
			return
		head_sprite = candidate as Sprite2D
	if head_sprite == null or head_sprite.texture == null:
		_eye_warning("eye_states.part", "does not resolve to a textured Sprite2D; keeping the original head")
		return
	if head_sprite.material != _light_material:
		_eye_warning("eye_states.part", "head does not use the shared character-light material; keeping the original head")
		return

	var texture_defs_value: Variant = skin.get("textures", {})
	var parts_value: Variant = skin.get("parts", [])
	if typeof(texture_defs_value) != TYPE_DICTIONARY or typeof(parts_value) != TYPE_ARRAY:
		_eye_warning("eye_states", "textures and parts must be dictionaries/arrays; keeping the original head")
		return
	var textures: Dictionary = texture_defs_value
	var original_key := ""
	var part_matches := 0
	for entry: Variant in parts_value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_name := str(entry.get("name", entry.get("texture", "")))
		if entry_name == part_name:
			part_matches += 1
			original_key = str(entry.get("texture", ""))
	if part_matches != 1 or not textures.has(original_key):
		_eye_warning("eye_states.part", "must map to exactly one existing parts texture; keeping the original head")
		return

	var open_key := str(config.get("open_texture", original_key))
	var half_key := str(config.get("half_texture", ""))
	var closed_key := str(config.get("closed_texture", ""))
	if open_key.is_empty() or half_key.is_empty() or closed_key.is_empty():
		_eye_warning("eye_states", "open_texture (optional), half_texture, and closed_texture must name textures")
		return
	var open_def_value: Variant = textures.get(open_key)
	if typeof(open_def_value) != TYPE_DICTIONARY:
		_eye_warning("eye_states.open_texture", "texture definition is missing; keeping the original head")
		return
	var open_def: Dictionary = open_def_value
	var expected_size := head_sprite.texture.get_size()
	var expected_pivot := -head_sprite.offset
	if not _valid_eye_metadata(open_def, expected_size, expected_pivot, "eye_states.open_texture"):
		return
	var open_path := _eye_texture_path(open_def)
	var original_path := _eye_texture_path(textures[original_key])
	var normal_required := ResourceLoader.exists(_eye_normal_map_path(original_path))
	if not ResourceLoader.exists(open_path):
		_eye_warning("eye_states.open_texture", "source file is missing: %s; keeping the original head" % open_path)
		return
	var open_raw := load(open_path) as Texture2D
	if open_raw == null or open_raw.get_size() != Vector2(expected_size):
		_eye_warning("eye_states.open_texture", "source file is unreadable or has the wrong dimensions: %s" % open_path)
		return
	var open_texture := head_sprite.texture if open_key == original_key else LitTextures.load_texture(open_path, expected_size)
	if open_texture == null or open_texture.get_size() != Vector2(expected_size):
		_eye_warning("eye_states.open_texture", "LitTextures returned an invalid texture; keeping the original head")
		return
	if not _eye_normal_map_matches(open_path, expected_size, "eye_states.open_texture", normal_required):
		return

	var half_texture := _load_eye_state_texture(textures, half_key, expected_size, expected_pivot, "eye_states.half_texture", normal_required)
	if half_texture == null:
		return
	var closed_texture := _load_eye_state_texture(textures, closed_key, expected_size, expected_pivot, "eye_states.closed_texture", normal_required)
	if closed_texture == null:
		return

	var glow_node := _find_eye_glow(head_sprite)
	var has_glow := glow_node != null
	var open_glow := _load_eye_glow(open_def, expected_size, has_glow, "eye_states.open_texture")
	if has_glow and open_glow == null:
		return
	var half_def: Dictionary = textures[half_key]
	var half_glow := _load_eye_glow(half_def, expected_size, has_glow, "eye_states.half_texture")
	if has_glow and half_glow == null:
		return
	var closed_def: Dictionary = textures[closed_key]
	var closed_glow := _load_eye_glow(closed_def, expected_size, has_glow, "eye_states.closed_texture")
	if has_glow and closed_glow == null:
		return
	if not has_glow:
		for pair: Array in [["open_texture", open_def], ["half_texture", half_def], ["closed_texture", closed_def]]:
			var glow_value: Variant = pair[1].get("glow", "")
			if typeof(glow_value) != TYPE_STRING or not str(glow_value).is_empty():
				_eye_warning("eye_states.%s" % pair[0], "glow data requires an existing glow slot; keeping the original head")
				return

	var timing_value: Variant = config.get("timing", {})
	var timing: Dictionary = timing_value if typeof(timing_value) == TYPE_DICTIONARY else {}
	if typeof(timing_value) != TYPE_DICTIONARY:
		_eye_warning("eye_states.timing", "expected a dictionary; using EyeBlink safe defaults")
	var blink: Variant = EYE_BLINK_SCRIPT.new()
	blink.setup(skin_id, timing)
	_eye_part = head_sprite
	_eye_glow = glow_node
	_eye_open_texture = open_texture
	_eye_half_texture = half_texture
	_eye_closed_texture = closed_texture
	_eye_open_glow = open_glow
	_eye_half_glow = half_glow
	_eye_closed_glow = closed_glow
	_eye_blink = blink
	_eye_part.texture = _eye_open_texture
	if _eye_glow != null:
		_eye_glow.texture = _eye_open_glow


func _valid_eye_metadata(definition: Dictionary, expected_size: Vector2i, expected_pivot: Vector2, field: String) -> bool:
	var file_value: Variant = definition.get("file", "")
	var size_value: Variant = definition.get("size")
	var pivot_value: Variant = definition.get("pivot")
	if typeof(file_value) != TYPE_STRING or str(file_value).is_empty():
		_eye_warning(field, "texture file must be a non-empty path")
		return false
	if typeof(size_value) != TYPE_ARRAY or (size_value as Array).size() != 2:
		_eye_warning(field, "texture size must contain two values")
		return false
	if typeof(pivot_value) != TYPE_ARRAY or (pivot_value as Array).size() != 2:
		_eye_warning(field, "texture pivot must contain two values")
		return false
	for value: Variant in size_value:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			_eye_warning(field, "texture size contains a non-finite or non-numeric value")
			return false
	for value: Variant in pivot_value:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			_eye_warning(field, "texture pivot contains a non-finite or non-numeric value")
			return false
	var declared_size := Vector2(float(size_value[0]), float(size_value[1]))
	var declared_pivot := Vector2(float(pivot_value[0]), float(pivot_value[1]))
	if declared_size.x <= 0.0 or declared_size.y <= 0.0 or declared_size != Vector2(expected_size):
		_eye_warning(field, "texture size must match the original head canvas %s" % expected_size)
		return false
	if not declared_pivot.is_equal_approx(expected_pivot):
		_eye_warning(field, "texture pivot must match the original head pivot %s" % expected_pivot)
		return false
	return true


func _eye_texture_path(definition: Dictionary) -> String:
	return RigLibrary.character_dir(skin_id).path_join(str(definition.get("file", "")))


func _load_eye_state_texture(textures: Dictionary, texture_key: String, expected_size: Vector2i, expected_pivot: Vector2, field: String, normal_required: bool) -> Texture2D:
	var definition_value: Variant = textures.get(texture_key)
	if typeof(definition_value) != TYPE_DICTIONARY:
		_eye_warning(field, "texture '%s' is missing; keeping the original head" % texture_key)
		return null
	var definition: Dictionary = definition_value
	if not _valid_eye_metadata(definition, expected_size, expected_pivot, field):
		return null
	var path := _eye_texture_path(definition)
	if not ResourceLoader.exists(path):
		_eye_warning(field, "source file is missing: %s; keeping the original head" % path)
		return null
	var raw := load(path) as Texture2D
	if raw == null or raw.get_size() != Vector2(expected_size):
		_eye_warning(field, "source file is unreadable or has the wrong dimensions: %s" % path)
		return null
	if not _eye_normal_map_matches(path, expected_size, field, normal_required):
		return null
	var texture := LitTextures.load_texture(path, expected_size)
	if texture == null or texture.get_size() != Vector2(expected_size):
		_eye_warning(field, "LitTextures returned an invalid texture; keeping the original head")
		return null
	return texture


func _eye_normal_map_path(path: String) -> String:
	return path.get_basename() + "_n." + path.get_extension()


func _eye_normal_map_matches(path: String, expected_size: Vector2i, field: String, required: bool) -> bool:
	var normal_path := _eye_normal_map_path(path)
	if not ResourceLoader.exists(normal_path):
		if required:
			_eye_warning(field, "a normal map is required to preserve the original head lighting: %s" % normal_path)
			return false
		return true
	var normal := load(normal_path) as Texture2D
	if normal == null or normal.get_size() != Vector2(expected_size):
		_eye_warning(field, "normal map must match the head canvas %s: %s" % [expected_size, normal_path])
		return false
	return true


func _find_eye_glow(sprite: Sprite2D) -> Sprite2D:
	for child in sprite.get_children():
		if child is Sprite2D and (child as Sprite2D).material == _glow_material():
			return child as Sprite2D
	return null


func _load_eye_glow(definition: Dictionary, expected_size: Vector2i, required: bool, field: String) -> Texture2D:
	var glow_value: Variant = definition.get("glow", "")
	if typeof(glow_value) != TYPE_STRING:
		_eye_warning(field, "glow must be a path string when present")
		return null
	var glow_file := str(glow_value)
	if glow_file.is_empty():
		if required:
			_eye_warning(field, "glow texture is required to preserve the existing head glow")
		return null
	if not required:
		_eye_warning(field, "glow texture has no existing glow slot; keeping the original head")
		return null
	var path := RigLibrary.character_dir(skin_id).path_join(glow_file)
	if not ResourceLoader.exists(path):
		_eye_warning(field, "glow source file is missing: %s" % path)
		return null
	var glow := RigLibrary.optional_texture(path)
	if glow == null or glow.get_size() != Vector2(expected_size):
		_eye_warning(field, "glow texture must match the head canvas %s: %s" % [expected_size, path])
		return null
	return glow


func _eye_warning(field: String, reason: String) -> void:
	push_warning("[CharacterRig] %s.%s invalid; %s" % [skin_id, field, reason])


func _update_eye_states(delta: float, input: RigInput) -> void:
	if _eye_blink == null or _eye_part == null:
		return
	var state: StringName = _eye_blink.update(delta, input.talking, input.dead)
	if state == _eye_state:
		return
	_eye_state = state
	match state:
		&"open":
			_eye_part.texture = _eye_open_texture
			if _eye_glow != null:
				_eye_glow.texture = _eye_open_glow
		&"half":
			_eye_part.texture = _eye_half_texture
			if _eye_glow != null:
				_eye_glow.texture = _eye_half_glow
		&"closed":
			_eye_part.texture = _eye_closed_texture
			if _eye_glow != null:
				_eye_glow.texture = _eye_closed_glow


func _update_hand_grips(input: RigInput) -> void:
	for entry in _hand_grips:
		var closed := not _weapon_def.is_empty() and not input.dead
		if entry["bone"] == &"hand_back":
			closed = closed and input.two_handed and not input.shield_forward and input.action == &""
		if closed == entry["closed"]:
			continue
		var sprite: Sprite2D = entry["sprite"]
		sprite.texture = entry["grip_texture"] if closed else entry["open_texture"]
		sprite.offset = -entry["grip_pivot"] if closed else -entry["open_pivot"]
		entry["closed"] = closed


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
