class_name MeleeHum
extends Node
## 近戰武器拿在手上時的待機聲（NE-261）：熱刃的低嗡、戟的電弧、鞭的細鳴…，很小聲，收起武器就淡出停止。
## 每把武器的聲音寫在它的招式組資料（data/melee/<招式組>.json 的 idle_sound），沒有寫就沒有待機聲。
## 只佔一個迴圈聲道，掛在音效匯流排（跟著設定的音效音量）；出招時壓低一點，讓揮動聲與命中聲清楚。
## 音效庫沒有那個聲音時記錄一次，之後不處理（武器照常使用，只是沒有待機聲）。

## 拿在手上時的音量（素材本身約 -29 dB）：比腳步聲小 6 dB 以上、比環境音與配樂小 10 dB 以上，安靜的地方才注意得到。
const BASE_DB := -12.0
## 出招那一下壓低多少（0～1 的倍率）。
const SWING_DUCK := 0.45
## 每秒音量最多變化多少（0～1）：拿出來約 0.3 秒淡入，收起來約 0.2 秒淡出。
const FADE_IN := 3.5
const FADE_OUT := 5.0
const SILENT := 0.02

var _player: AudioStreamPlayer
var _sound: StringName = &""
var _gain := 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = Sfx.BUS
	add_child(_player)


## 每影格由主角的外觀呼叫：手上有近戰武器就響它的待機聲，沒有就淡出。
func follow(visual: PlayerVisual, delta: float) -> void:
	var wanted: StringName = &""
	if visual.shows_melee_weapon() and visual.is_visible_in_tree() and Sfx.enabled:
		wanted = MeleeData.set_of(visual.player.loadout.active_weapon()).idle_sound()
	if wanted != _sound and _gain <= SILENT:
		_switch(wanted)
	var target := 0.0
	if wanted == _sound and not _sound.is_empty() and _player.stream != null:
		target = SWING_DUCK if visual.player.is_melee_swinging() else 1.0
	_gain = move_toward(_gain, target, delta * (FADE_IN if target > _gain else FADE_OUT))
	if _gain <= SILENT:
		if _player.playing:
			_player.stop()
		return
	_player.volume_db = BASE_DB + linear_to_db(_gain)
	if not _player.playing:
		_player.play()


## 現在響的是哪個聲音（沒有在響回傳空字串）與音量倍率（測試與量測用）。
func sounding() -> StringName:
	return _sound if _player.playing else &""


func gain() -> float:
	return _gain


func _switch(sound: StringName) -> void:
	_sound = sound
	_player.stop()
	_player.stream = null
	if sound.is_empty():
		return
	var variants := Sfx.bank().variants(sound)
	if variants.is_empty():
		AudioData.report("melee_hum:" + String(sound), "[MeleeHum] 音效庫沒有「%s」，這把近戰武器沒有待機聲" % sound)
		return
	var stream: AudioStream = variants[0]
	if &"loop" in stream:
		stream = stream.duplicate()
		stream.set(&"loop", true)
	_player.stream = stream
