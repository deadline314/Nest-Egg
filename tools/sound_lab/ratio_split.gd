class_name SoundLabRatioSplit
extends SplitContainer
## 兩格的可拖動分隔，用「前一格佔的比例」而不是像素記錄位置：視窗放大時兩邊的內容區一起變大（清單多顯示列數），
## 比例交給 SoundLabLayout 存檔，下次開啟還原。兩個子節點都要在分隔方向上 EXPAND_FILL。

## 使用者拖動後的新比例。
signal ratio_changed(ratio: float)

var ratio := 0.5
var _layout: SoundLabLayout
var _key := ""


## 綁定存檔：key 是這個分隔在設定檔裡的名字；tip 是滑鼠停在分隔線上的說明。
func setup(layout: SoundLabLayout, key: String, default_ratio: float, tip: String) -> void:
	_layout = layout
	_key = key
	ratio = layout.ratio(key, default_ratio) if layout != null else default_ratio
	tooltip_text = tip
	dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	dragged.connect(_on_dragged)
	resized.connect(_apply_ratio_deferred)
	child_order_changed.connect(_apply_ratio_deferred)
	_apply_ratio_deferred()


## 改比例並立刻套用（測試與還原用）。
func set_ratio(value: float) -> void:
	ratio = clampf(value, SoundLabLayout.MIN_RATIO, SoundLabLayout.MAX_RATIO)
	_apply_ratio()


## 可分配給兩格的長度（扣掉分隔線本身）。
func _available() -> float:
	var length := size.y if vertical else size.x
	return length - get_theme_constant(&"separation")


func _apply_ratio_deferred() -> void:
	_apply_ratio.call_deferred()


func _apply_ratio() -> void:
	var available := _available()
	if available <= 0.0 or get_child_count() < 2:
		return
	# 兩格 EXPAND_FILL 時預設各佔一半；偏移量 = 想要的前一格長度 - 一半。
	split_offset = roundi((ratio - 0.5) * available)


func _on_dragged(offset: int) -> void:
	var available := _available()
	if available <= 0.0:
		return
	ratio = clampf(0.5 + float(offset) / available, SoundLabLayout.MIN_RATIO, SoundLabLayout.MAX_RATIO)
	if _layout != null and not _key.is_empty():
		_layout.set_ratio(_key, ratio)
	ratio_changed.emit(ratio)
