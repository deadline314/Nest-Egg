class_name SoundStage
extends SubViewportContainer
## 實驗室的畫面舞台：遊戲真正的關卡、玩家、敵人、HUD 與特效放在自己的畫面裡，情境（data/audio/stage_scenes.json）的動作在這裡做，
## 聲音由遊戲自己的程式路徑播出。執行時記錄實際響了哪些音效；也能把某個位置的聲音暫時換成備選素材的預聽檔來試。
## 實體按鍵預設鎖住（點實驗室的按鈕不會讓玩家開槍），要自己玩時用 set_free_play(true)。

signal scene_started(scene_id: String)
signal scene_finished(scene_id: String)
## 情境執行中每響一個音效就送出一次（音效 id）。
signal sound_recorded(id: StringName)

const VIEW_SIZE := Vector2i(640, 360)
const MIN_SPEED := 0.1

var arena: LabArena
var actions: StageActions
var scenes: StageScenes = StageScenes.shared()
var recorded: Array[StringName] = []
var current_scene := ""
var running := false
var speed := 1.0 : set = set_speed
var _viewport: SubViewport
var _input_lock := StageInputLock.new()
var _free_play := false
var _run_serial := 0


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(320, 180)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.size_2d_override = VIEW_SIZE
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	add_child(_viewport)
	arena = LabArena.new()
	_viewport.add_child(arena)
	actions = StageActions.new(arena)
	_input_lock.lock()
	Sfx.sound_played.connect(_on_sound_played)
	# 環境音與背景音樂不走音效庫的播放函式，各自送訊號讓這裡也記錄得到。
	Ambience.layer_started.connect(_on_sound_played)
	Music.track_started.connect(_on_sound_played)
	arena.build()


func _exit_tree() -> void:
	_input_lock.unlock()
	Engine.time_scale = 1.0
	Sfx.clear_previews()
	for source: Signal in [Sfx.sound_played, Ambience.layer_started, Music.track_started]:
		if source.is_connected(_on_sound_played):
			source.disconnect(_on_sound_played)


## 隱藏舞台時不繪圖（省效能）；情境仍可執行，只是看不到。
func set_active(on: bool) -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func is_ready() -> bool:
	return arena != null and arena.is_ready()


func set_speed(value: float) -> void:
	speed = clampf(value, MIN_SPEED, 1.0)
	Engine.time_scale = speed


func set_free_play(on: bool) -> void:
	_free_play = on
	if on:
		_input_lock.unlock()
	else:
		_input_lock.lock()


func is_free_play() -> bool:
	return _free_play


## 等場地建好（剛開啟實驗室時關卡還在建）。
func wait_ready() -> void:
	while not is_ready():
		await get_tree().process_frame


## 執行一個情境。preview：{音效 id: 預聽串流}，這次執行期間暫時取代那些音效（備選素材試聽），結束或取消後還原。
## 回傳是否完整跑完（被新的情境取代、被停止或找不到情境回傳 false）。
func run_scene(scene_id: String, preview: Dictionary = {}) -> bool:
	var scene := scenes.scene(scene_id)
	if scene.is_empty():
		push_error("[SoundStage] 沒有這個情境「%s」（%s）" % [scene_id, scenes.path])
		return false
	return await run_action(str(scene["action"]), scene.get("params", {}), scene_id, preview)


## 直接執行一個動作（不經過情境目錄，例如時間軸編輯器的「在畫面換彈」）；label 當作情境名稱顯示與記錄。
func run_action(action: String, params: Dictionary, label: String, preview: Dictionary = {}) -> bool:
	await wait_ready()
	actions.cancel()
	_run_serial += 1
	var run_id := _run_serial
	running = true
	current_scene = label
	await arena.reset()
	if run_id != _run_serial:
		return false
	recorded.clear()
	Sfx.clear_previews()
	for id: Variant in preview.keys():
		Sfx.set_preview(StringName(str(id)), preview[id])
	scene_started.emit(label)
	await actions.run(action, params, label)
	if run_id != _run_serial:
		return false
	running = false
	arena.release_all()
	Sfx.clear_previews()
	if arena.audio_on:
		# 音樂與環境音的情境結束就淡出，下一個情境不會接著響。
		Music.stop(0.4)
		Ambience.stop_all(0.4)
	UiKit.set_cursor_visible(true)
	scene_finished.emit(label)
	return true


## 立刻停止目前的情境（放開按鍵、停掉聲音、還原備選素材試聽）。
func stop() -> void:
	_run_serial += 1
	actions.cancel()
	running = false
	Sfx.clear_previews()
	Sfx.stop_all()
	if arena.audio_on:
		Music.stop(0.2)
		Ambience.stop_all(0.2)


## 這次情境實際響過的音效 id（去重，依第一次出現的順序）。
func recorded_unique() -> PackedStringArray:
	var out := PackedStringArray()
	for id in recorded:
		if not out.has(String(id)):
			out.append(String(id))
	return out


func _on_sound_played(id: StringName) -> void:
	if running:
		recorded.append(id)
		sound_recorded.emit(id)
