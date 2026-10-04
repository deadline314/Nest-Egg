class_name AuditionPlayer
extends Node
## 試聽播放器：播放素材目錄的預聽檔（音樂走 Music 匯流排、其餘走 SFX），一次只播一個，新的取代舊的。
## 預聽檔已經用正式加工的響度標準處理過，所以聽到的音量就是套用後的音量。

signal started(asset_id: String)
signal stopped

var _player := AudioStreamPlayer.new()
var _catalog: AudioCatalog
var current_id := ""


func setup(catalog: AudioCatalog) -> void:
	_catalog = catalog
	_player.finished.connect(_on_finished)
	add_child(_player)


## 播放某個素材的預聽檔。沒有預聽檔回傳 false（呼叫端提示怎麼產生）。
func play_asset(asset_id: String) -> bool:
	var stream := _catalog.load_preview(asset_id) if _catalog != null else null
	if stream == null:
		return false
	_player.stop()
	_player.bus = &"Music" if asset_id.begins_with("MUS-") else &"SFX"
	_player.stream = stream
	_player.play()
	current_id = asset_id
	started.emit(asset_id)
	return true


func stop() -> void:
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
