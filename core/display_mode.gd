class_name DisplayMode
extends RefCounted
## 視窗模式與畫面縮放的共用工具：全螢幕開關，以及「遊戲畫面等比放到視窗放得下的最大尺寸」的縮放設定。
## 只有視窗比例和遊戲畫面比例不同時才會留黑邊。

const DESIGN_SIZE := Vector2i(640, 360)


## 無頭模式（測試、伺服器）沒有真的視窗，不去動視窗。
static func has_window() -> bool:
	return DisplayServer.get_name() != "headless"


static func is_fullscreen(window: Window) -> bool:
	return window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN


static func set_fullscreen(window: Window, enabled: bool) -> void:
	if not has_window() or is_fullscreen(window) == enabled:
		return
	window.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED


## 把視窗的內容縮放設為專案設定的樣子：以 640×360 為基準、等比放大填滿視窗。
## 其他工具（例如實驗室）暫時改過縮放後，遊戲啟動與切換全螢幕時用這個還原。
static func ensure_scaling(window: Window) -> void:
	window.content_scale_size = DESIGN_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
