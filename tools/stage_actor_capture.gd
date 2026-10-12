extends Node2D
## 過場舞台的站位檢查（BG-46）：在指定舞台上放一個演員，用正式的過場播放器（含上下黑邊與對話框）拍原生畫面，
## 看頭有沒有被上黑邊切掉、腳有沒有被對話框蓋住、和立繪裡的家具比例對不對。舞台還沒有接進劇本時用這支。
## 用法（原生 Forward+）：
##   godot --path . res://tools/stage_actor_capture.tscn -- --out=<絕對資料夾> --stage=<舞台 id> [--actor=ali] [--scale=3.9]
##     --shot=<名稱>:<鏡頭 x>,<鏡頭 y>,<倍率>:<演員 x>,<演員 y>:<姿勢>   （可以給很多個）
## 每個 --shot 輸出 <舞台>-<名稱>.png。演員姿勢見 CutsceneActor.POSES。

const Capture := preload("res://tools/viewport_capture.gd")
const SETTLE_SECONDS := 2.4

var _out := ""
var _stage := ""
var _actor := "ali"
var _scale := 3.9
var _shots: PackedStringArray = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--stage="):
			_stage = argument.trim_prefix("--stage=")
		elif argument.begins_with("--actor="):
			_actor = argument.trim_prefix("--actor=")
		elif argument.begins_with("--scale="):
			_scale = float(argument.trim_prefix("--scale="))
		elif argument.begins_with("--shot="):
			_shots.append(argument.trim_prefix("--shot="))
	if _out.is_empty() or _stage.is_empty() or _shots.is_empty():
		printerr("[stage_actor_capture] 需要 --out、--stage 與至少一個 --shot")
		get_tree().quit(2)
		return
	if not StageLibrary.ids().has(StringName(_stage)):
		printerr("[stage_actor_capture] 沒有 %s 這個舞台" % _stage)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var failed := false
	for shot in _shots:
		if not await _capture(shot):
			failed = true
	get_tree().quit(1 if failed else 0)


func _capture(shot: String) -> bool:
	var parts := shot.split(":")
	var camera := parts[1].split_floats(",") if parts.size() == 4 else PackedFloat64Array()
	var at := parts[2].split_floats(",") if parts.size() == 4 else PackedFloat64Array()
	if camera.size() != 3 or at.size() != 2:
		printerr("[stage_actor_capture] 看不懂 --shot=%s（格式：名稱:鏡頭x,鏡頭y,倍率:演員x,演員y:姿勢）" % shot)
		return false
	var scene := {"mode": "animated", "steps": [
		{"do": "scene", "id": _stage, "pos": [camera[0], camera[1]], "zoom": camera[2], "fade": 0.25},
		{"do": "actor", "id": _actor, "kind": _actor, "pos": [at[0], at[1]], "facing": 1, "scale": _scale, "weapon": "", "speaker": _actor, "pose": parts[3]},
		{"do": "say", "speaker": _actor, "text": "（站位檢查：這一行只是為了讓對話框出現。）"},
		{"do": "wait", "time": 60.0},
	]}
	var player := CutscenePlayer.new()
	add_child(player)
	player.play(StringName("stage_actor_capture_" + parts[0]), scene)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [_out, _stage, parts[0]]
	var saved := Capture.image(get_viewport()).save_png(path) == OK
	print("[stage_actor_capture] %s %s" % [path, "ok" if saved else "寫不進去"])
	player.skip()
	while is_instance_valid(player) and player.is_running():
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	return saved
