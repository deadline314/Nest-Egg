class_name SidePortrait
extends Control
## 背包右側陪伴閱讀的角色立繪（NE-244）：靜態高解析圖，腳底貼齊下緣、依可用高度等比縮放，
## 後方一道冷青背光、腳下一條接觸影。只在背包開著時持有貼圖，關閉就放掉，開關多次也只有一份。
## 圖缺少或讀不到時記錄路徑並留白，不影響清單與操作。

const DEFAULT_TEXTURE := "res://art/portraits/rin_inventory.png"
## 背光與接觸影（HDR 2D 在線性色彩混色，透明度要比感覺低）。背光是放射漸層，中心最亮、往外淡到透明。
const GLOW := Color(0.25, 0.85, 0.95, 0.22)
const SHADOW := Color(0.0, 0.0, 0.0, 0.45)
## 背光相對立繪的大小（寬、高倍率）與中心高度（從頭頂算起的比例）。
const GLOW_SCALE := Vector2(1.5, 0.9)
const GLOW_CENTER := 0.42

static var _glow: GradientTexture2D

var texture_path := DEFAULT_TEXTURE

var _texture: Texture2D
var _reported := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)
	if _glow == null:
		# 共用一張 64×64 的小漸層，所有背包畫面都畫同一張。
		var gradient := Gradient.new()
		gradient.set_color(0, GLOW)
		gradient.set_color(1, Color(GLOW, 0.0))
		gradient.add_point(0.55, Color(GLOW, GLOW.a * 0.35))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64


## 背包開啟時呼叫。重複呼叫不會多讀一份。
func acquire() -> void:
	if _texture != null:
		return
	if ResourceLoader.exists(texture_path):
		_texture = load(texture_path) as Texture2D
	if _texture == null and not _reported:
		_reported = true
		push_error("[SidePortrait] 讀不到背包立繪 %s，右側留白。" % texture_path)
	queue_redraw()


## 背包關閉時呼叫：放掉貼圖，下次開啟再讀（引擎的資源快取讓重開不必重新解碼）。
func release() -> void:
	_texture = null
	queue_redraw()


func has_texture() -> bool:
	return _texture != null


## 立繪實際畫在哪裡（控制項座標）；測試用它確認不壓到文字與按鈕。
func drawn_rect() -> Rect2:
	if _texture == null or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var source := Vector2(_texture.get_size())
	var scale := minf(size.x / source.x, size.y / source.y)
	var drawn := source * scale
	return Rect2(Vector2((size.x - drawn.x) * 0.5, size.y - drawn.y), drawn)


func _draw() -> void:
	var rect := drawn_rect()
	if not rect.has_area():
		return
	var center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * GLOW_CENTER)
	var glow_size := Vector2(rect.size.x * GLOW_SCALE.x * 1.4, rect.size.y * GLOW_SCALE.y)
	draw_texture_rect(_glow, Rect2(center - glow_size * 0.5, glow_size), false)
	draw_set_transform(Vector2(rect.get_center().x, rect.end.y - 2.0), 0.0, Vector2(1.0, 0.18))
	draw_circle(Vector2.ZERO, rect.size.x * 0.42, SHADOW)
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(_texture, rect, false)
