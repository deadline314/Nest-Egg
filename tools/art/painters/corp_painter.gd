extends HumanoidPainter
## 天穹集團人員的暫代繪製：回收員（第二章頭目的外觀）與第二批敵人——狙擊手、火焰兵、重裝機槍手。
## 輪廓要一眼分得出來：回收員窄長、狙擊手披著斗篷、火焰兵圓厚、重裝機槍手方正巨大；
## 預兆相關的發光（回收員的單眼、狙擊手的鏡片、火焰兵的護目鏡、機槍手的視窗）都放在自發光層。


# ---------------------------------------------------------------------------
# 頭
# ---------------------------------------------------------------------------

func _head_detail(o: Vector2, _skin: Color) -> void:
	match kind:
		"reclaimer":
			_head_reclaimer(o)
		"sniper":
			_head_sniper(o)
		"flamer":
			_head_flamer(o)
		"heavy_gunner":
			_head_heavy(o)
		_:
			super._head_detail(o, _skin)


## 窄長的頭盔、橘色單眼視窗、頭頂天線。
func _head_reclaimer(o: Vector2) -> void:
	var shell := _c("armor")
	var helmet := _p([-12, -8, -15, -26, -11, -44, -3, -50, 7, -50, 15, -42, 18, -30, 15, -14, 6, -8], o)
	_shade(helmet, shell.darkened(0.45), shell.lightened(0.12))
	if not glow:
		K.line(c, _p([-9, -40, -1, -46, 11, -43], o), Color(1, 1, 1, 0.45), 1.8)
		K.line(c, _p([-5, -49, -9, -59], o), shell.darkened(0.3), 1.8)
		K.poly(c, _p([3, -35, 20, -33, 20, -24, 5, -25], o), Color("140a04"), O, 1.5)
		for i in 3:
			K.line(c, _p([5 + i * 4, -19, 6 + i * 4, -11], o), shell.darkened(0.6), 1.5)
	_emit_line(_p([5, -29, 19, -28.5], o), _c("eye"), 2.8)
	_emit_circle(o + Vector2(15, -28.5), 1.8, _c("eye").lightened(0.5))
	_emit_circle(o + Vector2(-9, -59), 1.4, _c("accent"))


## 兜帽與面罩：只露出一枚紅色鏡片，像一隻不眨眼的眼睛。
func _head_sniper(o: Vector2) -> void:
	var cloth := _c("coat")
	var hood := _p([-17, -6, -21, -26, -15, -43, -3, -52, 9, -50, 18, -40, 19, -28, 15, -22, 14, -8, 4, -5], o)
	_shade(hood, cloth.darkened(0.4), cloth.lightened(0.12))
	if not glow:
		K.poly(c, _p([2, -30, 19, -29, 18, -9, 4, -6], o), cloth.darkened(0.55), O, 1.5)
		K.line(c, _p([-12, -42, -2, -49, 10, -47], o), Color(1, 1, 1, 0.25), 1.6)
		K.line(c, _p([-14, -24, -6, -14, 2, -8], o), cloth.darkened(0.55), 1.4)
		K.poly(c, K.ellipse(o + Vector2(12, -27), 6.0, 5.5, 14), Color("14080a"), O, 1.5)
		K.line(c, _p([8, -35, 12, -33], o), cloth.darkened(0.6), 1.4)
	_emit_circle(o + Vector2(12, -27), 4.0, _c("eye"))
	if not glow:
		c.draw_circle(o + Vector2(12, -27), 1.4, Color("ffd9dc"))


## 圓形的耐熱頭盔、兩枚橘色護目鏡與濾罐。
func _head_flamer(o: Vector2) -> void:
	var shell := _c("armor")
	var helmet := K.ellipse(o + Vector2(0, -28), 18.5, 19.5, 16, PI, TAU)
	helmet.append_array(_p([18.5, -24, 19, -14, 12, -7, -4, -7, -14, -12, -18.5, -22], o))
	_shade(helmet, shell.darkened(0.45), shell.lightened(0.1))
	if not glow:
		K.line(c, _p([-13, -38, 0, -46, 12, -42], o), shell.lightened(0.35), 2.0)
		K.poly(c, _p([2, -18, 20, -17, 20, -8, 3, -7], o), Color("2b2622"), O, 1.5)
		K.poly(c, K.ellipse(o + Vector2(20, -12), 4.0, 5.0, 12), Color("4a423a"), O, 1.5)
		K.line(c, _p([18, -14, 22, -10], o), Color("6c6458"), 1.4)
		for lens: Vector2 in [Vector2(5, -29), Vector2(13, -28)]:
			K.poly(c, K.ellipse(o + lens, 4.8, 4.8, 14), Color("1a0f08"), O, 1.5)
	for lens: Vector2 in [Vector2(5, -29), Vector2(13, -28)]:
		_emit_circle(o + lens, 3.2, _c("eye"))
	_emit_line(_p([-17, -22, -9, -22], o), _c("accent"), 1.5)


## 方正的重盔：窄窄的洋紅視窗與厚下顎護板。
func _head_heavy(o: Vector2) -> void:
	var shell := _c("armor")
	var helmet := _p([-16, -8, -19, -30, -14, -44, -2, -50, 10, -48, 19, -38, 20, -18, 12, -8], o)
	_shade(helmet, shell.darkened(0.45), shell.lightened(0.08))
	if not glow:
		K.line(c, _p([-13, -42, -2, -48, 10, -45], o), Color(1, 1, 1, 0.4), 1.8)
		K.poly(c, _p([3, -35, 21, -33, 21, -24, 4, -26], o), Color("160a14"), O, 1.5)
		K.poly(c, _p([6, -21, 21, -19, 18, -9, 8, -9], o), shell.darkened(0.25), O, 1.5)
		for i in 3:
			K.line(c, _p([-13, -32 + i * 5, -6, -31 + i * 5], o), shell.darkened(0.6), 1.5)
	_emit_line(_p([5, -30, 20, -29], o), _c("eye"), 3.0)
	_emit_circle(o + Vector2(-16, -20), 1.4, _c("accent"))


# ---------------------------------------------------------------------------
# 軀幹
# ---------------------------------------------------------------------------

func _torso_body(o: Vector2) -> void:
	var suit := _c("suit")
	match kind:
		"flamer":
			_shade(_p([-12, 0, -14, -16, -15, -32, -11, -41, 11, -41, 16, -32, 17, -20, 13, -10, 11, 0], o), suit.darkened(0.2), suit.lightened(0.1))
		"heavy_gunner":
			_shade(_p([-13, 0, -15, -16, -16, -32, -12, -41, 12, -41, 17, -32, 18, -20, 15, -10, 12, 0], o), suit.darkened(0.2), suit.lightened(0.1))
		_:
			super._torso_body(o)


func _torso_detail(o: Vector2) -> void:
	var armor := _c("armor")
	var coat := _c("coat")
	match kind:
		"reclaimer":
			# 窄身的回收部制服：斜向橘色條紋與胸口的回收標誌。
			var vest := _p([-12, -4, -13, -38, -8, -45, 9, -45, 14, -36, 14, -8, 9, -2], o)
			_shade(vest, armor.darkened(0.4), armor.lightened(0.05))
			if not glow:
				for i in 3:
					K.poly(c, _p([-12 + i * 9, -6, -8 + i * 9, -6, -3 + i * 9, -16, -7 + i * 9, -16], o), _c("accent").darkened(0.2), Color.TRANSPARENT)
				K.line(c, _p([-12, -30, 14, -30], o), armor.darkened(0.5), 1.5)
				K.poly(c, _p([-10, -44, -6, -50, 4, -48, 3, -43], o), armor.darkened(0.25), O, 1.2)
			_emit_line(_p([-12, -33, 14, -33], o), _c("accent"), 1.5)
			_emit_circle(o + Vector2(5, -22), 2.6, _c("accent"))
		"sniper":
			# 披著斗篷的瘦長身形、斜背彈帶、胸口一顆紅色測距燈。
			var cloak := _p([-14, -4, -16, -34, -10, -44, 8, -44, 13, -34, 14, -10, 9, -2], o)
			_shade(cloak, coat.darkened(0.4), coat.lightened(0.08))
			if not glow:
				K.poly(c, _p([-8, -40, -4, -42, 12, -16, 8, -13], o), Color("0e1117"), O, 1.0)
				for i in 3:
					K.poly(c, _p([-1 + i * 4, -33 + i * 6, 2 + i * 4, -34 + i * 6, 3 + i * 4, -30 + i * 6, i * 4, -29 + i * 6], o), _c("accent").darkened(0.3), O, 0.8)
				K.line(c, _p([-12, -38, -2, -43], o), Color(1, 1, 1, 0.25), 1.5)
			_emit_circle(o + Vector2(8, -34), 1.5, _c("eye"))
		"flamer":
			# 厚重的耐熱服：橫向絕緣縫線，背後的接口連著燃料管。
			var suit_shell := _p([-15, -2, -17, -34, -10, -44, 10, -44, 17, -34, 18, -6, 12, 0], o)
			_shade(suit_shell, coat.darkened(0.3), coat.lightened(0.1))
			if not glow:
				for y: float in [-34.0, -26.0, -18.0, -10.0]:
					K.line(c, _p([-15, y, 16, y + 1], o), coat.darkened(0.55), 1.5)
				K.poly(c, _p([-8, -40, -4, -42, 13, -16, 9, -13], o), Color("1b140f"), O, 1.0)
				K.poly(c, _p([-22, -36, -15, -36, -15, -14, -22, -14], o), Color("2b2622"), O, 1.5)
			_emit_circle(o + Vector2(-19, -25), 2.4, _c("accent"))
			_emit_line(_p([-15, -4, 6, -3], o), _c("accent"), 1.5)
		"heavy_gunner":
			# 巨大的胸甲、交叉的彈鏈，背後有一個彈藥箱。
			var plate := _p([-14, -3, -17, -34, -11, -45, 11, -45, 18, -34, 18, -8, 12, -1], o)
			_shade(plate, armor.darkened(0.4), armor.lightened(0.06))
			if not glow:
				K.poly(c, _p([-24, -36, -15, -36, -15, -10, -24, -10], o), Color("2e3038"), O, 1.5)
				for i in 8:
					var t := float(i) / 7.0
					var at := Vector2(lerpf(-12.0, 15.0, t), lerpf(-40.0, -10.0, t))
					K.poly(c, _p([at.x - 2, at.y - 2, at.x + 3, at.y - 3, at.x + 4, at.y + 2, at.x - 1, at.y + 3], o), Color("b08a3a"), O, 0.8)
				K.line(c, _p([-14, -22, 17, -22], o), armor.darkened(0.5), 1.5)
			_emit_line(_p([-12, -14, 16, -14], o), _c("accent"), 1.5)
			_emit_circle(o + Vector2(12, -38), 1.6, _c("accent"))
		_:
			super._torso_detail(o)
