extends RefCounted
## The same visible weapon silhouette, sampled after MeleeHeld publishes this physics pose.
## Local triangles are cached once per weapon. World buffers are reused; sweeps include every edge.
static var _meshes: Dictionary = {}
var _local := PackedVector2Array()
var current := PackedVector2Array()
var previous := PackedVector2Array()
var tick := -1
var previous_tick := -1
var _weapon: WeaponData
var _facing := 0
var _span := Vector2(-512.0, 512.0)
var _valid := false

func clear() -> void:
	_valid = false
	tick = -1
	previous_tick = -1

func capture(weapon: WeaponData, xf: Transform2D, facing: int, rope: SoftWhip, canvas: Transform2D, span := Vector2(-512.0, 512.0)) -> void:
	var changed := weapon != _weapon or facing != _facing or span != _span
	if changed:
		_weapon = weapon
		_span = span
		_facing = facing
		_local = _mesh(weapon, span) if weapon.melee_shape != "whip" else PackedVector2Array()
		var count := _local.size() if weapon.melee_shape != "whip" else (SoftWhip.NODES - 1) * 6
		current.resize(count)
		previous.resize(count)
		_valid = false
	previous_tick = tick
	tick = Engine.get_physics_frames()
	for i in current.size():
		previous[i] = current[i]
	if weapon.melee_shape == "whip":
		if rope == null or not rope.is_laid():
			clear()
			return
		var inverse := canvas.affine_inverse()
		for i in range(1, SoftWhip.NODES):
			# Match SoftWhip.draw body width in its drawing canvas, including canvas scale.
			var a := inverse * rope.node(i - 1)
			var b := inverse * rope.node(i)
			var half := (b - a).normalized().orthogonal() * lerpf(SoftWhip.ROOT_WIDTH, SoftWhip.TIP_WIDTH, float(i) / (SoftWhip.NODES - 1)) * 0.5
			var at := (i - 1) * 6
			current[at] = canvas * (a - half)
			current[at + 1] = canvas * (b - half)
			current[at + 2] = canvas * (b + half)
			current[at + 3] = current[at]
			current[at + 4] = current[at + 2]
			current[at + 5] = canvas * (a + half)
	else:
		for i in _local.size():
			current[i] = xf * _local[i]
	if not _valid:
		for i in current.size():
			previous[i] = current[i]
		previous_tick = tick
	_valid = true

func contact(box: Hurtbox, from_fraction := 0.0, to_fraction := 1.0) -> Vector2:
	if not _valid:
		return Vector2.INF
	for i in range(0, current.size(), 3):
		var a := previous[i].lerp(current[i], to_fraction)
		var b := previous[i + 1].lerp(current[i + 1], to_fraction)
		var c := previous[i + 2].lerp(current[i + 2], to_fraction)
		var pa := previous[i].lerp(current[i], from_fraction)
		var pb := previous[i + 1].lerp(current[i + 1], from_fraction)
		var pc := previous[i + 2].lerp(current[i + 2], from_fraction)
		var point := box.triangle_contact(a, b, c)
		if point.is_finite():
			return point
		point = box.triangle_contact(pa, pb, pc)
		if point.is_finite():
			return point
		point = _edge_contact(box, pa, pb, a, b)
		if point.is_finite():
			return point
		point = _edge_contact(box, pb, pc, b, c)
		if point.is_finite():
			return point
		point = _edge_contact(box, pc, pa, c, a)
		if point.is_finite():
			return point
	return Vector2.INF


static func _edge_contact(box: Hurtbox, pa: Vector2, pb: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var point := box.triangle_contact(pa, a, b)
	return point if point.is_finite() else box.triangle_contact(pa, b, pb)


static func _mesh(weapon: WeaponData, span: Vector2) -> PackedVector2Array:
	var art := MeleeArt.art(weapon)
	var texture := art.get("texture") as Texture2D
	var key := "%s/%s/%s/%s/%s/%s/%s" % [weapon.id, weapon.melee_shape, weapon.melee_length, texture.get_instance_id() if texture != null else 0, art.get("size"), art.get("grip"), span]
	if _meshes.has(key):
		return _meshes[key]
	var triangles := PackedVector2Array()
	if texture != null:
		var image := texture.get_image()
		if image != null and image.is_compressed() and image.decompress() != OK:
			image = null
		if image != null and not image.is_empty():
			var rect := MeleeArt.texture_rect(art)
			var scale := rect.size / Vector2(image.get_size())
			# Merge equal opaque vertical runs across columns. Unlike an outer contour this
			# preserves transparent holes as well as concavities, using the actual source alpha.
			var active: Dictionary = {}
			for x in range(image.get_width() + 1):
				var runs: Dictionary = {}
				var first := -1
				for y in range(image.get_height() + 1):
					var opaque := x < image.get_width() and y < image.get_height() and image.get_pixel(x, y).a > 0.1
					if opaque and first < 0:
						first = y
					elif not opaque and first >= 0:
						runs[Vector2i(first, y)] = true
						first = -1
				for run: Vector2i in active.keys():
					if not runs.has(run):
						var start := int(active[run])
						_append_quad(triangles, Vector2(start, run.x) * scale + rect.position, Vector2(x, run.y) * scale + rect.position, span)
						active.erase(run)
				for run: Vector2i in runs:
					if not active.has(run):
						active[run] = x
		else:
			push_error("[MeleeContact] Cannot read visible weapon alpha: %s (%s); contact disabled for unreadable visible art" % [weapon.id, texture.resource_path])
	if texture == null:
		for segment in MeleeArt.segments(weapon):
			var a: Vector2 = segment["a"]
			var b: Vector2 = segment["b"]
			var side := (b - a).normalized().orthogonal() * float(segment["w"]) * 0.5
			var polygon := _clip_span(PackedVector2Array([a - side, b - side, b + side, a + side]), span)
			var indices := Geometry2D.triangulate_polygon(polygon)
			for index in indices:
				triangles.append(polygon[index])
	_meshes[key] = triangles
	return triangles


static func _append_quad(into: PackedVector2Array, from: Vector2, to: Vector2, span: Vector2) -> void:
	from.x = maxf(from.x, span.x)
	to.x = minf(to.x, span.y)
	if from.x >= to.x:
		return
	into.append_array(PackedVector2Array([from, Vector2(to.x, from.y), to, from, to, Vector2(from.x, to.y)]))


static func _clip_span(polygon: PackedVector2Array, span: Vector2) -> PackedVector2Array:
	for side in 2:
		if polygon.is_empty():
			break
		var result := PackedVector2Array()
		var previous_point := polygon[-1]
		var previous_inside := previous_point.x >= span.x if side == 0 else previous_point.x <= span.y
		for point in polygon:
			var inside := point.x >= span.x if side == 0 else point.x <= span.y
			if inside != previous_inside:
				var boundary := span.x if side == 0 else span.y
				result.append(previous_point.lerp(point, (boundary - previous_point.x) / (point.x - previous_point.x)))
			if inside:
				result.append(point)
			previous_point = point
			previous_inside = inside
		polygon = result
	return polygon
