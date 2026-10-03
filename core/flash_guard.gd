class_name FlashGuard
extends RefCounted
## 閃光防護（NE-146）：全螢幕閃光的峰值亮度上限，以及「每秒明暗交替不超過三次」。
## 超過頻率的閃光直接丟棄；「減少閃光」會把強度再降到 25%。診斷數字（目前頻率、峰值、丟棄次數）給實驗室讀。

const MAX_AMOUNT := 0.3
const MAX_PER_SECOND := 3
const WINDOW_MSEC := 1000

static var _starts: Array[int] = []
static var peak := 0.0
static var dropped := 0
static var accepted := 0


## 申請一次全螢幕閃光：回傳實際可用的強度（0 = 被丟棄）。
static func request(amount: float, now_msec: int = Time.get_ticks_msec()) -> float:
	while not _starts.is_empty() and now_msec - _starts[0] > WINDOW_MSEC:
		_starts.pop_front()
	if _starts.size() >= MAX_PER_SECOND:
		dropped += 1
		return 0.0
	var granted := minf(amount, MAX_AMOUNT) * Settings.flash_scale()
	if granted <= 0.0:
		return 0.0
	_starts.append(now_msec)
	accepted += 1
	peak = maxf(peak, granted)
	return granted


## 最近一秒內的閃光次數。
static func rate(now_msec: int = Time.get_ticks_msec()) -> int:
	var count := 0
	for start in _starts:
		if now_msec - start <= WINDOW_MSEC:
			count += 1
	return count


## 超標警示：頻率達到上限（再來的會被丟棄），或峰值貼著上限。
static func warning() -> String:
	if rate() >= MAX_PER_SECOND:
		return "閃光頻率達上限（每秒 %d 次），之後的閃光會被略過" % MAX_PER_SECOND
	return ""


static func reset() -> void:
	_starts.clear()
	peak = 0.0
	dropped = 0
	accepted = 0
