class_name CinematicEntrance
extends Node2D
## 玩家主動確認的電影入口。接近只提供畫幅與提示，不呼叫 Story.play。

var data: CinematicEntryData
var _prompt: WorldPrompt
var _player: Player
var _playing := false


func configure(entry: CinematicEntryData) -> void:
	data = entry


func _ready() -> void:
	if data == null:
		push_error("[CinematicEntrance] 缺少入口資料。")
		queue_free()
		return
	var errors := data.validate()
	if not errors.is_empty() or not _scene_eligible():
		push_error("[CinematicEntrance] %s/%s 必須引用正式電影場景：%s" % [data.id, data.scene, errors])
		queue_free()
		return
	_prompt = WorldPrompt.new()
	_prompt.text = data.prompt
	_prompt.radius = NpcActor.INTERACT_RANGE
	_prompt.offset = Vector2(0, -42)
	_prompt.reach_check = interaction_available
	add_child(_prompt)
	Story.framing.register_target(self)
	EventBus.player_spawned.connect(_player_spawned)
	_player = get_tree().get_first_node_in_group(&"player") as Player
	queue_redraw()


func _player_spawned(player: Node2D) -> void:
	_player = player as Player


func _scene_eligible() -> bool:
	return Story.has_scene(data.scene) and Story.scene_mode(data.scene) in [Story.MODE_CINEMATIC, Story.MODE_ANIMATED] \
		and Story.uses_cinematic_framing(data.scene)


func preview_available() -> bool:
	return not _playing and _scene_eligible() and (not data.once or not Story.was_seen(data.scene))


func interaction_available() -> bool:
	if get_tree().paused or GameplayLock.is_locked():
		return false
	if not preview_available() or not is_instance_valid(_player) or _player.is_dead() or _player.state == Player.State.MOUNTED:
		return false
	var offset := global_position - _player.global_position
	return absf(offset.x) <= NpcActor.INTERACT_RANGE and absf(offset.y) <= CinematicFraming.VERTICAL_RANGE


func _physics_process(_delta: float) -> void:
	if get_tree().paused or GameplayLock.is_locked():
		return
	if Input.is_action_just_pressed(&"interact") and interaction_available() and Story.framing.is_interaction_target(self):
		Story.framing.interaction_started(self)
		_playing = true
		await Story.play_and_wait(data.scene, data.once, {"framing_source": "entry", "source_id": str(data.id)})
		_playing = false


func _draw() -> void:
	# 入口記號只傳達這裡可開始演出，不冒充人物或告示牌。
	draw_rect(Rect2(-7, -27, 14, 10), Palette.UI_PANEL)
	draw_rect(Rect2(-7, -27, 14, 10), Palette.CYAN, false)
	for i in 3:
		draw_line(Vector2(-6 + i * 5, -31), Vector2(-3 + i * 5, -28), Palette.CYAN, 1.0)
