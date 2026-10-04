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

var catalog := AudioCatalog.new()
var doc := PlacementDoc.new()
var audition := AuditionPlayer.new()
## 位置清單文件的路徑（測試時指到複本，不動真正的文件）。
var doc_path := PlacementDoc.PATH
## 要不要建立右側的畫面舞台（測試其他分頁時關掉，省去建關卡的時間）。
var stage_enabled := true
var dock: SoundLabStageDock
var slots_tab: SoundLabSlotsTab
var scenes_tab: SoundLabScenesTab
var live_tab: SoundLabLiveTab
var music_tab: SoundLabMusicTab
var mixer_tab: SoundLabMixerTab
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
	var split := HSplitContainer.new()
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
	if _changed_scale_mode:
		get_window().content_scale_mode = _scale_mode_before


func _process(delta: float) -> void:
	_sync_left -= delta
	if _sync_left > 0.0:
		return
	_sync_left = SYNC_INTERVAL
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
	var file := str(a.get("file", "")).get_file()
	return "%s  %5.1fs  %s／%s" % [asset_id, float(a.get("dur", 0.0)), str(a.get("pack", "")).trim_prefix("oga_").trim_prefix("kenney_"), file]


## 清單因為沒有預聽檔而隱藏了素材時，放在清單旁的一句說明。
func hidden_assets_note(hidden: int) -> String:
	return "另有 %d 個素材沒有預聽檔而隱藏，補齊：python tools/audio/build_candidates.py" % hidden


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
	return theme
