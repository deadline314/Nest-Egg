class_name ContrastProbe
extends RefCounted
## 開發工具共用：從目前畫面量測角色（玩家、敵人）的輪廓對比。暗場可讀性量測（readability_check）與
## 光影預設場景量測（lighting_scene_check）共用同一套算法與門檻，兩邊的數字才能互相對照。
## 對比 = (內 − 外) / (外 + 0.02)：身體範圍的亮部（第 90 百分位）比周圍一圈亮，或身體比周圍暗（剪影），取較大者。
## 剪影：背景夠亮（白天、室內白牆）時，角色瘦長、只占量測框的一部分，用中位數量到的會是背景，所以改量身體的暗部（第 25 百分位）；
## 背景很暗時分母趨近 0，黑對近黑會被放大成高對比，所以維持用中位數。

## 門檻。敵人的門檻是「不得更差」的防線（BG-13）；要再提高得靠敵人本身的美術。
const MIN_PLAYER_CONTRAST := 0.6
const MIN_EDGE_CONTRAST := 1.0
const MIN_ENEMY_CONTRAST := 0.45
## 角色身體範圍（相對腳底）與周圍一圈的寬度（世界像素）。
const PLAYER_BOX := Rect2(-9, -44, 18, 40)
const RING := 20.0
## 量「身體比周圍暗」用的百分位：背景平均亮度達 SILHOUETTE_MIN_OUTER 時用暗部百分位，否則用中位數。
const DARK_PERCENTILE := 0.25
const MEDIAN_PERCENTILE := 0.5
const SILHOUETTE_MIN_OUTER := 0.12

var _image: Image
var _scale := 1.0
var _to_screen := Transform2D.IDENTITY


## 擷取 viewport 目前畫面。每次量測前建立一個（會複製整張畫面，不要每影格呼叫）。
static func capture(viewport: Viewport) -> ContrastProbe:
	var probe := ContrastProbe.new()
	probe._image = viewport.get_texture().get_image()
	probe._scale = float(probe._image.get_width()) / viewport.get_visible_rect().size.x
	probe._to_screen = viewport.get_canvas_transform()
	return probe


## 腳底在 feet（世界座標）的角色的輪廓對比。
func character_contrast(feet: Vector2) -> float:
	return contrast(Rect2(feet + PLAYER_BOX.position, PLAYER_BOX.size), RING)


## 方框內與外圈（向外擴 ring 像素）平均亮度的對比：亮部比周圍亮多少，或身體比周圍暗多少（剪影），取較大者。
func contrast(box: Rect2, ring: float) -> float:
	var inner := _percentile_luma(box, 0.9)
	var outer_box := box.grow(ring)
	var outer_total := _luma_sum(outer_box) - _luma_sum(box)
	var outer_count := _pixel_count(outer_box) - _pixel_count(box)
	var outer := outer_total / maxf(1.0, outer_count)
	var bright := (inner - outer) / (outer + 0.02)
	var body := _percentile_luma(box, DARK_PERCENTILE if outer >= SILHOUETTE_MIN_OUTER else MEDIAN_PERCENTILE)
	var dark := (outer - body) / (outer + 0.02)
	return maxf(bright, dark)


## 地面頂面亮邊：腳下 1~3 像素 vs 再往下 6~12 像素的對比。
func edge_contrast(feet: Vector2) -> float:
	var edge_rect := Rect2(feet + Vector2(-24, 0), Vector2(48, 3))
	var below_rect := Rect2(feet + Vector2(-24, 8), Vector2(48, 6))
	var below := mean_luma(below_rect)
	return (mean_luma(edge_rect) - below) / (below + 0.02)


func mean_luma(world_rect: Rect2) -> float:
	return _luma_sum(world_rect) / maxf(1.0, _pixel_count(world_rect))


## 方框內像素亮度的第 q 百分位（0~1）。
func _percentile_luma(world_rect: Rect2, q: float) -> float:
	var rect := _screen_rect(world_rect)
	var values: Array[float] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			values.append(LightKit.luminance(_image.get_pixel(x, y)))
	if values.is_empty():
		return 0.0
	values.sort()
	return values[clampi(int(float(values.size() - 1) * q), 0, values.size() - 1)]


func _screen_rect(world_rect: Rect2) -> Rect2i:
	var a := _to_screen * world_rect.position * _scale
	var b := _to_screen * world_rect.end * _scale
	return Rect2i(Vector2i(a.floor()), Vector2i((b - a).ceil())).intersection(Rect2i(Vector2i.ZERO, _image.get_size()))


func _pixel_count(world_rect: Rect2) -> float:
	return world_rect.size.x * _scale * world_rect.size.y * _scale


func _luma_sum(world_rect: Rect2) -> float:
	var rect := _screen_rect(world_rect)
	var total := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			total += LightKit.luminance(_image.get_pixel(x, y))
	return total
