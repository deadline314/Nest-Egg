class_name AuditionPlayer
extends Node
## 試聽播放器：播放素材目錄的預聽檔（音樂走 Music 匯流排、其餘走 SFX），一次只播一個，新的取代舊的。
## 預聽檔已經用正式加工的響度標準處理過，所以聽到的音量就是套用後的音量。

signal started(asset_id: String)
signal stopped

var _player := AudioStreamPlayer.new()
var _catalog: AudioCatalog
var current_id := ""
var _stop_at := -1.0


func setup(catalog: AudioCatalog) -> void:
	_catalog = catalog
	_player.finished.connect(_on_finished)
	add_child(_player)


## 播放某個素材的預聽檔。沒有預聽檔回傳 false（呼叫端提示怎麼產生）。
## from／length：只播預聽檔從 from 秒起的 length 秒（短曲取用範圍的試聽）；起點超過預聽檔長度也回傳 false。
func play_asset(asset_id: String, from := 0.0, length := 0.0) -> bool:
	var stream := _catalog.load_preview(asset_id) if _catalog != null else null
	if stream == null or from >= stream.get_length():
		return false
	_player.stop()
	_stop_at = from + length if length > 0.0 else -1.0
	set_process(_stop_at > 0.0)
	_player.bus = &"Music" if asset_id.begins_with("MUS-") else &"SFX"
	_player.stream = stream
	_player.play(maxf(0.0, from))
	current_id = asset_id
	started.emit(asset_id)
	return true


func _process(_delta: float) -> void:
	if _stop_at > 0.0 and _player.playing and _player.get_playback_position() >= _stop_at:
		stop()


func stop() -> void:
	_stop_at = -1.0
	set_process(false)
	if _player.playing:
		_player.stop()
	current_id = ""
	stopped.emit()


func is_playing() -> bool:
	return _player.playing


func position_seconds() -> float:
	return _player.get_playback_position() if _player.playing else 0.0


func length_seconds() -> float:
	return _player.stream.get_length() if _player.stream != null else 0.0


func _on_finished() -> void:
	current_id = ""
	stopped.emit()
