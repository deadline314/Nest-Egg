class_name GroundSection
extends Node2D
## 地面剖面（BG-72）：可走地面以下原本是整片重複的地磚或死黑；這一層蓋在地形上，讓它像一個有結構的剖面：
## 緊貼走道的一段（start 像素）維持原樣，以下換成不透明的剖面底色、往下逐漸變暗到 fade；中間有一道橋面樑、間隔不一的基樁、偶爾一條管線，
## 結構比底色亮一點、上緣一條很淡的亮邊，讀得出形狀但不搶走道。
## 資料：地圖 JSON 頂層的 "ground_section"：{"start": 14, "fade": 0.82, "piles": [最小間隔, 最大間隔], "pipes": 0~1}。
## 只畫一次（靜態，不重畫）；三個畫質都畫（它是構圖不是特效）。資料壞掉時記錄是哪個區域哪一項，這一層不畫。

## 地面下面至少要有幾格實心，才算「有剖面」的地面（薄薄一層的平台不算）。
const MIN_DEPTH_TILES := 2
const DEFAULT_START := 14.0
const DEFAULT_FADE := 0.82
const DEFAULT_PILES := Vector2(56.0, 104.0)
const DEFAULT_PIPES := 0.5
## 橋面樑的厚度、基樁的寬度、管線的粗細（像素）。
const BEAM := 5.0
const PILE_WIDTH := Vector2(7.0, 12.0)
const PIPE := 5.0

var start := DEFAULT_START
var fade := DEFAULT_FADE
var piles := DEFAULT_PILES
var pipes := DEFAULT_PIPES
## 剖面底色（最暗處）與結構的顏色、結構上緣亮邊的顏色。
var base := Color(0.06, 0.05, 0.06)
var deep := Color(0.02, 0.02, 0.03)
var structure := Color(0.09, 0.08, 0.09)
var edge := Color(1, 1, 1, 0.08)
var _runs: Array[Rect2] = []
var _seed := 0
static var _gradient: GradientTexture2D


## 讀資料並找出要畫的地面（每一段：平的、下面有剖面的地面），回傳 false 代表這一區不畫。
## ambient 是區段的環境光（決定底色與結構的色調）；accent 是結構上緣亮邊的顏色（主光色或白色）。
func setup(layout: LevelLayout, spec: Variant, where: String, ambient: Color, accent: Color) -> bool:
	name = "GroundSection"
	if spec == null:
		return false
	if typeof(spec) != TYPE_DICTIONARY:
		push_error("[GroundSection] %s 的 ground_section 必須是物件，這一區不畫地面剖面" % where)
		return false
	var data := spec as Dictionary
	var problems := PackedStringArray()
	start = _number(data, "start", DEFAULT_START, 0.0, 64.0, problems)
	fade = _number(data, "fade", DEFAULT_FADE, 0.0, 1.0, problems)
	pipes = _number(data, "pipes", DEFAULT_PIPES, 0.0, 1.0, problems)
	var raw_piles: Variant = data.get("piles", [DEFAULT_PILES.x, DEFAULT_PILES.y])
	if typeof(raw_piles) != TYPE_ARRAY or (raw_piles as Array).size() != 2 or typeof(raw_piles[0]) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(raw_piles[1]) not in [TYPE_INT, TYPE_FLOAT] or float(raw_piles[0]) < 24.0 or float(raw_piles[1]) < float(raw_piles[0]):
		problems.append("piles 必須是 [最小間隔（至少 24）, 最大間隔]")
	else:
		piles = Vector2(float(raw_piles[0]), float(raw_piles[1]))
	if not problems.is_empty():
		push_error("[GroundSection] %s 的 ground_section 有問題，這一區不畫地面剖面：%s" % [where, "；".join(problems)])
		return false
	base = Color(ambient.r * 0.5, ambient.g * 0.43, ambient.b * 0.4)
	deep = Color(ambient.r * 0.1, ambient.g * 0.09, ambient.b * 0.09)
	structure = Color(ambient.r * 0.78, ambient.g * 0.68, ambient.b * 0.62)
	edge = Color(accent, 0.3)
	_seed = hash(where)
	_find_runs(layout)
	return not _runs.is_empty()


func run_count() -> int:
	return _runs.size()


## 每一欄：可走的地面那一格是實心、下面還有至少 MIN_DEPTH_TILES 格實心的，才算有剖面；平的相鄰欄併成一段。
## （用可走地面的高度，不是最上面的實心格：室內的天花板不會被當成走道。）
func _find_runs(layout: LevelLayout) -> void:
	var tile := float(layout.tile_size)
	var current := Rect2()
	for column in mini(layout.width, layout.surface_heights.size()):
		var top := int(layout.surface_heights[column] / tile)
		var deep_enough := top >= 0 and top < layout.height and layout.cell(column, top) == LevelBuilder.SOLID
		for k in MIN_DEPTH_TILES:
			deep_enough = deep_enough and layout.cell(column, top + 1 + k) == LevelBuilder.SOLID
		if not deep_enough:
			if current.size.x > 0.0:
				_runs.append(current)
			current = Rect2()
			continue
		var bottom := top
		while bottom + 1 < layout.height and layout.cell(column, bottom + 1) == LevelBuilder.SOLID:
			bottom += 1
		var rect := Rect2(column * tile, top * tile + start, tile, (bottom + 1 - top) * tile - start)
		if current.size.x > 0.0 and is_equal_approx(current.position.y, rect.position.y) and is_equal_approx(current.end.x, rect.position.x) and is_equal_approx(current.end.y, rect.end.y):
			current = current.merge(rect)
		else:
			if current.size.x > 0.0:
				_runs.append(current)
			current = rect
	if current.size.x > 0.0:
		_runs.append(current)


func _draw() -> void:
	var gradient := _texture()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for run in _runs:
		# 不透明的底色蓋掉重複的地磚，再往下變暗：從走道下方 start 處的底色，到最下面疊上 fade 的深色。
		draw_rect(run, base)
		draw_texture_rect(gradient, run, false, Color(deep, fade))
		# 橋面樑：緊貼在變暗起點下面的一道。
		draw_rect(Rect2(run.position.x, run.position.y, run.size.x, BEAM), structure)
		draw_line(Vector2(run.position.x, run.position.y), Vector2(run.end.x, run.position.y), edge, 1.0)
		# 基樁：間隔不一、寬度不一，從樑往下到底。
		var x := run.position.x + rng.randf_range(8.0, piles.x)
		var last := run.position.x
		while x < run.end.x - 6.0:
			var width := rng.randf_range(PILE_WIDTH.x, PILE_WIDTH.y)
			var pile := Rect2(x, run.position.y + BEAM, width, run.size.y - BEAM)
			draw_rect(pile, structure)
			draw_line(pile.position + Vector2(1, 0), Vector2(pile.position.x + 1, pile.end.y), edge, 1.0)
			# 偶爾在兩根基樁之間有一條管線（高度不一，兩端有接頭）。
			if rng.randf() < pipes and x - last > 24.0:
				var y := run.position.y + BEAM + rng.randf_range(8.0, maxf(9.0, run.size.y * 0.55))
				var pipe := Rect2(last + 2.0, y, x - last - 2.0, PIPE)
				draw_rect(pipe, structure)
				draw_line(pipe.position, Vector2(pipe.end.x, pipe.position.y), edge, 1.0)
				draw_rect(Rect2(pipe.position.x - 1.0, y - 1.0, 3.0, PIPE + 2.0), structure)
				draw_rect(Rect2(pipe.end.x - 2.0, y - 1.0, 3.0, PIPE + 2.0), structure)
			last = x + width
			x += width + rng.randf_range(piles.x, piles.y)


## 由上往下變不透明的漸層（全部共用一張）：上緣透明、下面全黑，中間較快變暗。
static func _texture() -> GradientTexture2D:
	if _gradient == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0.0))
		gradient.set_color(1, Color(1, 1, 1, 1.0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.6))
		_gradient = GradientTexture2D.new()
		_gradient.gradient = gradient
		_gradient.fill_from = Vector2(0.5, 0.0)
		_gradient.fill_to = Vector2(0.5, 1.0)
		_gradient.width = 4
		_gradient.height = 64
	return _gradient


static func _number(data: Dictionary, key: String, fallback: float, low: float, high: float, problems: PackedStringArray) -> float:
	if not data.has(key):
		return fallback
	var value: Variant = data[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < low or float(value) > high:
		problems.append("%s 要是 %s~%s 的數字（%s）" % [key, low, high, value])
		return fallback
	return float(value)
