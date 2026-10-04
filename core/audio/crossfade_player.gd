class_name CrossfadePlayer
extends Node
## 交叉淡化播放器：兩個串流播放器輪流上場，換曲時舊的淡出、新的淡入（環境音與背景音樂共用）。
## 音量用分貝線性漸變，不用 Tween，所以沒有殘留的動畫物件；節點在暫停時照常運作（音樂不因暫停中斷）。
## 迴圈：需要時把串流複製一份再開啟 loop，不會改到共用的音效庫資源。

const SILENT_DB := -60.0

var bus: StringName = &"Master"
var _players: Array[AudioStreamPlayer] = []
var _targets: Array[float] = [SILENT_DB, SILENT_DB]
var _rates: Array[float] = [0.0, 0.0]
var _active := -1
var _stream: AudioStream
var _volume_db := 0.0


func _init(p_bus: StringName = &"Master") -> void:
	bus = p_bus
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)


## 播放 stream。同一個串流已經在播時只調整音量，不重頭播。回傳是否換了曲目。
func play(stream: AudioStream, volume_db := 0.0, fade_in := 1.5, fade_out := 1.5, loop := true, from_position := 0.0) -> bool:
	if stream == null:
		return false
	if _active >= 0 and _stream == stream and _players[_active].playing:
		set_volume(volume_db, fade_in)
		return false
	if _active >= 0:
		_fade_to(_active, SILENT_DB, fade_out)
	_active = 1 - _active if _active >= 0 else 0
	_stream = stream
	_volume_db = volume_db
	var player := _players[_active]
	player.stream = _prepared(stream, loop)
	player.volume_db = SILENT_DB if fade_in > 0.0 else volume_db
	_targets[_active] = volume_db
	_rates[_active] = (volume_db - SILENT_DB) / maxf(0.05, fade_in) if fade_in > 0.0 else 0.0
	player.play(from_position)
	return true


## 目前這首漸變到新的音量（實驗室調音量、暫停降音量用）。
func set_volume(volume_db: float, fade := 0.3) -> void:
	_volume_db = volume_db
	if _active >= 0:
		_fade_to(_active, volume_db, fade)


func stop(fade := 1.5) -> void:
	if _active >= 0:
		_fade_to(_active, SILENT_DB, fade)
	_active = -1
	_stream = null


func is_playing() -> bool:
	return _active >= 0 and _players[_active].playing


func current_stream() -> AudioStream:
	return _stream


func playback_position() -> float:
	return _players[_active].get_playback_position() if _active >= 0 and _players[_active].playing else 0.0


func seek(seconds: float) -> void:
	if _active >= 0:
		_players[_active].seek(seconds)


## 目前的目標音量（dB）。
func target_volume() -> float:
	return _volume_db


## 兩個播放器中正在發聲的數量（診斷用，換曲淡化期間是 2）。
func voices_playing() -> int:
	var count := 0
	for player in _players:
		count += 1 if player.playing else 0
	return count


func _fade_to(index: int, target_db: float, fade: float) -> void:
	_targets[index] = target_db
	var distance := absf(target_db - _players[index].volume_db)
	_rates[index] = distance / maxf(0.05, fade) if fade > 0.0 else 0.0
	if fade <= 0.0:
		_players[index].volume_db = target_db


func _process(delta: float) -> void:
	for i in _players.size():
		var player := _players[i]
		if not player.playing:
			continue
		if _rates[i] > 0.0 and not is_equal_approx(player.volume_db, _targets[i]):
			player.volume_db = move_toward(player.volume_db, _targets[i], _rates[i] * delta)
		if i != _active and player.volume_db <= SILENT_DB + 0.01:
			player.stop()


## 需要迴圈時複製串流並開啟 loop（OGG、MP3 有 loop 屬性）；不支援的格式原樣播放並記錄。
static func _prepared(stream: AudioStream, loop: bool) -> AudioStream:
	if not loop:
		return stream
	if &"loop" in stream:
		var copy := stream.duplicate() as AudioStream
		copy.set(&"loop", true)
		return copy
	AudioData.report("loop:" + stream.resource_path, "[CrossfadePlayer] 這個格式不能迴圈，改為只播一次：%s" % stream.resource_path, false)
	return stream
