extends Node
## 音效播放：檔案優先、合成音退路。
## 音效庫（data/audio/sound_bank.json，見 SoundBank）把音效 id 對應到一或多個音訊檔（變體）；
## 沒有登記、或檔案遺失／損毀的 id 退回下面 SOUNDS 的程式合成音，所以沒有素材也聽得到回饋。
## 合成音由一或多個「層」混合而成（例如：低頻重擊 + 高頻噪音）。呼叫端只認 id，換素材不用改程式。

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
	&"thunder": [
		{"wave": "noise", "time": 1.1, "volume": 0.5, "lowpass": 0.88, "decay": 1.1, "attack": 0.06},
		{"wave": "sine", "from": 75.0, "to": 28.0, "time": 1.2, "volume": 0.5, "decay": 1.0, "attack": 0.05},
	],
	&"reload_start": [
		{"wave": "square", "from": 900.0, "to": 700.0, "time": 0.03, "volume": 0.14, "decay": 3.0},
		{"wave": "noise", "time": 0.05, "volume": 0.16, "lowpass": 0.5, "decay": 3.0},
	],
	&"reload_done": [
		{"wave": "square", "from": 1300.0, "to": 900.0, "time": 0.025, "volume": 0.16, "decay": 3.0},
		{"wave": "noise", "time": 0.04, "volume": 0.22, "lowpass": 0.3, "decay": 3.5},
		{"wave": "sine", "from": 400.0, "to": 200.0, "time": 0.05, "volume": 0.18, "decay": 2.5},
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
	&"hit_a": [
		{"wave": "noise", "time": 0.04, "volume": 0.34, "lowpass": 0.12, "decay": 3.0},
		{"wave": "square", "from": 950.0, "to": 620.0, "time": 0.03, "volume": 0.12, "decay": 2.0},
		{"wave": "sine", "from": 160.0, "to": 90.0, "time": 0.05, "volume": 0.2, "decay": 2.0},
	],
	&"hit_b": [
		{"wave": "noise", "time": 0.035, "volume": 0.38, "lowpass": 0.28, "decay": 3.0},
		{"wave": "square", "from": 760.0, "to": 480.0, "time": 0.035, "volume": 0.12, "decay": 2.0},
		{"wave": "sine", "from": 200.0, "to": 100.0, "time": 0.05, "volume": 0.2, "decay": 2.0},
	],
	&"hit_c": [
		{"wave": "noise", "time": 0.045, "volume": 0.3, "lowpass": 0.05, "decay": 2.6},
		{"wave": "tri", "from": 1100.0, "to": 700.0, "time": 0.03, "volume": 0.14, "decay": 2.0},
		{"wave": "sine", "from": 140.0, "to": 80.0, "time": 0.06, "volume": 0.22, "decay": 2.0},
	],
	&"hit_tail": [
		{"wave": "noise", "time": 0.16, "volume": 0.12, "lowpass": 0.8, "decay": 2.4},
	],
	&"mat_generic": [
		{"wave": "noise", "time": 0.04, "volume": 0.3, "lowpass": 0.2, "decay": 3.0},
		{"wave": "sine", "from": 300.0, "to": 150.0, "time": 0.04, "volume": 0.15, "decay": 2.0},
	],
	&"mat_flesh": [
		{"wave": "noise", "time": 0.06, "volume": 0.3, "lowpass": 0.7, "decay": 2.4},
		{"wave": "sine", "from": 120.0, "to": 55.0, "time": 0.08, "volume": 0.34, "decay": 2.0},
	],
	&"mat_armor": [
		{"wave": "noise", "time": 0.03, "volume": 0.25, "lowpass": 0.1, "decay": 3.0},
		{"wave": "square", "from": 520.0, "to": 360.0, "time": 0.06, "volume": 0.14, "decay": 2.2},
		{"wave": "sine", "from": 1500.0, "to": 1300.0, "time": 0.08, "volume": 0.1, "decay": 3.0},
	],
	&"mat_metal": [
		{"wave": "noise", "time": 0.02, "volume": 0.22, "lowpass": 0.05, "decay": 3.0},
		{"wave": "sine", "from": 2200.0, "to": 2000.0, "time": 0.14, "volume": 0.16, "decay": 2.6},
		{"wave": "sine", "from": 3300.0, "to": 3100.0, "time": 0.1, "volume": 0.1, "decay": 3.0},
	],
	&"mat_glass": [
		{"wave": "noise", "time": 0.07, "volume": 0.2, "lowpass": 0.0, "decay": 2.4},
		{"wave": "sine", "from": 4200.0, "to": 3600.0, "time": 0.1, "volume": 0.14, "decay": 3.0},
		{"wave": "sine", "from": 5600.0, "to": 5000.0, "time": 0.07, "volume": 0.09, "decay": 3.0},
	],
	&"mat_wood": [
		{"wave": "noise", "time": 0.035, "volume": 0.28, "lowpass": 0.55, "decay": 3.0},
		{"wave": "tri", "from": 260.0, "to": 130.0, "time": 0.06, "volume": 0.26, "decay": 2.2},
	],
	&"mat_concrete": [
		{"wave": "noise", "time": 0.07, "volume": 0.34, "lowpass": 0.45, "decay": 2.6},
		{"wave": "sine", "from": 180.0, "to": 90.0, "time": 0.06, "volume": 0.18, "decay": 2.0},
	],
	&"mat_energy": [
		{"wave": "saw", "from": 1800.0, "to": 600.0, "time": 0.09, "volume": 0.14, "noise": 0.2, "decay": 2.2},
		{"wave": "sine", "from": 900.0, "to": 1500.0, "time": 0.07, "volume": 0.1, "decay": 2.4},
	],
	&"ricochet": [
		{"wave": "sine", "from": 3600.0, "to": 1800.0, "time": 0.16, "volume": 0.16, "decay": 2.2},
		{"wave": "noise", "time": 0.03, "volume": 0.2, "lowpass": 0.0, "decay": 3.0},
	],
	&"hit_weak": [
		{"wave": "sine", "from": 1900.0, "to": 2300.0, "time": 0.1, "volume": 0.18, "decay": 2.4},
		{"wave": "sine", "from": 2850.0, "to": 3300.0, "time": 0.08, "volume": 0.1, "decay": 2.8},
	],
	&"reload_mid": [
		{"wave": "noise", "time": 0.03, "volume": 0.3, "lowpass": 0.15, "decay": 3.0},
		{"wave": "square", "from": 420.0, "to": 300.0, "time": 0.05, "volume": 0.14, "decay": 2.4},
		{"wave": "sine", "from": 150.0, "to": 90.0, "time": 0.06, "volume": 0.2, "decay": 2.0},
	],
	&"guard_break": [
		{"wave": "noise", "time": 0.3, "volume": 0.5, "lowpass": 0.6, "decay": 1.8},
		{"wave": "saw", "from": 900.0, "to": 120.0, "time": 0.26, "volume": 0.24, "noise": 0.3, "decay": 1.6},
		{"wave": "sine", "from": 110.0, "to": 40.0, "time": 0.3, "volume": 0.4, "decay": 1.5},
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
	# 近戰（NE-157）：出手聲與命中聲，沒有音效檔時的合成音。
	&"melee_swing": [
		{"wave": "noise", "time": 0.1, "volume": 0.26, "lowpass": 0.45, "decay": 1.2, "attack": 0.02},
	],
	&"melee_swing_heavy": [
		{"wave": "noise", "time": 0.16, "volume": 0.34, "lowpass": 0.7, "decay": 1.2, "attack": 0.04},
	],
	&"melee_hit": [
		{"wave": "noise", "time": 0.035, "volume": 0.35, "lowpass": 0.1, "decay": 3.0},
		{"wave": "square", "from": 900.0, "to": 600.0, "time": 0.03, "volume": 0.12, "decay": 2.0},
	],
	&"melee_hit_heavy": [
		{"wave": "noise", "time": 0.05, "volume": 0.38, "lowpass": 0.3, "decay": 3.0},
		{"wave": "square", "from": 720.0, "to": 480.0, "time": 0.04, "volume": 0.12, "decay": 2.0},
		{"wave": "sine", "from": 130.0, "to": 70.0, "time": 0.08, "volume": 0.3, "decay": 2.0},
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
	&"crate_break": [
		{"wave": "noise", "time": 0.16, "volume": 0.4, "lowpass": 0.45, "decay": 2.2},
		{"wave": "square", "from": 240.0, "to": 90.0, "time": 0.1, "volume": 0.14, "decay": 2.0},
	],
	&"glass_break": [
		{"wave": "noise", "time": 0.28, "volume": 0.3, "lowpass": 0.05, "decay": 1.6},
		{"wave": "sine", "from": 4200.0, "to": 2600.0, "time": 0.2, "volume": 0.14, "decay": 2.2},
		{"wave": "sine", "from": 3100.0, "to": 5200.0, "time": 0.14, "volume": 0.1, "decay": 2.5},
	],
	&"switch": [
		{"wave": "square", "from": 420.0, "to": 300.0, "time": 0.05, "volume": 0.16, "decay": 2.0},
		{"wave": "noise", "time": 0.04, "volume": 0.18, "lowpass": 0.3, "decay": 3.0},
	],
	&"gate": [
		{"wave": "saw", "from": 90.0, "to": 60.0, "time": 0.45, "volume": 0.2, "lowpass": 0.25, "decay": 1.0, "attack": 0.05},
		{"wave": "noise", "time": 0.4, "volume": 0.18, "lowpass": 0.4, "decay": 1.4},
	],
	&"power_down": [
		{"wave": "saw", "from": 600.0, "to": 40.0, "time": 0.8, "volume": 0.22, "lowpass": 0.3, "decay": 1.0},
		{"wave": "sine", "from": 120.0, "to": 30.0, "time": 0.9, "volume": 0.3, "decay": 1.2},
	],
	&"power_up": [
		{"wave": "saw", "from": 60.0, "to": 520.0, "time": 0.6, "volume": 0.18, "lowpass": 0.3, "decay": 1.2, "attack": 0.1},
		{"wave": "tri", "from": 330.0, "to": 660.0, "time": 0.2, "volume": 0.14, "decay": 1.5},
	],
	&"emp": [
		{"wave": "saw", "from": 120.0, "to": 1800.0, "time": 0.25, "volume": 0.2, "lowpass": 0.4, "decay": 1.2},
		{"wave": "noise", "time": 0.3, "volume": 0.28, "lowpass": 0.7, "decay": 1.6},
		{"wave": "sine", "from": 900.0, "to": 120.0, "time": 0.35, "volume": 0.3, "decay": 1.4},
	],
	&"overclock": [
		{"wave": "saw", "from": 200.0, "to": 900.0, "time": 0.3, "volume": 0.18, "lowpass": 0.5, "decay": 1.1, "attack": 0.05},
		{"wave": "tri", "from": 600.0, "to": 1500.0, "time": 0.2, "volume": 0.16, "decay": 1.4},
	],
	&"ability_ready": [
		{"wave": "tri", "from": 900.0, "to": 1400.0, "time": 0.09, "volume": 0.12, "decay": 1.6},
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
	# 電話亭（NE-121）：拿起話筒、撥號（三種音高）、話筒裡的錄音（占位，之後換成配音）、掛上、來電鈴聲。
	&"phone_pickup": [
		{"wave": "noise", "time": 0.04, "volume": 0.2, "lowpass": 0.35, "decay": 3.0},
		{"wave": "sine", "from": 140.0, "to": 90.0, "time": 0.1, "volume": 0.2, "decay": 2.0},
	],
	&"phone_dial": [
		{"wave": "sine", "from": 697.0, "to": 697.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
		{"wave": "sine", "from": 1209.0, "to": 1209.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
	],
	&"phone_dial2": [
		{"wave": "sine", "from": 770.0, "to": 770.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
		{"wave": "sine", "from": 1336.0, "to": 1336.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
	],
	&"phone_dial3": [
		{"wave": "sine", "from": 852.0, "to": 852.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
		{"wave": "sine", "from": 1477.0, "to": 1477.0, "time": 0.09, "volume": 0.1, "decay": 1.0},
	],
	&"phone_voice": [
		{"wave": "noise", "time": 0.7, "volume": 0.1, "lowpass": 0.78, "decay": 0.6, "attack": 0.1},
		{"wave": "saw", "from": 175.0, "to": 138.0, "time": 0.7, "volume": 0.06, "lowpass": 0.88, "decay": 0.7, "attack": 0.08},
	],
	&"phone_hangup": [
		{"wave": "noise", "time": 0.05, "volume": 0.22, "lowpass": 0.3, "decay": 3.0},
		{"wave": "sine", "from": 220.0, "to": 120.0, "time": 0.08, "volume": 0.18, "decay": 2.0},
	],
	&"phone_ring": [
		{"wave": "sine", "from": 440.0, "to": 440.0, "time": 0.3, "volume": 0.08, "decay": 0.5},
		{"wave": "sine", "from": 480.0, "to": 480.0, "time": 0.3, "volume": 0.08, "decay": 0.5},
	],
	# 第二批敵人（NE-46～48）：探照無人機的嗶聲與警報、狙擊手的雷射閃爍、火焰、機槍旋轉、電擊犬、偽裝箱。
	&"beep": [
		{"wave": "square", "from": 1900.0, "to": 1900.0, "time": 0.05, "volume": 0.11, "decay": 1.2},
	],
	&"alarm": [
		{"wave": "saw", "from": 700.0, "to": 1150.0, "time": 0.28, "volume": 0.16, "lowpass": 0.4, "decay": 0.8},
		{"wave": "saw", "from": 1150.0, "to": 700.0, "time": 0.28, "volume": 0.1, "lowpass": 0.4, "decay": 0.8},
	],
	&"laser_flash": [
		{"wave": "sine", "from": 2600.0, "to": 2200.0, "time": 0.09, "volume": 0.14, "decay": 1.6},
	],
	&"flame": [
		{"wave": "noise", "time": 0.22, "volume": 0.3, "lowpass": 0.6, "decay": 1.2, "attack": 0.03},
		{"wave": "sine", "from": 120.0, "to": 70.0, "time": 0.2, "volume": 0.24, "decay": 1.4},
	],
	&"ignite": [
		{"wave": "noise", "time": 0.1, "volume": 0.2, "lowpass": 0.3, "decay": 2.5},
		{"wave": "square", "from": 500.0, "to": 900.0, "time": 0.08, "volume": 0.08, "decay": 2.0},
	],
	&"spin": [
		{"wave": "saw", "from": 160.0, "to": 420.0, "time": 0.18, "volume": 0.12, "lowpass": 0.6, "decay": 0.9},
	],
	&"vent": [
		{"wave": "noise", "time": 0.5, "volume": 0.26, "lowpass": 0.15, "decay": 1.6, "attack": 0.05},
	],
	&"growl": [
		{"wave": "saw", "from": 90.0, "to": 70.0, "time": 0.32, "volume": 0.24, "lowpass": 0.8, "decay": 1.1, "attack": 0.05},
		{"wave": "noise", "time": 0.3, "volume": 0.12, "lowpass": 0.7, "decay": 1.4},
	],
	&"zap": [
		{"wave": "square", "from": 1800.0, "to": 300.0, "time": 0.12, "volume": 0.16, "noise": 0.5, "decay": 2.0},
		{"wave": "noise", "time": 0.1, "volume": 0.18, "lowpass": 0.1, "decay": 2.5},
	],
	&"rattle": [
		{"wave": "square", "from": 260.0, "to": 200.0, "time": 0.12, "volume": 0.14, "noise": 0.6, "decay": 1.5},
	],
	&"chomp": [
		{"wave": "square", "from": 320.0, "to": 90.0, "time": 0.09, "volume": 0.22, "noise": 0.4, "decay": 2.0},
		{"wave": "noise", "time": 0.07, "volume": 0.22, "lowpass": 0.3, "decay": 3.0},
	],
}

var enabled := true

## 每個 id 的預設串流：音效庫第一個可用的檔案，沒有就是合成音。
var _streams: Dictionary[StringName, AudioStream] = {}
var _bank := SoundBank.new()
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_play_msec: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()
## 每個發聲位的優先級、原本音量與預計結束時間（毫秒），給優先級搶位與壓低其他聲音用。
var _voice_priority: Array[int] = []
var _voice_base_db: Array[float] = []
var _voice_end_msec: Array[int] = []
var _events: Dictionary = {}
var _fallback_sound: StringName = &"hit"
var _last_variant: Dictionary = {}
var _chains: Dictionary = {}
var _duck_db := 0.0
var _duck_until_msec := 0
var _duck_release := 0.2
var _duck_priority := 0
var _reported: Dictionary = {}
## 因發聲位滿載而被丟棄的次數（診斷用）。
var dropped_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_bank.load_bank()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
		_voice_priority.append(0)
		_voice_base_db.append(0.0)
		_voice_end_msec.append(0)
	_build_streams()
	load_events()


## 重新讀取音效庫並重建串流（啟動時與實驗室寫回資料後呼叫）。
func reload_bank(fresh := false) -> void:
	_bank.load_bank(SoundBank.PATH, fresh)
	_build_streams()


func _build_streams() -> void:
	_streams.clear()
	for id: StringName in SOUNDS.keys():
		_streams[id] = _load_or_synthesize(id)
	for id: Variant in _bank.ids():
		var key := StringName(str(id))
		if not _streams.has(key) and _bank.has_files(key):
			_streams[key] = _bank.variants(key)[0]


## 音效庫（唯讀）：實驗室與診斷用。
func bank() -> SoundBank:
	return _bank


## 這個 id 目前的聲音來源：file（音效庫的檔案）、synth（合成音）、missing（兩者都沒有）。
func source_of(id: StringName) -> StringName:
	if _bank.has_files(id):
		return &"file"
	return &"synth" if SOUNDS.has(id) else &"missing"


## 所有已定義音效的 id（合成音與音效庫的聯集）。
func sound_ids() -> Array:
	var ids: Dictionary = {}
	for id: StringName in SOUNDS.keys():
		ids[String(id)] = true
	for id: Variant in _bank.ids():
		ids[str(id)] = true
	var result := ids.keys()
	result.sort()
	return result


## 診斷：用檔案與用合成音的音效各有幾個，以及載入失敗的檔案數。
func source_counts() -> Dictionary:
	var counts := {"file": 0, "synth": 0, "failed": 0}
	for id: String in sound_ids():
		counts[String(source_of(StringName(id)))] = int(counts.get(String(source_of(StringName(id))), 0)) + 1
	for id: Variant in _bank.failed_files():
		counts["failed"] += (_bank.failed_files()[id] as PackedStringArray).size()
	return counts


## 停止所有播放中的音效（切換場景或結束遊戲時呼叫，避免播放實例殘留）。
func stop_all() -> void:
	for player in _players:
		player.stop()
		player.stream = null


func _exit_tree() -> void:
	stop_all()


## 是否有這個音效（資料檔引用音效時檢查用）。
func has_sound(id: StringName) -> bool:
	return SOUNDS.has(id) or _bank.has_files(id)


func play(id: StringName, volume_db := 0.0, pitch_jitter := 0.06, priority := 0, pitch_scale := 1.0) -> void:
	_play_voice(id, volume_db, pitch_scale * (1.0 + randf_range(-pitch_jitter, pitch_jitter)), priority)


## 依名稱播放：是聲音事件就播事件，否則當成單一音效；資料檔（武器、角色）引用的名稱用這個。空名稱什麼都不做。
func play_named(id: StringName, volume_db := 0.0) -> void:
	if id == &"":
		return
	if has_event(id):
		play_event(id, {"volume_db": volume_db})
	else:
		play(id, volume_db)


## 資料檔引用的名稱是否存在（事件或音效）。
func has_named(id: StringName) -> bool:
	return id == &"" or has_event(id) or has_sound(id)


## 播一個發聲位；回傳是否真的播放。滿載時只搶優先級不高於自己的聲音，沒有可搶的就丟棄。
func _play_voice(id: StringName, volume_db: float, pitch: float, priority: int) -> bool:
	if not enabled:
		return false
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		_report_once("sound:" + String(id), "[Sfx] 未定義的音效：%s" % id, false)
		return false
	if _bank.has_files(id):
		var variants := _bank.variants(id)
		stream = variants[_pick_variant("file:" + String(id), variants.size())]
		volume_db += _bank.volume_db(id)
		var pitch_range := _bank.pitch_range(id)
		if pitch_range != Vector2.ONE:
			pitch *= _random_between(pitch_range.x, pitch_range.y)
	var now := Time.get_ticks_msec()
	if now - int(_last_play_msec.get(id, -1000)) < MIN_INTERVAL_MSEC:
		return false
	var index := _acquire_voice(priority, now)
	if index < 0:
		dropped_count += 1
		return false
	_last_play_msec[id] = now
	var player := _players[index]
	player.stream = stream
	_voice_priority[index] = priority
	_voice_base_db[index] = volume_db
	_voice_end_msec[index] = now + int(stream.get_length() * 1000.0 / maxf(0.1, pitch))
	player.volume_db = volume_db + (_duck_db if now < _duck_until_msec and priority < _duck_priority else 0.0)
	player.pitch_scale = pitch
	player.play()
	return true


## 找發聲位：先找空的；全滿時搶優先級不高於自己、最快播完的那一個；都比自己高就回傳 -1。
func _acquire_voice(priority: int, now: int) -> int:
	var best := -1
	for step in _players.size():
		var i := (_next_voice + step) % _players.size()
		if not _players[i].playing or now >= _voice_end_msec[i]:
			_next_voice = (i + 1) % _players.size()
			return i
		if _voice_priority[i] <= priority and (best < 0 or _voice_end_msec[i] < _voice_end_msec[best]):
			best = i
	return best


func voices_playing() -> int:
	var count := 0
	var now := Time.get_ticks_msec()
	for i in _players.size():
		if _players[i].playing and now < _voice_end_msec[i]:
			count += 1
	return count


# ---------------------------------------------------------------------------
# 聲音事件（data/feel/sound_events.json）：多層、變體輪播、音高範圍、連鎖升音、壓低其他聲音、優先級
# ---------------------------------------------------------------------------

const EVENTS_PATH := "res://data/feel/sound_events.json"


func load_events() -> void:
	_events = {}
	var json: JSON = load(EVENTS_PATH) as JSON if ResourceLoader.exists(EVENTS_PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY or typeof((json.data as Dictionary).get("events")) != TYPE_DICTIONARY:
		_report_once("events", "[Sfx] 無法讀取聲音事件資料：%s（需要 events 字典）" % EVENTS_PATH)
		return
	_events = (json.data as Dictionary)["events"]
	_fallback_sound = StringName(str((json.data as Dictionary).get("fallback_sound", "hit")))


func has_event(id: StringName) -> bool:
	return _events.has(String(id))


func event_ids() -> Array:
	return _events.keys()


## 資料檢查：回傳錯誤訊息清單（空 = 沒問題）。
func validate_events() -> PackedStringArray:
	var errors := PackedStringArray()
	if not has_sound(_fallback_sound):
		errors.append("%s 的 fallback_sound「%s」不存在" % [EVENTS_PATH, _fallback_sound])
	for id: String in _events.keys():
		var def: Variant = _events[id]
		var layers: Variant = (def as Dictionary).get("layers") if typeof(def) == TYPE_DICTIONARY else null
		if typeof(layers) != TYPE_ARRAY or (layers as Array).is_empty():
			errors.append("%s 的事件「%s」沒有 layers" % [EVENTS_PATH, id])
			continue
		for n in (layers as Array).size():
			var layer: Variant = (layers as Array)[n]
			var variants: Variant = (layer as Dictionary).get("sounds") if typeof(layer) == TYPE_DICTIONARY else null
			if typeof(variants) != TYPE_ARRAY or (variants as Array).is_empty():
				errors.append("%s 的事件「%s」第 %d 層沒有 sounds" % [EVENTS_PATH, id, n + 1])
				continue
			for sound: Variant in variants:
				if not has_sound(StringName(str(sound))):
					errors.append("%s 的事件「%s」第 %d 層引用不存在的音效「%s」" % [EVENTS_PATH, id, n + 1, sound])
			var pitch: Variant = (layer as Dictionary).get("pitch", [1.0, 1.0])
			if typeof(pitch) != TYPE_ARRAY or (pitch as Array).size() != 2 or float(pitch[0]) > float(pitch[1]) or float(pitch[0]) <= 0.0:
				errors.append("%s 的事件「%s」第 %d 層的 pitch 要是 [最小, 最大]，且大於 0" % [EVENTS_PATH, id, n + 1])
	return errors


## 播放聲音事件。ctx：volume_db（整體增減）。事件不存在時記錄一次錯誤並播 fallback 音效。
func play_event(id: StringName, ctx: Dictionary = {}) -> void:
	var def: Variant = _events.get(String(id))
	if typeof(def) != TYPE_DICTIONARY or typeof((def as Dictionary).get("layers")) != TYPE_ARRAY:
		_report_once("event:" + String(id), "[Sfx] 沒有這個聲音事件「%s」（%s），改播「%s」" % [id, EVENTS_PATH, _fallback_sound])
		play(_fallback_sound)
		return
	var d := def as Dictionary
	Feel.record("聲音", String(id))
	FeelRecord.capture("sound", String(id))
	var priority := int(d.get("priority", 0))
	var now := Time.get_ticks_msec()
	var chain_pitch := _chain_pitch(String(id), d.get("chain"), now)
	var base_db := float(ctx.get("volume_db", 0.0)) + float(d.get("volume_db", 0.0))
	var played := false
	for n in (d["layers"] as Array).size():
		var layer: Dictionary = (d["layers"] as Array)[n]
		var variants: Array = layer.get("sounds", [])
		if variants.is_empty():
			continue
		var pick := _pick_variant("%s:%d" % [id, n], variants.size())
		var pitch_range: Array = layer.get("pitch", [1.0, 1.0])
		var pitch := _random_between(float(pitch_range[0]), float(pitch_range[1])) * chain_pitch
		var volume := base_db + float(layer.get("volume_db", 0.0))
		var delay := float(layer.get("delay", 0.0))
		var sound := StringName(str(variants[pick]))
		if delay > 0.0:
			get_tree().create_timer(delay, true, false, true).timeout.connect(_play_voice.bind(sound, volume, pitch, priority))
		else:
			played = _play_voice(sound, volume, pitch, priority) or played
	var duck: Variant = d.get("duck")
	if played and typeof(duck) == TYPE_DICTIONARY:
		_start_duck(float((duck as Dictionary).get("db", -6.0)), float((duck as Dictionary).get("time", 0.15)), priority, now)


func _random_between(low: float, high: float) -> float:
	return low if is_equal_approx(low, high) else randf_range(low, high)


## 變體輪播：有兩個以上變體時，不連續播同一個。
func _pick_variant(key: String, count: int) -> int:
	if count <= 1:
		_last_variant[key] = 0
		return 0
	var pick := randi() % count
	if pick == int(_last_variant.get(key, -1)):
		pick = (pick + 1 + randi() % (count - 1)) % count
	_last_variant[key] = pick
	return pick


## 連鎖升音：視窗內連續觸發同一事件，每次升 step 個半音，最多 max 次。
func _chain_pitch(key: String, chain: Variant, now: int) -> float:
	if typeof(chain) != TYPE_DICTIONARY:
		return 1.0
	var c := chain as Dictionary
	var entry: Array = _chains.get(key, [0, -100000])
	var count := int(entry[0]) + 1 if float(now - int(entry[1])) <= float(c.get("window", 0.6)) * 1000.0 else 0
	count = mini(count, int(c.get("max", 5)))
	_chains[key] = [count, now]
	return pow(2.0, float(c.get("step", 1.0)) * float(count) / 12.0)


## 壓低優先級低於這個事件的其他聲音：db 是深度、time 是持續秒數，結束後平滑回復。
func _start_duck(db: float, time: float, priority: int, now: int) -> void:
	_duck_db = minf(_duck_db, db) if now < _duck_until_msec else db
	_duck_until_msec = now + int(time * 1000.0)
	_duck_release = maxf(0.05, time * 0.5)
	_duck_priority = priority
	for i in _players.size():
		if _players[i].playing and _voice_priority[i] < priority:
			_players[i].volume_db = _voice_base_db[i] + _duck_db


func _process(delta: float) -> void:
	if _duck_db == 0.0 or Time.get_ticks_msec() < _duck_until_msec:
		return
	_duck_db = move_toward(_duck_db, 0.0, absf(_duck_db) / _duck_release * delta)
	for i in _players.size():
		if _players[i].playing and _voice_priority[i] < _duck_priority:
			_players[i].volume_db = _voice_base_db[i] + _duck_db


func _report_once(key: String, message: String, as_error := true) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	if as_error:
		push_error(message)
	else:
		push_warning(message)


func _load_or_synthesize(id: StringName) -> AudioStream:
	if _bank.has_files(id):
		return _bank.variants(id)[0]
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
