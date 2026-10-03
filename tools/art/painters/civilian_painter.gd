extends HumanoidPainter
## 平民角色的暫代繪製：老 K（掮客）、芽（駭客）、航（十一歲的病童）。
## 髮色、服裝以對話頭像為準（見 portrait_painter.gd）。沒有可破壞裝甲；
## 航使用較小的 scale（character.json），貼圖規格與其他角色完全相同。
## 自發光只留給最能代表角色的小東西：老 K 的墨鏡反光、芽的耳機與護目鏡、航的醫療手環。


# ---------------------------------------------------------------------------
# 頭與頭髮
# ---------------------------------------------------------------------------

func _head_detail(o: Vector2, skin: Color) -> void:
	match kind:
		"old_k":
			_face_shape(o, skin, 3.0)
			_old_k_face(o, skin)
		"mei":
			_face_shape(o, skin, 0.0)
			_girl_eye(o, 2.6, false, false)
			_mei_gear(o)
		"wataru":
			_face_shape(o, skin, -1.0)
			_girl_eye(o, 3.4, true, true)
		_:
			_face_shape(o, skin, 0.0)


## 臉的輪廓、耳朵與下顎陰影（jaw：下巴往外加寬的量，老 K 比較方正）。
func _face_shape(o: Vector2, skin: Color, jaw: float) -> void:
	var shape := K.ellipse(o + Vector2(1, -30), 16.5, 18.5, 16, PI, TAU)
	shape.append_array(_p([17, -26, 17, -18, 13 + jaw, -9, 6, -4, -2, -5, -10 - jaw, -11, -15, -21], o))
	_shade(shape, skin.darkened(0.22), skin.lightened(0.08))
	if not glow:
		K.line(c, _p([-10, -11, -2, -5, 6, -4], o), skin.darkened(0.35), 1.5)
		K.poly(c, K.ellipse(o + Vector2(-6, -21), 3.0, 4.5, 12), skin.darkened(0.1), O, 1.5)


## 動漫風的大眼睛（芽與航共用）；big = true 時眼睛更大更圓（航）；glowing_iris = false 時虹膜不進發光層。
func _girl_eye(o: Vector2, iris_radius: float, big: bool, glowing_iris: bool) -> void:
	var iris_at := o + Vector2(12.5, -25.5) if not big else o + Vector2(10.5, -25)
	if not glow:
		var eye := _p([7, -27, 15, -28, 16, -24, 9, -22], o) if not big else _p([5, -28.5, 14.5, -29.5, 15.5, -22.5, 6.5, -21], o)
		K.poly(c, eye, Color("f4f7ff"), Color.TRANSPARENT)
		K.line(c, _p([6, -27.5, 11, -29.5, 16.5, -28.5], o) if not big else _p([4, -29, 10, -31, 15.5, -30], o), O, 2.5)
		K.line(c, _p([16.5, -28.5, 18, -30], o) if not big else _p([15.5, -30, 17, -31.5], o), O, 1.5)
		K.line(c, _p([7, -34, 12, -35.5, 16, -34.5], o), Color("2a2d3a"), 1.5)
		K.line(c, _p([17.5, -22, 18.5, -19.5, 17, -19], o), _c("skin").darkened(0.3), 1.2)
		K.line(c, _p([12, -13.5, 15, -13], o), Color("7a3a44") if not big else Color("a8606a"), 1.4)
		c.draw_circle(o + Vector2(10, -15), 3.0, Color(1.0, 0.45, 0.5, 0.25))
		if big:
			# 眼袋：久病的蒼白。
			K.line(c, _p([8, -19.5, 13, -19, 16.5, -20], o), Color(0.45, 0.4, 0.6, 0.35), 1.2)
	if glowing_iris:
		_emit_circle(iris_at, iris_radius, _c("eye"))
	elif not glow:
		c.draw_circle(iris_at, iris_radius, _c("eye").darkened(0.15))
	if not glow:
		c.draw_circle(iris_at, iris_radius * 0.42, Color("0a0c14"))
		c.draw_circle(iris_at + Vector2(1.2, -1.2), 1.0, Color.WHITE)


func _old_k_face(o: Vector2, _skin: Color) -> void:
	var gold := _c("accent")
	if not glow:
		# 粗眉、鬍渣與疤痕
		K.line(c, _p([3, -35, 10, -36.5, 17, -35], o), Color("4d4a48"), 2.2)
		for i in 24:
			c.draw_circle(o + Vector2(2.0 + (i % 8) * 2.0, -12.0 + (i / 8) * 2.6), 0.55, Color("6b5244"))
		K.line(c, _p([11, -22, 13, -17, 12.5, -13], o), Color("8f5a4a"), 1.4)
		K.line(c, _p([17.5, -22, 19, -19.5, 17, -18.5], o), _c("skin").darkened(0.3), 1.2)
		K.line(c, _p([9, -12, 15, -11.5], o), Color("5a2a2a"), 1.6)
		# 墨鏡：深色鏡框，黃色鏡片的反光
		K.poly(c, _p([3, -32, 19.5, -31, 19.5, -23, 5, -22], o), Color("1d190c"), O, 1.5)
		K.line(c, _p([-14, -29, 3, -28], o), O, 1.5)
	_emit_line(_p([6, -29, 17, -29.5], o), gold, 1.8)
	_emit_line(_p([7, -25, 12, -25], o), gold.darkened(0.2), 1.2)


## 芽的耳機（耳罩與麥克風）與半透明護目鏡。
func _mei_gear(o: Vector2) -> void:
	var violet := _c("trim")
	if not glow:
		K.poly(c, _p([3, -33, 19.5, -32, 20, -20, 5, -19], o), Color(0.65, 0.42, 1.0, 0.3), O, 1.2)
		K.line(c, _p([-14, -28, 3, -27], o), Color("1c1a26"), 2.0)
		# 耳罩
		K.poly(c, K.ellipse(o + Vector2(-5, -23), 6.5, 8.5, 14), Color("1c1a26"), O, 1.5)
		# 麥克風臂
		K.line(c, _p([-5, -17, -2, -8, 8, -4, 15, -7], o), Color("1c1a26"), 2.0)
	_emit_circle(o + Vector2(-5, -23), 3.0, violet)
	_emit_circle(o + Vector2(15, -7), 1.6, violet)
	_emit_line(_p([3, -33, 19.5, -32, 20, -20, 5, -19, 3, -33], o), violet.darkened(0.15), 0.9)


func _hair_front(pv: Vector2) -> void:
	var o := pv + Vector2(1, 0)
	var hair := _c("hair")
	match kind:
		"old_k":
			# 往後梳的灰色油頭與鬢角。
			var mass := _p([-17, -20, -19, -32, -15, -43, -5, -49, 7, -49, 15, -43, 17, -36, 10, -39, 2, -41, -6, -38, -12, -30, -14, -20], o)
			_shade(mass, hair.darkened(0.35), hair.lightened(0.2), Vector2(0.4, -1))
			if not glow:
				K.poly(c, _p([-9, -23, -4, -23, -4, -15, -9, -17], o), hair.darkened(0.2), Color.TRANSPARENT)
				K.line(c, _p([11, -45, -1, -47, -11, -41], o), Color(1, 1, 1, 0.4), 1.6)
				K.line(c, _p([13, -41, 2, -44, -8, -38], o), Color(1, 1, 1, 0.25), 1.2)
		"mei":
			# 齊瀏海的紫色鮑伯，耳機頭帶從頭頂繞過去。
			var bob := _p([-20, -12, -22, -28, -17, -43, -4, -51, 10, -50, 20, -42, 22, -33, 19, -29.5, 15, -33.5, 11, -29, 7, -34, 3, -30, -1, -34, -5, -30, -9, -31, -11, -14], o)
			_shade(bob, hair.darkened(0.3), hair.lightened(0.1), Vector2(0.4, -1))
			if not glow:
				for x: float in [-12.0, -4.0, 4.0, 12.0]:
					K.line(c, _p([x + 4, -48, x, -42, x - 2, -34], o), hair.darkened(0.45), 1.2)
				K.line(c, _p([-7, -45, 3, -49, 13, -46], o), Color(1, 1, 1, 0.45), 1.8)
				K.line(c, _p([-5, -31, -13, -42, -3, -50.5, 10, -50, 17, -44], o), Color("1c1a26"), 2.4)
		"wataru":
			# 蓬鬆凌亂的深色短髮，頭頂翹起一撮。
			var fluff := _p([-19, -14, -21, -30, -17, -44, -5, -51, 9, -51, 19, -44, 22, -35, 19, -26, 16, -32, 13, -24, 10, -33, 6, -26, 3, -34, -3, -30, -9, -36, -12, -26, -13, -14], o)
			_shade(fluff, hair, hair.lightened(0.28), Vector2(0.3, -1))
			if not glow:
				K.poly(c, _p([-3, -50, 0, -57, 3, -50], o), hair.lightened(0.1), O, 1.2)
				K.line(c, _p([-8, -45, 2, -48, 11, -45], o), Color(1, 1, 1, 0.3), 1.5)


func _hair_back(pv: Vector2, size: Vector2, _tail: bool) -> void:
	# 後髮只有第一段（鮑伯、後腦的髮絲）：短而厚。
	var hair := _c("hair")
	var w := size.x * 0.34
	var length := 24.0 if kind == "mei" else 15.0
	var shape := _p([-w, 0, w, 0, w * 0.9, length * 0.7, 2, length, -w * 0.8, length * 0.78], pv)
	_shade(shape, hair.darkened(0.35), hair.darkened(0.05), Vector2(0, 1))
	if not glow and kind == "mei":
		K.line(c, _p([-w * 0.3, 2, -w * 0.2, length * 0.6], pv), Color(1, 1, 1, 0.3), 1.5)


# ---------------------------------------------------------------------------
# 軀幹與衣服
# ---------------------------------------------------------------------------

func _torso_body(o: Vector2) -> void:
	var suit := _c("suit")
	match kind:
		"old_k":
			# 富態的中年身形：肚子比一般角色圓。
			_shade(_p([-10, 0, -12, -16, -13, -32, -10, -40, 10, -40, 15, -32, 17, -22, 14, -10, 10, 0], o), suit.darkened(0.2), suit.lightened(0.12))
		"wataru":
			_shade(_p([-8, 0, -10, -16, -10, -32, -8, -40, 8, -40, 11, -32, 12, -22, 10, -12, 8, 0], o), suit.darkened(0.1), suit.lightened(0.15))
		_:
			super._torso_body(o)


func _torso_detail(o: Vector2) -> void:
	var coat := _c("coat")
	match kind:
		"old_k":
			# 長大衣：高領、敞開的前襟露出裡面的襯衫，黃色滾邊。
			var shell := _p([-16, -4, -17, -36, -11, -44, -3, -46, 3, -45, 5, -38, 7, -28, 6, -14, 2, -6, -2, -2], o)
			_shade(shell, coat.darkened(0.3), coat.lightened(0.1))
			if not glow:
				K.poly(c, _p([1, -45, 7, -30, 6, -12, 3, -8, 3, -30, 0, -42], o), _c("lining"), Color.TRANSPARENT)
				K.poly(c, _p([-13, -42, -10, -51, 0, -48, 3, -42], o), coat.darkened(0.2), O, 1.5)
				K.poly(c, _p([3, -42, 7, -50, 14, -44, 11, -37], o), coat.darkened(0.1), O, 1.5)
				for y: float in [-30.0, -20.0]:
					c.draw_circle(o + Vector2(-2, y), 1.3, _c("accent").darkened(0.35))
			_emit_line(_p([-16, -5, -3, -2], o), _c("trim"), 1.5)
			_emit_line(_p([3, -42, 6, -30, 5, -14], o), _c("trim"), 1.2)
		"mei":
			# 短版連帽夾克（洋紅換成紫色內裡），胸前有一條發光的訊號線。
			var jacket := _p([-13, -14, -14, -34, -10, -43, -4, -47, 2, -46, 4, -40, 6, -30, 4, -20, -2, -14], o)
			_shade(jacket, coat.darkened(0.25), coat.lightened(0.12))
			if not glow:
				K.poly(c, _p([2, -46, 6, -30, 4, -20, 1, -22, 3, -32, 0, -42], o), _c("lining"), Color.TRANSPARENT)
				K.poly(c, _p([-8, -38, -5, -40, 13, -18, 10, -16], o), Color("0e1117"), O, 1.0)
				K.poly(c, _p([-11, -42, -6, -48, 2, -46, 1, -41], o), coat.darkened(0.15), O, 1.2)
			_emit_line(_p([-13, -15, -2, -14], o), _c("trim"), 1.5)
			_emit_line(_p([0, -42, 3, -32, 1, -22], o), _c("trim"), 1.2)
			_emit_circle(o + Vector2(-9, -33), 1.3, _c("trim"))
		"wataru":
			# 病號服：淡綠色、V 領、背後綁帶，胸前掛著醫療識別扣。
			var gown := _p([-10, -2, -11, -34, -8, -42, 8, -42, 12, -34, 13, -6, 10, 0], o)
			_shade(gown, coat.darkened(0.2), coat.lightened(0.1))
			if not glow:
				K.poly(c, _p([-2, -42, 7, -42, 3, -30], o), _c("skin").darkened(0.15), O, 1.0)
				K.line(c, _p([-2, -42, 3, -30, 7, -42], o), _c("trim"), 1.5)
				K.line(c, _p([-9, -24, -2, -23], o), coat.darkened(0.4), 1.2)
			_emit_circle(o + Vector2(7, -26), 1.8, _c("eye"))
		_:
			super._torso_detail(o)


func _pelvis(pv: Vector2) -> void:
	if kind != "wataru":
		super._pelvis(pv)
		return
	# 病號褲：沒有腰帶，鬆鬆的。
	var pants := _c("pants")
	_shade(_p([-12, -8, 12, -8, 14, 6, 10, 18, -10, 18, -14, 6], pv), pants.darkened(0.15), pants.lightened(0.1))
	if not glow:
		K.line(c, _p([-12, -6, 12, -6], pv), pants.darkened(0.35), 1.5)


# ---------------------------------------------------------------------------
# 四肢
# ---------------------------------------------------------------------------

func _arm_upper(pv: Vector2) -> void:
	var skin := _c("skin")
	match kind:
		"wataru":
			# 短袖病號服：上半是布，下半是手臂。
			_shade(K.capsule(pv, pv + Vector2(0, 36), 6.5, 5.5), skin.darkened(0.25), skin.lightened(0.05))
			_shade(K.capsule(pv, pv + Vector2(0, 18), 7.5, 7.0), _c("coat").darkened(0.2), _c("coat").lightened(0.1))
		"mei":
			var sleeve := _c("coat")
			_shade(K.capsule(pv, pv + Vector2(0, 36), 7.0, 6.0), sleeve.darkened(0.3), sleeve.lightened(0.1))
			if not glow:
				K.poly(c, _p([-6, 26, 6, 26, 6, 31, -6, 31], pv), sleeve.darkened(0.35), O, 1.0)
			_emit_line(_p([4, 4, 4.5, 24], pv), _c("trim"), 1.5)
		_:
			var coat := _c("coat")
			_shade(K.capsule(pv, pv + Vector2(0, 36), 8.5, 7.0), coat.darkened(0.3), coat.lightened(0.1))
			if not glow:
				K.poly(c, _p([-7.5, 26, 7.5, 26, 7.5, 31, -7.5, 31], pv), coat.darkened(0.35), O, 1.0)


func _arm_lower(pv: Vector2) -> void:
	var skin := _c("skin")
	match kind:
		"wataru":
			_shade(K.capsule(pv, pv + Vector2(0, 32), 5.0, 4.0), skin.darkened(0.25), skin.lightened(0.08))
			if not glow:
				K.poly(c, _p([-5, 22, 5, 22, 4.5, 28, -4.5, 28], pv), Color("e9f7ee"), O, 1.0)
			# 醫療手環：細細的一圈淡綠光。
			_emit_line(_p([-4.5, 25, 4.5, 25], pv), _c("trim").darkened(0.1), 1.8)
		"mei":
			var sleeve := _c("suit")
			_shade(K.capsule(pv, pv + Vector2(0, 32), 6.0, 5.0), sleeve.darkened(0.3), sleeve.lightened(0.1))
			if not glow:
				K.poly(c, _p([-6, 18, 6, 18, 5.5, 30, -5.5, 30], pv), _c("armor"), O, 1.2)
			_emit_line(_p([-5, 20, -5, 28], pv), _c("trim"), 1.5)
		_:
			var coat := _c("coat")
			_shade(K.capsule(pv, pv + Vector2(0, 32), 7.0, 5.5), coat.darkened(0.3), coat.lightened(0.1))
			if not glow:
				K.poly(c, _p([-7, 24, 7, 24, 6, 31, -6, 31], pv), _c("lining"), O, 1.0)


func _hand(pv: Vector2) -> void:
	var glove := _c("skin").darkened(0.05)
	if kind == "mei":
		glove = Color("1c1a26")
	var fist := _p([-3, -5, 9, -5, 12, -1, 12, 6, 8, 9, -3, 8, -5, 2], pv)
	_shade(fist, glove.darkened(0.2), glove.lightened(0.2))
	if not glow:
		K.line(c, _p([4, -4, 4, 7], pv), glove.darkened(0.35), 1.0)
		K.line(c, _p([8, -4, 8, 8], pv), glove.darkened(0.35), 1.0)
		K.poly(c, _p([-2, -6, 4, -8, 6, -5, 0, -3], pv), glove.lightened(0.15), O, 1.0)


func _leg_lower(pv: Vector2) -> void:
	if kind != "wataru":
		super._leg_lower(pv)
		return
	var pants := _c("pants")
	var skin := _c("skin")
	_shade(K.capsule(pv, pv + Vector2(0, 44), 6.5, 5.0), skin.darkened(0.2), skin.lightened(0.08))
	_shade(K.capsule(pv, pv + Vector2(0, 14), 8.0, 7.5), pants.darkened(0.15), pants.lightened(0.1))


func _foot(pv: Vector2) -> void:
	if kind != "wataru":
		super._foot(pv)
		return
	# 醫院的拖鞋：扁、淺色，沒有霓虹鞋底。
	var slipper := _c("boots")
	var shoe := _p([-6, -3, 6, -3, 10, 5, 19, 8, 22, 12, 21, 15, -8, 15, -8, 4], pv)
	_shade(shoe, slipper.darkened(0.2), slipper.lightened(0.1))
	if not glow:
		K.line(c, _p([4, 0, 10, 6, 18, 9], pv), slipper.lightened(0.3), 1.2)
		K.line(c, _p([-8, 12.5, 21, 12.5], pv), slipper.darkened(0.4), 1.5)
