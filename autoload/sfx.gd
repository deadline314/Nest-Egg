extends Node
## 程式合成音效：沒有音效素材也能提供射擊／命中／爆炸／移動的即時聽覺回饋。
## 每個音效由一或多個「層」混合而成（例如：低頻重擊 + 高頻噪音）。
## 之後換成正式音效檔：在 OVERRIDES 填入 id -> 路徑，呼叫端完全不用改。

const MIX_RATE := 22050
const VOICES := 24
## 同一音效的最短重播間隔，避免同一影格疊加造成爆音。
const MIN_INTERVAL_MSEC := 25
## 音量由設定選單控制（見 Settings.AUDIO_BUSES）。
const BUS := &"SFX"

## 層參數：wave(sine/square/saw/tri/noise)、from/to(Hz，指數滑音)、time(秒)、
## volume、noise(0~1 混入噪音)、lowpass(0~0.95 平滑)、decay(包絡曲線指數)、attack(秒)
const SOUNDS := {
	&"shot_rifle": [
		{"wave": "square", "from": 1400.0, "to": 260.0, "time": 0.07, "volume": 0.2, "noise": 0.35, "decay": 2.0},
		{"wave": "noise", "time": 0.05, "volume": 0.28, "lowpass": 0.3, "decay": 3.0},
		{"wave": "sine", "from": 180.0, "to": 70.0, "time": 0.07, "volume": 0.22, "decay": 2.0},
	],
	&"shot_pistol": [
		{"wave": "square", "from": 1100.0, "to": 280.0, "time": 0.06, "volume": 0.2, "noise": 0.35, "decay": 2.2},
		{"wave": "noise", "time": 0.05, "volume": 0.3, "lowpass": 0.2, "decay": 3.0},
		{"wave": "sine", "from": 220.0, "to": 80.0, "time": 0.07, "volume": 0.28, "decay": 2.0},
	],
	&"shot_smg": [
		{"wave": "square", "from": 1500.0, "to": 420.0, "time": 0.045, "volume": 0.15, "noise": 0.3, "decay": 2.2},
		{"wave": "noise", "time": 0.035, "volume": 0.22, "lowpass": 0.15, "decay": 3.0},
	],
	&"shot_launcher": [
		{"wave": "sine", "from": 260.0, "to": 110.0, "time": 0.16, "volume": 0.4, "decay": 1.8},
		{"wave": "noise", "time": 0.11, "volume": 0.25, "lowpass": 0.65, "decay": 2.5},
	],
	&"shot_railgun": [
		{"wave": "saw", "from": 300.0, "to": 3200.0, "time": 0.12, "volume": 0.16, "lowpass": 0.3, "decay": 1.2},
		{"wave": "noise", "time": 0.22, "volume": 0.35, "lowpass": 0.5, "decay": 2.0},
		{"wave": "sine", "from": 130.0, "to": 40.0, "time": 0.26, "volume": 0.42, "decay": 1.6},
	],
	&"shot_spread": [
		{"wave": "noise", "time": 0.16, "volume": 0.45, "lowpass": 0.55, "decay": 2.5},
		{"wave": "sine", "from": 180.0, "to": 60.0, "time": 0.12, "volume": 0.4, "decay": 2.0},
	],
	&"shot_laser": [
		{"wave": "saw", "from": 2200.0, "to": 500.0, "time": 0.14, "volume": 0.2, "lowpass": 0.4, "decay": 1.5},
		{"wave": "sine", "from": 900.0, "to": 300.0, "time": 0.14, "volume": 0.25, "decay": 1.5},
	],
	&"shot_cannon": [
		{"wave": "noise", "time": 0.22, "volume": 0.5, "lowpass": 0.75, "decay": 2.0},
		{"wave": "sine", "from": 140.0, "to": 40.0, "time": 0.2, "volume": 0.55, "decay": 1.6},
	],
	&"shot_enemy": [
		{"wave": "square", "from": 620.0, "to": 300.0, "time": 0.09, "volume": 0.16, "lowpass": 0.3, "decay": 2.0},
	],
	&"hit": [
		{"wave": "noise", "time": 0.035, "volume": 0.35, "lowpass": 0.1, "decay": 3.0},
		{"wave": "square", "from": 900.0, "to": 600.0, "time": 0.03, "volume": 0.12, "decay": 2.0},
	],
	&"block": [
		{"wave": "sine", "from": 2600.0, "to": 2400.0, "time": 0.12, "volume": 0.2, "decay": 2.5},
		{"wave": "sine", "from": 3900.0, "to": 3700.0, "time": 0.09, "volume": 0.12, "decay": 3.0},
	],
	&"kill": [
		{"wave": "noise", "time": 0.18, "volume": 0.4, "lowpass": 0.5, "decay": 2.0},
		{"wave": "sine", "from": 220.0, "to": 55.0, "time": 0.16, "volume": 0.45, "decay": 1.8},
	],
	&"explosion": [
		{"wave": "noise", "time": 0.45, "volume": 0.6, "lowpass": 0.82, "decay": 1.6},
		{"wave": "sine", "from": 110.0, "to": 30.0, "time": 0.35, "volume": 0.6, "decay": 1.4},
	],
	&"finisher": [
		{"wave": "sine", "from": 160.0, "to": 40.0, "time": 0.25, "volume": 0.6, "decay": 1.5},
		{"wave": "saw", "from": 300.0, "to": 2400.0, "time": 0.12, "volume": 0.15, "lowpass": 0.3, "decay": 1.2},
		{"wave": "noise", "time": 0.1, "volume": 0.3, "lowpass": 0.2, "decay": 3.0},
	],
	&"jump": [
		{"wave": "tri", "from": 280.0, "to": 620.0, "time": 0.08, "volume": 0.18, "decay": 1.5},
	],
	&"land": [
		{"wave": "noise", "time": 0.06, "volume": 0.2, "lowpass": 0.8, "decay": 2.5},
	],
	&"dash": [
		{"wave": "noise", "time": 0.14, "volume": 0.3, "lowpass": 0.6, "decay": 1.2, "attack": 0.03},
	],
	&"hurt": [
		{"wave": "square", "from": 520.0, "to": 140.0, "time": 0.2, "volume": 0.25, "lowpass": 0.4, "decay": 1.5},
		{"wave": "noise", "time": 0.08, "volume": 0.25, "lowpass": 0.3, "decay": 2.5},
	],
	&"pickup": [
		{"wave": "tri", "from": 660.0, "to": 660.0, "time": 0.07, "volume": 0.2, "decay": 1.0},
		{"wave": "tri", "from": 990.0, "to": 1320.0, "time": 0.16, "volume": 0.2, "decay": 1.2, "attack": 0.06},
	],
	&"parry": [
		{"wave": "sine", "from": 3200.0, "to": 2600.0, "time": 0.22, "volume": 0.22, "decay": 2.0},
		{"wave": "tri", "from": 900.0, "to": 1800.0, "time": 0.12, "volume": 0.2, "decay": 1.5},
		{"wave": "noise", "time": 0.08, "volume": 0.3, "lowpass": 0.15, "decay": 3.0},
	],
	&"telegraph": [
		{"wave": "square", "from": 1250.0, "to": 1250.0, "time": 0.06, "volume": 0.1, "decay": 1.0},
	],
	&"empty": [
		{"wave": "square", "from": 220.0, "to": 200.0, "time": 0.04, "volume": 0.12, "decay": 2.0},
	],
	&"ui_move": [
		{"wave": "tri", "from": 880.0, "to": 880.0, "time": 0.03, "volume": 0.12, "decay": 2.0},
	],
	&"ui_confirm": [
		{"wave": "tri", "from": 660.0, "to": 1320.0, "time": 0.1, "volume": 0.18, "decay": 1.5},
	],
}

## id -> res:// 路徑（AudioStream）。有設定時優先使用正式音效。
const OVERRIDES := {}

var enabled := true

var _streams: Dictionary[StringName, AudioStream] = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_play_msec: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	for id: StringName in SOUNDS.keys():
		_streams[id] = _load_or_synthesize(id)


## 停止所有播放中的音效（切換場景或結束遊戲時呼叫，避免播放實例殘留）。
func stop_all() -> void:
	for player in _players:
		player.stop()
		player.stream = null


func _exit_tree() -> void:
	stop_all()


func play(id: StringName, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	if not enabled:
		return
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		push_warning("[Sfx] 未定義的音效：%s" % id)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play_msec.get(id, -1000)) < MIN_INTERVAL_MSEC:
		return
	_last_play_msec[id] = now
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func _load_or_synthesize(id: StringName) -> AudioStream:
	var override_path: String = OVERRIDES.get(id, "")
	if not override_path.is_empty():
		var loaded := load(override_path) as AudioStream if ResourceLoader.exists(override_path) else null
		if loaded != null:
			return loaded
		push_warning("[Sfx] 音效檔載入失敗，改用合成音：%s" % override_path)
	return _synthesize(SOUNDS[id])


func _synthesize(layers: Array) -> AudioStreamWAV:
	var duration := 0.0
	for layer: Dictionary in layers:
		duration = maxf(duration, float(layer.get("time", 0.1)))
	var count := maxi(1, int(duration * MIX_RATE))
	var mix := PackedFloat32Array()
	mix.resize(count)
	mix.fill(0.0)
	for layer: Dictionary in layers:
		_render_layer(layer, mix)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _render_layer(layer: Dictionary, mix: PackedFloat32Array) -> void:
	var wave := str(layer.get("wave", "sine"))
	var from_hz := float(layer.get("from", 440.0))
	var to_hz := float(layer.get("to", from_hz))
	var count := mini(mix.size(), int(float(layer.get("time", 0.1)) * MIX_RATE))
	var volume := float(layer.get("volume", 0.3))
	var noise_mix := 1.0 if wave == "noise" else float(layer.get("noise", 0.0))
	var smoothing := clampf(float(layer.get("lowpass", 0.0)), 0.0, 0.95)
	var decay := float(layer.get("decay", 2.0))
	var attack_samples := maxf(1.0, float(layer.get("attack", 0.003)) * MIX_RATE)
	var ratio := to_hz / maxf(1.0, from_hz)
	var phase := 0.0
	var filtered := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase = fmod(phase + from_hz * pow(ratio, t) / MIX_RATE, 1.0)
		var tone: float
		match wave:
			"square":
				tone = 1.0 if phase < 0.5 else -1.0
			"saw":
				tone = phase * 2.0 - 1.0
			"tri":
				tone = 1.0 - 4.0 * absf(phase - 0.5)
			_:
				tone = sin(phase * TAU)
		var sample := lerpf(tone, _rng.randf_range(-1.0, 1.0), noise_mix)
		filtered = lerpf(sample, filtered, smoothing)
		var envelope := minf(1.0, float(i) / attack_samples) * pow(1.0 - t, decay)
		mix[i] += filtered * envelope * volume
