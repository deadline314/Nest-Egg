extends RefCounted
## Small cel-style heads. Bright geometry stays inside the physical circle;
## the muted rear marks describe weapon identity, never extra damage reach.
const INK := Color(0.055, 0.065, 0.085, 0.95)
static var _dart := PackedVector2Array([Vector2(0.9, 0), Vector2(-0.55, -0.65), Vector2(-0.85, 0), Vector2(-0.55, 0.65)])
static var _diamond := PackedVector2Array([Vector2(0.9, 0), Vector2(0, -0.9), Vector2(-0.9, 0), Vector2(0, 0.9)])
static var _shell := PackedVector2Array([Vector2(0.9, 0), Vector2(0.1, -0.75), Vector2(-0.75, -0.75), Vector2(-0.75, 0.75), Vector2(0.1, 0.75)])
## 紙頁：略斜的平行四邊形（看起來像飄著的單子，不像子彈）。
static var _sheet := PackedVector2Array([Vector2(-0.9, -0.35), Vector2(0.75, -0.75), Vector2(0.9, 0.35), Vector2(-0.75, 0.75)])
static var _octagon := PackedVector2Array([Vector2(0.9, 0.35), Vector2(0.35, 0.9), Vector2(-0.35, 0.9), Vector2(-0.9, 0.35), Vector2(-0.9, -0.35), Vector2(-0.35, -0.9), Vector2(0.35, -0.9), Vector2(0.9, -0.35)])


static func paint(canvas: CanvasItem, spec: ProjectileSpec, color: Color, team: Combat.Team, reflected: bool) -> void:
	var r := maxf(1.0, spec.radius)
	var head := LightKit.glow(color, 1.25)
	var core := Color(0.96, 0.96, 0.88)
	var rear := Color(color, 0.5)
	var tail := minf(spec.length, 22.0)
	# A thin neutral outline survives both lit plaster and dark scenery without bloom.
	_outline(canvas, spec.visual_style, r)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(r, r))
	match spec.visual_style:
		"rifle":
			canvas.draw_colored_polygon(_dart, head)
			canvas.draw_line(Vector2(-0.5, 0), Vector2(0.4, 0), core, 0.4)
		"compact":
			canvas.draw_rect(Rect2(-0.72, -0.42, 1.44, 0.84), head)
			canvas.draw_line(Vector2(0.1, -0.4), Vector2(0.1, 0.4), core, 0.4)
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
	# Weapon-specific muted rear structure; shorter and dimmer than the head.
	match spec.visual_style:
		"rifle":
			canvas.draw_line(Vector2(-r - tail * 0.6, 0), Vector2(-r, 0), rear, 1.1)
		"compact":
			canvas.draw_line(Vector2(-r - 4, 0), Vector2(-r - 2, 0), rear, 1.0)
		"energy":
			canvas.draw_line(Vector2(-r - 7, -1), Vector2(-r - 3, -1), rear, 1.0)
			canvas.draw_line(Vector2(-r - 7, 1), Vector2(-r - 3, 1), rear, 1.0)
		"rail":
			canvas.draw_line(Vector2(-r - tail, -1.2), Vector2(-r - 3, -1.2), rear, 0.8)
			canvas.draw_line(Vector2(-r - tail, 1.2), Vector2(-r - 3, 1.2), rear, 0.8)
		"shell":
			canvas.draw_line(Vector2(-r - 5, -1), Vector2(-r - 2, -1), rear, 1.2)
			canvas.draw_line(Vector2(-r - 5, 1), Vector2(-r - 2, 1), rear, 1.2)
	# Hostile heads have a broken warm rim; reflected rounds a compact cyan rear notch.
	# Shape and team survive grayscale/color changes and the low-effect setting.
	if team == Combat.Team.ENEMY:
		canvas.draw_arc(Vector2.ZERO, r + 0.85, -0.95, 0.95, 5, Color(1.0, 0.3, 0.18), 0.85)
	if reflected:
		canvas.draw_line(Vector2(-r - 2, -2), Vector2(-r - 3, 0), Palette.CYAN, 1.0)
		canvas.draw_line(Vector2(-r - 3, 0), Vector2(-r - 2, 2), Palette.CYAN, 1.0)


static func _outline(canvas: CanvasItem, style: String, r: float) -> void:
	var border := 0.5
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (r + border))
	match style:
		"rifle", "rail":
			canvas.draw_colored_polygon(_dart, INK)
		"energy":
			canvas.draw_colored_polygon(_diamond, INK)
		"grenade":
			canvas.draw_colored_polygon(_octagon, INK)
		"shell":
			canvas.draw_colored_polygon(_shell, INK)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match style:
		"compact":
			canvas.draw_rect(Rect2(-0.72 * r - border, -0.42 * r - border, 1.44 * r + border * 2, 0.84 * r + border * 2), INK)
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
		"rifle", "rail", "energy", "grenade", "shell":
			pass
		_:
			canvas.draw_circle(Vector2.ZERO, 0.74 * r + border, INK)
