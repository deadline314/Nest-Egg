class_name TerrainEdges
extends ChunkedDrawer
## 地形與平台的亮邊：自發光，環境光再暗也看得到可站立的表面，跳躍落點不會看不清。
## 只畫頂面的細線；地形本體仍然受光，亮邊是「被濕氣與遠處霓虹微微照亮的金屬邊緣」。

const SOLID_EDGE_ALPHA := 0.55
const PLATFORM_EDGE_ALPHA := 0.7

var _solid_tops: Array[Rect2] = []
var _platform_tops: Array[Rect2] = []


func _init() -> void:
	emissive = true


## 傳入地形的實心矩形與單向平台矩形（世界座標），並依地圖範圍建立區塊。
func build(solids: Array[Rect2], platforms: Array[Rect2], bounds: Rect2) -> void:
	_solid_tops = solids
	_platform_tops = platforms
	build_chunks(bounds)


func _draw_chunk(canvas: CanvasItem, area: Rect2) -> void:
	for full in _solid_tops:
		if full.position.y < area.position.y or full.position.y > area.end.y:
			continue
		var from_x := maxf(full.position.x, area.position.x)
		var to_x := minf(full.end.x, area.end.x)
		if to_x > from_x:
			canvas.draw_line(Vector2(from_x, full.position.y), Vector2(to_x, full.position.y), Color(Palette.TERRAIN_TOP, SOLID_EDGE_ALPHA), 2.0)
	for full in _platform_tops:
		var from_x := maxf(full.position.x, area.position.x)
		var to_x := minf(full.end.x, area.end.x)
		if to_x > from_x:
			canvas.draw_line(Vector2(from_x, full.position.y), Vector2(to_x, full.position.y), Color(Palette.TERRAIN_TOP, PLATFORM_EDGE_ALPHA), 1.0)
