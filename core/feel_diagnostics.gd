class_name FeelDiagnostics
extends Label
## 手感診斷面板（NE-149）：時間（頓幀預算、凍結數、慢動作）、鏡頭、粒子、聲音、閃光、效能與最近事件時間軸。
## 每 0.1 秒更新一次（每秒約 10 次）；重複使用同一個計數字典與同一個字串緩衝，數字沒變就不重設文字。
## 各系統用 Feel.register_counter 註冊自己的計數器，這裡不需要知道它們。

const UPDATE_INTERVAL := 0.1
## 計數顯示順序與標籤（沒列在這裡的計數會接在後面）。
const ORDER: PackedStringArray = ["fps", "frame_ms", "hitstop_budget_left", "frozen_nodes", "slowmo_active", "camera_shake_px", "camera_zoom", "input_latency_ms", "input_latency_avg_ms", "particles", "voices_playing", "sounds_dropped", "flash_per_second", "flash_peak", "flash_dropped"]

var updates := 0
var _counters: Dictionary = {}
var _left := 0.0
var _last_text := ""
var _lines := PackedStringArray()


func _ready() -> void:
	add_theme_font_size_override(&"font_size", 6)
	add_theme_color_override(&"font_color", Palette.UI_MUTED)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = UPDATE_INTERVAL
	refresh()


## 立刻重算一次文字（測試與手動刷新用）。
func refresh() -> void:
	updates += 1
	Feel.read_counters_into(_counters)
	_lines.clear()
	for key in ORDER:
		if _counters.has(key):
			_lines.append("%s: %s" % [key, _counters[key]])
	for key: String in _counters.keys():
		if not ORDER.has(key):
			_lines.append("%s: %s" % [key, _counters[key]])
	var warning := FlashGuard.warning()
	if warning != "":
		_lines.append("警示：" + warning)
	_lines.append("— 最近事件 —")
	_lines.append_array(Feel.recent)
	var text := "\n".join(_lines)
	if text != _last_text:
		_last_text = text
		self.text = text


## 暫時顯示一段訊息（例如儲存預覽），seconds 秒後恢復診斷數字。
func show_message(message: String, seconds: float) -> void:
	_last_text = message
	text = message
	_left = seconds
