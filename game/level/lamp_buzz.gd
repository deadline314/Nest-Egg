class_name LampBuzz
extends Node
## 快壞的燈的電流聲（BG-35）：整關共用一個迴圈聲道，音量跟著離鏡頭最近、正在掙扎的那盞燈，離遠就聽不到。
## 不替每盞燈各開一個聲道：同時有幾盞快壞的燈也只佔一個。聲音掛在環境音匯流排，跟著設定的環境音音量。
## 音效庫沒有這個聲音時記錄一次，之後不處理（燈照樣閃，只是沒有聲音）。

const SOUND: StringName = &"lamp_buzz"
## 離鏡頭中心多遠以內聽得到（像素）。
const RANGE := 210.0
## 貼著燈時的音量（素材本身是 -30 dB）：和這一區的環境音底噪差不多，不蓋過腳步；電流聲是氣氛。
const BASE_DB := -7.0
const UPDATE_INTERVAL := 0.08
## 每秒音量最多變化多少（0～1），避免忽大忽小。
const SLEW := 3.0
const SILENT := 0.02

var _lamps: Array[Lamp] = []
var _player: AudioStreamPlayer
var _since := 0.0
var _gain := 0.0


## lamps＝這一關會發出電流聲的燈。
func setup(lamps: Array[Lamp]) -> void:
	_lamps = lamps


func _ready() -> void:
	var variants := Sfx.bank().variants(SOUND)
	if variants.is_empty():
		AudioData.report("lamp_buzz", "[LampBuzz] 音效庫沒有「%s」，快壞的燈沒有電流聲" % SOUND)
		set_process(false)
		return
	var stream: AudioStream = variants[0]
	if &"loop" in stream:
		stream = stream.duplicate()
		stream.set(&"loop", true)
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = Ambience.BUS
	add_child(_player)


func _process(delta: float) -> void:
	_since += delta
	if _since < UPDATE_INTERVAL:
		return
	_gain = move_toward(_gain, loudest(), _since * SLEW)
	_since = 0.0
	if _gain <= SILENT:
		if _player.playing:
			_player.stop()
		return
	_player.volume_db = BASE_DB + linear_to_db(_gain)
	if not _player.playing:
		_player.play()


## 現在該有多大聲（0～1）：最近的那盞快壞的燈的遠近（平方衰減）乘上它當下的電流聲。
func loudest() -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return 0.0
	var centre := camera.get_screen_center_position()
	var best := 0.0
	for lamp: Lamp in _lamps:
		if not is_instance_valid(lamp):
			continue
		best = maxf(best, nearness(lamp.global_position.distance_to(centre)) * lamp.buzz_level())
	return best


## 距離 distance（像素）的燈聽起來有多近（0～1）：平方衰減，到 RANGE 歸零。
static func nearness(distance: float) -> float:
	var near := clampf(1.0 - distance / RANGE, 0.0, 1.0)
	return near * near


## 測試與量測用：目前的音量比例與是否正在播放。
func gain() -> float:
	return _gain


func is_sounding() -> bool:
	return _player != null and _player.playing
