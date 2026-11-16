class_name TextureRelease
extends RefCounted
## 釋放用不到的環境貼圖（BG-32）。
##
## 貼圖快取（RigLibrary、LitTextures）原本只進不出：看過的過場舞台、走過的區域的圖會一直留在記憶體。
## 這裡在「換區域」與「過場結束」之後，把快取裡除了快取以外沒有人在用的環境貼圖放掉。
## 還在場景上的、預載（AssetPrefetch，有上限）手上拿著的都不會被放掉，所以馬上要用的不會因此重載。
## 釋放排在幾個影格之後：等舊的節點真的被刪掉、新的區域把自己的圖拿好。

const PREFIXES: PackedStringArray = ["res://art/environment/"]
## 要求之後等幾個影格才釋放。
const SETTLE_FRAMES := 3

static var released_total := 0
static var _pending := -1


## 要求釋放一次（同一段時間內多次要求只做一次）。
static func request() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var already := _pending >= 0
	_pending = SETTLE_FRAMES
	if not already:
		tree.process_frame.connect(_tick)


## 現在就釋放（量測與測試用）。
static func release_now() -> int:
	var dropped := LitTextures.release_unused(PREFIXES)
	dropped += RigLibrary.release_unused(PREFIXES)
	released_total += dropped
	return dropped


static func _tick() -> void:
	_pending -= 1
	if _pending > 0:
		return
	_pending = -1
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_tick):
		tree.process_frame.disconnect(_tick)
	release_now()
