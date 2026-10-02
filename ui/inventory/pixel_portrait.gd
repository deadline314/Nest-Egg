class_name PixelPortrait
extends Control
## 角色像素立繪：把分層 PNG（後髮、身體、頭、閉眼頭，見 ItemIcons.PORTRAIT_LAYERS）疊起來，加上待機動畫。
## 動畫全部以「整個像素」為單位位移，保持像素畫的銳利：
##   呼吸＝上半身與頭每個週期升降 1 像素；眨眼＝每隔數秒換成閉眼層；頭髮擺動＝後髮逐段左右位移，越下面幅度越大。

const SCALE := 2
const BREATH_SPEED := 2.2
const BREATH_SPLIT := 70
const HAIR_STRIP := 3
const HAIR_SWAY_PX := 2.0
const BLINK_TIME := 0.12
const BLINK_MIN_GAP := 2.4
const BLINK_MAX_GAP := 5.0

var character := "rin"

var _layers: Dictionary[StringName, Texture2D] = {}
var _hair_rows := Vector2i.ZERO
var _time := 0.0
var _blink_left := 0.0
var _next_blink := 2.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	custom_minimum_size = Vector2(ItemIcons.PORTRAIT_SIZE * SCALE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	for layer in ItemIcons.PORTRAIT_LAYERS:
		_layers[layer] = ItemIcons.portrait_layer(character, layer)
	_hair_rows = _used_rows(_layers[&"hair_back"])


func _process(delta: float) -> void:
	_time += delta
	if _blink_left > 0.0:
		_blink_left -= delta
	else:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_left = BLINK_TIME
			_next_blink = _rng.randf_range(BLINK_MIN_GAP, BLINK_MAX_GAP)
	queue_redraw()


func _draw() -> void:
	var source_size := ItemIcons.PORTRAIT_SIZE
	# 腳下的光圈。
	draw_set_transform(Vector2.ZERO)
	var floor_center := Vector2(46.0, 124.0) * float(SCALE)
	draw_circle(floor_center, 34.0, Color(Palette.CYAN, 0.06))
	draw_circle(floor_center, 22.0, Color(Palette.CYAN, 0.08))
	var breath := 1 if sin(_time * BREATH_SPEED) > 0.2 else 0
	_draw_hair(source_size, breath)
	_draw_split(_layers[&"body"], source_size, breath)
	var head: Texture2D = _layers[&"head_blink"] if _blink_left > 0.0 else _layers[&"head"]
	_blit(head, Rect2i(0, 0, source_size.x, source_size.y), Vector2i(0, -breath))


## 身體：腰部以上隨呼吸升降，以下固定。
func _draw_split(tex: Texture2D, source_size: Vector2i, breath: int) -> void:
	_blit(tex, Rect2i(0, 0, source_size.x, BREATH_SPLIT), Vector2i(0, -breath))
	_blit(tex, Rect2i(0, BREATH_SPLIT, source_size.x, source_size.y - BREATH_SPLIT), Vector2i.ZERO)


## 後髮：逐段左右位移，從髮根（上）到髮尾（下）幅度漸增。
func _draw_hair(source_size: Vector2i, breath: int) -> void:
	var rows := _hair_rows
	if rows.y <= rows.x:
		return
	var span := float(rows.y - rows.x)
	var y := rows.x
	while y < rows.y:
		var t := float(y - rows.x) / span
		var sway := roundi(sin(_time * 1.9 + t * 2.6) * HAIR_SWAY_PX * t)
		var strip_h := mini(HAIR_STRIP, rows.y - y)
		_blit(_layers[&"hair_back"], Rect2i(0, y, source_size.x, strip_h), Vector2i(sway, -breath))
		y += HAIR_STRIP


func _blit(tex: Texture2D, source: Rect2i, shift: Vector2i) -> void:
	var dest := Rect2(Vector2(source.position + shift) * float(SCALE), Vector2(source.size) * float(SCALE))
	draw_texture_rect_region(tex, dest, Rect2(source))


## 貼圖中有內容的列範圍（頭髮擺動只作用在這個範圍）。讀不到影像時回傳空範圍。
func _used_rows(tex: Texture2D) -> Vector2i:
	var image := tex.get_image()
	if image == null:
		return Vector2i.ZERO
	var used := image.get_used_rect()
	return Vector2i(used.position.y, used.end.y)
