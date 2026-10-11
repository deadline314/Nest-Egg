class_name IconPlate
extends Control
## 詳情面板的大圖示：暗色底板、四角標記、淡淡的光暈，圖示每半拍上下浮動 1 像素（逐像素、不模糊）。

const PLATE_SIZE := Vector2(132, 104)
## 高解析圖示在預設底板裡的邊長；底板變小時等比縮小。
const HD_EDGE := 96.0
const BOB_SPEED := 3.0

var icon: Texture2D
var icon_scale := 3
var accent := Palette.CYAN
var dimmed := false
var high_resolution := false
## 底板大小（背包詳情用較小的底板，見 DetailPanel）。在加入場景樹前設定。
var plate_size := PLATE_SIZE

var _time := 0.0


func _ready() -> void:
	custom_minimum_size = plate_size
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_icon(p_icon: Texture2D, p_scale: int, p_accent: Color, p_dimmed: bool, p_high_resolution := false) -> void:
	icon = p_icon
	icon_scale = p_scale
	accent = p_accent
	dimmed = p_dimmed
	high_resolution = p_high_resolution
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if high_resolution else CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	PixelUi.frame(self, Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.95), Color(accent, 0.5), 4, 1)
	var center := size * 0.5
	var ratio := minf(size.x / PLATE_SIZE.x, size.y / PLATE_SIZE.y)
	draw_circle(center, 44.0 * ratio, Color(accent, 0.07))
	draw_circle(center, 30.0 * ratio, Color(accent, 0.07))
	# 四角的標記。
	var corner := Color(accent, 0.9)
	for sx in [6.0, size.x - 6.0]:
		for sy in [6.0, size.y - 6.0]:
			var dx := 4.0 if sx < size.x * 0.5 else -4.0
			var dy := 4.0 if sy < size.y * 0.5 else -4.0
			draw_line(Vector2(sx, sy), Vector2(sx + dx, sy), corner, 1.0)
			draw_line(Vector2(sx, sy), Vector2(sx, sy + dy), corner, 1.0)
	if icon == null:
		return
	var icon_size := display_size()
	var bob := floorf(sin(_time * BOB_SPEED) + 0.5)
	var origin := (center - icon_size * 0.5 + Vector2(0, bob)).floor()
	draw_texture_rect(icon, Rect2(origin, icon_size), false, Color(1, 1, 1, 0.4 if dimmed else 1.0))


func display_size() -> Vector2:
	if icon == null:
		return Vector2.ZERO
	var source := Vector2(icon.get_size())
	var ratio := minf(plate_size.x / PLATE_SIZE.x, plate_size.y / PLATE_SIZE.y)
	if high_resolution:
		return source * (HD_EDGE * ratio / maxf(source.x, source.y))
	# 像素圖示維持整數倍（不糊）；底板變小時降倍率，至少 1 倍。
	var room := plate_size - Vector2(8, 8)
	var fit := floori(minf(room.x / maxf(1.0, source.x), room.y / maxf(1.0, source.y)))
	return source * float(clampi(fit, 1, icon_scale))
