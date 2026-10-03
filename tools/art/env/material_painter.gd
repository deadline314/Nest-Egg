class_name MaterialPainter
extends RefCounted
## 地形材質的程式繪製（暫代美術）：每種材質輸出 body（64×64，可雙向平鋪）、top（64×24，沿頂端橫向平鋪）、
## side（24×64，沿邊緣縱向平鋪）。要換成手繪，只要覆蓋同名 PNG。
## 所有雜訊都以座標雜湊產生，邊緣相接處沒有接縫。

const BODY := Vector2i(64, 64)
const TOP := Vector2i(64, 24)
const SIDE := Vector2i(24, 64)

## 材質清單：id -> {name, base（主色）, accent（點綴）, kind（繪製函式）}。
const CATALOG: Array[Dictionary] = [
	{"id": "asphalt", "name": "濕柏油路", "base": "2a2e38", "accent": "3a4254", "kind": "asphalt"},
	{"id": "concrete", "name": "混凝土", "base": "3a3f48", "accent": "566070", "kind": "concrete"},
	{"id": "brick", "name": "老舊磚牆", "base": "3c2a2c", "accent": "5a3a38", "kind": "brick"},
	{"id": "rooftop", "name": "屋頂", "base": "2c3036", "accent": "484e58", "kind": "rooftop"},
	{"id": "container_red", "name": "紅色貨櫃", "base": "5a2a28", "accent": "7a3a34", "kind": "container"},
	{"id": "container_blue", "name": "藍色貨櫃", "base": "26405a", "accent": "36597c", "kind": "container"},
	{"id": "container_green", "name": "綠色貨櫃", "base": "2a4a3a", "accent": "3a6650", "kind": "container"},
	{"id": "container_rust", "name": "鏽蝕貨櫃", "base": "5a3a24", "accent": "7a5030", "kind": "container"},
	{"id": "steel_plate", "name": "鋼板", "base": "343c48", "accent": "50607a", "kind": "steel"},
	{"id": "grate", "name": "格柵", "base": "262c36", "accent": "46566a", "kind": "grate"},
	{"id": "facility_floor", "name": "設施地板", "base": "2e3844", "accent": "35e0ff", "kind": "facility_floor"},
	{"id": "facility_panel", "name": "設施面板", "base": "2a3442", "accent": "35e0ff", "kind": "facility_panel"},
	{"id": "glass_curtain", "name": "玻璃帷幕", "base": "1c2c3c", "accent": "5a8aa8", "kind": "glass"},
	{"id": "hangar", "name": "機庫地板", "base": "30343c", "accent": "ffc94a", "kind": "hangar"},
	{"id": "old_metal", "name": "老舊金屬", "base": "3a3430", "accent": "6a4a30", "kind": "rust"},
]


## 回傳 {"body": EnvCanvas, "top": EnvCanvas, "side": EnvCanvas}。
static func paint(spec: Dictionary) -> Dictionary:
	var seed_value := absi(str(spec["id"]).hash())
	var body := EnvCanvas.new(BODY.x, BODY.y, seed_value)
	var top := EnvCanvas.new(TOP.x, TOP.y, seed_value + 1)
	var side := EnvCanvas.new(SIDE.x, SIDE.y, seed_value + 2)
	var base := Color(str(spec["base"]))
	var accent := Color(str(spec["accent"]))
	match str(spec["kind"]):
		"asphalt":
			_asphalt(body, top, side, base, accent)
		"concrete":
			_concrete(body, top, side, base, accent)
		"brick":
			_brick(body, top, side, base, accent)
		"rooftop":
			_rooftop(body, top, side, base, accent)
		"container":
			_container(body, top, side, base, accent)
		"steel":
			_steel(body, top, side, base, accent)
		"grate":
			_grate(body, top, side, base, accent)
		"facility_floor":
			_facility_floor(body, top, side, base, accent)
		"facility_panel":
			_facility_panel(body, top, side, base, accent)
		"glass":
			_glass(body, top, side, base, accent)
		"hangar":
			_hangar(body, top, side, base, accent)
		_:
			_rust(body, top, side, base, accent)
	return {"body": body, "top": top, "side": side}


# 共用：頂面條的高光邊（亮在上緣）與側邊條的暗邊。
static func _top_finish(top: EnvCanvas, base: Color, highlight := 0.16) -> void:
	top.hline(0, base.lightened(highlight + 0.1), 0, -1, 2)
	top.hline(2, base.lightened(highlight), 0, -1, 2)
	top.hline(TOP.y - 3, base.darkened(0.3), 0, -1, 3)


static func _side_finish(side: EnvCanvas, base: Color) -> void:
	side.vline(0, base.lightened(0.12), 0, -1, 2)
	side.vline(SIDE.x - 3, base.darkened(0.28), 0, -1, 3)


static func _asphalt(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.022)
	body.speckle(0.06, base.lightened(0.12), 11)
	body.speckle(0.05, base.darkened(0.25), 12)
	# 積水的反光斑與細裂縫（都在格子內，不跨邊）。
	body.rect_noise(8, 40, 30, 8, accent, 0.01, 4)
	body.hline(42, Color(0.5, 0.65, 0.9, 0.12), 10, 36)
	body.line(Vector2i(46, 6), Vector2i(40, 22), base.darkened(0.45))
	body.line(Vector2i(40, 22), Vector2i(42, 30), base.darkened(0.45))
	top.fill_noise(base.lightened(0.1), 0.02)
	top.hline(0, Color(0.55, 0.65, 0.85, 0.5), 0, -1, 2)
	top.speckle(0.08, base.lightened(0.3), 3)
	_top_finish(top, base.lightened(0.06), 0.1)
	side.fill_noise(base.darkened(0.1), 0.02)
	_side_finish(side, base)


static func _concrete(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.03)
	body.speckle(0.04, base.lightened(0.1), 5)
	body.hline(0, base.darkened(0.3), 0, -1, 2)
	body.vline(0, base.darkened(0.3), 0, -1, 2)
	body.hline(2, base.lightened(0.07), 0, -1, 1)
	body.rivet(8, 8, base, 2)
	body.rivet(56, 8, base, 2)
	body.rivet(8, 56, base, 2)
	body.rivet(56, 56, base, 2)
	body.streak(24, 6, 36, Color(0.0, 0.0, 0.0, 0.18), 2)
	body.streak(41, 18, 24, Color(0.0, 0.0, 0.0, 0.14), 5)
	top.fill_noise(accent, 0.025)
	_top_finish(top, accent, 0.1)
	top.vline(32, accent.darkened(0.25), 3, 20)
	side.fill_noise(base.darkened(0.05), 0.03)
	_side_finish(side, base)


static func _brick(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	var colors: Array[Color] = [base, base.lightened(0.05), base.darkened(0.08), accent.darkened(0.15), base.lightened(0.1)]
	body.bricks(0, 0, 64, 64, 16, 8, colors, base.darkened(0.45), 2)
	body.speckle(0.05, Color(0, 0, 0, 0.2), 8)
	body.streak(10, 0, 40, Color(0, 0, 0, 0.18), 9)
	top.bricks(0, 0, 64, 24, 16, 12, [accent, accent.lightened(0.06), accent.darkened(0.08)], base.darkened(0.5), 2)
	_top_finish(top, accent, 0.12)
	side.bricks(0, 0, 24, 64, 12, 8, colors, base.darkened(0.45), 2)
	_side_finish(side, base)


static func _rooftop(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.03)
	body.speckle(0.16, accent, 13)
	body.speckle(0.08, base.darkened(0.3), 14)
	body.speckle(0.03, accent.lightened(0.25), 15)
	top.fill_noise(accent.darkened(0.15), 0.025)
	top.speckle(0.1, accent.lightened(0.15), 4)
	_top_finish(top, accent, 0.14)
	top.hline(10, accent.darkened(0.2), 0, -1, 1)
	side.fill_noise(base.darkened(0.05), 0.03)
	side.speckle(0.1, accent, 9)
	_side_finish(side, base)


static func _container(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.corrugation(0, 0, 64, 64, 8, base, 0.08, 0.12)
	body.speckle(0.04, base.lightened(0.15), 6)
	body.streak(6, 0, 50, Color(0.0, 0.0, 0.0, 0.2), 1)
	body.streak(38, 8, 40, Color(0.3, 0.15, 0.05, 0.22), 2)
	body.hline(0, base.darkened(0.3), 0, -1, 2)
	body.hline(62, base.darkened(0.3), 0, -1, 2)
	top.fill_noise(accent, 0.02)
	top.corrugation(0, 4, 64, 14, 8, accent.darkened(0.08), 0.06, 0.1)
	_top_finish(top, accent, 0.14)
	side.fill_noise(accent.darkened(0.1), 0.02)
	side.rect(6, 0, 12, 64, accent.darkened(0.2))
	for y in [8, 32, 56]:
		side.rivet(12, y, accent, 2)
	_side_finish(side, accent)


static func _steel(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.025)
	body.frame(0, 0, 64, 64, base.darkened(0.35), 2)
	body.frame(2, 2, 60, 60, base.lightened(0.07), 1)
	for p in [Vector2i(7, 7), Vector2i(57, 7), Vector2i(7, 57), Vector2i(57, 57)]:
		body.rivet(p.x, p.y, base, 2)
	body.hline(32, base.darkened(0.2), 4, 60, 1)
	body.streak(20, 34, 26, accent.darkened(0.3), 3)
	top.fill_noise(accent.darkened(0.3), 0.02)
	_top_finish(top, accent.darkened(0.2), 0.14)
	side.fill_noise(base, 0.02)
	_side_finish(side, base)
	for y in [10, 42]:
		side.rivet(11, y, base, 2)


static func _grate(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base.darkened(0.55), 0.01)
	for i in range(0, 64, 8):
		body.rect(i, 0, 4, 64, base)
		body.rect(i, 0, 1, 64, accent)
		body.rect(0, i, 64, 4, base.lightened(0.05))
		body.rect(0, i, 64, 1, accent)
	top.fill_noise(base, 0.02)
	for i in range(0, 64, 8):
		top.rect(i, 0, 4, 24, base.lightened(0.04))
	_top_finish(top, accent, 0.2)
	side.fill_noise(base, 0.02)
	_side_finish(side, base)


static func _facility_floor(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.015)
	body.frame(0, 0, 64, 64, base.darkened(0.4), 2)
	body.frame(2, 2, 60, 60, base.lightened(0.05), 1)
	body.rect(28, 4, 8, 2, accent.darkened(0.2))
	body.rect(28, 58, 8, 2, accent.darkened(0.2))
	body.speckle(0.03, base.lightened(0.14), 7)
	top.fill_noise(base.lightened(0.1), 0.015)
	top.hline(1, accent, 0, -1, 2)
	top.hline(3, accent.darkened(0.5), 0, -1, 1)
	_top_finish(top, base.lightened(0.1), 0.1)
	side.fill_noise(base, 0.015)
	_side_finish(side, base)


static func _facility_panel(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.015)
	body.bevel(4, 4, 56, 26, base.lightened(0.02), 0.05, 0.1, 2)
	body.bevel(4, 34, 56, 26, base.darkened(0.04), 0.05, 0.1, 2)
	for i in 5:
		body.rect(12 + i * 4, 10, 2, 14, base.darkened(0.5))
	body.rect(40, 42, 14, 2, accent.darkened(0.35))
	body.rect(40, 48, 8, 2, accent.darkened(0.55))
	body.rivet(8, 38, base, 1)
	body.rivet(8, 56, base, 1)
	top.fill_noise(base.lightened(0.08), 0.015)
	top.hline(4, accent.darkened(0.3), 0, -1, 1)
	_top_finish(top, base.lightened(0.08), 0.12)
	side.fill_noise(base, 0.015)
	_side_finish(side, base)


static func _glass(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.012)
	body.rect_gradient(0, 0, 64, 64, base.lightened(0.06), base.darkened(0.15))
	body.line(Vector2i(8, 40), Vector2i(30, 8), Color(accent, 0.22))
	body.line(Vector2i(12, 52), Vector2i(40, 10), Color(accent, 0.14))
	body.frame(0, 0, 64, 64, base.darkened(0.45), 3)
	body.vline(31, base.darkened(0.5), 0, -1, 2)
	top.fill_noise(base.lightened(0.05), 0.012)
	top.hline(1, accent, 0, -1, 2)
	_top_finish(top, base.lightened(0.15), 0.14)
	side.fill_noise(base, 0.012)
	_side_finish(side, base)


static func _hangar(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.02)
	body.frame(0, 0, 64, 64, base.darkened(0.4), 2)
	body.hline(32, base.darkened(0.3), 2, 62, 2)
	body.diagonal_stripes(0, 58, 64, 6, accent.darkened(0.35), base.darkened(0.2), 8)
	body.speckle(0.05, base.lightened(0.1), 3)
	body.streak(14, 4, 26, Color(0, 0, 0, 0.2), 4)
	top.fill_noise(base.lightened(0.04), 0.02)
	top.diagonal_stripes(0, 4, 64, 8, accent.darkened(0.15), base.darkened(0.3), 8)
	_top_finish(top, base.lightened(0.08), 0.12)
	side.fill_noise(base, 0.02)
	_side_finish(side, base)


static func _rust(body: EnvCanvas, top: EnvCanvas, side: EnvCanvas, base: Color, accent: Color) -> void:
	body.fill_noise(base, 0.03)
	body.speckle(0.14, accent.darkened(0.2), 21)
	body.speckle(0.06, accent, 22)
	body.streak(12, 0, 52, accent.darkened(0.1), 23)
	body.streak(40, 6, 40, accent.darkened(0.25), 24)
	body.hline(31, base.darkened(0.4), 0, -1, 2)
	top.fill_noise(accent.darkened(0.2), 0.03)
	top.speckle(0.1, accent, 25)
	_top_finish(top, accent, 0.1)
	side.fill_noise(base.darkened(0.05), 0.03)
	side.speckle(0.1, accent, 26)
	_side_finish(side, base)
