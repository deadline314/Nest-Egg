class_name NpcActor
extends Area2D
## 場景人物：站在關卡裡，玩家靠近會顯示提示，按互動鍵開始對話（遊戲暫停、用對話框演出），說完可以給補給、信用點或收集品。
## 人物不受傷，也不會被敵人當成目標：沒有受擊盒、不在 enemies 群組。原點在腳底。
## 談過幾次與已領的獎勵跟著檢查點存檔（WorldState）：回溯後人物與玩家的信用點、補給一起還原，所以不會多領。

## 互動距離（玩家與人物的水平距離）：提示出現的範圍與按互動鍵有效的範圍用同一個數字，看得到提示就一定能互動。
## 場景裡所有人物所在的群組（地圖氣泡找講者用）。
const GROUP := &"npc_actors"
const INTERACT_RANGE := 48.0
const PLAYER_HALF_WIDTH := 6.0
const REACH := Vector2(2.0 * (INTERACT_RANGE - PLAYER_HALF_WIDTH), 56)
const PROMPT_RADIUS := INTERACT_RANGE
## 沒有骨架外觀（記號、剪影）時的提示文字與泡泡位置；有骨架外觀時依實際頭頂高度排（_fit_to_figure）。
const PROMPT_OFFSET := Vector2(0, -78)
const BUBBLE_POS := Vector2(0, -48)
## 出現條件改變時淡入淡出的秒數。
const PRESENCE_FADE := 0.6
## 泡泡底邊離頭頂、提示文字底邊離泡泡頂的距離。
const BUBBLE_GAP := 4.0
const LABEL_GAP := 4.0
const BUBBLE_SIZE := Vector2(16, 10)
## 其他提示文字要避開的人物範圍的半寬（高度到對話泡泡頂為止）。
const FIGURE_HALF_WIDTH := 12.0
const BUBBLE_BOB := 1.5
const TALK_COOLDOWN := 0.5
const SILHOUETTE_SCALE := 0.6

var data: NpcData
var cell := Vector2i.ZERO
## 這個人物已經談過幾次。
var talk_count := 0
## 已領過獎勵的對話（NpcData.talks 的位置）。
var claimed: Dictionary[int, bool] = {}

var _actor: CutsceneActor
var _prompt: WorldPrompt
var _bubble_pos := BUBBLE_POS
var _player_in_range := false
var _prompt_player: Player
var _talking := false
var _cooldown := 0.0
var _time := 0.0
## 走近反應與聽到聲響的反應（NE-240）；只有有骨架的人物才有。
var awareness: NpcAwareness
var _looking := false
## 依 NpcData 的出現條件目前是否在地圖上。
var _present := true
var _fade: Tween


func configure(p_data: NpcData, p_cell: Vector2i) -> void:
	data = p_data
	cell = p_cell


func _ready() -> void:
	if data == null:
		push_error("[NpcActor] 格 %s 的人物沒有指定 NpcData，已移除。" % [cell])
		queue_free()
		return
	for problem in data.validate():
		push_error("[NpcActor] 格 %s：%s" % [cell, problem])
	if data.talks.is_empty():
		queue_free()
		return
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = REACH
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(0, -REACH.y * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if data.kind == NpcData.Kind.PERSON:
		_build_visual()
		ContactShadow.attach(self, FIGURE_HALF_WIDTH)
	_prompt = WorldPrompt.new()
	_prompt.text = data.prompt_text()
	_prompt.radius = PROMPT_RADIUS
	_prompt.offset = PROMPT_OFFSET
	_prompt.reach_check = _prompt_available
	add_child(_prompt)
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	var light := LightKit.create_point_light(Palette.NEON_YELLOW if data.kind == NpcData.Kind.PERSON else Palette.CYAN, 56.0, 0.35, false)
	light.position = Vector2(0, -24)
	add_child(light)
	add_to_group(WorldState.GROUP)
	add_to_group(GROUP)
	Story.framing.register_target(self)
	if _actor != null and _actor.rig != null:
		_fit_to_figure()
	_present = data.should_spawn()
	_apply_presence(false)
	Story.scene_finished.connect(_on_story_scene_finished)


## 劇情進度改變出現條件時淡入或淡出（例如阿梨收店）；不在地圖上時不能互動、不擋提示。
func _on_story_scene_finished(_scene: StringName) -> void:
	var present := data.should_spawn()
	if present != _present:
		_present = present
		_apply_presence(true)


func is_present() -> bool:
	return _present


func _apply_presence(animate: bool) -> void:
	set_deferred(&"monitoring", _present)
	if not _present:
		_player_in_range = false
		Music.set_safe(self, false)
	if is_instance_valid(_prompt):
		_prompt.enabled = _present
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not animate or not is_inside_tree():
		visible = _present
		modulate.a = 1.0
		return
	visible = true
	modulate.a = 0.0 if _present else 1.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0 if _present else 0.0, PRESENCE_FADE)
	if not _present:
		_fade.tween_callback(hide)


## 等骨架擺好第一個姿勢後量頭頂高度，把泡泡與提示文字排在頭頂上方（站、蹲、靠牆各自對得上，不蓋到臉）。
func _fit_to_figure() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(_actor) or _actor.rig == null or not _actor.rig.has_bone(&"head"):
		return
	var skin := RigLibrary.character(data.rig_id)
	var head_def: Dictionary = (skin.get("textures", {}) as Dictionary).get("head", {})
	if head_def.is_empty():
		push_warning("[NpcActor] %s 的外觀沒有 head 貼圖，提示維持預設位置。" % data.id)
		return
	var above_pivot := RigLibrary.vec2(head_def.get("pivot")).y * float(skin.get("texture_scale", 0.25)) * float(skin.get("scale", 1.0))
	var head_top := -to_local(_actor.rig.bone(&"head").global_position).y + above_pivot
	if head_top <= 0.0:
		return
	_bubble_pos = Vector2(0.0, -(head_top + BUBBLE_GAP) - BUBBLE_SIZE.y * 0.2)
	var bubble_top := _bubble_pos.y - BUBBLE_SIZE.y * 0.8 - BUBBLE_BOB
	_prompt.offset = Vector2(0.0, bubble_top - LABEL_GAP - WorldPrompt.PADDING.y)
	_prompt.position = _prompt.offset


## 人物（含頭上的對話泡泡）在世界座標的範圍：附近其他物件的提示文字會自動避開，不蓋住人物的臉。
func prompt_obstacle_rect() -> Rect2:
	var top := _bubble_pos.y - BUBBLE_SIZE.y * 0.8 - BUBBLE_BOB
	return Rect2(global_position + Vector2(-FIGURE_HALF_WIDTH, top), Vector2(FIGURE_HALF_WIDTH * 2.0, -top))


## 有骨架外觀就用骨架，沒有就用講者的頭像做剪影（兩者都沒有時只畫一個記號）。
func _build_visual() -> void:
	var rig_id := data.rig_id if ResourceLoader.exists(RigLibrary.CHARACTER_PATH % data.rig_id) else ""
	var portrait := str(Story.speaker(data.speaker).get("portrait", ""))
	_actor = CutsceneActor.new()
	add_child(_actor)
	if not _actor.setup(data.id, rig_id, portrait, 1.0 if not rig_id.is_empty() else SILHOUETTE_SCALE, ""):
		_actor.queue_free()
		_actor = null
		return
	_actor.set_pose(data.pose)
	_actor.set_loop(data.loop, data.loop_scale)
	_actor.face(data.facing)
	if not rig_id.is_empty():
		awareness = NpcAwareness.new(_actor, data)
		EventBus.world_noise.connect(_on_world_noise)


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if _actor != null:
		_actor.set_listening(_player_in_range and not _talking and (awareness == null or not awareness.is_cowering()))
	if awareness != null:
		var player := get_tree().get_first_node_in_group(&"player") as Node2D
		if awareness.step(delta, global_position, player.global_position if player != null else Vector2.INF, _talking):
			awareness.react(_reaction_context())
		var look := awareness.look_direction()
		if look != 0 and not _talking:
			_actor.face(look)
		elif _looking and not _player_in_range:
			_actor.face(data.facing)  # 看完聲音來源，轉回原本的方向
		_looking = look != 0
	if _player_in_range and (awareness == null or awareness.look_direction() == 0 or _talking):
		_face_player()
	if _player_in_range:
		if _cooldown <= 0.0 and not _talking and not get_tree().paused and Input.is_action_just_pressed(&"interact") \
				and Story.framing.is_interaction_target(self):
			_talk()
	queue_redraw()


## 挑走近反應用的讀取函式（與挑對話同一套條件來源）。
func _reaction_context() -> Dictionary:
	return {"talks": talk_count, "seen": Story.was_seen, "deaths": GameState.deaths, "flag": GameState.has_flag, "item": StoryItems.owns}


func _on_world_noise(world_position: Vector2, loudness: float) -> void:
	if awareness != null and is_inside_tree():
		awareness.hear(global_position, world_position, loudness, _talking)


func _face_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null and _actor != null and absf(player.global_position.x - global_position.x) > 4.0:
		_actor.face(1 if player.global_position.x > global_position.x else -1)


## 現在要說的是哪一段（沒有可用的回傳 -1）。
func current_talk_index() -> int:
	return data.pick_talk(talk_count, Story.was_seen, GameState.deaths, GameState.has_flag, StoryItems.owns)


func preview_available() -> bool:
	if data == null or data.kind != NpcData.Kind.PERSON or not _present or _talking or _cooldown > 0.0:
		return false
	var index := current_talk_index()
	return index >= 0 and Story.has_scene(data.talks[index].scene) and Story.scene_mode(data.talks[index].scene) == Story.MODE_DIALOGUE


func _prompt_available() -> bool:
	return _present and _player_in_range and not _talking and is_instance_valid(_prompt_player) and not _prompt_player.is_dead() and _prompt_player.state != Player.State.MOUNTED


func interaction_available() -> bool:
	return _present and _player_in_range and not _talking and _cooldown <= 0.0 and current_talk_index() >= 0


## 開始對話：說完記下次數並發放獎勵。可用於測試直接呼叫。
func _talk() -> bool:
	var index := current_talk_index()
	if index < 0:
		return false
	return await _present_talk(index, data.talks[index].scene, data.talks[index].once)


func _present_talk(index: int, scene: StringName, once: bool) -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.is_dead() or player.state == Player.State.MOUNTED:
		return false
	Story.framing.interaction_started(self)
	_talking = true
	_prompt.hide()  # gameplay暫停後WorldPrompt不會再淡出，先同步隱藏避免重複互動提示。
	if _actor != null:
		_actor.set_talking(true)
	var completed := await Story.play_and_wait(scene, once,
		{"framing_source": "person" if data.kind == NpcData.Kind.PERSON else "object", "source_id": state_key(), "talk_index": index})
	_talking = false
	if is_instance_valid(_prompt):
		_prompt.show()
	if _actor != null and is_instance_valid(_actor):
		_actor.set_talking(false)
	if not is_inside_tree() or not completed:
		return false
	talk_count += 1
	_cooldown = TALK_COOLDOWN
	if is_instance_valid(player):
		_give_reward(index, player)
	return true


## 續玩必須經真正人物的結算路徑；來源與目前可用場景不符時不猜測或發獎勵。
func can_resume_presentation(scene: StringName, index := -1) -> bool:
	if index < 0:
		index = current_talk_index()
	return not _talking and index >= 0 and index < data.talks.size() and Story.is_chained_scene(data.talks[index].scene, scene)


func resume_presentation(scene: StringName, index := -1) -> bool:
	if index < 0:
		index = current_talk_index()
	if not can_resume_presentation(scene, index):
		return false
	return await _present_talk(index, scene, false)


## 發放這一段對話的獎勵（每一段只領一次）。補給帶滿時整份先保留，下次再說話時補領。
func _give_reward(index: int, player: Player) -> void:
	var talk := data.talks[index]
	if claimed.has(index) or not talk.has_reward():
		return
	if talk.consumable != null and player.consumables.is_full(talk.consumable):
		EventBus.toast_requested.emit("%s已達上限 %d，先用掉再來" % [talk.consumable.display_name, talk.consumable.max_carry])
		return
	claimed[index] = true
	var parts := PackedStringArray()
	if talk.credits > 0:
		parts.append("信用點 +%d" % Progression.add_credits(talk.credits))
	if talk.consumable != null and player.consumables.add(talk.consumable):
		parts.append(talk.consumable.display_name)
	if talk.story_item != null and StoryItems.acquire(talk.story_item.id, false):
		parts.append(StoryItems.acquire_message(talk.story_item))
	var text := talk.reward_text if not talk.reward_text.is_empty() else "，".join(parts)
	if not text.is_empty():
		EventBus.toast_requested.emit(text)
		Sfx.play(&"pickup", -6.0)


func _on_body_entered(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_prompt_player = Pickup.resolve_player(body)
		_player_in_range = true
		if data.kind != NpcData.Kind.OBJECT:
			Music.set_safe(self, true)  # 場景人物旁是安全區，背景音樂放輕


func _on_body_exited(body: Node2D) -> void:
	if Pickup.resolve_player(body) != null:
		_player_in_range = false
		Music.set_safe(self, false)


func _draw() -> void:
	if data.kind == NpcData.Kind.OBJECT:
		_draw_object_marker()
		return
	# 還沒說過話：頭上有個對話泡泡。沒有任何外觀時畫一個站著的記號。
	if _actor == null:
		draw_rect(Rect2(-6, -34, 12, 34), Color(Palette.UI_PANEL, 0.9))
		draw_rect(Rect2(-6, -34, 12, 34), Palette.CYAN_DIM, false, 1.0)
	if talk_count == 0:
		var bob := sin(_time * 3.0) * BUBBLE_BOB
		var glow := LightKit.glow(Palette.NEON_YELLOW, 1.6)
		var box := Rect2(_bubble_pos + Vector2(-BUBBLE_SIZE.x * 0.5, -BUBBLE_SIZE.y * 0.8 + bob), BUBBLE_SIZE)
		draw_rect(box, Color(Palette.UI_PANEL, 0.9))
		draw_rect(box, glow, false, 1.0)
		for i in 3:
			draw_circle(box.position + Vector2(4.0 + i * 4.0, 5.0), 0.8, glow)


## 可調查物：一個緩緩呼吸的青色菱形記號。
func _draw_object_marker() -> void:
	var glow := LightKit.glow(Palette.CYAN, 1.4 + 0.5 * sin(_time * 3.0))
	var points := PackedVector2Array([Vector2(0, -22), Vector2(5, -17), Vector2(0, -12), Vector2(-5, -17), Vector2(0, -22)])
	draw_polyline(points, glow, 1.0)
	draw_circle(Vector2(0, -17), 1.2, glow)


# ---------------------------------------------------------------------------
# 檢查點存檔（WorldState）
# ---------------------------------------------------------------------------

func state_key() -> String:
	return "npc:%s@%d,%d" % [data.id, cell.x, cell.y]


func capture_state() -> Variant:
	var claimed_list: Array = []
	for index in claimed:
		claimed_list.append(index)
	return {"talks": talk_count, "claimed": claimed_list, "reacted": awareness.capture() if awareness != null else []}


func restore_state(state: Variant) -> void:
	claimed.clear()
	talk_count = 0
	if typeof(state) != TYPE_DICTIONARY:
		return
	talk_count = maxi(0, int((state as Dictionary).get("talks", 0)))
	if awareness != null:
		awareness.restore((state as Dictionary).get("reacted", []))
	var raw: Variant = (state as Dictionary).get("claimed", [])
	if typeof(raw) == TYPE_ARRAY:
		for index: Variant in raw:
			claimed[int(index)] = true
