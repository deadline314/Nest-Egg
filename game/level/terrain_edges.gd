class_name TerrainEdges
extends ChunkedDrawer
## 地形與平台的亮邊：自發光，環境光再暗也看得到可站立的表面，跳躍落點不會看不清。
## 只畫頂面的細線；地形本體仍然受光，亮邊是「被濕氣與遠處霓虹微微照亮的金屬邊緣」。

const SOLID_EDGE_ALPHA := 0.55
const PLATFORM_EDGE_ALPHA := 0.7

var _solid_tops: Array[Rect2] = []
var _platform_tops: Array[Rect2] = []
## 環境主題（亮邊顏色取自各區段材質的 edge_color）；null 代表使用預設亮邊色。
var _theme: EnvironmentTheme
var _tile := 16


func _init() -> void:
	emissive = true


## 傳入地形的實心矩形與單向平台矩形（世界座標），並依地圖範圍建立區塊。
func build(solids: Array[Rect2], platforms: Array[Rect2], bounds: Rect2, theme: EnvironmentTheme = null, tile := 16) -> void:
	_solid_tops = solids
	_platform_tops = platforms
	_theme = theme
	_tile = tile
	build_chunks(bounds)


func _draw_chunk(canvas: CanvasItem, area: Rect2) -> void:
	for full in _solid_tops:
		if full.position.y < area.position.y or full.position.y > area.end.y:
			continue
		_draw_line_segments(canvas, maxf(full.position.x, area.position.x), minf(full.end.x, area.end.x), full.position.y, SOLID_EDGE_ALPHA, 2.0)
	for full in _platform_tops:
		_draw_line_segments(canvas, maxf(full.position.x, area.position.x), minf(full.end.x, area.end.x), full.position.y, PLATFORM_EDGE_ALPHA, 1.0)


## 畫一段亮邊；有環境主題時依區段切開，各段用該區段材質指定的顏色。
func _draw_line_segments(canvas: CanvasItem, from_x: float, to_x: float, y: float, default_alpha: float, width: float) -> void:
	if to_x <= from_x:
		return
	var x := from_x
	while x < to_x:
		var next_x := to_x
		var color := Color(Palette.TERRAIN_TOP, default_alpha)
		if _theme != null:
			for zone in _theme.zones:
				if zone != null and float(zone.from_tile * _tile) > x and float(zone.from_tile * _tile) < next_x:
					next_x = float(zone.from_tile * _tile)
			var zone_here := _theme.zone_at(int(floor(x / _tile)))
			if zone_here != null and zone_here.material != null and zone_here.material.edge_color.a > 0.0:
				color = zone_here.material.edge_color
		canvas.draw_line(Vector2(x, y), Vector2(next_x, y), color, width)
		x = next_x
