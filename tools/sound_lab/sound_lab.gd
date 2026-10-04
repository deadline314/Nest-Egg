class_name SoundLab
extends Node
## 音效實驗室（NE-162）：試聽、挑選遊戲裡每個位置的聲音，並和位置清單文件（design/16-audio/PLACEMENTS.md）雙向連動。
## 開啟：godot --path . res://tools/sound_lab/sound_lab.tscn（只能從命令列，主選單與遊戲流程都不會進來；匯出時排除 tools/）。
## 右側是遊戲真實畫面的舞台（情境、備選素材試聽、換彈時間軸）。
## 分頁：位置與備選（挑聲音、跨類別搜尋、預計使用、手動放入）、情境清單（所有畫面情境）、即時試玩（用遊戲裡真正的角色、武器、材質、地面查表播放）、
## 背景音樂與環境音（cue、狀態、迴圈接縫、交叉淡化）、混音與診斷（匯流排音量、音量表、發聲數、缺檔）。
## 預聽檔要先產生：python tools/audio/build_candidates.py（沒有時會提示，不會崩潰）。

const SYNC_INTERVAL := 1.0
const FONT_SIZE := 15
## Freesound 預聽 mp3 的檔名是「聲音編號_使用者編號-hq.mp3」。
var FREESOUND_FILE := RegEx.create_from_string("^\\d+_\\d+-[hl]q\\.mp3$")
## 左邊工作區佔整個視窗寬度的預設比例。
const MAIN_SPLIT_DEFAULT := 0.55
## 分隔線的粗細：夠寬才看得出、抓得到。
const SPLIT_SEPARATION := 12

var catalog := AudioCatalog.new()
var doc := PlacementDoc.new()
var audition := AuditionPlayer.new()
## 位置清單文件的路徑（測試時指到複本，不動真正的文件）。
var doc_path := PlacementDoc.PATH
## 各分隔比例的存檔路徑（測試時指到暫存檔，不動使用者的設定）。
var layout_path := SoundLabLayout.DEFAULT_PATH
var layout: SoundLabLayout
## 要不要建立右側的畫面舞台（測試其他分頁時關掉，省去建關卡的時間）。
var stage_enabled := true
var dock: SoundLabStageDock
var slots_tab: SoundLabSlotsTab
var scenes_tab: SoundLabScenesTab
var live_tab: SoundLabLiveTab
var music_tab: SoundLabMusicTab
var mixer_tab: SoundLabMixerTab
## 擷取片段介面（NE-180）；沒開著時是 null。擷取工具的呼叫包裝，測試時換成假的。
var clip_editor: SoundLabClipEditor
var clip_runner := ClipToolRunner.new()
## 「套用到遊戲」面板（NE-186）；沒開著時是 null。套用工具的呼叫包裝，測試時換成假的。
var apply_panel: SoundLabApplyPanel
var apply_runner := ApplyToolRunner.new()
var tabs: TabContainer
var status_label: Label
var _sync_left := SYNC_INTERVAL
var _theme: Theme
var _scale_mode_before := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var _changed_scale_mode := false


func _ready() -> void:
	# 舞台裡的暫停選單、過場會暫停整棵樹；實驗室的介面與舞台要照常動。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 單獨開啟時用視窗的實際解析度（遊戲本身是 640×360 放大），文字才讀得清楚；測試裡不動共用的視窗。
	if get_tree().current_scene == self:
		_scale_mode_before = get_window().content_scale_mode
		_changed_scale_mode = true
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	layout = SoundLabLayout.new(layout_path)
	catalog.load_all()
	doc.load_doc(doc_path)
	audition.setup(catalog)
	add_child(audition)
	_theme = _build_theme()
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := PanelContainer.new()
	root.theme = _theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var split := SoundLabRatioSplit.new()
	split.setup(layout, "lab_stage_column", MAIN_SPLIT_DEFAULT, "拖動調整左邊工作區和右邊畫面舞台的寬度")
	root.add_child(split)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(560, 0)
	split.add_child(box)
	if stage_enabled:
		dock = SoundLabStageDock.new(self)
		dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(dock)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	slots_tab = SoundLabSlotsTab.new(self)
	scenes_tab = SoundLabScenesTab.new(self)
	live_tab = SoundLabLiveTab.new(self)
	music_tab = SoundLabMusicTab.new(self)
	mixer_tab = SoundLabMixerTab.new(self)
	for entry: Array in [["位置與備選", slots_tab], ["情境清單", scenes_tab], ["即時試玩", live_tab], ["背景音樂與環境音", music_tab], ["混音與診斷", mixer_tab]]:
		(entry[1] as Control).name = entry[0]
		tabs.add_child(entry[1])
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	status_label = Label.new()
	status_label.tooltip_text = "最近一次操作的結果，以及位置清單文件的同步狀態"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	bottom.add_child(status_label)
	var apply_button := Button.new()
	apply_button.text = "⬇ 套用到遊戲…"
	apply_button.tooltip_text = "把位置清單裡你挑的「預計使用」換進遊戲：先列出會改哪些位置，勾選並確認後才套用"
	apply_button.pressed.connect(func() -> void: open_apply_panel())
	bottom.add_child(apply_button)
	if dock != null:
		var show_stage := CheckBox.new()
		show_stage.text = "畫面舞台"
		show_stage.button_pressed = true
		show_stage.tooltip_text = "顯示或隱藏右側的遊戲畫面舞台；隱藏時舞台不繪圖，分頁可以用滿整個視窗"
		show_stage.toggled.connect(func(on: bool) -> void: dock.set_shown(on))
		bottom.add_child(show_stage)
	if not catalog.is_loaded():
		notify("找不到素材目錄或位置登記：請先執行 python tools/audio/build_catalog.py 與 build_slots.py")
	else:
		notify("已載入 %d 個素材、%d 個位置；位置清單文件：%s（F5 開發工具選單）" % [catalog.assets.size(), catalog.slots.size(), doc.path])


## 從 F5 開發工具選單離開實驗室時，把視窗縮放還原給遊戲。
func _exit_tree() -> void:
	layout.flush()
	if _changed_scale_mode:
		get_window().content_scale_mode = _scale_mode_before


func _process(delta: float) -> void:
	_sync_left -= delta
	if _sync_left > 0.0:
		return
	_sync_left = SYNC_INTERVAL
	layout.flush()
	sync_now()


## 位置清單文件被外部改過就重新載入並刷新畫面；回傳是否重新載入。
func sync_now() -> bool:
	if not doc.reload_if_changed():
		return false
	slots_tab.refresh()
	notify("位置清單文件被外部修改，已重新載入")
	return true


## 右側的畫面舞台；沒開啟時回傳 null。
func stage() -> SoundStage:
	return dock.stage if dock != null else null


func notify(text: String) -> void:
	if status_label != null:
		status_label.text = text


## 清單裡一個素材的一行說明：編號、時長、素材包／檔名。
func asset_line(asset_id: String) -> String:
	var a := catalog.asset(asset_id)
	if a.has("parent"):
		return "%s  %5.1fs  ✂ 擷取自 %s %.2f–%.2f" % [asset_id, float(a.get("dur", 0.0)), a["parent"], float(a.get("start", 0.0)), float(a.get("end", 0.0))]
	var file := str(a.get("file", "")).get_file()
	if FREESOUND_FILE.search(file) != null and not str(a.get("desc", "")).is_empty():
		file = str(a["desc"]).left(60)  # Freesound 的檔名只是編號，看不出是什麼；改顯示聲音的標題與作者
	return "%s  %5.1fs  %s／%s" % [asset_id, float(a.get("dur", 0.0)), str(a.get("pack", "")).trim_prefix("oga_").trim_prefix("kenney_"), file]


## 並排比較用的一行說明：編號與時長、（擷取片段標來源與起訖）、說明（槍種等）、檔名，素材包放最後（被截斷也無妨，完整內容在 tooltip）。
func asset_detail(asset_id: String) -> String:
	var a := catalog.asset(asset_id)
	if a.is_empty():
		return "%s（素材目錄找不到這個編號）" % asset_id
	var parts := PackedStringArray(["%s  %.1f 秒" % [asset_id, float(a.get("dur", 0.0))]])
	var source := a
	if a.has("parent"):
		parts.append("✂ 擷取自 %s %.2f–%.2f 秒" % [a["parent"], float(a.get("start", 0.0)), float(a.get("end", 0.0))])
		source = catalog.asset(str(a["parent"]))
	if source.is_empty():
		parts.append("（原檔不在目錄）")
		return "　".join(parts)
	var desc := str(source.get("desc", ""))
	if not desc.is_empty():
		parts.append(", ".join(desc.split(", ").slice(0, 2)))  # 槍種與型號（說明的前兩段）
	parts.append("%s（%s）" % [str(source.get("file", "")).get_file(), str(source.get("pack", "")).trim_prefix("oga_").trim_prefix("kenney_")])
	return "　".join(parts)


## 清單因為沒有預聽檔而隱藏了素材時，放在清單旁的一句說明。
func hidden_assets_note(hidden: int) -> String:
	return "另有 %d 個素材沒有預聽檔而隱藏，補齊：python tools/audio/build_candidates.py" % hidden


## 開啟「套用到遊戲」面板（蓋在整個實驗室上），列出會改的位置；回傳是否成功。
func open_apply_panel() -> bool:
	if apply_panel != null:
		return true
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var panel := SoundLabApplyPanel.new()
	panel.theme = _theme
	panel.setup(self, apply_runner)
	layer.add_child(panel)
	panel.tree_exited.connect(layer.queue_free)
	apply_panel = panel
	return await panel.open()


## 開啟擷取片段介面（蓋在整個實驗室上），載入這個素材的完整波形；回傳是否成功。
func open_clip_editor(asset_id: String) -> bool:
	if clip_editor != null:
		clip_editor.close()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var editor := SoundLabClipEditor.new()
	editor.theme = _theme
	editor.setup(self, clip_runner)
	layer.add_child(editor)
	editor.tree_exited.connect(layer.queue_free)
	clip_editor = editor
	return await editor.open(asset_id)


## 試聽一個素材（預聽檔）；沒有預聽檔時提示怎麼產生。
func audition_asset(asset_id: String) -> bool:
	if audition.play_asset(asset_id):
		var a := catalog.asset(asset_id)
		notify("試聽 %s（%.1f 秒）  %s／%s" % [asset_id, float(a.get("dur", 0.0)), a.get("pack", ""), a.get("file", "")])
		return true
	notify("沒有 %s 的預聽檔：請先執行 python tools/audio/build_candidates.py" % asset_id)
	return false


func _build_theme() -> Theme:
	var theme := UiKit.theme().duplicate() as Theme
	theme.default_font_size = FONT_SIZE
	for type in ["Button", "Label", "LineEdit", "ItemList", "OptionButton", "CheckBox", "TabContainer", "TabBar"]:
		theme.set_font_size(&"font_size", type, FONT_SIZE)
	_style_splits(theme)
	return theme


## 分隔線：加粗、上色並畫三個點，一眼看得出可以拖。
func _style_splits(theme: Theme) -> void:
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(Palette.CYAN, 0.18)
	bar.set_corner_radius_all(3)
	for type in ["SplitContainer", "HSplitContainer", "VSplitContainer"]:
		theme.set_constant(&"separation", type, SPLIT_SEPARATION)
		theme.set_constant(&"minimum_grab_thickness", type, SPLIT_SEPARATION)
		theme.set_stylebox(&"split_bar_background", type, bar)
	var tall := _grip_icon(true)
	var wide := _grip_icon(false)
	for type in ["SplitContainer", "HSplitContainer"]:
		theme.set_icon(&"grabber", type, tall)
		theme.set_icon(&"h_grabber", type, tall)
	theme.set_icon(&"v_grabber", "SplitContainer", wide)
	theme.set_icon(&"grabber", "VSplitContainer", wide)
	theme.set_icon(&"v_grabber", "VSplitContainer", wide)


## 三個點排成的抓把圖示；vertical 是左右分隔用的直條。
func _grip_icon(vertical: bool) -> ImageTexture:
	var image := Image.create(SPLIT_SEPARATION, SPLIT_SEPARATION * 3, false, Image.FORMAT_RGBA8) if vertical else Image.create(SPLIT_SEPARATION * 3, SPLIT_SEPARATION, false, Image.FORMAT_RGBA8)
	var length := maxi(image.get_width(), image.get_height())
	for i in 3:
		var center := length / 2 + (i - 1) * 8
		var rect := Rect2i(SPLIT_SEPARATION / 2 - 2, center - 2, 4, 4) if vertical else Rect2i(center - 2, SPLIT_SEPARATION / 2 - 2, 4, 4)
		image.fill_rect(rect, Palette.CYAN)
	return ImageTexture.create_from_image(image)
