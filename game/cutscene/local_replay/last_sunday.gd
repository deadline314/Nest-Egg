extends CanvasLayer
## Plays a two-location memory without instantiating any live gameplay entities.

const Stage = preload("res://game/cutscene/local_replay/level_memory_stage.gd")
const WARD := "res://data/levels/ch4_nursing_ward.tres"
const SAFETY := "res://data/levels/ch4_factory_safety.tres"
const LEVER := "res://data/environment/scene_props/dock_warehouse/dock_warehouse__bridge_lever.tres"

const COPY := {
	"title": ["最後一個週日", "The Last Sunday", "最後の日曜日"],
	"ward": ["安養病房・鷺", "Care ward · Egret", "療養病棟・鷺"],
	"safety": ["清理線安全臺・鷺", "Sweep line safe platform · Egret", "清掃線の安全台・鷺"],
	"loading": ["正在載入回放。", "Loading the memory.", "回想を読み込んでいます。"],
	"place": ["走到棠床邊，把短箋放進櫃子的上層。", "Walk to Linden’s bedside and leave the note in the upper drawer.", "棠のベッド脇へ行き、短い手紙を棚の上段に入れる。"],
	"place_prompt": ["{interact} 放入短箋", "{interact} Leave the note", "{interact} 手紙を入れる"],
	"egret_ward": ["鷺　下層是妳要給訪客看的紙。我把我的信放上面，只要妳想看再拿。", "Egret  The papers for your visitors are in the lower drawer. I’ll leave my letter in the upper one. Take it when you feel like reading.", "鷺　下の段はお見舞いの人に見せる書類ね。私の手紙は上に入れておく。読みたくなったら出して。"],
	"linden": ["棠　妳把它放我伸得到的地方就好。", "Linden  Just leave it where I can reach it.", "棠　私の手が届くところに置いてくれればいいよ。"],
	"next": ["{interact} 繼續", "{interact} Continue", "{interact} 続ける"],
	"ward_exit": ["沿病房走廊走到盡頭。", "Follow the ward corridor to the far door.", "病棟の廊下を奥の扉まで進む。"],
	"ward_exit_prompt": ["{interact} 從內廊離開", "{interact} Leave by the inner passage", "{interact} 内廊下から出る"],
	"lever": ["走到門栓前，從安全臺打開員工捷徑。", "At the catch, open the staff shortcut from the safe platform.", "安全台の側から留め金を引き、職員用の近道を開ける。"],
	"lever_prompt": ["{interact} 拉開 SC7 門栓", "{interact} Pull the SC7 catch", "{interact} SC7 の留め金を引く"],
	"egret_factory": ["鷺　我先把回去的門開給凜看。", "Egret  I’ll open the way back so Rin can see it.", "鷺　凜に分かるように、帰り道の扉を先に開けておく。"],
	"factory_exit": ["往前穿過員工門，就能回到辦公室。", "Go through the staff door to return to the office.", "職員用の扉を抜けて事務室へ戻る。"],
	"factory_exit_prompt": ["{interact} 穿過員工門", "{interact} Go through the staff door", "{interact} 職員用の扉を通る"],
	"move": ["{move_left}／{move_right} 移動", "{move_left} / {move_right} Move", "{move_left}／{move_right} 移動"],
	"skip": ["{ui_cancel} 略過並返回", "{ui_cancel} Skip and return", "{ui_cancel} スキップして戻る"],
	"unavailable": ["回放讀取失敗，請從側門再試一次。", "The memory could not load. Try the side door again.", "回想を読み込めませんでした。側扉からやり直してください。"],
}

enum Beat { LOADING, PLACE_NOTE, EGRET_WARD, LINDEN, WARD_EXIT, RELEASE_LEVER, EGRET_FACTORY, FACTORY_EXIT }
const WALK_BEATS := [Beat.PLACE_NOTE, Beat.WARD_EXIT, Beat.RELEASE_LEVER, Beat.FACTORY_EXIT]

var _lock := 0
var _language := 0
var _beat := Beat.LOADING
var _stage: Stage
var _viewport: SubViewport
var _goal := Vector2.INF
var _exit := Vector2.INF
var _door: Sprite2D
var _chapter: Label
var _description: Label
var _control: Label
var _action: Label
var _leaving := false
var _formatted: Dictionary[String, String] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = UiLayers.LOCAL_REPLAY
	_lock = GameplayLock.acquire(self)
	_language = {"en": 1, "ja": 2}.get(Story.language, 0)
	_build_display()
	_refresh_bindings()
	InputBindings.bindings_changed.connect(_refresh_bindings)
	InputBindings.device_changed.connect(func(_pad: bool, _id: int) -> void: _refresh_bindings())
	_enter_room(WARD)


func _build_display() -> void:
	var root := UiKit.full_rect_root(self)
	var matte := ColorRect.new()
	matte.color = Color("0b111b")
	matte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(matte)
	UiKit.fill_parent(matte)
	var viewport_host := SubViewportContainer.new()
	viewport_host.stretch = true
	viewport_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(viewport_host)
	UiKit.fill_parent(viewport_host)
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.gui_disable_input = true
	viewport_host.add_child(_viewport)

	var banner := VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_constant_override(&"separation", 3)
	root.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 16
	banner.offset_right = -16
	banner.offset_top = 14
	var title := UiKit.heading(_copy("title"), Color("ffdc9d"))
	title.add_theme_color_override(&"font_outline_color", Color("15111b"))
	title.add_theme_constant_override(&"outline_size", 3)
	banner.add_child(title)
	_chapter = UiKit.caption("", Palette.UI_TEXT)
	_chapter.add_theme_color_override(&"font_outline_color", Color("15111b"))
	_chapter.add_theme_constant_override(&"outline_size", 3)
	banner.add_child(_chapter)
	_chapter.text = _copy("ward")

	var bottom := PanelContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.065, 0.09, 0.96)
	panel.border_color = Color("bd9359")
	panel.border_width_top = 1
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_bottom = 9
	panel.content_margin_top = 9
	bottom.add_theme_stylebox_override(&"panel", panel)
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var prompts := VBoxContainer.new()
	prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompts.add_theme_constant_override(&"separation", 5)
	bottom.add_child(prompts)
	_description = UiKit.heading("", Palette.UI_TEXT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompts.add_child(_description)
	_action = UiKit.caption("", Color("ffdc9d"))
	_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompts.add_child(_action)
	_control = UiKit.caption("", Palette.UI_MUTED)
	_control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompts.add_child(_control)
	_description.text = _copy("loading")


func _process(delta: float) -> void:
	if _leaving:
		return
	var show_movement := _beat in WALK_BEATS
	var formatted := _formatted["move"] if show_movement else _formatted["skip"]
	if _control.text != formatted:
		_control.text = formatted
	if not is_instance_valid(_stage) or _beat == Beat.LOADING:
		return
	_stage.advance_movement(Input.get_axis(&"move_left", &"move_right") if show_movement else 0.0, delta)
	var prompt := ""
	match _beat:
		Beat.PLACE_NOTE:
			if _stage.is_near(_goal):
				prompt = _formatted["place_prompt"]
		Beat.EGRET_WARD, Beat.LINDEN, Beat.EGRET_FACTORY:
			prompt = _formatted["next"]
		Beat.WARD_EXIT:
			if _stage.is_near(_exit):
				prompt = _formatted["ward_exit_prompt"]
		Beat.RELEASE_LEVER:
			if _stage.is_near(_goal):
				prompt = _formatted["lever_prompt"]
		Beat.FACTORY_EXIT:
			if _stage.is_near(_exit):
				prompt = _formatted["factory_exit_prompt"]
	if _action.text != prompt:
		_action.text = prompt
		_action.visible = not prompt.is_empty()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_leave.call_deferred()
	elif event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_interact()


func _interact() -> void:
	match _beat:
		Beat.PLACE_NOTE:
			if _stage.is_near(_goal):
				_stage.gesture(&"open_palm", _goal)
				_stage.set_speaking(true)
				_stage.mark(Vector2.INF)
				_place_note()
				_beat = Beat.EGRET_WARD
				_description.text = _copy("egret_ward")
		Beat.EGRET_WARD:
			_stage.set_speaking(false)
			_beat = Beat.LINDEN
			_description.text = _copy("linden")
		Beat.LINDEN:
			_stage.mark(_exit)
			_beat = Beat.WARD_EXIT
			_description.text = _copy("ward_exit")
		Beat.WARD_EXIT:
			if _stage.is_near(_exit):
				_enter_room(SAFETY)
		Beat.RELEASE_LEVER:
			if _stage.is_near(_goal):
				_stage.gesture(&"point", _goal)
				_stage.mark(Vector2.INF)
				_stage.set_speaking(true)
				Sfx.play(&"switch", -14.0)
				_open_staff_door()
				_beat = Beat.EGRET_FACTORY
				_description.text = _copy("egret_factory")
		Beat.EGRET_FACTORY:
			_stage.set_speaking(false)
			_stage.mark(_exit)
			_beat = Beat.FACTORY_EXIT
			_description.text = _copy("factory_exit")
		Beat.FACTORY_EXIT:
			if _stage.is_near(_exit):
				_leave.call_deferred()


func _enter_room(area: String) -> void:
	_beat = Beat.LOADING
	_description.text = _copy("loading")
	_action.text = ""
	_action.hide()
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_door = null
	# Paint the memory cover before loading either stage. The live area stays frozen.
	await get_tree().process_frame
	if _leaving:
		return
	var data := load(area) as LevelData if ResourceLoader.exists(area, "LevelData") else null
	var ward := area == WARD
	_stage = Stage.new()
	_stage.name = "MemoryWard" if ward else "MemorySafety"
	_viewport.add_child(_stage)
	var positions := await _stage.build(data, &"ch4_cabinet" if ward else &"ch4_safety_catch",
			&"ward_staff" if ward else &"safety_service", 0.0 if ward else 32.0)
	if _leaving:
		return
	if positions.is_empty():
		push_warning("[LastSunday] Invalid memory route: %s" % area)
		EventBus.toast_requested.emit(_copy("unavailable"))
		_leave.call_deferred()
		return
	_goal = positions["from"]
	_stage.mark(_goal)
	_exit = positions["to"]
	_door = _stage.place_fixture(&"door_steel", _exit, Vector2(30.0, 61.0))
	if not ward:
		var lever := ResourceLoader.load(LEVER) as PropData if ResourceLoader.exists(LEVER) else null
		if lever != null:
			_stage.place_scenery(lever, Rect2(_goal - Vector2(lever.size.x * 0.5, lever.size.y), lever.size))
	_chapter.text = _copy("ward" if ward else "safety")
	_description.text = _copy("place" if ward else "lever")
	_beat = Beat.PLACE_NOTE if ward else Beat.RELEASE_LEVER


func _place_note() -> void:
	var cabinet := _stage.scenery_rect(&"nursing_ward__bedside_locker")
	if not cabinet.has_area():
		return
	var note := Polygon2D.new()
	note.name = "PlacedLetter"
	note.position = cabinet.position + Vector2(cabinet.size.x * 0.56, cabinet.size.y * 0.28)
	note.polygon = PackedVector2Array([Vector2(-4, -1), Vector2(3, -2), Vector2(4, 1), Vector2(-3, 2)])
	note.color = Color("e0b985")
	note.z_index = WorldLayers.PROPS + 1
	_stage.add_child(note)


func _open_staff_door() -> void:
	if not is_instance_valid(_door):
		return
	var opening := _door.scale
	opening.x *= 0.25
	if Settings.get_reduce_ui_motion():
		_door.scale = opening
	else:
		create_tween().tween_property(_door, "scale", opening, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	hide()
	GameplayLock.release(_lock)
	_lock = 0
	queue_free()


func _refresh_bindings() -> void:
	for key: String in ["move", "skip", "place_prompt", "next", "ward_exit_prompt", "lever_prompt", "factory_exit_prompt"]:
		_formatted[key] = InputBindings.format(_copy(key))
	_formatted["move"] += "　" + _formatted["skip"]


func _copy(key: String) -> String:
	return COPY[key][_language]
