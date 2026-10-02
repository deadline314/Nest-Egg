class_name Explosion
extends Node2D
## 範圍爆炸：在第一個物理影格查詢範圍內的受擊框並造成傷害，之後只播放視覺效果。
## 請透過 Fx.explosion() 生成。

const DURATION := 0.3
const MAX_TARGETS := 32

var radius := 24.0
var damage := 1
var team: Combat.Team = Combat.Team.ENEMY
var source_id: StringName = &""
var color := Palette.WARNING

var _age := 0.0
var _applied := false


func _physics_process(delta: float) -> void:
	if not _applied:
		_applied = true
		_apply_damage()
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _apply_damage() -> void:
	if damage <= 0 or radius <= 0.0:
		return
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = Combat.hurtbox_mask_against(team)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var seen: Dictionary = {}
	for hit in get_world_2d().direct_space_state.intersect_shape(params, MAX_TARGETS):
		var hurtbox := hit.get("collider") as Hurtbox
		if hurtbox == null or seen.has(hurtbox):
			continue
		seen[hurtbox] = true
		var info := DamageInfo.create(damage, team, source_id)
		var away := hurtbox.global_position - global_position
		info.knockback = (away.normalized() if away.length_squared() > 1.0 else Vector2.UP) * 180.0 + Vector2(0, -80)
		info.origin = global_position
		info.bypass_guard = true
		hurtbox.receive(info)


func _draw() -> void:
	var t := clampf(_age / DURATION, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * (0.35 + 0.65 * t), Color(color, 0.55 * (1.0 - t)))
	draw_arc(Vector2.ZERO, radius * (0.6 + 0.4 * t), 0.0, TAU, 32, Color(Palette.WHITE, 1.0 - t), 2.0)
