class_name ItemCard
extends Control
## 背包清單中的一張卡片：像一張當票（右邊是撕線的鋸齒、左邊是印著編號的米白票根與打孔線），圖示、名稱、第二行、右上角斜蓋的橡皮章。
## 拼貼版面（NE-403、NE-412）：待機時外框微微傾斜（每張方向交錯），選到時轉正、浮起往前、投影拉開並掃過一道光，之後很慢地呼吸；
## 空欄位是淡的虛線空白票。文字與圖示永遠水平。資料更新時閃一下。動畫只在進行中（或選到後的呼吸）才會逐格重繪，看不到時停止。
## 點擊範圍跟著畫面上的當票形狀。「減少動態」時直接到位、不呼吸。

signal hovered(card: ItemCard)
signal activated(card: ItemCard)

const CARD_SIZE := Vector2(232, 44)
const ICON_CELL := Vector2(68, 36)
const LIFT := 2.0
const SHINE_TIME := 0.45
const FLASH_TIME := 0.3
const FILL := Color(0.05, 0.08, 0.12, 0.94)
const FILL_SELECTED := Color(0.08, 0.15, 0.2, 0.97)
## 待機時的傾斜（度，依序交錯）、選到時放大多少、呼吸的週期與幅度、撕線鋸齒的大小。
const TILTS: Array[float] = [-1.4, 1.1, -0.9, 1.5, -1.2, 0.9]
const ACTIVE_SCALE := 0.02
const BREATH_PERIOD := 2.8
const BREATH_SCALE := 0.008
const TOOTH := 3.0
const FRAME_INSET := 3.0
## 左邊米白票根的寬度、徽章橡皮章的傾斜（度）。
const STUB := 14.0
const STAMP_TILT := -8.0

var entry: InventoryEntry
var index := 0
var selected := false:
	set(value):
		if value == selected:
			return
		selected = value
		_animate_selection()

var _lift := 0.0
var _shine := -1.0
var _flash := 0.0
var _tween: Tween
var _breath_time := 0.0


func _ready() -> void:
	add_to_group(UiKit.TEXT_GROUP)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit(self))
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func setup(p_entry: InventoryEntry, p_index: int) -> void:
	entry = p_entry
	index = p_index
	tooltip_text = entry.hint
	queue_redraw()


## 資料更新後閃一下（例如使用消耗品後數量改變）。
func flash() -> void:
	if Settings.get_reduce_ui_motion() or Settings.get_reduce_flashes():
		return
	_flash = 1.0
	set_process(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(self)
		accept_event()


func _process(delta: float) -> void:
	if Settings.get_reduce_ui_motion():
		_lift = 1.0 if selected else 0.0
		_shine = -1.0
		_flash = 0.0
		_breath_time = 0.0
		set_process(false)
		queue_redraw()
		return
	if not is_visible_in_tree():
		set_process(false)
		return
	# 選到之後很慢地呼吸（只有這張卡在重畫；看不到或沒選到就停）。
	var busy := selected
	if selected:
		_breath_time += delta
	var target_lift := 1.0 if selected else 0.0
	if not is_equal_approx(_lift, target_lift):
		_lift = move_toward(_lift, target_lift, delta / 0.1)
		busy = true
	if _shine >= 0.0:
		_shine += delta / SHINE_TIME
		busy = true
		if _shine > 1.0:
			_shine = -1.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_TIME)
		busy = busy or _flash > 0.0
	queue_redraw()
	if not busy:
		set_process(false)


func _animate_selection() -> void:
	if Settings.get_reduce_ui_motion():
		_lift = 1.0 if selected else 0.0
		_shine = -1.0
		queue_redraw()
		return
	if selected:
		_shine = 0.0
		_breath_time = 0.0
	set_process(true)


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and (selected or not is_equal_approx(_lift, 0.0)):
		set_process(true)


## 現在畫面上外框的傾斜（弧度）：待機傾斜，選到轉正。
func current_tilt() -> float:
	return deg_to_rad(TILTS[index % TILTS.size()]) * (1.0 - _lift)


## 畫面上當票外框的形狀（本地座標），繪製與點擊判斷共用。
func frame_points() -> PackedVector2Array:
	var lift := roundf(_lift * LIFT)
	var rect := Rect2(Vector2(0, LIFT - lift), CARD_SIZE - Vector2(0, LIFT))
	var breath := sin(_breath_time * TAU / BREATH_PERIOD) * BREATH_SCALE if selected and not Settings.get_reduce_ui_motion() else 0.0
	var grow := 1.0 + ACTIVE_SCALE * _lift + breath
	# 外框留 FRAME_INSET 的邊：放大與傾斜之後仍在卡片範圍裡（清單會裁掉超出去的部分）。
	rect = rect.grow(-FRAME_INSET)
	var center := rect.get_center()
	rect = Rect2(center - rect.size * 0.5 * grow, rect.size * grow)
	return CollageShapes.rotated(CollageShapes.ticket_polygon(rect, TOOTH), center, current_tilt())


func _has_point(point: Vector2) -> bool:
	return CollageShapes.contains(frame_points(), point)


func _draw() -> void:
	if entry == null:
		return
	var lift := roundf(_lift * LIFT)
	var accent := entry.accent
	var dim := 0.45 if entry.dimmed else 1.0
	var border := accent if selected else Color(accent, 0.35 * dim)
	var rect := Rect2(Vector2(0, LIFT - lift), CARD_SIZE - Vector2(0, LIFT))
	var points := frame_points()
	if entry.dimmed:
		# 空欄位：淡的虛線空白票（沒有實色票根）；選到時虛線換成項目顏色。
		draw_colored_polygon(points, Color(FILL, 0.35))
		_draw_dashed_outline(points, accent if selected else Color(Palette.UI_MUTED, 0.45))
		_draw_stub(points, true)
	else:
		if _lift > 0.0:
			# 浮起來的投影（跟著浮起的程度變深、往右下拉開）。
			var shadow := points.duplicate()
			for i in shadow.size():
				shadow[i] += Vector2(2.0, 2.0) * _lift
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.5 * _lift))
		CollageShapes.draw_shape(self, points, FILL_SELECTED if selected else FILL, border, 2.0 if selected else 1.0)
		_draw_stub(points, false)
	var icon_origin := rect.position + Vector2(STUB + 4.0, 0) + (ICON_CELL - _icon_size()) * 0.5
	if entry.icon != null:
		PixelUi.texture(self, entry.icon, icon_origin.floor(), entry.card_icon_scale, Color(1, 1, 1, dim))
	var font := UiKit.font()
	var text_x := rect.position.x + STUB + 4.0 + ICON_CELL.x + 4.0
	# 標題讓出右上角徽章的位置；放不下時用省略號結尾（英文名稱較長，不能壓到 NEW）。
	var badge_right := CARD_SIZE.x - (26.0 if entry.ammo_icon != null else 8.0)
	var title_right := CARD_SIZE.x - 8.0
	if not entry.badge.is_empty():
		var badge_size := UiKit.scaled_size(9)
		title_right = badge_right - (font.get_string_size(entry.badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size).x + 8.0) - 4.0
	var title_size := UiKit.scaled_size(12)
	draw_string(font, Vector2(text_x, rect.position.y + 19.0), fit_text(font, entry.title, title_right - text_x, title_size), HORIZONTAL_ALIGNMENT_LEFT,
			-1, title_size, Color(accent, dim) if selected else Color(Palette.UI_TEXT, dim))
	draw_string(font, Vector2(text_x, rect.position.y + 34.0), entry.subtitle, HORIZONTAL_ALIGNMENT_LEFT,
			CARD_SIZE.x - text_x - 8.0, UiKit.scaled_size(10), Color(Palette.UI_MUTED, dim))
	if entry.ammo_icon != null:
		var ammo_rect := Rect2(rect.position + Vector2(CARD_SIZE.x - 22.0, CARD_SIZE.y - 26.0), AmmoIcons.CELL * 1.3)
		draw_texture_rect(entry.ammo_icon, ammo_rect, false, Color(1, 1, 1, dim))
	if not entry.badge.is_empty():
		# 有彈種圖示時徽章讓到圖示左邊，兩者不重疊（放大文字時徽章會變高）。
		_draw_stamp(rect.position + Vector2(badge_right, 6.0), entry.badge, entry.badge_color)
	if _shine >= 0.0:
		_draw_shine(rect)
	if _flash > 0.0:
		draw_rect(rect.grow(-2), Color(1, 1, 1, 0.3 * _flash))


## 左邊的米白票根：跟著外框傾斜，右緣一條打孔線、上方一個打孔、印著編號（數字保持水平）。空欄位只畫虛線。
func _draw_stub(points: PackedVector2Array, blank: bool) -> void:
	var top_left := points[0]
	var bottom_left := points[points.size() - 1]
	var along := (points[1] - points[0]).normalized()
	var stub := PackedVector2Array([top_left, top_left + along * STUB, bottom_left + along * STUB, bottom_left])
	var down := bottom_left - top_left
	var font := UiKit.font()
	var number := "%02d" % (index + 1)
	var size_px := UiKit.scaled_size(8)
	var width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var center := (top_left + bottom_left) * 0.5 + along * STUB * 0.5
	if blank:
		draw_dashed_line(top_left + along * STUB, bottom_left + along * STUB, Color(Palette.UI_MUTED, 0.35), 1.0, 2.0)
		draw_string(font, center + Vector2(-width * 0.5, size_px * 0.9), number, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(Palette.UI_MUTED, 0.7))
		return
	draw_colored_polygon(stub, TagButton.PAPER.lerp(Color("fbf6e8"), _lift))
	var t := 0.12
	while t < 0.92:
		var from := top_left + along * STUB + down * t
		draw_line(from, from + down * 0.05, Color(TagButton.INK, 0.5), 1.0)
		t += 0.12
	draw_circle(center - down * 0.22, 2.0, Color(FILL, 0.95))
	draw_string(font, center + Vector2(-width * 0.5, size_px * 0.9), number, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, TagButton.INK)


## 虛線外框（空欄位）。
func _draw_dashed_outline(points: PackedVector2Array, color: Color) -> void:
	for i in points.size():
		draw_dashed_line(points[i], points[(i + 1) % points.size()], color, 1.0, 3.0)


## 斜蓋的橡皮章（例如「手上」）：雙線外框、字跟著章斜；右上角對齊 right_top。
func _draw_stamp(right_top: Vector2, text: String, color: Color) -> void:
	var font := UiKit.font()
	var size_px := UiKit.scaled_size(9)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var box := Vector2(text_size.x + 10.0, text_size.y + 4.0)
	var center := right_top + Vector2(-box.x * 0.5, box.y * 0.5)
	draw_set_transform(center, deg_to_rad(STAMP_TILT))
	var rect := Rect2(-box * 0.5, box)
	var outer := CollageShapes.tag_polygon(rect, 2.0)
	CollageShapes.draw_shape(self, outer, Color(color, 0.14), Color(color, 0.95), 1.5)
	CollageShapes.draw_shape(self, CollageShapes.tag_polygon(rect.grow(-2.5), 1.0), Color(0, 0, 0, 0), Color(color, 0.5), 1.0)
	draw_string(font, Vector2(-text_size.x * 0.5, -text_size.y * 0.5 + font.get_ascent(size_px)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## 斜向的像素光澤：每兩列一段，由左掃到右。
func _draw_shine(rect: Rect2) -> void:
	var sweep := lerpf(-30.0, rect.size.x + 30.0, _shine)
	var alpha := 0.22 * sin(_shine * PI)
	var y := 3.0
	while y < rect.size.y - 3.0:
		var x := clampf(sweep + y * 0.9, 4.0, rect.size.x - 4.0)
		var x_end := clampf(sweep + y * 0.9 + 14.0, 4.0, rect.size.x - 4.0)
		if x_end > x:
			draw_rect(Rect2(rect.position + Vector2(x, y), Vector2(x_end - x, 2)), Color(1, 1, 1, alpha))
		y += 2.0


func _icon_size() -> Vector2:
	return Vector2(entry.icon.get_size()) * float(entry.card_icon_scale) if entry.icon != null else Vector2.ZERO


## 文字超過寬度時從尾端截短並加上省略號（只在重畫時算，不每格配置）。
static func fit_text(font: Font, text: String, width: float, font_size: int) -> String:
	if width <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var keep := text.length()
	while keep > 1 and font.get_string_size(text.left(keep) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		keep -= 1
	return text.left(keep).strip_edges() + "…"

