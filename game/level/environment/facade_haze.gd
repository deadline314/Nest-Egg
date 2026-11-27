class_name FacadeHaze
extends Node2D
## 立面的空氣感（BG-69）：室外的立面依高度蓋一層區段的霧色（光影設定的 fog_color，和地面霧、遠景空氣同一個顏色，
## 由 LightingController 每次套用光影時更新），越往上越淡、越接近空氣的顏色；
## 走道往上 CLEAR 像素以內完全不蓋，角色與敵人身後的牆保持原本的對比。室內的段落（頭上有天花板）不畫。
## 只畫一次（靜態）；低畫質（沒有體積效果）時隱藏。

## 走道往上多少像素以內不加霧（高過高個子敵人的頭頂）。
const CLEAR := 80.0
## 預設濃度（立面最上緣的不透明度）；地圖 JSON 的 "facade_haze" 可以改（0 = 不加）。
const DEFAULT_STRENGTH := 0.22
const MAX_STRENGTH := 0.6

var strength := DEFAULT_STRENGTH
var _bands: Array[Rect2] = []
static var _gradient: GradientTexture2D


## geometry：立面的欄（outdoor、facade_top、ground）；panel_width：一欄的寬度（像素）。
func setup(geometry: BackWallGeometry, panel_width: float, p_strength: float) -> void:
	name = "FacadeHaze"
	strength = clampf(p_strength, 0.0, MAX_STRENGTH)
	z_as_relative = false
	z_index = WorldLayers.BACK_WALL
	light_mask = 0
	material = LightKit.emissive_material()
	for col in geometry.columns:
		if col >= geometry.outdoor.size() or geometry.outdoor[col] == 0:
			continue
		var top := geometry.facade_top[col]
		var bottom := geometry.ground[col] - CLEAR
		if not is_finite(top) or not is_finite(bottom) or bottom - top < 8.0:
			continue
		var rect := Rect2(col * panel_width, top, panel_width, bottom - top)
		# 相鄰、同高的欄併成一塊，少畫幾次。
		if not _bands.is_empty() and is_equal_approx(_bands[-1].end.x, rect.position.x) and is_equal_approx(_bands[-1].position.y, top) and is_equal_approx(_bands[-1].end.y, rect.end.y):
			_bands[-1] = _bands[-1].merge(rect)
		else:
			_bands.append(rect)
	Settings.display_changed.connect(_refresh)
	_refresh()


func band_count() -> int:
	return _bands.size()


func _refresh() -> void:
	visible = LightQuality.volumetrics() and strength > 0.0 and not _bands.is_empty()


## 區段霧色改變時更新顏色；不重畫。
func set_tint(fog: Color) -> void:
	var color := Color(fog.r, fog.g, fog.b, strength)
	if not modulate.is_equal_approx(color):
		modulate = color


func _draw() -> void:
	var gradient := _texture()
	for band in _bands:
		draw_texture_rect(gradient, band, false)


## 由上往下淡出的白色漸層（全部共用一張）。
static func _texture() -> GradientTexture2D:
	if _gradient == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.5, Color(1, 1, 1, 0.4))
		_gradient = GradientTexture2D.new()
		_gradient.gradient = gradient
		_gradient.fill_from = Vector2(0.5, 0.0)
		_gradient.fill_to = Vector2(0.5, 1.0)
		_gradient.width = 4
		_gradient.height = 64
	return _gradient
