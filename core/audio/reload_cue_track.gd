class_name ReloadCueTrack
extends RefCounted
## 一次換彈的聲音播放進度：依換彈進度播出時間軸上到點的 cue。
## begin() 取得該武器的時間軸並播出 at 為 0 的；advance(進度) 每影格呼叫；finish() 換彈完成時補播剩下的；cancel() 中途取消。
## 進度由換彈本身提供，所以義體加速換彈或改變換彈時間，聲音都會跟著動畫。

## cue 播出時送出（lab 用來標示游標經過的聲音）：第幾個 cue（排序後）、實際播的名稱（找不到聲音時為空）。
signal cue_played(index: int, sound: StringName)

var weapon_id: StringName = &""
var _cues: Array[ReloadCues.Cue] = []
var _next := 0
var _active := false


func begin(p_weapon_id: StringName) -> void:
	weapon_id = p_weapon_id
	_cues = ReloadCues.for_weapon(p_weapon_id)
	_next = 0
	_active = true
	advance(0.0)


## 播出所有時間點已到（含剛好等於）的 cue；回傳這次播了幾個。
func advance(progress: float) -> int:
	var played := 0
	while _active and _next < _cues.size() and _cues[_next].at <= progress:
		_play(_next)
		_next += 1
		played += 1
	return played


## 換彈完成：把還沒播的全部播完（最後一次更新可能剛好越過完成點）。
func finish() -> int:
	var played := advance(1.0)
	cancel()
	return played


func cancel() -> void:
	_cues = []
	_next = 0
	_active = false


func is_active() -> bool:
	return _active


func cues() -> Array[ReloadCues.Cue]:
	return _cues


func _play(index: int) -> void:
	var cue := _cues[index]
	var name := ReloadCues.sound_of(weapon_id, cue)
	if name != &"":
		Sfx.play_named(name, cue.volume_db)
	cue_played.emit(index, name)
