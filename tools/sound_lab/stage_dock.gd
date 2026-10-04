class_name SoundLabStageDock
extends VBoxContainer
## 實驗室右側的畫面舞台：遊戲真實畫面、目前情境、速度、實際響了哪些聲音、換彈時間軸編輯器。
## 其他分頁用 play_scene() 在這裡執行情境；位置分頁還能用 preview 暫時把某個位置的聲音換成備選素材。

var lab: SoundLab
var stage: SoundStage
var reload_editor: SoundLabReloadEditor
var _scene_label: Label
var _tip_label: Label
var _heard_label: Label
var _speed_slider: HSlider
var _speed_label: Label
var _free_play: CheckBox
var _content: SoundLabRatioSplit


func _init(p_lab: SoundLab) -> void:
	lab = p_lab
	custom_minimum_size = Vector2(400, 0)


func _ready() -> void:
	var head := HBoxContainer.new()
	add_child(head)
	head.add_child(_label("畫面舞台"))
	head.add_child(_button("■ 停止", stop, "停止目前的情境，放開按鍵、停掉聲音"))
	head.add_child(_button("重置場地", reset_arena, "清掉敵人與靶，玩家回到起點、彈藥補滿"))
	_free_play = CheckBox.new()
	_free_play.text = "自己操作"
	_free_play.tooltip_text = "打勾 = 鍵盤與滑鼠直接控制舞台裡的玩家（照遊戲的按鍵）；沒打勾時點實驗室的按鈕不會讓玩家誤開槍"
	_free_play.toggled.connect(func(on: bool) -> void: stage.set_free_play(on))
	head.add_child(_free_play)
	_content = SoundLabRatioSplit.new()
	_content.vertical = true
	_content.setup(lab.layout, "stage_rows", 0.55, "拖動調整畫面和下面換彈時間軸的高度")
	add_child(_content)
	var view := VBoxContainer.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(view)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.custom_minimum_size = Vector2(0, 240)
	aspect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	view.add_child(aspect)
	stage = SoundStage.new()
	stage.scene_started.connect(_on_scene_started)
	stage.scene_finished.connect(_on_scene_finished)
	stage.sound_recorded.connect(func(_id: StringName) -> void: _update_heard())
	aspect.add_child(stage)
	_scene_label = Label.new()
	_scene_label.text = "還沒有執行情境：在「情境清單」或「位置與備選」分頁選一個"
	_scene_label.tooltip_text = "目前（或最近一次）在畫面執行的情境"
	view.add_child(_scene_label)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.tooltip_text = "這個情境做了什麼"
	view.add_child(_tip_label)
	_heard_label = Label.new()
	_heard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heard_label.tooltip_text = "這個情境實際響過的音效（遊戲自己播出的，依第一次出現的順序）"
	view.add_child(_heard_label)
	var speed := HBoxContainer.new()
	view.add_child(speed)
	speed.add_child(_label("速度"))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = SoundStage.MIN_SPEED
	_speed_slider.max_value = 1.0
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(200, 0)
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.tooltip_text = "慢動作（0.1 到 1 倍）：動畫與聲音事件一起放慢，看聲音落在動畫的哪一格；離開實驗室會還原"
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed.add_child(_speed_slider)
	_speed_label = _label("1.00×")
	speed.add_child(_speed_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 200)
	_content.add_child(scroll)
	reload_editor = SoundLabReloadEditor.new(lab)
	reload_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(reload_editor)


## 顯示或隱藏整個舞台欄；隱藏時不繪圖也不接受情境。
func set_shown(on: bool) -> void:
	visible = on
	stage.set_active(on)


func _on_speed_changed(value: float) -> void:
	stage.speed = value
	_speed_label.text = "%.2f×" % stage.speed


## 在畫面執行一個情境（preview：{音效 id: 預聽串流} 暫時取代那些聲音）。回傳是否完整跑完。
func play_scene(scene_id: String, preview: Dictionary = {}) -> bool:
	var scene := stage.scenes.scene(scene_id)
	if not scene.is_empty() and str(scene.get("action", "")) == "reload":
		reload_editor.set_weapon(str((scene.get("params", {}) as Dictionary).get("weapon", reload_editor.weapon_id)))
	return await stage.run_scene(scene_id, preview)


func stop() -> void:
	stage.stop()
	lab.notify("已停止畫面情境")


func reset_arena() -> void:
	stage.stop()
	await stage.arena.build()
	lab.notify("場地已重置")


func _on_scene_started(scene_id: String) -> void:
	var scene := stage.scenes.scene(scene_id)
	_scene_label.text = "執行中：%s" % str(scene.get("name", scene_id))
	_tip_label.text = str(scene.get("tip", ""))
	_update_heard()


func _on_scene_finished(scene_id: String) -> void:
	var scene := stage.scenes.scene(scene_id)
	_scene_label.text = "完成：%s" % str(scene.get("name", scene_id))
	_update_heard()


func _update_heard() -> void:
	var heard := stage.recorded_unique()
	_heard_label.text = "實際響了：%s" % (", ".join(heard) if not heard.is_empty() else "（還沒有）")


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button
