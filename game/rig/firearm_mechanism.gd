extends Node2D
## Shared weapon art, with three reusable animated assemblies on the player's mount.

const DATA := "res://data/weapon_art/firearm_mechanisms.json"
const SHEET := "res://art/weapons/modular/firearm_mechanisms.png"
const GLOW := "res://art/weapons/modular/firearm_mechanisms_glow.png"
const SLOTS: Array[String] = ["cell", "barrel", "rail"] # WeaponUpgradeData.Effect order.
const FEEDS: Array[String] = ["drop", "rack", "split", "hinge"]

static var _recipes: Dictionary = {}
static var _ready_to_resolve := false

var _parts: Array[Sprite2D] = []
var _emitters: Array[Sprite2D] = []
var _sockets: Array[Vector2] = []
var _feed := 0
var _tier := 0
var _quick := false
var _scale := 1.0
var _progress := -1.0


func setup(weapon_root: Node2D, material: Material) -> void:
	hide()
	name = "Mechanism"
	weapon_root.add_child(self)
	for slot in SLOTS:
		var part := Sprite2D.new()
		part.name = slot
		part.centered = false
		part.material = material
		add_child(part)
		_parts.append(part)
		_sockets.append(Vector2.ZERO)
		var emission := Sprite2D.new()
		emission.centered = false
		LightKit.mark_emissive(emission)
		part.add_child(emission)
		_emitters.append(emission)


## Returns the stock shell with art for all three sockets, or null for the assembled fallback.
func present(visual_id: String, grip: Vector2, scale_per_texel: float, flags: int) -> Dictionary:
	visible = false
	_progress = -1.0
	if visual_id.is_empty():
		return {}
	if not _ready_to_resolve:
		_resolve()
	var recipe: Dictionary = _recipes.get(visual_id, {})
	if recipe.is_empty():
		return {}
	_scale = scale_per_texel
	_tier = int((flags & 1) != 0) + int((flags & 2) != 0) + int((flags & 4) != 0)
	_quick = (flags & 4) != 0
	_feed = recipe["feed"]
	var sockets: Array[Rect2] = recipe["sockets"]
	var styles: Array = recipe["styles"]
	for i in _parts.size():
		var upgraded := (flags & (1 << i)) != 0
		var skin: Dictionary = styles[i][1 if upgraded else 0]
		var art: Texture2D = skin["surface"]
		var socket := sockets[i]
		if upgraded:
			if i == 0:
				if _feed == 0:
					socket.size.y *= 1.28
				else:
					socket.size.x *= 1.15
			else:
				socket.position.y -= socket.size.y * 0.09
				socket.size.y *= 1.18
		_parts[i].texture = art
		_emitters[i].texture = skin["glow"]
		_parts[i].scale = socket.size * _scale / art.get_size()
		_sockets[i] = (socket.position - grip) * _scale
	visible = true
	update_reload(0.0)
	return recipe


func update_reload(fraction: float) -> void:
	if not visible or is_equal_approx(fraction, _progress):
		return
	_progress = fraction
	var latch := smoothstep(0.08, 0.28, fraction) * (1.0 - smoothstep(0.70, 0.94, fraction))
	var travel := smoothstep(0.18, 0.43, fraction) * (1.0 - smoothstep(0.50, 0.82, fraction))
	if _quick:
		travel = smoothstep(0.19, 0.34, fraction) * (1.0 - smoothstep(0.44, 0.67, fraction))
	var size := 1.0 + _tier * 0.11
	var motion := Vector2(-2.0, 23.0)
	var spin := -0.13
	match _feed:
		1:
			motion = Vector2(20.0, 7.0)
			spin = -0.04
		2:
			motion = Vector2(13.0, -16.0)
			spin = 0.18
		3:
			motion = Vector2(-11.0, 18.0)
			spin = 0.32
	_parts[0].position = _sockets[0] + motion * (travel * _scale * size)
	_parts[0].rotation = spin * travel
	var barrel_latch := latch if _tier > 0 else 0.0
	if _tier >= 2:
		barrel_latch = smoothstep(0.05, 0.19, fraction) * (1.0 - smoothstep(0.58, 0.82, fraction))
	_parts[1].position = _sockets[1] + Vector2(-5.0 - 2.0 * _tier, -4.5 * size) * (barrel_latch * _scale)
	var lift := latch
	if _tier == 3:
		# Two-stage servo return, with a short pause while the replacement cell locks.
		lift *= 0.70 + 0.30 * (1.0 - smoothstep(0.49, 0.66, fraction))
	_parts[2].position = _sockets[2] + Vector2(-7.0 - 2.0 * _tier, -10.0 * size) * (lift * _scale)
	_parts[2].rotation = -0.17 * lift
	var seal := smoothstep(0.77, 0.86, fraction) * (1.0 - smoothstep(0.86, 0.98, fraction))
	var gain := 1.0 + seal * _tier * 0.08 * Settings.flash_scale()
	_emitters[2].self_modulate = Color(gain, gain, gain)


static func _resolve() -> void:
	_ready_to_resolve = true
	var data := RigLibrary.load_json(DATA)
	var available := RigLibrary.optional_texture(SHEET)
	if available == null:
		push_warning("[FirearmMechanism] 找不到零件圖集，沿用組好的槍械：%s" % SHEET)
		return
	var sheet := LitTextures.load_texture(SHEET)
	var emission := RigLibrary.optional_texture(GLOW)
	if emission != null and emission.get_size() != sheet.get_size():
		push_warning("[FirearmMechanism] 零件發光圖集尺寸錯誤，停用：%s" % GLOW)
		emission = null
	var regions: Variant = data.get("regions")
	var guns: Variant = data.get("guns")
	if not regions is Dictionary or not guns is Dictionary:
		push_warning("[FirearmMechanism] %s 缺少 regions 或 guns" % DATA)
		return
	var styles: Array = []
	var image := Rect2(Vector2.ZERO, sheet.get_size())
	for slot in SLOTS:
		var pair: Variant = regions.get(slot)
		if not pair is Array or pair.size() != 2:
			_invalid(slot)
			return
		var plain := _region(pair[0], image)
		var upgrade := _region(pair[1], image)
		if not plain.has_area() or not upgrade.has_area():
			_invalid(slot)
			return
		styles.append([_skin(sheet, emission, plain), _skin(sheet, emission, upgrade)])
	for name: String in guns:
		var definition: Variant = guns[name]
		if not definition is Dictionary:
			_invalid(name)
			continue
		var body := _region(definition.get("body"), image)
		var visual := RigLibrary.weapon(name)
		var size := RigLibrary.vec2(visual.get("size"))
		var feed := FEEDS.find(str(definition.get("feed")))
		if not body.has_area() or body.size != size or feed < 0:
			_invalid(name)
			continue
		var sockets: Array[Rect2] = []
		for slot in SLOTS:
			var point := _region(definition.get(slot), Rect2(Vector2.ZERO, size))
			if not point.has_area():
				_invalid(name + "/" + slot)
				break
			sockets.append(point)
		if sockets.size() == SLOTS.size():
			_recipes[name] = {"body": _slice(sheet, body), "glow": _slice(emission, body), "feed": feed, "sockets": sockets, "styles": styles}


static func _region(value: Variant, field: Rect2) -> Rect2:
	if not value is Array or value.size() != 4:
		return Rect2()
	for component: Variant in value:
		if (not component is float and not component is int) or not is_finite(float(component)):
			return Rect2()
	var rect := Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return rect if rect.has_area() and field.encloses(rect) else Rect2()


static func _skin(sheet: Texture2D, emission: Texture2D, region: Rect2) -> Dictionary:
	return {"surface": _slice(sheet, region), "glow": _slice(emission, region)}


static func _slice(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	if sheet == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = region
	texture.filter_clip = true
	return texture


static func _invalid(entry: String) -> void:
	push_warning("[FirearmMechanism] %s/%s 的零件資料無效，沿用組好的槍械" % [DATA, entry])
