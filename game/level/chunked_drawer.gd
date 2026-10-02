class_name ChunkedDrawer
extends Node2D
## 分塊繪製框架：把大面積的靜態繪製切成多個區塊節點。
## 好處：畫面外的區塊自動被剔除；每個光源只需重繪「光照範圍內」的區塊，大幅降低光影成本。
## 子類別實作 _draw_chunk(canvas, rect)，在 rect（世界座標）範圍內呼叫 canvas.draw_*。

const CHUNK_WIDTH := 320.0

var _bounds := Rect2()


## 依範圍建立區塊。呼叫前請先設定子類別需要的資料。
func build_chunks(bounds: Rect2) -> void:
	_bounds = bounds
	for child in get_children():
		if child is _Chunk:
			child.queue_free()
	var x := bounds.position.x
	while x < bounds.end.x:
		var chunk := _Chunk.new()
		chunk.owner_drawer = self
		chunk.rect = Rect2(x, bounds.position.y, minf(CHUNK_WIDTH, bounds.end.x - x), bounds.size.y)
		add_child(chunk)
		x += CHUNK_WIDTH


## 子類別覆寫：只繪製落在 rect 內的內容（座標為本節點的區域座標）。
func _draw_chunk(_canvas: CanvasItem, _rect: Rect2) -> void:
	pass


class _Chunk:
	extends Node2D

	var owner_drawer: ChunkedDrawer
	var rect := Rect2()

	func _draw() -> void:
		if owner_drawer != null:
			owner_drawer._draw_chunk(self, rect)
