class_name DashSilhouettePool
extends Node2D
## Capture-only geometry work; fading changes modulation of eight reusable slots.
## A sibling of Player, in the same world CanvasItem coordinate space.
## Never clones a Rig, texture, mesh or viewport. Unsupported geometry rejects a
## whole sample, rather than silently substituting a rest pose or stick figure.

const CAPACITY := 8
const LIFETIME := 0.18
const MAX_COMMANDS := 160
const MAX_PARTS := 128
const MAX_VERTICES := 4096
const MAX_INDICES := 24576
const MAX_MELEE_SEGMENTS := 32
const QUALITY_BUDGETS := [2, 4, CAPACITY]
const QUALITY_INTERVALS := [0.09, 0.06, 0.03]
const SILHOUETTE_SHADER := preload("res://game/player/dash_silhouette.gdshader")
static var _shared_material: ShaderMaterial

class Command extends RefCounted:
	var source_id := 0
	var texture: Texture2D
	var transform := Transform2D.IDENTITY
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var line_width := 0.0

	func release() -> void:
		texture = null
		source_id = 0

class Snapshot extends Node2D:
	var commands: Array[Command] = []
	var used := 0
	var age := 0.0
	var serial := 0
	var facing := 1.0
	var vertices := 0
	var index_count := 0

	func _init() -> void:
		for i in MAX_COMMANDS:
			commands.append(Command.new())
		visible = false

	func clear() -> void:
		if used == 0 and not visible:
			return
		for i in used:
			commands[i].release()
		used = 0
		vertices = 0
		index_count = 0
		visible = false
		queue_redraw()

	func take(count: int, indices_count: int) -> Command:
		if used >= MAX_COMMANDS or vertices + count > MAX_VERTICES or index_count + indices_count > MAX_INDICES:
			return null
		var command := commands[used]
		used += 1
		vertices += count
		index_count += indices_count
		return command

	func _draw() -> void:
		var item := get_canvas_item()
		for i in used:
			var command := commands[i]
			RenderingServer.canvas_item_add_set_transform(item, command.transform)
			if command.line_width > 0.0:
				RenderingServer.canvas_item_add_line(item, command.points[0], command.points[1], command.colors[0], command.line_width)
			else:
				RenderingServer.canvas_item_add_triangle_array(item, command.indices, command.points,
					command.colors, command.uv, PackedInt32Array(), PackedFloat32Array(), command.texture.get_rid())
		RenderingServer.canvas_item_add_set_transform(item, Transform2D.IDENTITY)

var slots: Array[Snapshot] = []
var _cursor := 0
var _serial := 0
var failure_reason := ""
var _warned := false
var _melee_weapon: WeaponData
var _melee_shape := ""
var _melee_length := 0.0
var _melee_color := Color.WHITE
var _melee_segments: Array[Dictionary] = []

func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SILHOUETTE_SHADER
	# Below every live character part (-9), above terrain (-20).
	z_index = WorldLayers.ENTITY_BEHIND
	for i in CAPACITY:
		var slot := Snapshot.new()
		slot.name = "Snapshot%d" % i
		slot.material = _shared_material
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(slot)
		slots.append(slot)
	Settings.display_changed.connect(_on_display_changed)

func _on_display_changed() -> void:
	# Signals still run while gameplay is paused: release every sample immediately.
	if not Settings.get_dash_silhouettes():
		clear()

## Project budgets, not a measured GPU/RAM limit. Do not use UI-motion preference
## to remove gameplay motion: Settings explicitly limits that preference to UI.
static func slot_budget() -> int:
	if not Settings.get_dash_silhouettes() or Settings.get_feel_scale("particles") <= 0.0:
		return 0
	var budget: int = QUALITY_BUDGETS[LightQuality.tier()]
	return mini(budget, 2) if Settings.get_reduce_flashes() else budget

static func sample_interval() -> float:
	var interval: float = QUALITY_INTERVALS[LightQuality.tier()]
	return maxf(interval, 0.09) if Settings.get_reduce_flashes() else interval

func tick(delta: float) -> void:
	var budget := slot_budget()
	for i in slots.size():
		var slot := slots[i]
		if not slot.visible:
			continue
		if i >= budget:
			slot.clear()
			continue
		slot.age += maxf(0.0, delta)
		if slot.age >= LIFETIME:
			slot.clear()
		else:
			slot.self_modulate.a = opacity() * (1.0 - slot.age / LIFETIME)

static func opacity() -> float:
	return 0.24 * Settings.flash_scale() * Settings.get_feel_scale("particles")

func clear() -> void:
	for slot in slots:
		slot.clear()
	_cursor = 0

func active_count() -> int:
	var count := 0
	for slot in slots:
		count += int(slot.visible)
	return count

func capture(visual: PlayerVisual) -> bool:
	failure_reason = ""
	var budget := slot_budget()
	if budget == 0 or not is_instance_valid(visual) or not visual.is_visible_in_tree() or not is_instance_valid(visual.rig) or not is_instance_valid(visual.player):
		return false
	if slots.size() != CAPACITY:
		return _reject(null, "pool has not finished setup")
	var rig := visual.rig
	# Visual.self_modulate affects its own procedural drawing, not Rig children.
	# Each source freezes its own alpha below; a transparent Visual can still
	# contain a visible body and gun.
	if not rig.is_valid() or rig._parts.size() > MAX_PARTS or rig._pose_slots.size() > MAX_PARTS or not _finite_transform(global_transform):
		return _reject(null, "invalid rig or world transform")
	var slot := slots[_cursor % budget]
	slot.clear()
	var pool_inverse := global_transform.affine_inverse()
	# Bound the existing Rig API's temporary work before it allocates skin arrays.
	var source_vertices := 0
	for part_value: Variant in rig._parts:
		if not is_instance_valid(part_value):
			continue
		var part := part_value as CanvasItem
		if part == null or not part.is_visible_in_tree():
			continue
		if part is Sprite2D:
			source_vertices += 4
		elif part is Polygon2D:
			var polygon := part as Polygon2D
			source_vertices += polygon.polygon.size()
			if polygon.polygon.size() > MAX_VERTICES or polygon.get_bone_count() > 4 or polygon.polygons.size() > MAX_INDICES / 3:
				return _reject(slot, "native/CPU source exceeds the snapshot geometry budget")
		if source_vertices > MAX_VERTICES:
			return _reject(slot, "combined rig geometry exceeds the snapshot budget")
	# This existing formal Rig API returns actual current skin vertices in Skeleton
	# space. Its <=4 influence validation matches Polygon2D's native weight limit.
	var native_geometry := rig.active_pose_mesh_geometries()
	for part_value: Variant in rig._parts:
		if not is_instance_valid(part_value):
			continue
		var part := part_value as CanvasItem
		if part == null or not part.is_visible_in_tree():
			continue
		# This pool supports alpha modulation, not an arbitrary shader discard.
		if rig._dissolve_material != null and part.material == rig._dissolve_material:
			return _reject(slot, "dissolving presentation is not a dash snapshot source")
		if part is Sprite2D:
			if not _sprite(slot, part as Sprite2D, pool_inverse):
				return _reject(slot, "unsupported Sprite2D: %s" % part.name)
		elif part is RigPartMesh:
			var mesh := part as RigPartMesh
			if not _polygon(slot, mesh, mesh.deformed_vertices(), pool_inverse * mesh.global_transform):
				return _reject(slot, "unsupported deformed mesh: %s" % part.name)
		elif part is Polygon2D:
			var found := false
			for geometry: Dictionary in native_geometry:
				if geometry["mesh"] == part:
					found = _polygon(slot, part as Polygon2D, geometry["vertices"], pool_inverse * rig._skeleton.global_transform)
					break
			if not found:
				return _reject(slot, "missing native skin geometry: %s" % part.name)
		else:
			return _reject(slot, "unsupported part type: %s" % part.name)
	var weapon: Sprite2D = rig._weapon_sprite
	if is_instance_valid(weapon) and weapon.is_visible_in_tree() and weapon.texture != null:
		if not _sprite(slot, weapon, pool_inverse):
			return _reject(slot, "unsupported actual held weapon")
	if not _melee(slot, visual, pool_inverse):
		return _reject(slot, "invalid actual melee presentation")
	if slot.used == 0:
		return false
	_serial += 1
	slot.serial = _serial
	slot.facing = rig.facing
	slot.age = 0.0
	slot.self_modulate = Color(1, 1, 1, opacity())
	slot.visible = true
	slot.queue_redraw()
	_cursor = (_cursor + 1) % budget
	return true

func _reject(slot: Snapshot, reason: String) -> bool:
	if slot != null:
		slot.clear()
	failure_reason = reason
	if not _warned:
		_warned = true
		push_warning("[DashSilhouettePool] sample omitted: " + reason)
	return false

static func _finite_transform(xf: Transform2D) -> bool:
	return xf.x.is_finite() and xf.y.is_finite() and xf.origin.is_finite() and is_finite(xf.determinant()) and not is_zero_approx(xf.determinant())

## Snapshot alpha below the common world parent. Parent self_modulate does not
## affect children. Shared world modulation is applied once by the pool's parent.
func _source_alpha(item: CanvasItem) -> float:
	var alpha := item.self_modulate.a
	var current: Node = item
	var depth := 0
	while current != get_parent() and current is CanvasItem and depth < 64:
		alpha *= (current as CanvasItem).modulate.a
		current = current.get_parent()
		depth += 1
	return clampf(alpha, 0.0, 1.0) if is_finite(alpha) and depth < 64 else 0.0

func _sprite(slot: Snapshot, sprite: Sprite2D, inverse: Transform2D) -> bool:
	if sprite.texture == null:
		return true
	var alpha := _source_alpha(sprite)
	if alpha <= 0.0:
		return true
	var xf := inverse * sprite.global_transform
	var size := sprite.texture.get_size()
	if not _finite_transform(xf) or size.x <= 0.0 or size.y <= 0.0:
		return false
	var source := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, size)
	var frame_size := source.size / Vector2(sprite.hframes, sprite.vframes)
	source = Rect2(source.position + Vector2(sprite.frame_coords) * frame_size, frame_size)
	# Current CharacterRig sprites are unframed and unclipped. Generic framed
	# sources remain supported, but outside-texture region clipping is refused.
	if not source.has_area() or source.position.x < 0.0 or source.position.y < 0.0 or source.end.x > size.x or source.end.y > size.y:
		return false
	var rect := sprite.get_rect()
	var command := slot.take(4, 6)
	if command == null:
		return false
	command.source_id = sprite.get_instance_id()
	command.texture = sprite.texture
	command.transform = xf
	command.points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var start := source.position / size
	var end := source.end / size
	if sprite.flip_h:
		var x := start.x
		start.x = end.x
		end.x = x
	if sprite.flip_v:
		var y := start.y
		start.y = end.y
		end.y = y
	command.uv = PackedVector2Array([start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)])
	command.indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
	command.colors = PackedColorArray([Color(1, 1, 1, alpha)])
	command.line_width = 0.0
	return true

func _polygon(slot: Snapshot, polygon: Polygon2D, vertices: PackedVector2Array, xf: Transform2D) -> bool:
	var alpha := _source_alpha(polygon)
	if alpha <= 0.0:
		return true
	if polygon.texture == null or polygon.invert_enabled or polygon.offset != Vector2.ZERO or not _finite_transform(xf):
		return false
	if vertices.size() < 3 or vertices.size() > MAX_VERTICES or polygon.uv.size() != vertices.size():
		return false
	var indices := PackedInt32Array()
	# Formal rig meshes provide triangles. Reject unknown topology before copying.
	for triangle: PackedInt32Array in polygon.polygons:
		if triangle.size() != 3 or indices.size() + 3 > MAX_INDICES:
			return false
		for index in triangle:
			if index < 0 or index >= vertices.size():
				return false
		indices.append_array(triangle)
	if indices.is_empty():
		return false
	var texture_size := polygon.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	var uv := PackedVector2Array()
	uv.resize(vertices.size())
	# Same source transform as Godot Polygon2D::_notification(NOTIFICATION_DRAW).
	var texture_xf := Transform2D(polygon.texture_rotation, polygon.texture_offset).scaled(polygon.texture_scale)
	for i in vertices.size():
		if not vertices[i].is_finite() or not polygon.uv[i].is_finite():
			return false
		uv[i] = texture_xf * polygon.uv[i] / texture_size
	var command := slot.take(vertices.size(), indices.size())
	if command == null:
		return false
	command.source_id = polygon.get_instance_id()
	command.texture = polygon.texture
	command.transform = xf
	command.points = vertices.duplicate()
	command.uv = uv
	command.indices = indices
	command.line_width = 0.0
	command.colors = PackedColorArray()
	if polygon.vertex_colors.size() == vertices.size():
		for color in polygon.vertex_colors:
			if not is_finite(color.a):
				return false
			command.colors.append(Color(1, 1, 1, alpha * color.a))
	else:
		if not is_finite(polygon.color.a):
			return false
		command.colors.append(Color(1, 1, 1, alpha * polygon.color.a))
	return true

func _melee(slot: Snapshot, visual: PlayerVisual, inverse: Transform2D) -> bool:
	var player := visual.player
	if not player.holds_melee_weapon() or visual._phone_t >= 0.0:
		return true
	var hand := visual.rig.bone(&"hand_front")
	var forearm := visual.rig.bone(&"arm_front_lower")
	if hand == null or forearm == null:
		return false
	# Identical coordinate recipe to PlayerVisual._draw_melee_weapon: its source
	# direction is world space, while its drawing occurs in PlayerVisual space.
	var direction := (hand.global_position - forearm.global_position).normalized()
	var weapon := player.loadout.active_weapon()
	if weapon == null or not direction.is_finite():
		return false
	if weapon != _melee_weapon or weapon.melee_shape != _melee_shape or weapon.melee_length != _melee_length or weapon.color != _melee_color:
		_melee_weapon = weapon
		_melee_shape = weapon.melee_shape
		_melee_length = weapon.melee_length
		_melee_color = weapon.color
		_melee_segments = MeleeArt.segments(weapon)
	if _melee_segments.size() > MAX_MELEE_SEGMENTS:
		return false
	var xf := Transform2D(direction.angle(), visual.to_local(hand.global_position))
	for segment: Dictionary in _melee_segments:
		var command := slot.take(2, 0)
		if command == null:
			return false
		command.source_id = player.get_instance_id()
		command.texture = null
		command.transform = inverse * visual.global_transform
		command.points = PackedVector2Array([xf * (segment["a"] as Vector2), xf * (segment["b"] as Vector2)])
		command.colors = PackedColorArray([Color(1, 1, 1, _source_alpha(visual) * (segment["c"] as Color).a)])
		command.line_width = float(segment["w"])
		if command.line_width <= 0.0 or not is_finite(command.line_width):
			return false
	return true
