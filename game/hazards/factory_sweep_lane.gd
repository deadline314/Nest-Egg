class_name FactorySweepLane
extends Area2D
## A proximity-activated sweep in a fixed, authored sector.
## The warning outline and live hitbox cover the same local rectangle.

const WARNING_COLOR := Color(0.92, 0.95, 0.97)
const WAKE_MARGIN := 80.0
const SOURCE := &"factory_sweep"

enum State { DORMANT, WARNING, LIVE, RECOVERING }

var _profile: MechanismData
var _sector := Rect2()
var _state := State.DORMANT
var _time_left := 0.0
var _contact: ContactHitbox


func configure(profile: MechanismData, tile: int) -> void:
	_profile = profile
	var size := Vector2(profile.size_tiles) * tile
	_sector = Rect2(Vector2(-size.x * 0.5, -size.y), size)


func _ready() -> void:
	LightKit.mark_emissive(self)
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
	Sfx.play(&"telegraph", -14.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		if _state == State.WARNING and not Settings.get_reduce_ui_motion():
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
		State.LIVE:
			_state = State.RECOVERING
			_time_left = _profile.sweep_rest_seconds
			_set_hazard_live(false)
		State.RECOVERING:
			_warn()
	queue_redraw()


func _draw() -> void:
	if _state == State.WARNING:
		draw_rect(_sector, Color(WARNING_COLOR, 0.85), false, 1.0)
		var progress := 0.5
		if not Settings.get_reduce_ui_motion():
			progress = clampf(1.0 - _time_left / _profile.sweep_warning_seconds, 0.0, 1.0)
		var x := lerpf(_sector.position.x, _sector.end.x, progress)
		draw_line(Vector2(x, _sector.position.y), Vector2(x, _sector.end.y), WARNING_COLOR, 1.5)
	elif _state == State.LIVE:
		draw_rect(_sector, Color(Palette.CYAN, 0.38))
		draw_line(_sector.position, Vector2(_sector.end.x, _sector.position.y), WARNING_COLOR, 2.0)
