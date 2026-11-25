class_name FactorySweepLane
extends Area2D
## A proximity-activated sweep in a fixed, authored sector.
## The warning outline and live hitbox cover the same local rectangle.

const SweepPresentation = preload("res://game/hazards/sweep_presentation.gd")
const WAKE_MARGIN := 80.0
const SOURCE := &"factory_sweep"

enum State { DORMANT, WARNING, LIVE, RECOVERING }

var _profile: MechanismData
var _sector := Rect2()
var _state := State.DORMANT
var _time_left := 0.0
var _warning_step := 0
var _contact: ContactHitbox


func configure(profile: MechanismData, tile: int) -> void:
	_profile = profile
	var size := Vector2(profile.size_tiles) * tile
	_sector = Rect2(Vector2(-size.x * 0.5, -size.y), size)


func _ready() -> void:
	LightKit.mark_emissive(self)
	SweepPresentation.mount_emitter(self, _sector)
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var wake := _sector.grow(WAKE_MARGIN)
	var shape := RectangleShape2D.new()
	shape.size = wake.size
	var volume := CollisionShape2D.new()
	volume.position = wake.get_center()
	volume.shape = shape
	add_child(volume)
	_contact = ContactHitbox.new()
	add_child(_contact)
	_contact.setup(Combat.Team.ENEMY, _profile.sweep_damage, SOURCE, _sector.size, _sector.get_center())
	_set_hazard_live(false)
	body_entered.connect(_on_player_enter)
	body_exited.connect(_on_player_exit)
	set_physics_process(false)


func _on_player_enter(body: Node2D) -> void:
	if _state == State.DORMANT and Pickup.resolve_player(body) != null:
		_warn()
		set_physics_process(true)


func _on_player_exit(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_state = State.DORMANT
		_set_hazard_live(false)
		set_physics_process(false)
		queue_redraw()


func _set_hazard_live(live: bool) -> void:
	_contact.active = live
	_contact.set_physics_process(live)


func _warn() -> void:
	_state = State.WARNING
	_time_left = _profile.sweep_warning_seconds
	_warning_step = SweepPresentation.scan_step(0.0, Settings.get_reduce_ui_motion())
	Sfx.play(&"telegraph", -14.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		if _state == State.WARNING:
			var progress := 1.0 - _time_left / _profile.sweep_warning_seconds
			var step := SweepPresentation.scan_step(progress, Settings.get_reduce_ui_motion())
			if step != _warning_step:
				_warning_step = step
				queue_redraw()
		return
	match _state:
		State.WARNING:
			_state = State.LIVE
			_time_left = _profile.sweep_live_seconds
			_set_hazard_live(true)
			if not _profile.sweep_clear_flag.is_empty() and not GameState.has_flag(_profile.sweep_clear_flag):
				GameState.set_flag(_profile.sweep_clear_flag, true)
			Sfx.play(&"hit", -9.0)
			_emit_switch_sparks()
		State.LIVE:
			_state = State.RECOVERING
			_time_left = _profile.sweep_rest_seconds
			_set_hazard_live(false)
		State.RECOVERING:
			_warn()
	queue_redraw()


func _draw() -> void:
	match _state:
		State.WARNING:
			SweepPresentation.draw_warning(self, _sector, _warning_step, false)
		State.LIVE:
			SweepPresentation.draw_live(self, _sector, Settings.get_reduce_flashes())


func _emit_switch_sparks() -> void:
	if Settings.get_reduce_ui_motion() or Settings.get_reduce_flashes() or not has_node("SweepEmitter"):
		return
	var emitter := to_global(SweepPresentation.lens_position(_sector) + Vector2.DOWN)
	Fx.sparks(emitter, Color(0.32, 0.36, 0.4, 0.65), 4, 24.0, 0.22, Vector2.DOWN, 1.3, 34.0)
