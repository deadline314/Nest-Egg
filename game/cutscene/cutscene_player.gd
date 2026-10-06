class_name CutscenePlayer
extends CanvasLayer
## 過場動畫播放器：依資料檔的步驟（scene、camera、actor、move、say、fx、title…）逐步演出。
## 演出時暫停遊戲，結束後還原暫停狀態與滑鼠模式。Esc 跳過整段；確認鍵／射擊／點擊推進台詞。
## 任何壞掉的步驟只記錄「場景 id 第 n 步」的錯誤並略過，不會卡住遊戲。
##
## 步驟一覽見 CutsceneChecker.STEP_FIELDS；資料格式說明在 design/10-presentation/DESIGN.md。

signal finished(scene_id: StringName)

const LAYER := UiLayers.CUTSCENE
const SCREEN := Vector2(640, 360)
const CENTER := Vector2(320, 180)
const BAR_HEIGHT := 34.0
const NOISE_SHADER := "res://ui/transition/transition.gdshader"
const TITLE_FADE := 0.5
## 效果層（色調、閃光、雜訊、淡入淡出、黑邊、字幕、對話）的 z_index 起點，需高於任何角色零件。
const EFFECT_Z := 200

var scene_id: StringName = &""
## 播放速度倍率（測試用；1 = 正常）。
var speed := 1.0
## 本段跳過（Esc 或設定要求）。
var skipping := false
## 玩家主動按了略過（與 end 步驟或播完不同；接續的場景據此一併略過）。
var user_skipped := false
var steps_run := 0

var cam_pos: Vector2 = CENTER:
	set(value):
		cam_pos = value
		_apply_camera()
var cam_zoom: float = 1.0:
	set(value):
		cam_zoom = maxf(0.1, value)
		_apply_camera()

var _steps: Array = []
var _handlers: Dictionary[String, Callable] = {}
var _stage: StageLibrary.Stage
var _stage_holder: Node2D
var _actors: Dictionary[StringName, CutsceneActor] = {}
var _root: Control
var _dialogue: CutsceneDialogue
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _fade: ColorRect
var _tint: ColorRect
var _flash: ColorRect
var _noise: ColorRect
var _center_text: Label
var _center_sub: Label
var _skip_hint: Label
var _advance_requested := false
var _shake := 0.0
var _shake_time := 0.0
var _running := false
var _lock_token := 0
var _tweens: Array[Tween] = []
## 疊加模式：不蓋黑底、不放舞台，直接在遊戲畫面上演出（右臂雜訊、警報等短演出）。
var _overlay_mode := false
## 目前執行的步驟位置（錯誤訊息用）與下一步是否也是台詞（決定要不要收起對話框）。
var _current_where := ""
var _next_is_say := false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_handlers = {
		"scene": _do_scene, "letterbox": _do_letterbox, "camera": _do_camera, "actor": _do_actor,
		"pose": _do_pose, "move": _do_move, "face": _do_face, "remove": _do_remove, "say": _do_say,
		"narrate": _do_narrate, "title": _do_title, "fx": _do_fx, "sfx": _do_sfx, "wait": _do_wait,
		"fade": _do_fade, "transition": _do_transition, "end": _do_end,
	}


func is_running() -> bool:
	return _running


## 開始播放。scene 是場景資料（含 steps）。
func play(id: StringName, scene: Dictionary) -> void:
	if _running or not is_inside_tree():
		push_warning("[Cutscene] 播放器已在播放或不在場景樹中：%s" % id)
		return
	scene_id = id
	var raw: Variant = scene.get("steps", [])
	_steps = raw if typeof(raw) == TYPE_ARRAY else []
	_overlay_mode = bool(scene.get("overlay", false))
	_build_ui()
	_lock_token = GameplayLock.acquire(self, Input.MOUSE_MODE_HIDDEN)
	Fx.reset_time()
	_running = true
	_run.call_deferred()


## 跳到結尾。
func skip() -> void:
	user_skipped = true
	skipping = true
	_advance_requested = true


func _run() -> void:
	if not _running or not is_inside_tree():
		return
	var index := 0
	for raw: Variant in _steps:
		index += 1
		if skipping:
			break
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("[Cutscene] 場景 %s 第 %d 步不是物件，已略過" % [scene_id, index])
			continue
		var step: Dictionary = raw
		var kind := str(step.get("do", ""))
		if kind == "end":
			break
		var handler: Callable = _handlers.get(kind, Callable())
		if not handler.is_valid():
			push_error("[Cutscene] 場景 %s 第 %d 步的動作「%s」不存在，已略過" % [scene_id, index, kind])
			continue
		_current_where = "場景 %s 第 %d 步（%s）" % [scene_id, index, kind]
		_next_is_say = index < _steps.size() and typeof(_steps[index]) == TYPE_DICTIONARY \
				and str((_steps[index] as Dictionary).get("do", "")) == "say"
		await handler.call(step)
		steps_run += 1
	await _finish()



func _finish() -> void:
	if not _running:
		return
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_running = false
	_root.visible = false
	Transition.abort_owned(self)
	GameplayLock.release(_lock_token)
	_lock_token = 0
	finished.emit(scene_id)
	queue_free()


func _exit_tree() -> void:
	_running = false
	skipping = true
	Transition.abort_owned(self)
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()


# ---------------------------------------------------------------------------
# 輸入
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _running:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"shoot") or event.is_action_pressed(&"jump") \
			or (event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		if _dialogue.visible and not _dialogue.is_complete():
			_dialogue.complete()
		else:
			_advance_requested = true
		get_viewport().set_input_as_handled()
	else:
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 介面
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.0 if _overlay_mode else 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.z_index = WorldLayers.STAGE_BACK - 100  # 舞台背景各層在 STAGE_BACK，黑底要再低一點才不會蓋住它們
	_root.add_child(backdrop)
	_stage_holder = Node2D.new()
	_root.add_child(_stage_holder)
	# 疊在舞台上的效果層（由下到上）：色調、閃光、雜訊、黑邊、淡入淡出、對話。
	_tint = _overlay(Color(0, 0, 0, 0))
	_flash = _overlay(Color(1, 1, 1, 0))
	_noise = _make_noise_rect()
	_fade = _overlay(Color(0, 0, 0, 0.0 if _overlay_mode else 1.0))
	_top_bar = _bar(true)
	_bottom_bar = _bar(false)
	_center_text = UiKit.label("", UiKit.FS_DISPLAY, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_center_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_text.offset_top = -12
	_center_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_center_text.modulate.a = 0.0
	_root.add_child(_center_text)
	_center_sub = UiKit.label("", UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_center_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_sub.offset_top = 36
	_center_sub.modulate.a = 0.0
	_root.add_child(_center_sub)
	_dialogue = CutsceneDialogue.new()
	_root.add_child(_dialogue)
	_skip_hint = UiKit.label(InputBindings.format("Esc 跳過"), UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.offset_left = -110
	_skip_hint.offset_right = -10
	_skip_hint.offset_top = 6
	_root.add_child(_skip_hint)
	# 角色骨架的零件有自己的 z_index，會畫在同層的淡入淡出、黑邊與對話之上；效果層一律拉高。
	var z := EFFECT_Z
	for child in _root.get_children():
		if child != _stage_holder and child != _root.get_child(0):
			(child as CanvasItem).z_index = z
			z += 1


func _overlay(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


func _bar(top: bool) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	rect.offset_top = 0.0 if top else 0.0
	rect.offset_bottom = 0.0
	_root.add_child(rect)
	return rect


func _make_noise_rect() -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	var shader := load(NOISE_SHADER) as Shader
	if shader != null:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter(&"kind", int(Transition.Kind.GLITCH))
		material.set_shader_parameter(&"accent", Palette.MAGENTA)
		material.set_shader_parameter(&"aspect", SCREEN.x / SCREEN.y)
		rect.material = material
	_root.add_child(rect)
	return rect


func _apply_camera() -> void:
	if _stage_holder == null:
		return
	_stage_holder.scale = Vector2.ONE * cam_zoom
	_stage_holder.position = CENTER - cam_pos * cam_zoom + _shake_offset()
	if _stage != null:
		_stage.apply_parallax(cam_pos)


func _shake_offset() -> Vector2:
	if _shake <= 0.01:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


func _process(delta: float) -> void:
	if not _running:
		return
	if _shake_time > 0.0:
		_shake_time -= delta
		if _shake_time <= 0.0:
			_shake = 0.0
		_apply_camera()


func _new_tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(speed)
	_tweens.append(tween)
	return tween


## 等待秒數；被跳過時立刻返回。
func _wait_time(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not skipping and _running:
		await get_tree().process_frame
		left -= get_process_delta_time() * speed


func _wait_tween(tween: Tween) -> void:
	while tween.is_valid() and tween.is_running() and not skipping and _running:
		await get_tree().process_frame


func _need_actor(step: Dictionary) -> CutsceneActor:
	var id := StringName(str(step.get("id", "")))
	var actor: CutsceneActor = _actors.get(id)
	if actor == null:
		push_error("[Cutscene] %s：找不到角色「%s」，已略過" % [_current_where, id])
	return actor


static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	return StageLayers.vec2_of(value, fallback)


# ---------------------------------------------------------------------------
# 步驟
# ---------------------------------------------------------------------------

func _do_scene(step: Dictionary) -> void:
	var id := StringName(str(step.get("id", "")))
	if not StageLibrary.exists(id):
		push_error("[Cutscene] %s：場景「%s」不存在，保留原本的場景" % [_current_where, id])
		return
	if _stage != null:
		_stage.queue_free()
		_actors.clear()
	_stage = StageLibrary.build(id)
	_stage_holder.add_child(_stage)
	cam_pos = _vec(step.get("pos"), _stage.default_camera_pos)
	cam_zoom = float(step.get("zoom", _stage.default_camera_zoom))
	_apply_camera()
	# 第一個場景從黑幕淡入（演出開始時畫面是黑的）。
	var fade_in := float(step.get("fade", 0.5 if _fade.color.a > 0.5 else 0.0))
	if fade_in > 0.0:
		await _do_fade({"to": 0.0, "time": fade_in})


func _do_letterbox(step: Dictionary) -> void:
	var height := BAR_HEIGHT if bool(step.get("on", true)) else 0.0
	var time := float(step.get("time", 0.4))
	var tween := _new_tween().set_parallel(true)
	tween.tween_property(_top_bar, "offset_bottom", height, time)
	tween.tween_property(_bottom_bar, "offset_top", -height, time)
	if bool(step.get("wait", false)):
		await _wait_tween(tween)


func _do_camera(step: Dictionary) -> void:
	var time := float(step.get("time", 0.0))
	var target_pos := _vec(step.get("pos"), cam_pos)
	var target_zoom := float(step.get("zoom", cam_zoom))
	if time <= 0.0:
		cam_pos = target_pos
		cam_zoom = target_zoom
		return
	var tween := _new_tween().set_parallel(true)
	var ease_type := Tween.EASE_IN_OUT
	tween.tween_property(self, "cam_pos", target_pos, time).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	tween.tween_property(self, "cam_zoom", target_zoom, time).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	if bool(step.get("wait", false)):
		await _wait_tween(tween)


func _do_actor(step: Dictionary) -> void:
	var id := StringName(str(step.get("id", "")))
	var actor := CutsceneActor.new()
	var ok := actor.setup(id, str(step.get("kind", "")), str(step.get("portrait", "")),
			float(step.get("scale", 1.0)), str(step.get("weapon", "")))
	if not ok:
		push_error("[Cutscene] %s：角色「%s」沒有可用的外觀或頭像，已略過" % [_current_where, id])
		actor.free()
		return
	actor.position = _vec(step.get("pos"), CENTER)
	actor.face(int(step.get("facing", 1)))
	actor.set_pose(StringName(str(step.get("pose", "idle"))))
	actor.set_loop(StringName(str(step.get("loop", ""))), float(step.get("loop_scale", 1.0)))
	actor.speaker_id = StringName(str(step.get("speaker", id)))
	actor.ground_y = float(step["ground"]) if step.has("ground") else (_stage.floor_y if _stage != null else NAN)
	var slot := _actor_slot(id, step)
	actor.layer_slot = slot
	actor.z_index = WorldLayers.stage_actor_z(slot)
	if _actors.has(id):
		_actors[id].queue_free()
	_actors[id] = actor
	_stage.actors.add_child(actor)


## 演員用的圖層組：每個演員佔自己的一組，兩個人重疊（走過、並肩）時零件不會互相穿插。
## step 的 layer 指定第幾組（數字大的在前面）；沒指定時重新登場的演員沿用原本的組，新演員接在最後（後登場的在前面）。
func _actor_slot(id: StringName, step: Dictionary) -> int:
	var slot := int(step.get("layer", -1))
	if slot < 0:
		var existing := _actors.get(id) as CutsceneActor
		slot = existing.layer_slot if existing != null else _actors.size()
	if slot >= WorldLayers.MAX_STAGE_ACTORS:
		push_warning("[Cutscene] %s：演員「%s」超過 %d 組圖層，與最後一組共用。" % [_current_where, id, WorldLayers.MAX_STAGE_ACTORS])
	return slot


func _do_pose(step: Dictionary) -> void:
	var actor := _need_actor(step)
	if actor != null:
		actor.set_pose(StringName(str(step.get("pose", "idle"))))
		if step.has("loop"):
			actor.set_loop(StringName(str(step.get("loop", ""))), float(step.get("loop_scale", 1.0)))


## 說話中的演員（id 與講者相同）點頭比手勢，其他人安靜聆聽。傳空字串＝大家都不說話。
func _set_talkers(speaker_id: StringName) -> void:
	for id: StringName in _actors.keys():
		var actor := _actors[id] as CutsceneActor
		if is_instance_valid(actor):
			var talks := speaker_id != &"" and (actor.speaker_id == speaker_id or id == speaker_id)
			actor.set_talking(talks)
			actor.set_listening(speaker_id != &"" and not talks)


func _do_face(step: Dictionary) -> void:
	var actor := _need_actor(step)
	if actor != null:
		actor.face(int(step.get("dir", 1)))


func _do_remove(step: Dictionary) -> void:
	var actor := _need_actor(step)
	if actor != null:
		_actors.erase(actor.actor_id)
		actor.queue_free()


func _do_move(step: Dictionary) -> void:
	var actor := _need_actor(step)
	if actor == null:
		return
	var target := _vec(step.get("to"), actor.position)
	var time := maxf(0.01, float(step.get("time", 1.0)))
	if absf(target.x - actor.position.x) > 0.5:
		actor.face(1 if target.x > actor.position.x else -1)
	actor.set_pose(StringName(str(step.get("pose", "walk"))))
	var tween := _new_tween()
	tween.tween_property(actor, "position", target, time)
	var then_pose := StringName(str(step.get("then", "idle")))
	tween.tween_callback(func() -> void:
		if is_instance_valid(actor):
			actor.set_pose(then_pose))
	if bool(step.get("wait", true)):
		await _wait_tween(tween)


func _do_say(step: Dictionary) -> void:
	var speaker := Story.speaker(str(step.get("speaker", "")))
	_set_talkers(StringName(str(step.get("speaker", ""))))
	_advance_requested = false
	_dialogue.show_line(speaker, str(step.get("text", "")), str(step.get("style", "normal")))
	var auto := float(step.get("auto", 0.0))
	var waited := 0.0
	while not skipping and _running:
		await get_tree().process_frame
		if _dialogue.is_complete():
			waited += get_process_delta_time() * speed
			if _advance_requested or (auto > 0.0 and waited >= auto):
				break
		else:
			_advance_requested = false
	_advance_requested = false
	if not _next_is_say:
		_dialogue.hide_box()
		_set_talkers(&"")


func _do_narrate(step: Dictionary) -> void:
	var lines: Array = step.get("lines", [])
	var hold := float(step.get("time", 2.2))
	var text := "\n".join(PackedStringArray(lines.map(func(l: Variant) -> String: return str(l))))
	_center_text.add_theme_font_size_override(&"font_size", UiKit.FS_BODY)
	_center_text.add_theme_color_override(&"font_color", StageLayers.color_of(step.get("color", "#9fd6e4")))
	_center_text.text = text
	_center_text.visible_ratio = 0.0
	_center_text.modulate.a = 1.0
	var type_time := maxf(0.4, float(text.length()) * 0.05)
	var tween := _new_tween()
	tween.tween_property(_center_text, "visible_ratio", 1.0, type_time)
	await _wait_tween(tween)
	await _wait_time(hold)
	var out := _new_tween()
	out.tween_property(_center_text, "modulate:a", 0.0, 0.4)
	await _wait_tween(out)


func _do_title(step: Dictionary) -> void:
	var hold := float(step.get("time", 2.5))
	var color := StageLayers.color_of(step.get("color", "#ff2e88"))
	_center_text.add_theme_font_size_override(&"font_size", UiKit.FS_TITLE if bool(step.get("small", false)) else UiKit.FS_DISPLAY)
	_center_text.add_theme_color_override(&"font_color", LightKit.glow(color, 1.4))
	_center_text.text = str(step.get("text", ""))
	_center_text.visible_ratio = 1.0
	_center_sub.text = str(step.get("sub", ""))
	var tween_in := _new_tween().set_parallel(true)
	tween_in.tween_property(_center_text, "modulate:a", 1.0, TITLE_FADE)
	tween_in.tween_property(_center_sub, "modulate:a", 1.0, TITLE_FADE)
	await _wait_tween(tween_in)
	await _wait_time(hold)
	var tween_out := _new_tween().set_parallel(true)
	tween_out.tween_property(_center_text, "modulate:a", 0.0, TITLE_FADE)
	tween_out.tween_property(_center_sub, "modulate:a", 0.0, TITLE_FADE)
	await _wait_tween(tween_out)


func _do_fx(step: Dictionary) -> void:
	var time := float(step.get("time", 0.5))
	var reduced := Settings.get_reduce_flashes()
	match str(step.get("kind", "")):
		"shake":
			_shake = float(step.get("strength", 4.0))
			_shake_time = time
		"flash":
			_pulse(_flash, StageLayers.color_of(step.get("color", "#ffffff")), 0.35 if reduced else 1.0, time)
		"lightning":
			_pulse(_flash, Color("cfe0ff"), 0.3 if reduced else 0.9, maxf(time, 0.25))
			Sfx.play(&"thunder", -6.0, 0.0)
		"noise":
			_pulse_noise(time, reduced)
		"tint":
			var color := StageLayers.color_of(step.get("color", "#ff0033"))
			var target := Color(color, float(step.get("alpha", 0.25)))
			var tween := _new_tween()
			tween.tween_property(_tint, "color", target, time)
		"rain":
			var on := bool(step.get("on", true))
			for group: Node2D in [_stage.back, _stage.front]:
				for layer in group.get_children():
					if str(layer.get_meta(&"kind", "")) == "rain":
						layer.visible = on
		"vignette":
			pass
	if bool(step.get("wait", false)):
		await _wait_time(time)


## 閃光：瞬間升到 amount 再淡出。
func _pulse(rect: ColorRect, color: Color, amount: float, time: float) -> void:
	rect.color = Color(color, amount)
	var tween := _new_tween()
	tween.tween_property(rect, "color:a", 0.0, time).set_ease(Tween.EASE_OUT)


func _pulse_noise(time: float, reduced: bool) -> void:
	if reduced or _noise.material == null:
		_pulse(_flash, Color.WHITE, 0.2, time)
		return
	var material := _noise.material as ShaderMaterial
	_noise.visible = true
	material.set_shader_parameter(&"seed", randf() * 10.0)
	var tween := _new_tween()
	tween.tween_method(func(v: float) -> void:
		material.set_shader_parameter(&"progress", v)
		material.set_shader_parameter(&"time_s", Time.get_ticks_msec() * 0.001), 0.6, 0.0, time)
	tween.tween_callback(_noise.hide)


func _do_sfx(step: Dictionary) -> void:
	Sfx.play(StringName(str(step.get("id", ""))), float(step.get("volume", -4.0)), float(step.get("jitter", 0.0)))


func _do_wait(step: Dictionary) -> void:
	await _wait_time(float(step.get("time", 0.5)))


func _do_fade(step: Dictionary) -> void:
	var color := StageLayers.color_of(step.get("color", "#000000"))
	var target := float(step.get("to", 0.0))
	var time := float(step.get("time", 0.6))
	_fade.color = Color(color, _fade.color.a)
	var tween := _new_tween()
	tween.tween_property(_fade, "color:a", target, time)
	if bool(step.get("wait", true)):
		await _wait_tween(tween)


func _do_transition(step: Dictionary) -> void:
	var kind: int = Transition.kind_from_name(str(step.get("kind", "fade")))
	if kind < 0:
		push_error("[Cutscene] %s：轉場「%s」不存在，已略過" % [_current_where, step.get("kind", "")])
		return
	var time := float(step.get("time", -1.0))
	if str(step.get("mode", "cover")) == "reveal":
		await Transition.reveal(kind, time)
	else:
		await Transition.cover(kind, time, Vector2(0.5, 0.5), "", self)


func _do_end(_step: Dictionary) -> void:
	skipping = true
