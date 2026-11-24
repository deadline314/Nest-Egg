extends RefCounted
## 彈頭的共用貼圖以物理圓心定位。尾端與陣營標記只提供視覺資訊。
const HEADS_PATH := "res://art/projectiles/projectile_heads.png"
const CELL := 32
const HEADS := {"round": 0, "rifle": 1, "compact": 2, "pellet": 3, "energy": 4, "rail": 5, "grenade": 6, "shell": 7}
const INK := Color(0.055, 0.065, 0.085, 0.95)
static var _heads_texture: Texture2D = _load_heads()
static var _streak_points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _streak_colors := PackedColorArray([Color.TRANSPARENT, Color.WHITE, Color.WHITE])
static var _compact := PackedVector2Array([Vector2(0.83, 0), Vector2(0.26, -0.54), Vector2(-0.6, -0.38), Vector2(-0.79, 0), Vector2(-0.6, 0.38), Vector2(0.26, 0.54)])
static var _dart := PackedVector2Array([Vector2(0.9, 0), Vector2(-0.55, -0.65), Vector2(-0.85, 0), Vector2(-0.55, 0.65)])
static var _diamond := PackedVector2Array([Vector2(0.9, 0), Vector2(0, -0.9), Vector2(-0.9, 0), Vector2(0, 0.9)])
static var _shell := PackedVector2Array([Vector2(0.9, 0), Vector2(0.1, -0.75), Vector2(-0.75, -0.75), Vector2(-0.75, 0.75), Vector2(0.1, 0.75)])
## 紙頁：略斜的平行四邊形（看起來像飄著的單子，不像子彈）。
static var _sheet := PackedVector2Array([Vector2(-0.9, -0.35), Vector2(0.75, -0.75), Vector2(0.9, 0.35), Vector2(-0.75, 0.75)])
static var _octagon := PackedVector2Array([Vector2(0.9, 0.35), Vector2(0.35, 0.9), Vector2(-0.35, 0.9), Vector2(-0.9, 0.35), Vector2(-0.9, -0.35), Vector2(-0.35, -0.9), Vector2(0.35, -0.9), Vector2(0.9, -0.35)])


static func paint(canvas: CanvasItem, spec: ProjectileSpec, color: Color, team: Combat.Team, reflected: bool) -> void:
	var r := maxf(1.0, spec.radius)
	var head := LightKit.glow(color, 1.25)
	var rear := Color(color, 0.5)
	var tail := minf(spec.length, 22.0)
	var cell: int = HEADS.get(spec.visual_style, -1)
	if cell >= 0 and _heads_texture != null:
		var source := Rect2((cell % 4) * CELL, (cell >> 2) * CELL, CELL, CELL)
		canvas.draw_texture_rect_region(_heads_texture, Rect2(-r, -r, 2.0 * r, 2.0 * r), source, head)
	else:
		_paint_geometry(canvas, spec.visual_style, r, color, head)
	# Weapon-specific muted rear structure; shorter and dimmer than the head.
	match spec.visual_style:
		"rifle":
			_streak(canvas, -r - tail * 0.6, -r, 0, 1.1, rear)
		"compact":
			_streak(canvas, -r - 4, -r - 2, 0, 1.0, rear)
		"energy":
			_streak(canvas, -r - 7, -r - 3, -1, 1.0, rear)
			_streak(canvas, -r - 7, -r - 3, 1, 1.0, rear)
		"rail":
			_streak(canvas, -r - tail, -r - 3, -1.2, 0.8, rear)
			_streak(canvas, -r - tail, -r - 3, 1.2, 0.8, rear)
		"shell":
			_streak(canvas, -r - 5, -r - 2, -1, 1.2, rear)
			_streak(canvas, -r - 5, -r - 2, 1, 1.2, rear)
	# Hostile heads have a broken warm rim; reflected rounds a compact cyan rear notch.
	# Shape and team survive grayscale/color changes and the low-effect setting.
	if team == Combat.Team.ENEMY:
		canvas.draw_arc(Vector2.ZERO, r + 0.85, -0.95, 0.95, 5, Color(1.0, 0.3, 0.18), 0.85)
	if reflected:
		canvas.draw_line(Vector2(-r - 2, -2), Vector2(-r - 3, 0), Palette.CYAN, 1.0)
		canvas.draw_line(Vector2(-r - 3, 0), Vector2(-r - 2, 2), Palette.CYAN, 1.0)


static func _streak(canvas: CanvasItem, far: float, near: float, y: float, width: float, color: Color) -> void:
	_streak_points[0] = Vector2(far, y)
	_streak_points[1] = Vector2(near, y - width * 0.5)
	_streak_points[2] = Vector2(near, y + width * 0.5)
	_streak_colors[0] = Color(color, 0.0)
	_streak_colors[1] = color
	_streak_colors[2] = color
	canvas.draw_polygon(_streak_points, _streak_colors)


static func _load_heads() -> Texture2D:
	var texture := load(HEADS_PATH) as Texture2D if ResourceLoader.exists(HEADS_PATH) else null
	if texture != null and texture.get_size() == Vector2(4 * CELL, 2 * CELL):
		return texture
	push_warning("[ProjectileArt] 彈頭圖集遺失或尺寸錯誤，改用幾何彈頭：%s" % HEADS_PATH)
	return null


static func _paint_geometry(canvas: CanvasItem, style: String, r: float, color: Color, head: Color) -> void:
	var core := Color(0.96, 0.96, 0.88)
	# A thin neutral outline survives both lit plaster and dark scenery without bloom.
	_outline(canvas, style, r)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(r, r))
	match style:
		"rifle":
			canvas.draw_colored_polygon(_dart, head)
			canvas.draw_line(Vector2(-0.5, 0), Vector2(0.4, 0), core, 0.4)
		"compact":
			canvas.draw_colored_polygon(_compact, head)
			canvas.draw_line(Vector2(-0.32, 0), Vector2(0.36, 0), core, 0.34)
		"pellet":
			canvas.draw_circle(Vector2.ZERO, 0.62, head)
			canvas.draw_circle(Vector2(0.18, -0.18), 0.22, core)
		"energy":
			canvas.draw_colored_polygon(_diamond, head)
			canvas.draw_line(Vector2(-0.4, 0), Vector2(0.4, 0), core, 0.4)
		"rail":
			canvas.draw_colored_polygon(_dart, head)
			canvas.draw_line(Vector2(-0.5, 0), Vector2(0.6, 0), core, 0.35)
		"grenade":
			canvas.draw_colored_polygon(_octagon, color.darkened(0.28))
			canvas.draw_line(Vector2(-0.35, -0.7), Vector2(-0.35, 0.7), head, 0.4)
			canvas.draw_circle(Vector2(0.35, 0), 0.24, core)
		"shell":
			canvas.draw_colored_polygon(_shell, head)
			canvas.draw_line(Vector2(-0.5, -0.6), Vector2(-0.5, 0.6), INK, 0.3)
			canvas.draw_line(Vector2(0, -0.5), Vector2(0.5, 0), core, 0.3)
		"organic":
			canvas.draw_circle(Vector2(-0.18, 0), 0.7, color)
			canvas.draw_circle(Vector2(0.45, -0.18), 0.4, head)
			canvas.draw_circle(Vector2(0.25, -0.4), 0.18, core)
		"wave":
			canvas.draw_arc(Vector2.ZERO, 0.8, -1.8, 1.8, 10, head, 0.4)
			canvas.draw_arc(Vector2(-0.3, 0), 0.5, -1.7, 1.7, 8, core, 0.25)
		"paper":
			# 收帳單：米白的紙頁斜著飛，紅色印章一角（敵方的暖色在紙邊，不靠發光）。
			canvas.draw_colored_polygon(_sheet, Color(0.93, 0.9, 0.8))
			canvas.draw_line(Vector2(-0.55, -0.15), Vector2(0.35, -0.45), Color(0.45, 0.42, 0.38), 0.18)
			canvas.draw_line(Vector2(-0.45, 0.2), Vector2(0.45, -0.1), Color(0.45, 0.42, 0.38), 0.18)
			canvas.draw_circle(Vector2(0.45, 0.35), 0.22, color)
		_:
			canvas.draw_circle(Vector2.ZERO, 0.74, head)
			canvas.draw_line(Vector2(-0.3, 0), Vector2(0.45, 0), core, 0.45)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _outline(canvas: CanvasItem, style: String, r: float) -> void:
	var border := 0.5
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (r + border))
	match style:
		"rifle", "rail":
			canvas.draw_colored_polygon(_dart, INK)
		"compact":
			canvas.draw_colored_polygon(_compact, INK)
		"energy":
			canvas.draw_colored_polygon(_diamond, INK)
		"grenade":
			canvas.draw_colored_polygon(_octagon, INK)
		"shell":
			canvas.draw_colored_polygon(_shell, INK)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match style:
		"pellet":
			canvas.draw_circle(Vector2.ZERO, 0.62 * r + border, INK)
		"organic":
			canvas.draw_circle(Vector2(-0.18 * r, 0), 0.7 * r + border, INK)
			canvas.draw_circle(Vector2(0.45 * r, -0.18 * r), 0.4 * r + border, INK)
		"wave":
			canvas.draw_arc(Vector2.ZERO, r * 0.8, -1.8, 1.8, 10, INK, r * 0.4 + border)
		"paper":
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (r + border))
			canvas.draw_colored_polygon(_sheet, INK)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"round":
			canvas.draw_circle(Vector2.ZERO, 0.74 * r + border, INK)
		"rifle", "rail", "compact", "energy", "grenade", "shell":
			pass
		_:
			canvas.draw_circle(Vector2.ZERO, 0.74 * r + border, INK)
