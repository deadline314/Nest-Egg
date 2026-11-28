class_name GroundSection
extends Node2D
## 地面剖面（BG-72、BG-76）：可走地面以下原本是整片重複的地磚或死黑；這一層蓋在地形上，讓它像一個有材質的剖面：
## 緊貼走道的一段（start 像素）維持原樣（走道邊緣的對比不動），以下換成不透明的剖面底色，往下 fade_depth 像素內漸暗到最暗色，
## 再往下維持最暗色（不是純黑）。每一層地面下面都有（多層的室內與街道，下層的地面下面也有），不只最上面那層。
## 材質（style）：
## - steel：橋面樑、間隔不一的基樁（受光面與背光面、樁帽）、偶爾一條管線（港口、高架）。
## - masonry：室外的地基——錯縫的石塊、上方一道管溝（裡面一條管線）、間隔的排水口與往下的水痕。
## - interior：室內的樓板——頂端一道混凝土樓板、下面是有對拉孔的牆板、一條線槽與支架、偶爾一個地漏格柵。
## 懸空的高架段（under_deck > 0）：走道下面沒有實心地形時，從橋面下緣往下到下一層地面（或地圖底）畫一層由透明漸濃的霧，
## 霧裡有零星的遠處燈點與底部一兩道濕地面的反光，看得到「下面還有城市」而不是一片黑；畫在立面後面（不蓋到擺設與地形）。
## 夜景的環境光很暗，剖面的頂端有最低明度（min_level），讀得出材質但仍比走道暗；結構比底色亮一點。
## 剖面不畫水平的亮邊（只有朝主光的直邊有亮邊），不會被看成可以站的平台頂面。
## 資料：地圖 JSON 頂層的 "ground_section"：{"style": "steel", "start": 14, "fade": 0.82, "fade_depth": 0（0 = 整段）,
## "min_level": 0~1, "under_deck": 0~1, "lip_shadow": 0~1, "piles": [最小間隔, 最大間隔], "pipes": 0~1, "from": 欄, "to": 欄}。
## from／to（選填）只在這段欄位裡畫；地圖可以寫一串（同一區不同段用不同材質）。
## top_ramp：剖面頂端多少像素由暗漸到材質（搭配較小的 start，走道下就不會是一條平的暗帶）。
## lip_shadow：在維持原樣的那一段（走道下 start 像素內）往下疊一道淡淡的陰影，像地板邊緣下方的影子（走道邊緣更清楚）。
## 只畫一次（靜態，不重畫）；三個畫質都畫（它是構圖不是特效）。資料壞掉時記錄是哪個區域哪一項，這一層不畫。

## 地面下面至少要有幾格實心，才算「有剖面」的地面（薄薄一層的平台不算）。
const MIN_DEPTH_TILES := 2
const STYLES: Array[String] = ["steel", "masonry", "interior"]
const DEFAULT_START := 14.0
const DEFAULT_FADE := 0.82
const DEFAULT_MIN_LEVEL := 0.0
const DEFAULT_PILES := Vector2(56.0, 104.0)
const DEFAULT_PIPES := 0.5
## 最暗色的下限（感知亮度）：有設 min_level 時，最暗處也不會是純黑。
const DEEP_FLOOR := 0.6
## 橋面樑的厚度、基樁的寬度、管線的粗細（像素）。
const BEAM := 5.0
const PILE_WIDTH := Vector2(6.0, 16.0)
## 基樁頂端的樁帽比樁身寬多少、多高；背光面佔樁寬的比例與暗多少（往最暗的底色混）。
const PILE_CAP := Vector2(2.0, 3.0)
const SHADOW_SHARE := 0.45
const SHADOW_MIX := 0.55
const PIPE := 5.0
## 石塊的高與寬、管溝的高、排水口的間隔（像素）。
const COURSE := 9.0
const BLOCK := Vector2(18.0, 30.0)
const TRENCH := 8.0
## 管溝比結構暗多少（往最暗色混）：只暗一點，不在走道下面再疊一條黑帶。
const TRENCH_DARK := 0.45
const DRAINS := Vector2(70.0, 140.0)
## 室內：樓板厚度、牆板寬度、線槽離樓板多遠。
const SLAB := 7.0
const PANEL := Vector2(40.0, 64.0)
const TRAY_DROP := 14.0
## 懸空段：橋面下至少要空幾格才算懸空；霧漸淡的深度（像素）；燈點的平均間隔（像素）。
const VOID_TILES := 3
const VOID_FADE := 220.0
## 霧最濃時的不透明度（遠景畫到底之後的黑底上看得出霧，遠景本身仍透得過來）。
const FOG_ALPHA := 0.55
const LIGHT_SPACING := 34.0
## 霧的層：在立面後面（不蓋到擺設、地形與角色）。
const UNDER_DECK_Z := WorldLayers.BACK_WALL - 1
## 地板邊緣下方的影子從邊緣下多少像素開始（走道頂面的亮邊不動）。
const LIP_CLEAR := 4.0
## 分塊的寬度（像素）：畫面外的塊整塊不畫。
const CHUNK := 512.0

var style := "steel"
var start := DEFAULT_START
var fade := DEFAULT_FADE
var fade_depth := 0.0
var min_level := DEFAULT_MIN_LEVEL
var under_deck := 0.0
var lip_shadow := 0.0
var top_ramp := 0.0
var _voids: Array[Rect2] = []
var _lights: PackedColorArray = PackedColorArray()
var piles := DEFAULT_PILES
var pipes := DEFAULT_PIPES
## 剖面底色（頂端）、最暗色、結構的顏色、朝主光的直邊亮邊、細線（接縫、溝）的顏色。
var base := Color(0.06, 0.05, 0.06)
var deep := Color(0.02, 0.02, 0.03)
var structure := Color(0.09, 0.08, 0.09)
var edge := Color(1, 1, 1, 0.08)
var seam := Color(0, 0, 0, 0.4)
## 主光的 x（像素）：每根基樁朝主光那一側是受光面、另一側是背光面；NAN 時光從左邊來。
var key_x := NAN
var _runs: Array[Rect2] = []
var _from := 0
var _to := 0
var _seed := 0
## 目前正在畫的那一塊（_draw_chunk 設定）。
var _c: CanvasItem


## 讀資料並找出要畫的地面（每一段：平的、下面有剖面的地面），回傳 false 代表這一區不畫。
## ambient 是區段的環境光（決定底色與結構的色調）；accent 是直邊亮邊的顏色（主光色或白色）。
func setup(layout: LevelLayout, spec: Variant, where: String, ambient: Color, accent: Color) -> bool:
	name = "GroundSection"
	if spec == null:
		return false
	if typeof(spec) != TYPE_DICTIONARY:
		push_error("[GroundSection] %s 的 ground_section 必須是物件，這一區不畫地面剖面" % where)
		return false
	var data := spec as Dictionary
	var problems := PackedStringArray()
	style = str(data.get("style", "steel"))
	if style not in STYLES:
		problems.append("style 要是 %s（%s）" % ["、".join(STYLES), style])
	start = _number(data, "start", DEFAULT_START, 0.0, 64.0, problems)
	fade = _number(data, "fade", DEFAULT_FADE, 0.0, 1.0, problems)
	fade_depth = _number(data, "fade_depth", 0.0, 0.0, 2000.0, problems)
	min_level = _number(data, "min_level", DEFAULT_MIN_LEVEL, 0.0, 1.0, problems)
	under_deck = _number(data, "under_deck", 0.0, 0.0, 1.0, problems)
	lip_shadow = _number(data, "lip_shadow", 0.0, 0.0, 1.0, problems)
	top_ramp = _number(data, "top_ramp", 0.0, 0.0, 64.0, problems)
	pipes = _number(data, "pipes", DEFAULT_PIPES, 0.0, 1.0, problems)
	_from = int(_number(data, "from", 0.0, 0.0, 100000.0, problems))
	_to = int(_number(data, "to", float(layout.width), 0.0, 100000.0, problems))
	var raw_piles: Variant = data.get("piles", [DEFAULT_PILES.x, DEFAULT_PILES.y])
	if typeof(raw_piles) != TYPE_ARRAY or (raw_piles as Array).size() != 2 or typeof(raw_piles[0]) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(raw_piles[1]) not in [TYPE_INT, TYPE_FLOAT] or float(raw_piles[0]) < 24.0 or float(raw_piles[1]) < float(raw_piles[0]):
		problems.append("piles 必須是 [最小間隔（至少 24）, 最大間隔]")
	else:
		piles = Vector2(float(raw_piles[0]), float(raw_piles[1]))
	if not problems.is_empty():
		push_error("[GroundSection] %s 的 ground_section 有問題，這一區不畫地面剖面：%s" % [where, "；".join(problems)])
		return false
	_tone(ambient)
	edge = Color(accent, 0.3)
	_seed = hash(where)
	_lights = PackedColorArray([Color(accent, 1.0), Palette.CYAN, Palette.MAGENTA, Color(1.0, 0.72, 0.4)])
	_find_runs(layout)
	if under_deck > 0.0:
		_find_voids(layout)
	# 分塊（CHUNK 寬）：每塊是一個節點，畫面外的塊整塊不畫（一個橫跨整關的節點每格都要送出所有圖元）。
	var buckets := _chunked(_runs)
	for index: int in buckets:
		var chunk := Node2D.new()
		chunk.name = "Chunk%d" % index
		chunk.use_parent_material = true
		chunk.draw.connect(_draw_chunk.bind(chunk, buckets[index], index))
		add_child(chunk)
	var void_buckets := _chunked(_voids)
	for index: int in void_buckets:
		var layer := Node2D.new()
		layer.name = "UnderDeck%d" % index
		layer.z_as_relative = false
		layer.z_index = UNDER_DECK_Z
		layer.material = LightKit.emissive_material()
		layer.draw.connect(_draw_voids.bind(layer, void_buckets[index], index))
		add_child(layer)
	return not _runs.is_empty() or not _voids.is_empty()


## 把每一段切成不超過 CHUNK 寬的小段，依所在的塊分組：{塊編號: [Rect2]}。
static func _chunked(rects: Array[Rect2]) -> Dictionary:
	var buckets := {}
	for rect in rects:
		var x := rect.position.x
		while x < rect.end.x - 0.01:
			var index := int(floorf(x / CHUNK))
			var piece_end := minf(rect.end.x, (index + 1) * CHUNK)
			if not buckets.has(index):
				var list: Array[Rect2] = []
				buckets[index] = list
			(buckets[index] as Array[Rect2]).append(Rect2(x, rect.position.y, piece_end - x, rect.size.y))
			x = piece_end
	return buckets


func void_count() -> int:
	return _voids.size()


## 懸空段：可走的薄層（平台或不到 MIN_DEPTH_TILES 厚的實心）下面至少空 VOID_TILES 格，從薄層下緣往下到下一個實心（或地圖底）。
func _find_voids(layout: LevelLayout) -> void:
	var tile := float(layout.tile_size)
	var open := {}
	for column in range(_from, mini(layout.width, _to)):
		var here := {}
		var row := 1
		while row < layout.height - 1:
			var cell := layout.cell(column, row)
			var walkable := cell == LevelBuilder.SOLID or cell == LevelBuilder.PLATFORM
			if not walkable or layout.cell(column, row - 1) == LevelBuilder.SOLID:
				row += 1
				continue
			var under := row + 1
			while under < layout.height and layout.cell(column, under) == LevelBuilder.SOLID:
				under += 1
			var floor_end := under
			while under < layout.height and layout.cell(column, under) != LevelBuilder.SOLID:
				under += 1
			if floor_end - row <= MIN_DEPTH_TILES and under - floor_end >= VOID_TILES:
				var key := Vector2i(floor_end, under)
				var rect := Rect2(column * tile, floor_end * tile, tile, (under - floor_end) * tile)
				if open.has(key) and is_equal_approx((open[key] as Rect2).end.x, rect.position.x):
					here[key] = (open[key] as Rect2).merge(rect)
				else:
					here[key] = rect
			row = maxi(floor_end, row + 1)
		for key: Vector2i in open:
			if not here.has(key):
				_voids.append(open[key])
		open = here
	for key: Vector2i in open:
		_voids.append(open[key])


## 懸空段的霧、遠處燈點與濕地面的反光（畫在 UnderDeck 子節點上，在立面後面）。
func _draw_voids(layer: Node2D, areas: Array[Rect2], index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 1 + index * 7919
	# 霧從橋面下緣完全透明開始（遠景本來看得到的地方照樣看得到），往下漸濃；遠景畫到底之後的黑底就被霧蓋住。
	var fog := Color(structure.lerp(base, 0.4), FOG_ALPHA * under_deck)
	for area in areas:
		var span := minf(VOID_FADE, area.size.y)
		_fade_rect(layer, Rect2(area.position, Vector2(area.size.x, span)), fog)
		if span < area.size.y:
			layer.draw_rect(Rect2(area.position.x, area.position.y + span, area.size.x, area.size.y - span), fog)
		# 遠處的燈：在霧的下半部，稀疏、小、外面一圈很淡的光暈。
		var x := area.position.x + rng.randf_range(4.0, LIGHT_SPACING)
		while x < area.end.x - 2.0:
			var y := area.position.y + rng.randf_range(span * 0.35, maxf(span * 0.35 + 1.0, minf(area.size.y - 4.0, span * 1.1)))
			var color: Color = _lights[rng.randi() % _lights.size()]
			layer.draw_circle(Vector2(x, y), 3.5, Color(color, 0.12 * under_deck))
			layer.draw_circle(Vector2(x, y), 1.2, Color(color, 0.75 * under_deck))
			x += rng.randf_range(LIGHT_SPACING * 0.5, LIGHT_SPACING * 1.6)
		# 下層地面的濕反光：底部一兩道淡淡的橫向光痕（只在看得到地面的地方）。
		if area.size.y < 400.0:
			for k in 2:
				var streak_y := area.end.y - 3.0 - k * 4.0
				var from := area.position.x + rng.randf_range(0.0, area.size.x * 0.3)
				var to := minf(area.end.x, from + rng.randf_range(area.size.x * 0.3, area.size.x * 0.8))
				_line_rect(layer, Vector2(from, streak_y), Vector2(to, streak_y), Color(_lights[k % _lights.size()], 0.14 * under_deck))


## 顏色：色調取環境光；頂端的底色至少有 min_level 的亮度（夜景不會變成黑），最暗色也有下限。
func _tone(ambient: Color) -> void:
	base = Color(ambient.r * 0.5, ambient.g * 0.43, ambient.b * 0.4)
	if base.get_luminance() < min_level:
		base = ColorScript.match_luminance(base if base.get_luminance() > 0.001 else Color(0.5, 0.5, 0.55), min_level)
	structure = base * 1.45
	structure.a = 1.0
	var deep_level := maxf(base.get_luminance() * 0.2, min_level * DEEP_FLOOR)
	deep = ColorScript.match_luminance(Color(ambient.r * 0.1, ambient.g * 0.09, ambient.b * 0.09), deep_level) if deep_level > 0.0 else Color(ambient.r * 0.1, ambient.g * 0.09, ambient.b * 0.09)
	deep.a = 1.0
	seam = Color(deep, 0.55)


func run_count() -> int:
	return _runs.size()


## 每一層地面：實心格、上面不是實心、下面還有至少 MIN_DEPTH_TILES 格實心的，從那一格往下到這塊實心的底都算剖面
## （所以多層的區域每一層的地面下面都有；最上面一列與四周的邊界牆不算）。同一高度、同一底部的相鄰欄併成一段。
func _find_runs(layout: LevelLayout) -> void:
	var tile := float(layout.tile_size)
	var open := {}
	for column in range(_from, mini(layout.width, _to)):
		var here := {}
		var row := 1
		while row < layout.height:
			if layout.cell(column, row) != LevelBuilder.SOLID or layout.cell(column, row - 1) == LevelBuilder.SOLID:
				row += 1
				continue
			var bottom := row
			while bottom + 1 < layout.height and layout.cell(column, bottom + 1) == LevelBuilder.SOLID:
				bottom += 1
			if bottom - row >= MIN_DEPTH_TILES:
				var key := Vector2i(row, bottom)
				var rect := Rect2(column * tile, row * tile + start, tile, (bottom + 1 - row) * tile - start)
				here[key] = (open[key] as Rect2).merge(rect) if open.has(key) and is_equal_approx((open[key] as Rect2).end.x, rect.position.x) else rect
				if open.has(key) and not is_equal_approx((open[key] as Rect2).end.x, rect.position.x):
					_runs.append(open[key])
			row = bottom + 1
		for key: Vector2i in open:
			if not here.has(key):
				_runs.append(open[key])
		open = here
	for key: Vector2i in open:
		_runs.append(open[key])


## 畫一塊（_Chunk 的 draw 呼叫）：那一塊裡的剖面段，亂數依塊的編號固定（重畫或換塊順序都一樣）。
func _draw_chunk(chunk: Node2D, runs: Array[Rect2], index: int) -> void:
	_c = chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + index * 7919
	for run in runs:
		# 不透明的底色蓋掉重複的地磚，往下漸暗：fade_depth 內從底色漸到最暗色，再往下維持最暗色。
		_c.draw_rect(run, base)
		var span := run.size.y if fade_depth <= 0.0 else minf(fade_depth, run.size.y)
		_fade_rect(_c, Rect2(run.position, Vector2(run.size.x, span)), Color(deep, fade))
		if span < run.size.y:
			_c.draw_rect(Rect2(run.position.x, run.position.y + span, run.size.x, run.size.y - span), Color(deep, 1.0).lerp(base, 1.0 - fade))
		if top_ramp > 0.0:
			# 剖面的頂端由暗漸到材質（BG-77）：走道下面不是一條平的暗帶接著一段磚，而是從暗慢慢出現。
			_ramp_rect(_c, Rect2(run.position, Vector2(run.size.x, minf(top_ramp, run.size.y))), Color(deep, 1.0))
		if lip_shadow > 0.0 and start > LIP_CLEAR:
			# 地板邊緣下方的影子：從邊緣下 LIP_CLEAR 像素開始（走道頂面的亮邊不動）往下加深到剖面開始處。
			_fade_rect(_c, Rect2(run.position.x, run.position.y - start + LIP_CLEAR, run.size.x, start - LIP_CLEAR), Color(deep, lip_shadow))
		match style:
			"masonry":
				_masonry(run, rng)
			"interior":
				_interior(run, rng)
			_:
				_steel(run, rng)


## 鋼構：橋面樑、基樁、偶爾一條管線。
func _steel(run: Rect2, rng: RandomNumberGenerator) -> void:
	_c.draw_rect(Rect2(run.position.x, run.position.y, run.size.x, BEAM), structure)
	_line_rect(_c, Vector2(run.position.x, run.position.y + BEAM), Vector2(run.end.x, run.position.y + BEAM), seam)
	var x := run.position.x + rng.randf_range(8.0, piles.x)
	var last := run.position.x
	while x < run.end.x - 6.0:
		var width := rng.randf_range(PILE_WIDTH.x, PILE_WIDTH.y)
		_pile(Rect2(x, run.position.y + BEAM, width, run.size.y - BEAM))
		# 偶爾在兩根基樁之間有一條管線（高度不一，兩端有接頭）。
		if rng.randf() < pipes and x - last > 24.0:
			var y := run.position.y + BEAM + rng.randf_range(8.0, maxf(9.0, minf(run.size.y, _detail_depth(run)) * 0.55))
			var pipe := Rect2(last + 2.0, y, x - last - 2.0, PIPE)
			_c.draw_rect(pipe, structure)
			_line_rect(_c, Vector2(pipe.position.x, pipe.end.y), pipe.end, seam)
			_c.draw_rect(Rect2(pipe.position.x - 1.0, y - 1.0, 3.0, PIPE + 2.0), structure)
			_c.draw_rect(Rect2(pipe.end.x - 2.0, y - 1.0, 3.0, PIPE + 2.0), structure)
		last = x + width
		x += width + rng.randf_range(piles.x, piles.y)


## 一根基樁：受光面、背光面（朝主光的反方向、暗一截）、受光那側一條亮邊、頂端略寬的樁帽（樁帽不畫水平亮邊）。
func _pile(pile: Rect2) -> void:
	_c.draw_rect(pile, structure)
	var light_side := -1.0 if is_nan(key_x) or key_x < pile.get_center().x else 1.0
	var shadow_width := roundf(pile.size.x * SHADOW_SHARE)
	var shadow_x := pile.end.x - shadow_width if light_side < 0.0 else pile.position.x
	_c.draw_rect(Rect2(shadow_x, pile.position.y, shadow_width, pile.size.y), structure.lerp(deep, SHADOW_MIX))
	var lit_x := pile.position.x + 1.0 if light_side < 0.0 else pile.end.x - 1.0
	_line_rect(_c, Vector2(lit_x, pile.position.y), Vector2(lit_x, pile.end.y), edge)
	var cap := Rect2(pile.position.x - PILE_CAP.x, pile.position.y, pile.size.x + PILE_CAP.x * 2.0, PILE_CAP.y)
	_c.draw_rect(cap, structure)
	_line_rect(_c, Vector2(cap.position.x, cap.end.y), Vector2(cap.end.x, cap.end.y), structure.lerp(deep, SHADOW_MIX))


## 室外地基：上方一道管溝（裡面一條管線），下面錯縫的石塊（越往下越淡），間隔的排水口與往下的水痕。
func _masonry(run: Rect2, rng: RandomNumberGenerator) -> void:
	var depth := _detail_depth(run)
	var trench := Rect2(run.position.x, run.position.y + 3.0, run.size.x, TRENCH)
	_c.draw_rect(trench, structure.lerp(deep, TRENCH_DARK))
	_c.draw_rect(Rect2(trench.position.x, trench.position.y + TRENCH * 0.45, trench.size.x, 2.0), structure)
	var y := trench.end.y + 2.0
	var row := 0
	while y < run.position.y + depth:
		var strength := 1.0 - (y - run.position.y) / depth
		var line := Color(seam, seam.a * strength)
		_line_rect(_c, Vector2(run.position.x, y), Vector2(run.end.x, y), line)
		var x := run.position.x + (0.0 if row % 2 == 0 else BLOCK.x * 0.5) + rng.randf_range(0.0, 6.0)
		while x < run.end.x:
			_line_rect(_c, Vector2(x, y), Vector2(x, minf(y + COURSE, run.end.y)), line)
			# 偶爾一塊比較亮的石頭（受光），讀得出是一塊一塊的。
			if rng.randf() < 0.18:
				_c.draw_rect(Rect2(x + 1.0, y + 1.0, minf(BLOCK.x - 2.0, run.end.x - x - 1.0), COURSE - 2.0), Color(structure, 0.35 * strength))
			x += rng.randf_range(BLOCK.x, BLOCK.y)
		y += COURSE
		row += 1
	# 排水口：管溝下方的半圓暗口，下面一道往下淡掉的水痕。
	var drain := run.position.x + rng.randf_range(16.0, DRAINS.x)
	while drain < run.end.x - 8.0:
		var mouth := Vector2(drain, trench.end.y + 4.0)
		_c.draw_circle(mouth, 3.0, deep)
		_c.draw_rect(Rect2(mouth.x - 4.0, mouth.y - 4.0, 8.0, 1.0), structure)
		_c.draw_rect(Rect2(drain - 1.0, mouth.y + 3.0, 2.0, minf(depth * 0.5, run.size.y - 12.0)), Color(deep, 0.5))
		drain += rng.randf_range(DRAINS.x, DRAINS.y)


## 室內樓板：頂端一道混凝土樓板，下面有對拉孔的牆板（直縫），一條線槽與支架，偶爾一個地漏格柵。
func _interior(run: Rect2, rng: RandomNumberGenerator) -> void:
	var depth := _detail_depth(run)
	_c.draw_rect(Rect2(run.position.x, run.position.y, run.size.x, SLAB), structure)
	_line_rect(_c, Vector2(run.position.x, run.position.y + SLAB), Vector2(run.end.x, run.position.y + SLAB), seam)
	var x := run.position.x + rng.randf_range(0.0, PANEL.x * 0.5)
	while x < run.end.x:
		var width := rng.randf_range(PANEL.x, PANEL.y)
		_line_rect(_c, Vector2(x, run.position.y + SLAB), Vector2(x, run.position.y + depth), seam)
		# 對拉孔：每塊牆板兩排小點。
		for hole_y in [run.position.y + SLAB + 10.0, run.position.y + SLAB + 30.0]:
			if hole_y < run.position.y + depth:
				for hole_x in [x + width * 0.25, x + width * 0.75]:
					if hole_x < run.end.x:
						_c.draw_circle(Vector2(hole_x, hole_y), 1.2, Color(deep, 0.8))
		x += width
	# 線槽：一條橫向的槽，支架往上吊在樓板下。
	var tray_y := run.position.y + SLAB + TRAY_DROP
	if tray_y + 3.0 < run.end.y:
		_c.draw_rect(Rect2(run.position.x, tray_y, run.size.x, 3.0), structure)
		var hanger := run.position.x + rng.randf_range(8.0, 30.0)
		while hanger < run.end.x:
			_line_rect(_c, Vector2(hanger, run.position.y + SLAB), Vector2(hanger, tray_y), structure)
			hanger += rng.randf_range(36.0, 60.0)
	# 地漏格柵：偶爾一個，三條短橫槓。
	var grate := run.position.x + rng.randf_range(40.0, 120.0)
	while grate < run.end.x - 12.0:
		for k in 3:
			_line_rect(_c, Vector2(grate, run.position.y + 2.0 + k * 1.6), Vector2(grate + 10.0, run.position.y + 2.0 + k * 1.6), Color(deep, 0.9))
		grate += rng.randf_range(120.0, 220.0)


## 細節畫到多深：有 fade_depth 時就到那裡（再往下是最暗色），沒有時到整段的一半。
func _detail_depth(run: Rect2) -> float:
	return minf(fade_depth, run.size.y) if fade_depth > 0.0 else run.size.y * 0.5


## 由上往下變不透明的一塊：上緣透明、到 35% 處 0.6、底部 1.0（乘上 color 的 alpha）。用頂點顏色畫成兩段多邊形，
## 不用貼圖：整層都是沒有貼圖的三角形，能合成很少的繪製呼叫（BG-76 量過：貼圖和純色交錯會讓呼叫多出八百多次）。
static func _fade_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var mid := rect.position.y + rect.size.y * 0.35
	var top := Color(color, 0.0)
	var middle := Color(color, color.a * 0.6)
	var bottom := color
	canvas.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, mid), Vector2(rect.position.x, mid)]),
		PackedColorArray([top, top, middle, middle]))
	canvas.draw_polygon(PackedVector2Array([Vector2(rect.position.x, mid), Vector2(rect.end.x, mid), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([middle, middle, bottom, bottom]))


## 由上往下變透明的一塊（頂端是 color，底部完全透明），頂點顏色畫成。
static func _ramp_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var clear := Color(color, 0.0)
	canvas.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([color, color, clear, clear]))


## 一條水平或垂直的 1 像素線，畫成 1 像素寬的矩形（和其他矩形一起合批）。
static func _line_rect(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	canvas.draw_rect(Rect2(minf(from.x, to.x), minf(from.y, to.y), maxf(1.0, absf(to.x - from.x)), maxf(1.0, absf(to.y - from.y))), color)


static func _number(data: Dictionary, key: String, fallback: float, low: float, high: float, problems: PackedStringArray) -> float:
	if not data.has(key):
		return fallback
	var value: Variant = data[key]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < low or float(value) > high:
		problems.append("%s 要是 %s~%s 的數字（%s）" % [key, low, high, value])
		return fallback
	return float(value)
