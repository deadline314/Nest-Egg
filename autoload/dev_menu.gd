extends CanvasLayer
## 開發工具選單（NE-168）：在編輯器或除錯版按 F5 開關，列出實驗室等工具，點一下就切換過去，不用再打命令列。
## 工具清單在 tools/dev_tools.json（資料驅動，新增工具不改程式）；匯出版沒有 tools/ 資料夾，選單自動停用，玩家流程進不去。
## 開啟時暫停遊戲並顯示滑鼠，關閉或切換時還原；工具裡也能按 F5 切到別的工具或回主選單。

signal tool_chosen(entry: Dictionary)

const TOOLS_PATH := "res://tools/dev_tools.json"
const TOGGLE_KEY := KEY_F5
const LAYER_ORDER := 120
const BACK_TO_MENU_ENTRY := {"id": "main_menu", "name": "回到主選單", "scene": "", "tip": "離開目前的工具或關卡，重新開始遊戲的主選單"}

## 切換場景的方式；測試會換成記錄用的函式，避免真的離開測試場景。
var scene_changer: Callable = _change_scene

var entries: Array[Dictionary] = []
var is_open := false
var _root: Control
var _list: VBoxContainer
var _status: Label
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER_ORDER
	entries = load_entries(TOOLS_PATH)
	set_process_input(is_available())


## 編輯器與除錯版才啟用；匯出的正式版沒有 tools/，清單是空的，F5 什麼都不做。
func is_available() -> bool:
	return OS.is_debug_build() and not entries.is_empty()


## 讀工具清單；檔案不存在、格式錯誤或項目不完整都只略過並記錄，回傳能用的項目。
static func load_entries(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("tools")) != TYPE_ARRAY:
		push_error("[DevMenu] 工具清單格式錯誤（要有 tools 陣列）：%s" % path)
		return out
	var seen := {}
	for i in ((parsed as Dictionary)["tools"] as Array).size():
		var entry: Variant = parsed["tools"][i]
		if typeof(entry) != TYPE_DICTIONARY or str(entry.get("id", "")).is_empty() or str(entry.get("name", "")).is_empty() or str(entry.get("scene", "")).is_empty():
			push_error("[DevMenu] %s 的第 %d 個工具缺少 id、name 或 scene，已略過" % [path, i + 1])
			continue
		if seen.has(entry["id"]):
			push_error("[DevMenu] %s 的工具 id 重複：%s，已略過" % [path, entry["id"]])
			continue
		seen[entry["id"]] = true
		out.append(entry)
	return out


func _input(event: InputEvent) -> void:
	if GameplayLock.is_locked():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and is_open:
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open or not is_available() or GameplayLock.is_locked():
		return
	_build()
	_status.text = ""
	_root.visible = true
	is_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode


## 選一個工具：場景存在才切換；找不到就在面板上說明，留在原地。
func choose(entry: Dictionary) -> bool:
	var scene := str(entry.get("scene", ""))
	if scene.is_empty():
		scene = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not ResourceLoader.exists(scene):
		var message := "找不到 %s 的場景：%s" % [entry.get("name", entry.get("id", "")), scene]
		push_error("[DevMenu] " + message)
		if _status != null:
			_status.text = message
		return false
	tool_chosen.emit(entry)
	close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene_changer.call(scene)
	return true


func _change_scene(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)


func _build() -> void:
	if _root != null:
		return
	_root = UiKit.full_rect_root(self)
	var box := UiKit.centered_panel(_root, 360.0, 0.6)
	box.add_child(UiKit.label("開發工具", 14, Palette.CYAN))
	box.add_child(UiKit.label("按 F5 或 Esc 關閉；只有編輯器與除錯版有這個選單", 9, Palette.UI_MUTED))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	box.add_child(_list)
	for entry in entries:
		_list.add_child(UiKit.button(str(entry["name"]), choose.bind(entry), str(entry.get("tip", ""))))
	_list.add_child(UiKit.button(str(BACK_TO_MENU_ENTRY["name"]), choose.bind(BACK_TO_MENU_ENTRY), str(BACK_TO_MENU_ENTRY["tip"])))
	_status = UiKit.label("", 9, Palette.UI_MUTED)
	box.add_child(_status)
