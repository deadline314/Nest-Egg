class_name HumanoidPainter
extends RefCounted
## 人形角色零件的程式繪製（暫代美術）。每個零件依 character.json 的畫布尺寸與支點繪製，
## glow = true 時只畫自發光的部分（霓虹飾條、義眼、指示燈），輸出成 *_glow.png。
## 依 painter_style.kind 產生不同角色：rin（主角）、trooper、grenadier、enforcer、warden。
## 其他角色（NPC 與第二批敵人）由 painters/ 底下的子類別覆寫頭、軀幹等零件，用 create() 依 kind 取得。
## 正式美術完成後這個檔案就不再需要；它同時也是「每個零件該畫什麼」的參考。

const K := preload("res://tools/art/painter_kit.gd")

var style: Dictionary
var kind := "rin"
var glow := false
var c: CanvasItem

## kind → 子類別腳本（路徑延遲載入，避免子類別與基底互相 preload）。新增角色種類只要在這裡登記。
const VARIANT_PATHS := {
	"old_k": "res://tools/art/painters/civilian_painter.gd",
	"mei": "res://tools/art/painters/civilian_painter.gd",
	"wataru": "res://tools/art/painters/civilian_painter.gd",
	"reclaimer": "res://tools/art/painters/corp_painter.gd",
	"sniper": "res://tools/art/painters/corp_painter.gd",
	"flamer": "res://tools/art/painters/corp_painter.gd",
	"heavy_gunner": "res://tools/art/painters/corp_painter.gd",
}

var O: Color  # 描邊
var W := 2.0  # 描邊寬


func _init(p_style: Dictionary) -> void:
	style = p_style
	kind = str(style.get("kind", "rin"))
	O = K.col(style, "outline", Color("07080d"))


## 依 painter_style.kind 建立對應的繪製器；找不到子類別時退回基底（rin 風格），並記錄原因。
static func create(p_style: Dictionary) -> HumanoidPainter:
	var painter_kind := str(p_style.get("kind", "rin"))
	var path: String = VARIANT_PATHS.get(painter_kind, "")
	if not path.is_empty():
		var script := load(path) as GDScript
		if script != null:
			return script.new(p_style) as HumanoidPainter
		push_error("[HumanoidPainter] 無法載入 %s 的繪製腳本：%s" % [painter_kind, path])
	return HumanoidPainter.new(p_style)


func paint(canvas: CanvasItem, texture_name: String, size: Vector2, pivot: Vector2, emissive: bool) -> void:
	c = canvas
	glow = emissive
	match texture_name:
		"head": _head(pivot)
		"hair_front": _hair_front(pivot)
		"hair_back_1": _hair_back(pivot, size, false)
		"hair_back_2": _hair_back(pivot, size, true)
		"torso": _torso(pivot)
		"pelvis": _pelvis(pivot)
		"arm_upper": _arm_upper(pivot)
		"arm_lower": _arm_lower(pivot)
		"hand": _hand(pivot)
		"leg_upper": _leg_upper(pivot)
		"leg_lower": _leg_lower(pivot)
		"foot": _foot(pivot)
		"coat_1": _coat(pivot, size, false)
		"coat_2": _coat(pivot, size, true)
		"armor_chest": _armor_chest(pivot)
		"armor_shoulder": _armor_shoulder(pivot)
		"armor_forearm": _armor_forearm(pivot)
		"armor_knee": _armor_knee(pivot)
		"riot_shield": _riot_shield(pivot, size)
		_:
			push_warning("[HumanoidPainter] 沒有 %s 的繪製方式" % texture_name)


func _c(key: String) -> Color:
	return K.col(style, key)


## 只在基礎層繪製。
func _base(points: PackedVector2Array, fill: Color, outline := true) -> void:
	if not glow:
		K.poly(c, points, fill, O if outline else Color.TRANSPARENT, W)


func _shade(points: PackedVector2Array, dark: Color, light: Color, axis := Vector2.RIGHT, outline := true) -> void:
	if not glow:
		K.grad_poly(c, points, dark, light, axis, O if outline else Color.TRANSPARENT, W)


## 自發光：基礎層畫亮色，發光層畫同樣形狀（之後會被加法混合並 HDR 增亮）。
func _emit_line(points: PackedVector2Array, color: Color, width := 1.5) -> void:
	K.line(c, points, color if not glow else color.lightened(0.2), width)


func _emit_poly(points: PackedVector2Array, color: Color) -> void:
	c.draw_colored_polygon(points, color if not glow else color.lightened(0.2))


func _emit_circle(center: Vector2, radius: float, color: Color) -> void:
	c.draw_circle(center, radius, color if not glow else color.lightened(0.2))


func _p(values: Array, origin := Vector2.ZERO) -> PackedVector2Array:
	var result := K.pts(values)
	for i in result.size():
		result[i] += origin
	return result


# ---------------------------------------------------------------------------
# 頭
# ---------------------------------------------------------------------------

func _head(pv: Vector2) -> void:
	# 以脖子根部為原點的相對座標（向上為負）。
	var o := pv
	var skin := _c("skin")
	# 脖子
	_shade(_p([-5, -16, 5, -16, 5, 2, -5, 2], o), skin.darkened(0.35), skin.darkened(0.15))
	_head_detail(o, skin)


## 頭部本體（依 kind 不同）；子類別覆寫這個函式換臉。
func _head_detail(o: Vector2, skin: Color) -> void:
	match kind:
		"rin":
			_head_rin(o, skin)
		"trooper", "enforcer":
			_head_helmet(o, kind == "enforcer")
		"grenadier":
			_head_gasmask(o)
		"warden":
			_head_warden(o)
		_:
			_head_rin(o, skin)


func _head_rin(o: Vector2, skin: Color) -> void:
	var shape := K.ellipse(o + Vector2(1, -30), 16.5, 18.5, 16, PI, TAU)
	shape.append_array(_p([17, -26, 17, -18, 13, -9, 6, -4, -2, -5, -10, -11, -15, -21], o))
	_shade(shape, skin.darkened(0.22), skin.lightened(0.08))
	if not glow:
		# 頰紅與下顎陰影
		c.draw_circle(o + Vector2(10, -15), 3.0, Color(1.0, 0.45, 0.5, 0.25))
		K.line(c, _p([-10, -11, -2, -5, 6, -4], o), skin.darkened(0.35), 1.5)
		# 耳朵
		K.poly(c, K.ellipse(o + Vector2(-6, -21), 3.0, 4.5, 12), skin.darkened(0.1), O, 1.5)
		# 眼睛（眼白、眼線、睫毛）
		var eye := _p([7, -27, 15, -28, 16, -24, 9, -22], o)
		K.poly(c, eye, Color("f4f7ff"), Color.TRANSPARENT)
		K.line(c, _p([6, -27.5, 11, -29.5, 16.5, -28.5], o), O, 2.5)
		K.line(c, _p([16.5, -28.5, 18, -30], o), O, 1.5)
		# 眉毛（被瀏海蓋住一半）
		K.line(c, _p([7, -33, 12, -34.5, 16, -33.5], o), Color("2a2d3a"), 1.5)
		# 鼻、嘴
		K.line(c, _p([17.5, -22, 18.5, -19.5, 17, -19], o), skin.darkened(0.3), 1.2)
		K.line(c, _p([12, -13.5, 15, -13], o), Color("7a3a44"), 1.4)
	# 義眼虹膜（自發光）與臉頰義體線
	_emit_circle(o + Vector2(12.5, -25.5), 2.6, _c("eye"))
	if not glow:
		c.draw_circle(o + Vector2(12.5, -25.5), 1.0, Color.WHITE)
	_emit_line(_p([3, -17, 8, -16, 10, -13], o), _c("trim"), 1.2)
	# 頸圈（choker）
	if not glow:
		K.poly(c, _p([-5.5, -8, 5.5, -8, 5.5, -5, -5.5, -5], o), Color("12151c"), O, 1.0)
	_emit_circle(o + Vector2(3, -6.5), 1.0, _c("lining"))


func _head_helmet(o: Vector2, riot: bool) -> void:
	var shell := _c("armor")
	var helmet := K.ellipse(o + Vector2(0, -28), 17.5, 19.0, 16, PI, TAU)
	helmet.append_array(_p([17.5, -24, 18, -14, 12, -7, -4, -7, -14, -12, -17.5, -22], o))
	_shade(helmet, shell.darkened(0.4), shell.lightened(0.12))
	if not glow:
		K.line(c, _p([-14, -36, 0, -45, 12, -42], o), shell.lightened(0.35), 2.0)
		K.poly(c, _p([-10, -14, 2, -12, 2, -8, -10, -9], o), shell.darkened(0.3), O, 1.5)
		if riot:
			# 透明面罩
			K.poly(c, _p([4, -36, 19, -32, 20, -14, 6, -10], o), Color(0.6, 0.75, 0.9, 0.35), O, 1.5)
			K.line(c, _p([8, -34, 17, -31], o), Color(1, 1, 1, 0.5), 1.5)
	# 護目鏡（自發光）
	var visor := _p([2, -30, 18.5, -28, 18.5, -22, 3, -23], o)
	if not glow:
		K.poly(c, visor, Color("1a0a10"), O, 1.5)
	_emit_poly(_p([4, -28, 17.5, -26.5, 17.5, -24, 4, -25], o), _c("eye"))
	_emit_line(_p([-16, -24, -8, -24], o), _c("accent"), 1.5)


func _head_gasmask(o: Vector2) -> void:
	var shell := _c("armor")
	var hood := K.ellipse(o + Vector2(-1, -28), 17.0, 19.0, 16, PI, TAU)
	hood.append_array(_p([16, -22, 12, -8, -4, -6, -15, -12, -18, -22], o))
	_shade(hood, shell.darkened(0.45), shell.lightened(0.05))
	if not glow:
		# 面具與濾罐
		K.poly(c, _p([2, -30, 16, -28, 19, -18, 14, -9, 3, -9], o), Color("2b2a26"), O, 1.5)
		K.poly(c, K.ellipse(o + Vector2(17, -12), 4.5, 5.0, 12), Color("4a463d"), O, 1.5)
		K.line(c, _p([15, -14, 19, -10], o), Color("6c665a"), 1.5)
	for lens: Vector2 in [Vector2(8, -24), Vector2(14, -24)]:
		if not glow:
			K.poly(c, K.ellipse(o + lens, 3.2, 3.2, 12), Color("15120d"), O, 1.2)
		_emit_circle(o + lens, 2.0, _c("eye"))


func _head_warden(o: Vector2) -> void:
	var chrome := _c("chrome")
	var shape := _p([-15, -16, -17, -32, -10, -44, 6, -46, 17, -38, 19, -24, 15, -12, 4, -6, -8, -8], o)
	_shade(shape, chrome.darkened(0.55), chrome.lightened(0.1))
	if not glow:
		K.line(c, _p([-12, -38, 4, -42, 15, -35], o), chrome.lightened(0.4), 2.0)
		K.poly(c, _p([2, -32, 19, -30, 19, -20, 4, -20], o), Color("130608"), O, 1.5)
		K.line(c, _p([-14, -24, -2, -22, 0, -10], o), chrome.darkened(0.4), 1.5)
	# 單眼（自發光）
	_emit_circle(o + Vector2(13, -25), 3.4, _c("eye"))
	_emit_line(_p([5, -25, 18, -25], o), _c("eye"), 1.5)


# ---------------------------------------------------------------------------
# 頭髮（只有主角）
# ---------------------------------------------------------------------------

func _hair_front(pv: Vector2) -> void:
	if kind != "rin":
		return
	var o := pv + Vector2(1, 0)
	var hair := _c("hair")
	var tip := _c("hair_tip")
	# 不對稱短鮑伯：頭頂蓬鬆、瀏海往右前方掃，髮尾帶洋紅漸層。
	var mass := _p([-19, -16, -21, -30, -16, -43, -4, -50, 10, -49, 19, -42, 22, -33, 20, -24, 17, -28, 15, -22, 12, -30,
			9, -25, 6, -32, 0, -31, -8, -36, -11, -26, -13, -12], o)
	_shade(mass, hair.darkened(0.2), hair.lightened(0.05), Vector2(0.3, -1))
	if not glow:
		# 髮尾洋紅（瀏海尖端）
		for tri: Array in [[20, -24, 17, -28, 21, -30], [15, -22, 12, -30, 16, -29], [9, -25, 6, -32, 10, -31], [-13, -12, -11, -26, -16, -20]]:
			K.poly(c, _p(tri, o), tip, Color.TRANSPARENT)
		# 光澤
		K.line(c, _p([-10, -42, -2, -46, 8, -45], o), Color(1, 1, 1, 0.7), 2.0)
		K.line(c, _p([-14, -34, -12, -40], o), Color(1, 1, 1, 0.4), 1.5)
		# 髮夾（黃色）
		K.poly(c, _p([-6, -40, 0, -42, 1, -39, -5, -37], o), _c("accent"), O, 1.0)


func _hair_back(pv: Vector2, size: Vector2, tail: bool) -> void:
	if kind != "rin":
		return
	var hair := _c("hair")
	var tip := _c("hair_tip")
	var w := size.x * 0.32 if not tail else size.x * 0.26
	var length := size.y - pv.y - 4.0
	var shape := _p([-w, 0, w, 0, w * 0.8, length * 0.6, 2, length, -w * 0.6, length * 0.7], pv)
	_shade(shape, hair.darkened(0.3), hair if not tail else tip, Vector2(0, 1))
	if not glow:
		K.line(c, _p([-w * 0.3, 2, -w * 0.2, length * 0.6], pv), Color(1, 1, 1, 0.35), 1.5)


# ---------------------------------------------------------------------------
# 軀幹
# ---------------------------------------------------------------------------

func _torso(pv: Vector2) -> void:
	# 原點＝腰部；肩膀在 y=-40，脖子在 y=-48；胸口朝右。
	_torso_body(pv)
	_torso_detail(pv)


func _torso_body(o: Vector2) -> void:
	var suit := _c("suit")
	_shade(_p([-9, 0, -11, -16, -12, -32, -9, -40, 9, -40, 13, -32, 14, -22, 11, -12, 9, 0], o), suit.darkened(0.2), suit.lightened(0.12))


## 軀幹的服裝與裝備（依 kind 不同）；子類別覆寫這個函式換衣服。
func _torso_detail(o: Vector2) -> void:
	var coat := _c("coat")
	match kind:
		"rin":
			# 短版外套（開襟，洋紅內裡）＋高領
			var jacket := _p([-13, -14, -14, -34, -10, -43, -4, -47, 2, -46, 4, -40, 6, -30, 4, -20, -2, -14], o)
			_shade(jacket, coat.darkened(0.25), coat.lightened(0.1))
			if not glow:
				K.poly(c, _p([2, -46, 6, -30, 4, -20, 1, -22, 3, -32, 0, -42], o), _c("lining"), Color.TRANSPARENT)
				# 胸前斜背帶與扣環
				K.poly(c, _p([-8, -38, -5, -40, 13, -18, 10, -16], o), Color("0e1117"), O, 1.0)
				K.poly(c, _p([3, -29, 7, -29, 7, -25, 3, -25], o), _c("accent"), O, 1.0)
			_emit_line(_p([-13, -15, -2, -14], o), _c("trim"), 1.5)
			_emit_line(_p([0, -42, 3, -32, 1, -22], o), _c("trim"), 1.2)
			_emit_circle(o + Vector2(-9, -33), 1.3, _c("trim"))
		"trooper", "enforcer":
			var vest := _p([-13, -6, -14, -36, -9, -43, 9, -43, 15, -34, 15, -10, 9, -4], o)
			_shade(vest, _c("armor").darkened(0.35), _c("armor").lightened(0.08))
			if not glow:
				K.line(c, _p([-10, -24, 13, -24], o), _c("armor").darkened(0.45), 1.5)
				for x: float in [-6.0, 1.0, 8.0]:
					K.poly(c, _p([x - 3, -20, x + 3, -20, x + 3, -12, x - 3, -12], o), Color("1d2129"), O, 1.0)
				if kind == "enforcer":
					for i in 3:
						K.poly(c, _p([-12 + i * 9, -38, -8 + i * 9, -38, -10 + i * 9, -32, -14 + i * 9, -32], o), _c("accent"), Color.TRANSPARENT)
			_emit_line(_p([-12, -30, 14, -30], o), _c("accent"), 1.5)
			_emit_circle(o + Vector2(10, -38), 1.4, _c("eye"))
		"grenadier":
			var vest := _p([-14, -4, -15, -36, -9, -44, 9, -44, 15, -34, 16, -8, 10, -2], o)
			_shade(vest, _c("armor").darkened(0.35), _c("armor").lightened(0.06))
			if not glow:
				# 背上的彈藥罐
				K.poly(c, _p([-18, -36, -12, -36, -12, -8, -18, -8], o), Color("4c4436"), O, 1.5)
				for y: float in [-30.0, -20.0]:
					K.poly(c, K.ellipse(o + Vector2(4, y), 3.5, 3.0, 10), Color("6d6250"), O, 1.0)
			_emit_circle(o + Vector2(-15, -32), 1.5, _c("accent"))
			_emit_circle(o + Vector2(-15, -14), 1.5, _c("accent"))
		"warden":
			var chrome := _c("chrome")
			var plate := _p([-15, -2, -17, -34, -11, -46, 11, -46, 18, -34, 17, -8, 11, 0], o)
			_shade(plate, chrome.darkened(0.55), chrome.lightened(0.05))
			if not glow:
				K.line(c, _p([-12, -36, 0, -40, 14, -34], o), chrome.lightened(0.35), 2.0)
				K.poly(c, K.ellipse(o + Vector2(2, -24), 7.0, 7.0, 16), Color("1a0608"), O, 1.5)
			_emit_circle(o + Vector2(2, -24), 4.5, _c("eye"))
			_emit_line(_p([-12, -12, 14, -12], o), _c("accent"), 1.5)


func _pelvis(pv: Vector2) -> void:
	var o := pv
	var pants := _c("pants")
	var hips := _p([-13, -8, 13, -8, 15, 6, 11, 18, -11, 18, -15, 6], o)
	_shade(hips, pants.darkened(0.25), pants.lightened(0.08))
	if not glow:
		# 腰帶、扣環、側包
		K.poly(c, _p([-14, -8, 14, -8, 14, -3, -14, -3], o), Color("101218"), O, 1.5)
		K.poly(c, _p([6, -8, 11, -8, 11, -3, 6, -3], o), _c("accent") if kind == "rin" else _c("chrome"), O, 1.0)
		K.poly(c, _p([-17, -4, -10, -4, -10, 8, -17, 8], o), _c("coat").darkened(0.2), O, 1.5)
	_emit_line(_p([-16, 2, -11, 2], o), _c("trim"), 1.2)


# ---------------------------------------------------------------------------
# 四肢
# ---------------------------------------------------------------------------

func _arm_upper(pv: Vector2) -> void:
	var o := pv
	var sleeve := _c("coat") if kind != "warden" else _c("chrome")
	_shade(K.capsule(o, o + Vector2(0, 36), 8.0, 6.5), sleeve.darkened(0.3), sleeve.lightened(0.1))
	if not glow:
		K.poly(c, _p([-7, 26, 7, 26, 7, 31, -7, 31], o), sleeve.darkened(0.35), O, 1.0)
	_emit_line(_p([5, 4, 5.5, 24], o), _c("trim"), 1.5)


func _arm_lower(pv: Vector2) -> void:
	var o := pv
	if kind == "rin" or kind == "warden":
		# 義體前臂：鉻金屬＋發光接縫
		var chrome := _c("chrome")
		_shade(K.capsule(o, o + Vector2(0, 32), 6.0, 5.0), chrome.darkened(0.45), chrome.lightened(0.2))
		if not glow:
			K.line(c, _p([-5, 10, 5, 10], o), chrome.darkened(0.5), 1.2)
			K.line(c, _p([-4.5, 22, 4.5, 22], o), chrome.darkened(0.5), 1.2)
			K.line(c, _p([2, 2, 3, 30], o), Color(1, 1, 1, 0.6), 1.2)
		for y: float in [6.0, 16.0, 26.0]:
			_emit_circle(o + Vector2(-2.5, y), 1.1, _c("trim"))
		_emit_line(_p([-1, 12, -1, 20], o), _c("trim"), 1.0)
	else:
		var sleeve := _c("suit")
		_shade(K.capsule(o, o + Vector2(0, 32), 6.0, 5.0), sleeve.darkened(0.3), sleeve.lightened(0.1))
		if not glow:
			K.poly(c, _p([-6, 18, 6, 18, 5.5, 30, -5.5, 30], o), _c("armor").darkened(0.15), O, 1.2)


func _hand(pv: Vector2) -> void:
	var o := pv
	var glove := Color("161a22") if kind != "warden" else _c("chrome").darkened(0.3)
	# 握拳（拳面朝右）
	var fist := _p([-3, -5, 9, -5, 12, -1, 12, 6, 8, 9, -3, 8, -5, 2], o)
	_shade(fist, glove.darkened(0.2), glove.lightened(0.25))
	if not glow:
		K.line(c, _p([4, -4, 4, 7], o), glove.lightened(0.35), 1.0)
		K.line(c, _p([8, -4, 8, 8], o), glove.lightened(0.35), 1.0)
		K.poly(c, _p([-2, -6, 4, -8, 6, -5, 0, -3], o), glove.lightened(0.15), O, 1.0)


func _leg_upper(pv: Vector2) -> void:
	var o := pv
	var pants := _c("pants")
	_shade(K.capsule(o, o + Vector2(0, 44), 9.5, 7.5), pants.darkened(0.3), pants.lightened(0.1))
	if not glow:
		K.line(c, _p([4, 6, 5, 40], o), pants.darkened(0.4), 1.2)
		if kind == "rin":
			# 大腿槍套綁帶
			K.poly(c, _p([-9, 16, 9, 18, 9, 22, -9, 20], o), Color("0e1117"), O, 1.0)
			K.poly(c, _p([-10, 18, -4, 18, -4, 32, -10, 30], o), Color("181c24"), O, 1.0)


func _leg_lower(pv: Vector2) -> void:
	var o := pv
	var boots := _c("boots")
	_shade(K.capsule(o, o + Vector2(0, 44), 7.5, 6.0), boots.darkened(0.15), boots.lightened(0.18))
	if not glow:
		for y: float in [14.0, 26.0, 36.0]:
			K.poly(c, _p([-7, y, 7, y + 1.5, 7, y + 4, -7, y + 2.5], o), Color("05060a"), Color.TRANSPARENT)
		K.line(c, _p([3, 4, 4, 40], o), boots.lightened(0.35), 1.2)
	_emit_line(_p([-6.5, 9, 6.5, 10], o), _c("trim") if kind == "rin" else _c("accent"), 1.2)


func _foot(pv: Vector2) -> void:
	var o := pv
	var boots := _c("boots")
	var shoe := _p([-6, -3, 6, -3, 10, 4, 20, 6, 23, 10, 22, 15, -8, 15, -8, 4], o)
	_shade(shoe, boots.darkened(0.1), boots.lightened(0.2))
	if not glow:
		K.line(c, _p([4, 0, 10, 5, 19, 7], o), boots.lightened(0.4), 1.2)
	# 霓虹鞋底
	_emit_poly(_p([-8, 12, 22, 12, 22, 15, -8, 15], o), _c("lining") if kind == "rin" else _c("accent").darkened(0.3))


func _coat(pv: Vector2, size: Vector2, lower: bool) -> void:
	var o := pv
	var coat := _c("coat")
	var length := size.y - pv.y - 2.0
	var shape: PackedVector2Array
	if lower:
		shape = _p([-14, 0, 14, 0, 11, length * 0.85, 2, length, -10, length * 0.9], o)
	else:
		shape = _p([-12, 0, 12, 0, 14, length, -14, length], o)
	_shade(shape, coat.darkened(0.35), coat.lightened(0.05), Vector2(0.4, 1))
	if not glow:
		K.line(c, _p([-12, 0, -13, length * 0.9], o), _c("lining"), 2.0)
	if lower:
		_emit_line(_p([-10, length * 0.9, 2, length, 11, length * 0.85], o), _c("trim"), 1.5)


# ---------------------------------------------------------------------------
# 可破壞裝甲
# ---------------------------------------------------------------------------

func _armor_chest(pv: Vector2) -> void:
	var o := pv
	var armor := _c("armor")
	var plate := _p([-14, -24, 10, -26, 16, -16, 15, -4, -12, -2, -16, -12], o)
	_shade(plate, armor.darkened(0.4), armor.lightened(0.15))
	if not glow:
		K.line(c, _p([-12, -14, 14, -14], o), armor.darkened(0.45), 1.2)
		K.line(c, _p([-10, -22, 8, -24], o), Color(1, 1, 1, 0.6), 1.5)
	_emit_line(_p([-8, -8, 10, -9], o), _c("trim"), 1.2)


func _armor_shoulder(pv: Vector2) -> void:
	var o := pv
	var armor := _c("armor")
	var pad := _p([-12, 0, -8, -9, 9, -9, 14, 0, 11, 12, -10, 12], o)
	_shade(pad, armor.darkened(0.4), armor.lightened(0.15), Vector2(0.6, -1))
	if not glow:
		K.line(c, _p([-8, -6, 9, -6], o), Color(1, 1, 1, 0.55), 1.5)
		K.line(c, _p([-10, 6, 12, 6], o), armor.darkened(0.45), 1.2)


func _armor_forearm(pv: Vector2) -> void:
	var o := pv
	var armor := _c("armor")
	_shade(_p([-8, -2, 8, -2, 7, 20, -7, 20], o), armor.darkened(0.4), armor.lightened(0.12))
	if not glow:
		K.line(c, _p([-6, 8, 6, 8], o), armor.darkened(0.45), 1.2)
	_emit_circle(o + Vector2(4, 14), 1.2, _c("trim"))


func _armor_knee(pv: Vector2) -> void:
	var o := pv
	var armor := _c("armor")
	_shade(_p([-9, -6, 9, -6, 11, 4, 0, 13, -11, 4], o), armor.darkened(0.4), armor.lightened(0.15))
	if not glow:
		K.line(c, _p([-6, -3, 6, -3], o), Color(1, 1, 1, 0.5), 1.5)


func _riot_shield(pv: Vector2, size: Vector2) -> void:
	var o := Vector2(pv.x, 0)
	var face := _p([2, 4, 26, 2, 30, 10, 30, size.y - 10, 26, size.y - 2, 2, size.y - 4], o)
	_shade(face, Color("1b2029"), Color("3a4352"))
	if not glow:
		for i in 4:
			var y := 16.0 + i * 16.0
			K.poly(c, _p([4, y, 28, y - 4, 28, y, 4, y + 4], o), _c("accent"), Color.TRANSPARENT)
		K.line(c, _p([6, 6, 6, size.y - 8], o), Color(1, 1, 1, 0.35), 1.5)
	_emit_poly(_p([10, 30, 24, 29, 24, 33, 10, 34], o), _c("eye"))
