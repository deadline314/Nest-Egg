class_name LevelLayout
extends RefCounted
## LevelBuilder 解析後的純資料結構（不含任何節點），方便測試與重複使用。

var tile_size := 16
var width := 0
var height := 0
var rows := PackedStringArray()

var has_player_start := false
var player_start := Vector2.ZERO
var solid_rects: Array[Rect2i] = []
var platform_rects: Array[Rect2i] = []
var spike_rects: Array[Rect2i] = []
var laser_rects: Array[Rect2i] = []
var checkpoints := PackedVector2Array()
var health_pickups := PackedVector2Array()
var lamps := PackedVector2Array()
## { "x": float（觸發的像素 x）, "scene": StringName }，依 x 排序。
var story_triggers: Array[Dictionary] = []
## { "kind": String, "cell": Vector2i, "position": Vector2（格子左上角像素）}
var decor: Array[Dictionary] = []
## 每一欄由上往下第一個地表（實心或平台）的像素高度；沒有則為 INF。
var surface_heights := PackedFloat32Array()
## 每一欄是否在室內（最上方一列就是實心＝有屋頂）。
var covered_columns := PackedByteArray()
## 主要地面高度（各欄地表的中位數），霧氣與倒影使用。
var ground_y := 0.0
## { "text": String, "position": Vector2 }
var hints: Array[Dictionary] = []
## { "resource": Resource, "position": Vector2 }
var spawns: Array[Dictionary] = []
## { "resource": EnemyData, "position": Vector2 }；空字典代表沒有頭目。
var boss_spawn: Dictionary = {}
## 頭目戰場左界（像素）；< 0 代表沒有頭目戰。
var arena_x := -1.0
var warnings := PackedStringArray()


func is_valid() -> bool:
	return width > 0 and height > 0 and has_player_start


func pixel_size() -> Vector2:
	return Vector2(width, height) * tile_size


func cells_to_pixels(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * tile_size, Vector2(rect.size) * tile_size)


## 格子 → 腳底座標（格子底邊中點）。
func cell_to_feet(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * tile_size, (y + 1) * tile_size)


## 從格子 (x, y) 往下找到的第一個地表（實心或平台）的像素高度；沒有則為 INF。
func floor_below(x: int, y: int) -> float:
	for yy in range(maxi(0, y), height):
		var c := cell(x, yy)
		if c == "#" or c == "=":
			return float(yy * tile_size)
	return INF


func cell(x: int, y: int) -> String:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return "."
	return rows[y][x]
