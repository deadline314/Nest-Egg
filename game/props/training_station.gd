class_name TrainingStation
extends Node2D
## 序章訓練站（見 TrainingData）：判定玩家真的完成一個動作，寫旗標、播劇情。
## 訓練器的出手只對玩家的受擊框送一次低傷害攻擊：擋下算完成；打中就停機、補回生命，不會致死、不計死亡。

const TRAINER_WARN := 0.9
const TRAINER_COOLDOWN := 1.6
const TRAINER_DAMAGE := 1
const TRAINER_KNOCKBACK := Vector2(150, -60)
const POLL_INTERVAL := 0.25
const ACTIVE_COLOR := Color(1.0, 0.62, 0.2)
const IDLE_COLOR := Color(0.45, 0.5, 0.58)
const DONE_COLOR := Color(0.35, 0.85, 0.55)

signal completed(station: TrainingStation)

var data: TrainingData
var _active := false
var _done := false
var _poll := 0.0
var _phase := &"idle"
var _phase_left := 0.0
var _last_side := 0
var _flash := 0.0
var _prompt: WorldPrompt
var _health: HealthComponent
var _hurtbox: Hurtbox


func configure(p_data: TrainingData) -> void:
	data = p_data


func _ready() -> void:
	if data == null:
		push_error("[TrainingStation] %s 沒有 TrainingData，已移除" % position)
		queue_free()
		return
	for problem in data.validate():
		push_error("[TrainingStation] %s" % problem)
	z_index = WorldLayers.ENTITY_BEHIND
	if data.kind in [TrainingData.Kind.TARGET, TrainingData.Kind.DUMMY]:
		_health = HealthComponent.new()
		_health.setup(1_000_000, 0.0)
		add_child(_health)
		_hurtbox = Hurtbox.new()
		add_child(_hurtbox)
		_hurtbox.setup(Combat.Team.ENEMY, _health, data.reach, Vector2(0, -data.reach.y * 0.5))
		_hurtbox.hit_received.connect(_on_hit)
	_prompt = WorldPrompt.new()
	_prompt.text = data.prompt
	_prompt.radius = maxf(96.0, data.reach.x * 2.0)
	_prompt.offset = Vector2(0, -data.height - 14.0)
	add_child(_prompt)
	_refresh()


func is_active() -> bool:
	return _active


func is_done() -> bool:
	return _done


func _refresh() -> void:
	_done = GameState.has_flag(data.done_flag)
	_active = not _done and (data.requires_flag == &"" or GameState.has_flag(data.requires_flag))
	_prompt.enabled = _active
	if _hurtbox != null:
		_hurtbox.enabled = _active
	queue_redraw()


func _physics_process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_INTERVAL
		var was_active := _active
		_refresh()
		if was_active != _active:
			_phase = &"idle"
	_flash = maxf(0.0, _flash - delta)
	if not _active:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.is_dead():
		return
	var offset := player.global_position - global_position
	match data.kind:
		TrainingData.Kind.REACH:
			if absf(offset.x) <= data.reach.x and absf(offset.y) <= data.reach.y:
				_complete()
		TrainingData.Kind.DASH_LINE:
			var side := signi(int(offset.x))
			if absf(offset.y) <= data.reach.y and side != 0 and _last_side != 0 and side != _last_side and player.state == Player.State.DASH:
				_complete()
			if side != 0:
				_last_side = side
		TrainingData.Kind.TRAINER:
			_run_trainer(player, offset, delta)


func _run_trainer(player: Player, offset: Vector2, delta: float) -> void:
	var in_range := absf(offset.x) <= data.reach.x * 1.6 and absf(offset.y) <= data.reach.y
	_phase_left -= delta
	match _phase:
		&"idle":
			if in_range and not GameplayLock.is_locked():
				_phase = &"warn"
				_phase_left = TRAINER_WARN
				Sfx.play(&"switch", -10.0)
				queue_redraw()
		&"warn":
			queue_redraw()
			if _phase_left <= 0.0:
				_strike(player, offset)
				_phase = &"cooldown"
				_phase_left = TRAINER_COOLDOWN
		&"cooldown":
			if _phase_left <= 0.0:
				_phase = &"idle"
				queue_redraw()


## 出手一次：只打前方有效距離內的玩家。擋下＝完成；打中＝停機並把生命補回（訓練不會致死）。
func _strike(player: Player, offset: Vector2) -> void:
	_flash = 0.25
	if absf(offset.x) > data.reach.x or absf(offset.y) > data.reach.y:
		return
	var direction := signf(offset.x) if offset.x != 0.0 else 1.0
	var info := DamageInfo.create(TRAINER_DAMAGE, Combat.Team.ENEMY, &"training_%s" % data.id, Vector2(TRAINER_KNOCKBACK.x * direction, TRAINER_KNOCKBACK.y))
	info.origin = global_position + Vector2(0, -data.height * 0.5)
	var before := player.health.current
	var result := player.hurtbox.receive(info)
	if result == Hurtbox.Result.BLOCKED or result == Hurtbox.Result.REFLECTED:
		_complete()
	elif result == Hurtbox.Result.DAMAGED:
		player.health.heal(maxi(0, before - player.health.current))
		_on_failed()


func _on_failed() -> void:
	if data.fail_flag != &"" and not GameState.has_flag(data.fail_flag):
		GameState.set_flag(data.fail_flag)
		if data.fail_scene != &"":
			Story.play(data.fail_scene)
	elif not data.fail_repeat_text.is_empty():
		EventBus.toast_requested.emit(data.fail_repeat_text)


func _on_hit(info: DamageInfo) -> void:
	_health.heal(_health.max_health)
	if not _active:
		return
	_flash = 0.2
	queue_redraw()
	var wanted_projectile := data.kind == TrainingData.Kind.TARGET
	if info.is_projectile == wanted_projectile:
		_complete()


func _complete() -> void:
	if _done:
		return
	_done = true
	_active = false
	GameState.set_flag(data.done_flag)
	Sfx.play(&"ui_confirm", -8.0)
	_prompt.enabled = false
	if _hurtbox != null:
		_hurtbox.enabled = false
	if data.done_scene != &"":
		Story.play(data.done_scene)
	completed.emit(self)
	queue_redraw()


func _process(_delta: float) -> void:
	if _flash > 0.0:
		queue_redraw()


## 器材外觀：簡潔的剪影，顏色表示狀態（灰＝還沒輪到、橘＝現在練這個、綠＝完成）。
func _draw() -> void:
	if data == null:
		return
	var color := DONE_COLOR if _done else (ACTIVE_COLOR if _active else IDLE_COLOR)
	var outline := Color(0.05, 0.06, 0.09, 0.9)
	var h := data.height
	match data.kind:
		TrainingData.Kind.REACH:
			draw_rect(Rect2(-14, -2, 28, 2), Color(color, 0.7))
		TrainingData.Kind.TARGET:
			draw_rect(Rect2(-1.5, -h * 0.55, 3, h * 0.55), outline)
			var center := Vector2(0, -h * 0.75)
			for i in 3:
				draw_circle(center, 9.0 - i * 3.0, outline if i % 2 == 0 else Color(0.92, 0.9, 0.84))
				draw_circle(center, 8.0 - i * 3.0, color if i % 2 == 0 else Color(0.92, 0.9, 0.84))
		TrainingData.Kind.DUMMY:
			draw_rect(Rect2(-7, -h, 14, h), outline)
			draw_rect(Rect2(-6, -h + 1, 12, h - 2), Color(0.32, 0.3, 0.3))
			draw_rect(Rect2(-6, -h * 0.7, 12, 4), color)
			draw_circle(Vector2(0, -h - 5), 6.0, Color(0.32, 0.3, 0.3))
		TrainingData.Kind.TRAINER:
			draw_rect(Rect2(-6, -h, 12, h), outline)
			draw_rect(Rect2(-5, -h + 1, 10, h - 2), Color(0.25, 0.28, 0.33))
			var warn := _phase == &"warn"
			var lamp := Color(1.0, 0.45, 0.1) if warn else Color(color, 0.8)
			draw_circle(Vector2(0, -h - 4), 4.0, lamp)
			var arm := -1.0 if warn else 0.0
			draw_line(Vector2(0, -h * 0.6), Vector2(-26.0 - arm * 6.0, -h * 0.6 + arm * 10.0), outline, 4.0)
			draw_line(Vector2(0, -h * 0.6), Vector2(26.0 + arm * 6.0, -h * 0.6 + arm * 10.0), outline, 4.0)
			if _flash > 0.0:
				draw_circle(Vector2(0, -h * 0.6), 18.0 * (_flash / 0.25), Color(1.0, 0.7, 0.3, 0.35))
		TrainingData.Kind.DASH_LINE:
			draw_rect(Rect2(-1, -data.reach.y, 2, data.reach.y), Color(color, 0.85))
			draw_circle(Vector2(0, -data.reach.y - 3), 3.0, color)
	if _flash > 0.0 and data.kind in [TrainingData.Kind.TARGET, TrainingData.Kind.DUMMY]:
		draw_circle(Vector2(0, -h * 0.7), 12.0 * (_flash / 0.2), Color(1.0, 0.85, 0.5, 0.45))
