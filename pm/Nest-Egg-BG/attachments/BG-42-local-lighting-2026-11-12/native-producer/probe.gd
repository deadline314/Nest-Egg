extends "res://tools/bg55_enemy_readability_probe.gd"
## BG42 historical prop counterfactual plus isolated office profile on today's held geometry.
var _prepared42: Level
var _authored42: Array[PropNode] = []
var _original42: Array[PropNode] = []
var _delta42: Dictionary = {}
var _reference_active42 := false


func _ready() -> void:
	_delta42 = JSON.parse_string(FileAccess.get_file_as_string("res://work/bg42-counterfactual-v2/prop-delta.json"))
	if OS.get_cmdline_user_args().has("--validate-only"):
		var checks := 0
		for id in _delta42:
			var data := load("res://data/levels/%s.tres" % id) as LevelData
			var authored := data.load_props()
			for entry in _delta42[id].added:
				var found := false
				for current in authored:
					if current == entry: found = true
				assert(found, "original BG42 added prop changed; review explicitly")
				checks += 1
			for entry in _delta42[id].removed:
				assert(PropLibrary.find_in(StringName(entry.id), data.environment.prop_dirs()) != null)
				checks += 1
		print("BG42_PROP_DELTA checks=", checks, " failures=0")
		get_tree().quit(0)
		return
	super._ready()
	for layer in get_children():
		if layer is CanvasLayer:
			for node in layer.get_children():
				if node is Label: node.visible = false


func _settle(frames: int) -> void:
	await super._settle(frames)
	if is_instance_valid(_held55) and _prepared42 != _held55:
		_prepared42 = _held55
		_authored42.clear()
		_original42.clear()
		var delta: Dictionary = _delta42[str(_held55.data.id)]
		for node in _held55._world.get_children():
			if not node is PropNode: continue
			for entry in delta.added:
				if str(node.data.id) == str(entry.id): _authored42.append(node)
		assert(_authored42.size() == delta.added.size(), "all BG42 added nodes must exist")
		for entry in delta.removed:
			var prop := PropLibrary.find_in(StringName(entry.id), _held55.data.environment.prop_dirs())
			var placed := PropPlacement.resolve(entry, prop, _held55._layout)
			assert(not placed.is_empty())
			var issue := ScenerySupport.check_prop(entry, prop, placed.rect, _held55._layout, _held55._scenery_walls, _held55.data.load_props(), _held55.data.environment.prop_dirs())
			assert(issue.is_empty(), issue)
			var node := _held55._place_prop(prop, placed.rect.position, bool(placed.flip))
			node.z_index = WorldLayers.PROPS
			node.visible = false
			_original42.append(node)
		HeldLighting55.preserve_physics_bodies(_held55)


func _variant42(level: Level, reference: bool) -> void:
	_reference_active42 = reference
	for node in _authored42: _prop_visible42(node, not reference)
	for node in _original42: _prop_visible42(node, reference)
	_sync55(level)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _prop_visible42(node: PropNode, active: bool) -> void:
	node.visible = active
	# LightBudget evaluates enabled lights even below a hidden parent. A prop
	# excluded from this variant must not consume the real owner's light slots.
	for light in node.find_children("*", "PointLight2D", true, false):
		if not light.has_meta(&"bg42_enabled"):
			light.set_meta(&"bg42_enabled", light.enabled)
		light.enabled = active and bool(light.get_meta(&"bg42_enabled"))


func _capture55(level: Level, world: Rect2, label: String) -> Dictionary:
	var record := await super._capture55(level, world.grow(24), label)
	var probe := ContrastProbe.capture(get_viewport())
	assert(bytes_sha(probe._image.get_data()) == record.raw_sha256)
	if level.player.is_visible_in_tree():
		var feet := level.player.global_position
		var parts := probe.character_parts(feet, true)
		var body := probe._body_box(feet, true)
		record["player"] = {"feet": [feet.x, feet.y], "parts": parts,
			"contrast": maxf(parts.bright, parts.dark), "edge_contrast": probe.edge_contrast(feet),
			"screen_rect": rect_values(probe._screen_rect(body)),
			"outer_screen_rect": rect_values(probe._screen_rect(body.grow(ContrastProbe.RING))),
			"edge_screen_rect": rect_values(probe._screen_rect(Rect2(feet + Vector2(-24, 0), Vector2(48, 3)))),
			"below_screen_rect": rect_values(probe._screen_rect(Rect2(feet + Vector2(-24, 8), Vector2(48, 6))))}
	record["prop_reference"] = _reference_active42
	var props: Array[Dictionary] = []
	for node in level._world.get_children():
		if node is PropNode:
			props.append({"id": str(node.data.id), "instance": node.get_instance_id(), "visible": node.is_visible_in_tree(),
				"position": [node.position.x, node.position.y], "z": node.z_index})
	record["props"] = props
	record["enemy_inventory"] = []
	for node in level._entities.get_children():
		if node is Enemy: record.enemy_inventory.append({"id": str(node.data.id), "instance": node.get_instance_id(), "alive": not node.health.is_dead, "visible": node.is_visible_in_tree()})
	return record


func _measure(level: Level, world: Rect2) -> Dictionary:
	_active_cell55 = _cell55
	_cell55 += 1
	var original := level._lighting.current.duplicate() as LightingProfile
	var candidate := original
	if str(level.data.id) == "ch2_ledger_office":
		candidate = load("res://work/bg42-counterfactual-v2/ledger_office_interior.tres") as LightingProfile
	assert(candidate != null and candidate.validate().is_empty())
	var sequence := [[true, false, "A0"], [true, false, "A1"], [false, false, "product-old"],
		[true, false, "restore-old"], [true, true, "reference-new"], [false, true, "product-new"],
		[true, true, "restore-new"], [true, false, "restore-original"], [false, true, "authored-final"]]
	var records: Array[Dictionary] = []
	for entry in sequence:
		await _apply55(level, candidate if entry[1] else original)
		await _variant42(level, entry[0])
		var record := await _capture55(level, world, entry[2])
		record["profile_candidate"] = entry[1]
		record["character_floor"] = level._lighting.current.character_floor
		record["enemy_fill_scale"] = level._lighting.current.enemy_fill_scale
		record["character_fill"] = LightKit.character_fill
		record["profile_valid"] = level._lighting.current.validate().is_empty()
		record["scope"] = "original BG42 prop delta and local office profile; current held geometry/runtime; no full historical checkout"
		records.append(record)
	var valid: bool = records[0].raw_sha256 == records[1].raw_sha256 and records[0].raw_sha256 == records[3].raw_sha256 and records[0].raw_sha256 == records[7].raw_sha256
	valid = valid and records[4].raw_sha256 == records[6].raw_sha256 and records[5].raw_sha256 == records[8].raw_sha256
	for record in records:
		valid = valid and record.held.lighting_owners.valid and record.profile_valid
		if record.has("player"): valid = valid and bool(record.held.player_support.valid)
	if not valid:
		_contrast_failures += 1
		printerr("[BG42] Identity/restoration/owner/support control failed")
	var final: Dictionary = records[-1]
	var passed: bool = valid
	if final.has("player"):
		passed = passed and final.player.contrast >= 0.6 and final.player.edge_contrast >= 1.0
	for enemy in final.enemies: passed = passed and enemy.contrast >= 0.45
	if not passed:
		_contrast_failures += 1
		printerr("[BG42] Original threshold failure: ", level.data.id, " ", final.get("player", {}))
	return {"bg42": {"controls_valid": valid, "records": records, "prop_delta": _delta42[str(level.data.id)],
		"scope": "same current runtime/geometry; only original BG42 prop additions/removals and local office profile; later unrelated props retained"}, "passed": passed}


func _frame_interval_ms() -> float:
	return 0.0 # This ticket records no performance metric.


func _tour(level_id: String) -> bool:
	var result := await super._tour(level_id)
	_prepared42 = null
	_authored42.clear()
	_original42.clear()
	return result
