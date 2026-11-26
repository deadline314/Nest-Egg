extends CanvasLayer
## Offers a playable memory, then retires the private viewport. Nothing in
## the memory owns the current level, inventory, payment or persistent time.

const Run = preload("res://game/cutscene/local_replay/flood_memory_run.gd")
const Stage = preload("res://game/cutscene/local_replay/flood_memory_stage.gd")

const COPY := {
	"title": ["洪水那一夜", "The Night of the Flood", "洪水の夜"],
	"loading": ["正在讀取記憶片。", "Reading the memory chip.", "記憶片を読み出しています。"],
	"location": ["七年前・港區低街", "Seven years ago · Low Harbor Street", "七年前・港の低地通り"],
	"approach": ["沿店燈的方向走，把凜背回當舖。", "Follow the shop lights and carry Rin back to the pawnshop.", "店の明かりを目印に、凛を背負って質屋へ戻る。"],
	"fork": ["沿低街可以抄近路。外側的樓梯有扶欄。", "Cut through the low street, or follow the rail up the dry stairs.", "低地を通れば近道。外階段は手すりを使って登れる。"],
	"flooded": ["低街已被淹沒。扶住欄杆，從外梯繞過去。", "The low street is flooded. Use the railing to take the outside stairs.", "低地は水に沈んだ。手すりを伝い、外階段を回ろう。"],
	"low_path": ["沿著低街的踏面往前。", "Stay on the low street's walkway.", "低地の足場を伝って進む。"],
	"high_path": ["扶欄走到乾臺，再沿店燈下樓。", "Follow the rail to the dry landing, then go down toward the shop light.", "手すりを伝って乾いた踊り場へ。店の明かりを目印に下りる。"],
	"read_path": ["當舖的椅子在前面。", "The pawnshop chair is up ahead.", "質屋の椅子はこの先だ。"],
	"read": ["把凜放上座椅，確認身分讀取。", "Set Rin on the chair and confirm the identity read.", "凛を椅子に座らせ、身元の読み取りを確認する。"],
	"testimony": ["老 K「妳現在答不了。我來按吧。」", "Old K: “You can't answer now. I'll press it for you.”", "老K「今は答えられないな。俺が押すよ。」"],
	"return": ["{interact} 回到地下室", "{interact} Return to the basement", "{interact} 地下室へ戻る"],
	"walk": ["{move_left}／{move_right} 移動", "{move_left} / {move_right} Move", "{move_left}／{move_right} 移動"],
	"take_low": ["{move_right} 沿低街", "{move_right} Take the low street", "{move_right} 低地を進む"],
	"rail": ["{interact} 扶欄上外梯", "{interact} Take the outside stairs", "{interact} 手すりを使って外階段へ"],
	"read_prompt": ["{interact} 確認讀取", "{interact} Confirm the read", "{interact} 読み取りを確認"],
	"skip": ["{ui_cancel} 略過至證詞", "{ui_cancel} Skip to the testimony", "{ui_cancel} 証言までスキップ"],
	"unavailable": ["記憶片無法播放，可以留在地下室。", "This chip could not play. You can stay in the basement.", "記憶片を再生できませんでした。地下室に戻ります。"],
}
const DIVIDER := "    "

var _lock := 0
var _language := 0
var _run: Run
var _stage: Stage
var _viewport: SubViewport
var _time: Label
var _objective: Label
var _guidance: Label
var _prompt: Label
var _leaving := false
var _testimony := false
var _ready_to_play := false
var _clock_at := -1
var _state := -1
var _formatted: Dictionary[String, String] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = UiLayers.LOCAL_REPLAY
	_lock = GameplayLock.acquire(self)
	_language = {"en": 1, "ja": 2}.get(Story.language, 0)
	_build_screen()
	_refresh_bindings()
	InputBindings.bindings_changed.connect(_refresh_bindings)
	InputBindings.device_changed.connect(func(_pad: bool, _id: int) -> void: _refresh_bindings())
	await get_tree().process_frame
	if _leaving or _testimony:
		return
	_run = Run.new()
	_stage = Stage.new()
	_viewport.add_child(_stage)
	var built := await _stage.build(_run.position)
	if _leaving or _testimony:
		return
	if not built:
		EventBus.toast_requested.emit(_copy("unavailable"))
		_leave()
		return
	_ready_to_play = true
	_refresh_hud()


func _build_screen() -> void:
	var root := UiKit.full_rect_root(self)
	var matte := ColorRect.new()
	matte.color = Color("111b23")
	matte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(matte)
	UiKit.fill_parent(matte)

	var host := SubViewportContainer.new()
	host.stretch = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(host)
	UiKit.fill_parent(host)
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	host.add_child(_viewport)

	var header := VBoxContainer.new()
	root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 17
	header.offset_top = 14
	header.add_child(UiKit.heading(_copy("title"), Color("ffdc9d")))
	header.add_child(UiKit.caption(_copy("location"), Palette.UI_MUTED))
	_time = UiKit.heading("", Color("ffdc9d"))
	header.add_child(_time)

	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var paint := StyleBoxFlat.new()
	paint.bg_color = Color("121923f4")
	paint.border_color = Color("aa875b")
	paint.border_width_top = 1
	paint.content_margin_left = 16
	paint.content_margin_right = 16
	paint.content_margin_top = 9
	paint.content_margin_bottom = 10
	panel.add_theme_stylebox_override(&"panel", paint)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	panel.add_child(rows)
	_objective = UiKit.heading(_copy("loading"), Palette.UI_TEXT)
	_prompt = UiKit.caption("", Color("ffdc9d"))
	_guidance = UiKit.caption("", Palette.UI_MUTED)
	for line: Label in [_objective, _prompt, _guidance]:
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(line)


func _process(delta: float) -> void:
	if _leaving or _testimony or not _ready_to_play:
		return
	var old := _run.position
	_run.tick(Input.get_axis(&"move_left", &"move_right"), delta)
	var walking := old.distance_squared_to(_run.position) > 0.04
	_stage.present(_run.position, _run.facing, _run.segment == Run.Segment.DRY_STAIRS, walking, _run.flooded)
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _testimony:
			_leave.call_deferred()
		else:
			_show_testimony(false)
		return
	if _testimony and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_leave.call_deferred()
		return
	if not _ready_to_play:
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		if _run.phase == Run.Phase.CHOOSE_ROUTE:
			_run.choose_path(true)
		elif _run.phase == Run.Phase.READING:
			_show_testimony(true)
	elif _run.phase == Run.Phase.CHOOSE_ROUTE and event.is_action_pressed(&"move_right"):
		get_viewport().set_input_as_handled()
		_run.choose_path(false)


func _show_testimony(physical: bool) -> void:
	_testimony = true
	if physical:
		_run.show_testimony()
		_stage.read_terminal()
	_time.hide()
	_objective.text = _copy("testimony")
	_prompt.text = _formatted["return"]
	_guidance.text = ""


func _refresh_hud() -> void:
	if _testimony:
		return
	var seconds := ceili(_run.remaining)
	if seconds != _clock_at:
		_clock_at = seconds
		_time.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	var state := int(_run.phase) * 16 + int(_run.segment) * 2 + int(_run.flooded)
	if state == _state:
		return
	_state = state
	_guidance.text = _formatted["walk"] + DIVIDER + _formatted["skip"]
	_prompt.text = ""
	if _run.phase == Run.Phase.CHOOSE_ROUTE:
		_objective.text = _copy("flooded" if _run.flooded else "fork")
		_prompt.text = _formatted["rail"] if _run.flooded else _formatted["take_low"] + DIVIDER + _formatted["rail"]
	elif _run.phase == Run.Phase.READING:
		_objective.text = _copy("read")
		_prompt.text = _formatted["read_prompt"]
	else:
		var route := ["approach", "low_path", "high_path", "read_path"]
		_objective.text = _copy(route[_run.segment])


func _refresh_bindings() -> void:
	for key: String in ["return", "walk", "take_low", "rail", "read_prompt", "skip"]:
		_formatted[key] = InputBindings.format(_copy(key))
	_state = -1
	if _testimony:
		_prompt.text = _formatted["return"]
	elif _run != null and is_instance_valid(_stage):
		_refresh_hud()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	hide()
	GameplayLock.release(_lock)
	_lock = 0
	queue_free()


func _copy(key: String) -> String:
	return COPY[key][_language]
