class_name DeathScreen
extends CanvasLayer
## 失敗畫面：雜訊溶解進入、標題「回溯 #n」、敗北圖鑑卡片像檔案一樣展開。
## 每次死亡都有收穫：新卡片標示 NEW，附一句攻略。

signal retry_requested
signal menu_requested

const NOISE_SHADER := "res://ui/transition/transition.gdshader"
const NOISE_TIME := 0.45
const CARD_OPEN_TIME := 0.28
const CARD_WIDTH := 380.0

var _card: Dictionary = {}
var _can_continue := true


func setup(card: Dictionary, can_continue: bool) -> void:
	_card = card
	_can_continue = can_continue


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.set_cursor_visible(true)
	var root := UiKit.full_rect_root(self)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.03, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(column)

	column.add_child(UiKit.label("回溯 #%d" % GameState.deaths, UiKit.FS_DISPLAY, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("任務失敗", UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var file := _make_file_card()
	column.add_child(file)
	var retry_text := "從檢查點重來" if _can_continue else "重新開始關卡"
	var retry := UiKit.button(retry_text, retry_requested.emit, "立即再挑戰")
	var menu := UiKit.button("回主選單", menu_requested.emit, "可在主選單查看所有敗北圖鑑")
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 8)
	retry.custom_minimum_size = Vector2(170, 0)
	menu.custom_minimum_size = Vector2(140, 0)
	buttons.add_child(retry)
	buttons.add_child(menu)
	column.add_child(buttons)
	retry.grab_focus.call_deferred()

	_play_noise_in(root)
	_open_card(file)


func _make_file_card() -> Control:
	var panel := UiPanel.new("敗北圖鑑 No.%02d" % int(_card.get("number", 0)), Palette.WARNING)
	if bool(_card.get("is_new", false)):
		panel.body.add_child(UiKit.label("NEW　新解鎖", UiKit.FS_BODY, Palette.NEON_YELLOW))
	panel.body.add_child(UiKit.label(str(_card.get("title", "???")), UiKit.FS_TITLE, Palette.UI_TEXT))
	var text := UiKit.label(str(_card.get("text", "")), UiKit.FS_BODY, Palette.UI_MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	panel.body.add_child(text)
	var hint_text := str(_card.get("hint", ""))
	if not hint_text.is_empty():
		panel.body.add_child(UiDivider.new())
		var hint := UiKit.label("攻略　" + hint_text, UiKit.FS_BODY, Palette.CYAN)
		hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		panel.body.add_child(hint)
	if not _can_continue:
		panel.body.add_child(UiKit.label("殘機用盡，將從關卡開頭重新開始。", UiKit.FS_BODY, Palette.DANGER))
	return panel


## 檔案卡展開：以上緣為軸從壓扁展開。
func _open_card(card: Control) -> void:
	card.pivot_offset_ratio = Vector2(0.5, 0.0)
	card.scale = Vector2(1.0, 0.05)
	card.modulate.a = 0.0
	var tween := card.create_tween().set_parallel(true)
	tween.tween_property(card, "scale:y", 1.0, CARD_OPEN_TIME).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.12).set_delay(0.25)


## 進入時的雜訊溶解（減少閃光時改為單純淡入）。
func _play_noise_in(root: Control) -> void:
	if Settings.get_reduce_flashes():
		root.modulate.a = 0.0
		root.create_tween().tween_property(root, "modulate:a", 1.0, NOISE_TIME)
		return
	var shader := load(NOISE_SHADER) as Shader
	if shader == null:
		return
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"kind", int(Transition.Kind.GLITCH))
	material.set_shader_parameter(&"accent", Palette.MAGENTA)
	material.set_shader_parameter(&"seed", randf() * 10.0)
	material.set_shader_parameter(&"aspect", 640.0 / 360.0)
	material.set_shader_parameter(&"progress", 1.0)
	rect.material = material
	root.add_child(rect)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		material.set_shader_parameter(&"progress", v)
		material.set_shader_parameter(&"time_s", Time.get_ticks_msec() * 0.001), 0.75, 0.0, NOISE_TIME)
	tween.tween_callback(rect.queue_free)
