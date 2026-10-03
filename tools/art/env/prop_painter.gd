class_name PropPainter
extends RefCounted
## 場景道具的程式繪製（暫代美術）：每個道具輸出 diffuse 與（有發光時）glow。
## 尺寸為邏輯像素 × 4；要換成手繪只要覆蓋同名 PNG（左上角對齊）。
## CATALOG 同時是 PropData 資料檔的來源（tools/art/paint_environment.gd 依它輸出 .tres）。

const S := 4

const STEEL := Color("3a4452")
const DARK := Color("1c222c")
const RUST := Color("5a3a28")
const WARM := Color("ffb066")
const CYAN := Color("35e0ff")
const MAGENTA := Color("ff2e88")
const YELLOW := Color("ffc94a")

## id, name, size, layer（back/front）, category, painter, glow, light {color, radius, energy, offset}, flicker, platform, shadow
const CATALOG: Array[Dictionary] = [
	# 屋頂與巷弄
	{"id": "water_tower", "name": "水塔", "size": [40, 56], "cat": "rooftop", "painter": "water_tower", "shadow": true},
	{"id": "ac_unit", "name": "冷氣室外機", "size": [24, 16], "cat": "rooftop", "painter": "ac_unit"},
	{"id": "ac_unit_big", "name": "大型冷氣機", "size": [36, 22], "cat": "rooftop", "painter": "ac_unit"},
	{"id": "antenna", "name": "天線", "size": [14, 56], "cat": "rooftop", "painter": "antenna", "glow": true, "light": [[1.0, 0.2, 0.15], 40.0, 0.4, [7, 3]], "flicker": 0.6},
	{"id": "satellite_dish", "name": "衛星天線", "size": [22, 22], "cat": "rooftop", "painter": "dish"},
	{"id": "clothesline", "name": "晾衣架", "size": [64, 36], "cat": "rooftop", "painter": "clothesline"},
	{"id": "vent_stack", "name": "排氣管", "size": [16, 32], "cat": "rooftop", "painter": "vent_stack"},
	{"id": "chimney_stack", "name": "煙囪", "size": [20, 44], "cat": "rooftop", "painter": "chimney", "shadow": true},
	{"id": "rooftop_hut", "name": "樓梯間", "size": [40, 32], "cat": "rooftop", "painter": "hut", "glow": true, "light": [[1.0, 0.75, 0.4], 56.0, 0.6, [20, 22]], "shadow": true},
	# 街道
	{"id": "trash_can", "name": "垃圾桶", "size": [12, 16], "cat": "street", "painter": "trash_can"},
	{"id": "dumpster", "name": "大型垃圾箱", "size": [40, 24], "cat": "street", "painter": "dumpster", "shadow": true},
	{"id": "crates_stack", "name": "貨箱堆", "size": [32, 28], "cat": "street", "painter": "crates", "shadow": true},
	{"id": "barrels", "name": "油桶堆", "size": [28, 20], "cat": "street", "painter": "barrels"},
	{"id": "fire_escape", "name": "逃生梯", "size": [48, 72], "cat": "street", "painter": "fire_escape", "platform": [0, 26, 48, 4]},
	{"id": "fire_escape_ladder", "name": "逃生爬梯", "size": [12, 56], "cat": "street", "painter": "ladder"},
	{"id": "pipe_vertical", "name": "直立管線", "size": [6, 64], "cat": "street", "painter": "pipe_v"},
	{"id": "pipe_horizontal", "name": "橫向管線", "size": [64, 8], "cat": "street", "painter": "pipe_h"},
	{"id": "puddle", "name": "積水", "size": [40, 4], "cat": "street", "painter": "puddle", "glow": true},
	{"id": "graffiti", "name": "塗鴉", "size": [32, 24], "cat": "street", "painter": "graffiti", "glow": true},
	{"id": "utility_pole", "name": "電線桿", "size": [48, 80], "cat": "street", "painter": "pole", "layer": "front"},
	{"id": "street_lamp", "name": "路燈", "size": [20, 60], "cat": "street", "painter": "street_lamp", "glow": true, "light": [[1.0, 0.8, 0.5], 90.0, 0.9, [4, 6]], "flicker": 0.08},
	{"id": "vending_machine", "name": "販賣機", "size": [18, 32], "cat": "street", "painter": "vending", "glow": true, "light": [[0.5, 0.9, 1.0], 44.0, 0.6, [9, 14]]},
	{"id": "neon_sign_v", "name": "直式霓虹招牌", "size": [14, 40], "cat": "street", "painter": "neon_v", "glow": true, "light": [[1.0, 0.18, 0.53], 60.0, 0.8, [7, 20]], "flicker": 0.3},
	{"id": "neon_sign_h", "name": "橫式霓虹招牌", "size": [40, 14], "cat": "street", "painter": "neon_h", "glow": true, "light": [[0.2, 0.88, 1.0], 60.0, 0.8, [20, 7]], "flicker": 0.15},
	{"id": "billboard_ad", "name": "廣告看板", "size": [64, 32], "cat": "street", "painter": "billboard", "glow": true, "light": [[0.55, 0.65, 1.0], 80.0, 0.6, [32, 16]]},
	{"id": "lantern_string", "name": "燈籠串", "size": [96, 16], "cat": "street", "painter": "lanterns", "glow": true, "light": [[1.0, 0.6, 0.3], 80.0, 0.7, [48, 10]]},
	{"id": "noodle_stall", "name": "麵攤", "size": [64, 48], "cat": "street", "painter": "noodle_stall", "glow": true, "light": [[1.0, 0.72, 0.4], 96.0, 1.0, [32, 28]], "platform": [2, 8, 60, 4]},
	{"id": "awning", "name": "雨棚", "size": [48, 14], "cat": "street", "painter": "awning", "platform": [0, 5, 48, 4]},
	{"id": "bench", "name": "長椅", "size": [28, 14], "cat": "street", "painter": "bench"},
	{"id": "bus_stop", "name": "候車亭", "size": [44, 40], "cat": "street", "painter": "bus_stop", "glow": true, "light": [[0.6, 0.85, 1.0], 56.0, 0.5, [22, 18]]},
	# 貨運站
	{"id": "container_back", "name": "背景貨櫃", "size": [48, 24], "cat": "cargo", "painter": "container_prop"},
	{"id": "crane_arm", "name": "起重機", "size": [128, 72], "cat": "cargo", "painter": "crane", "glow": true, "light": [[1.0, 0.3, 0.2], 40.0, 0.4, [118, 6]], "flicker": 0.5},
	{"id": "forklift", "name": "堆高機", "size": [40, 26], "cat": "cargo", "painter": "forklift", "glow": true},
	{"id": "fence", "name": "鐵絲網柵欄", "size": [32, 22], "cat": "cargo", "painter": "fence"},
	{"id": "worker_hut", "name": "工人休息室", "size": [64, 40], "cat": "cargo", "painter": "worker_hut", "glow": true, "light": [[1.0, 0.8, 0.5], 90.0, 0.9, [24, 24]], "shadow": true},
	{"id": "pallet_stack", "name": "棧板堆", "size": [28, 22], "cat": "cargo", "painter": "pallets"},
	# 設施
	{"id": "control_console", "name": "控制台", "size": [28, 22], "cat": "facility", "painter": "console", "glow": true, "light": [[0.2, 0.88, 1.0], 48.0, 0.6, [14, 8]]},
	{"id": "server_rack", "name": "伺服器機櫃", "size": [18, 40], "cat": "facility", "painter": "rack", "glow": true, "light": [[0.2, 0.88, 1.0], 40.0, 0.4, [9, 20]]},
	{"id": "camera_wall", "name": "監視攝影機", "size": [14, 12], "cat": "facility", "painter": "camera", "glow": true, "light": [[1.0, 0.2, 0.15], 24.0, 0.4, [10, 8]], "flicker": 0.3},
	{"id": "emergency_light", "name": "應急燈", "size": [14, 8], "cat": "facility", "painter": "emergency", "glow": true, "light": [[1.0, 0.2, 0.15], 70.0, 0.9, [7, 6]], "flicker": 0.45},
	{"id": "cables_hang", "name": "垂下的電纜", "size": [48, 28], "cat": "facility", "painter": "cables", "layer": "front"},
	{"id": "gate_door", "name": "閘門", "size": [24, 48], "cat": "facility", "painter": "gate", "glow": true},
	{"id": "hazard_sign", "name": "警示牌", "size": [16, 16], "cat": "facility", "painter": "hazard", "glow": true},
	{"id": "facility_pipes", "name": "設施管線", "size": [64, 16], "cat": "facility", "painter": "facility_pipes"},
	{"id": "floor_marking", "name": "地面標線", "size": [64, 4], "cat": "facility", "painter": "marking"},
	# 機庫
	{"id": "gantry_crane", "name": "龍門吊", "size": [160, 80], "cat": "hangar", "painter": "gantry", "glow": true, "light": [[1.0, 0.3, 0.2], 60.0, 0.5, [20, 70]], "flicker": 0.4},
	{"id": "hangar_light", "name": "機庫燈", "size": [20, 10], "cat": "hangar", "painter": "hangar_light", "glow": true, "light": [[1.0, 0.9, 0.7], 110.0, 0.9, [10, 8]]},
	{"id": "fuel_tank", "name": "燃料槽", "size": [32, 40], "cat": "hangar", "painter": "tank", "shadow": true},
]


## 回傳 {"diffuse": EnvCanvas, "glow": EnvCanvas 或 null}。
static func paint(spec: Dictionary) -> Dictionary:
	var size: Array = spec["size"]
	var seed_value := absi(str(spec["id"]).hash())
	var c := EnvCanvas.new(int(size[0]) * S, int(size[1]) * S, seed_value)
	var g: EnvCanvas = EnvCanvas.new(c.width(), c.height(), seed_value + 1) if bool(spec.get("glow", false)) else null
	var painter := str(spec["painter"])
	var callable := Callable(PropPainter, "_p_" + painter)
	if callable.is_valid():
		callable.call(c, g)
	else:
		push_error("[PropPainter] 沒有繪製函式：%s" % painter)
	c.outline(Color(0.02, 0.03, 0.05, 1.0))
	return {"diffuse": c, "glow": g}


# ---- 共用零件 -------------------------------------------------------------

static func _metal(c: EnvCanvas, x: int, y: int, w: int, h: int, base := STEEL) -> void:
	c.bevel(x, y, w, h, base, 0.08, 0.14, 3)
	c.speckle(0.05, base.lightened(0.12), 3, x, y, w, h)


static func _pipe_h(c: EnvCanvas, x: int, y: int, w: int, h: int, base := STEEL) -> void:
	c.rect(x, y, w, h, base)
	c.rect(x, y, w, h / 4, base.lightened(0.14))
	c.rect(x, y + h - h / 4, w, h / 4, base.darkened(0.25))


static func _pipe_v(c: EnvCanvas, x: int, y: int, w: int, h: int, base := STEEL) -> void:
	c.rect(x, y, w, h, base)
	c.rect(x, y, w / 4, h, base.lightened(0.14))
	c.rect(x + w - w / 4, y, w / 4, h, base.darkened(0.25))


static func _ribs(c: EnvCanvas, x: int, y: int, w: int, h: int, step: int, color: Color) -> void:
	var yy := y
	while yy < y + h:
		c.hline(yy, color, x, x + w, 2)
		yy += step


# ---- 屋頂 -----------------------------------------------------------------

static func _p_water_tower(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	for x in [40, 120]:
		c.rect(x, 130, 10, 94, DARK.lightened(0.05))
	c.line(Vector2i(45, 140), Vector2i(125, 220), DARK.lightened(0.1))
	c.line(Vector2i(125, 140), Vector2i(45, 220), DARK.lightened(0.1))
	c.rect(20, 56, 120, 80, RUST.lightened(0.05))
	c.corrugation(20, 56, 120, 80, 10, RUST, 0.06, 0.1)
	c.polygon(PackedVector2Array([Vector2(20, 56), Vector2(80, 24), Vector2(140, 56)]), RUST.darkened(0.1))
	c.hline(100, RUST.darkened(0.4), 20, 140, 3)
	c.streak(50, 60, 60, Color(0, 0, 0, 0.3), 2)
	c.rect(74, 8, 12, 20, DARK.lightened(0.1))


static func _p_ac_unit(c: EnvCanvas, _g: EnvCanvas) -> void:
	_metal(c, 4, 12, c.width() - 8, c.height() - 16, Color("48525e"))
	var fan_r := float(c.height() - 24) * 0.4
	c.circle(c.width() * 0.3, c.height() * 0.55, fan_r, DARK)
	c.circle(c.width() * 0.3, c.height() * 0.55, fan_r * 0.45, STEEL.lightened(0.1))
	for i in 4:
		c.hline(22 + i * 6, DARK, int(c.width() * 0.6), c.width() - 14, 3)
	c.rect(8, c.height() - 8, 6, 8, DARK)
	c.rect(c.width() - 14, c.height() - 8, 6, 8, DARK)
	c.streak(c.width() - 20, c.height() - 8, 20, Color(0.3, 0.4, 0.5, 0.35), 3)


static func _p_antenna(c: EnvCanvas, g: EnvCanvas) -> void:
	var mid := c.width() / 2
	c.rect(mid - 3, 24, 6, c.height() - 24, STEEL)
	for i in 4:
		var y := 40 + i * 44
		c.rect(mid - 20 + i * 3, y, 40 - i * 6, 4, STEEL.lightened(0.08))
	c.line(Vector2i(mid, 24), Vector2i(mid - 14, c.height()), STEEL.darkened(0.2))
	c.line(Vector2i(mid, 24), Vector2i(mid + 14, c.height()), STEEL.darkened(0.2))
	c.circle(mid, 16, 8, Color("ff4030"))
	g.circle(mid, 16, 12, Color(1.0, 0.25, 0.15, 0.95))


static func _p_dish(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(w / 2 - 4, c.height() - 28, 8, 28, STEEL)
	c.ellipse(w / 2.0, c.height() * 0.4, w * 0.42, c.height() * 0.32, Color("c6d0da").darkened(0.35))
	c.ellipse(w / 2.0, c.height() * 0.4, w * 0.34, c.height() * 0.24, Color("c6d0da").darkened(0.15))
	c.line(Vector2i(w / 2, int(c.height() * 0.4)), Vector2i(w - 14, 8), STEEL.lightened(0.1))
	c.circle(w - 14, 8, 4, DARK)


static func _p_clothesline(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(10, 40, 6, c.height() - 40, DARK.lightened(0.1))
	c.rect(w - 16, 40, 6, c.height() - 40, DARK.lightened(0.1))
	c.hline(44, DARK.lightened(0.2), 10, w - 10, 3)
	var colors := [Color("5a6a8a"), Color("8a5a6a"), Color("6a8a7a"), Color("9a8a5a"), Color("4a5a7a")]
	for i in 5:
		var x := 28 + i * 44
		var h := 50 + (i % 3) * 14
		c.polygon(PackedVector2Array([Vector2(x, 46), Vector2(x + 34, 46), Vector2(x + 38, 46 + h), Vector2(x - 4, 46 + h)]), colors[i])
		c.hline(46, colors[i].lightened(0.15), x, x + 34, 3)
		c.streak(x + 14, 60, h - 20, Color(0, 0, 0, 0.18), i)


static func _p_vent_stack(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	_pipe_v(c, 16, 24, w - 32, c.height() - 24, Color("4a5460"))
	c.ellipse(w / 2.0, 24.0, (w - 24) / 2.0, 14.0, Color("56606c"))
	c.ellipse(w / 2.0, 24.0, (w - 40) / 2.0, 8.0, DARK)
	c.rect(8, 60, w - 16, 8, STEEL.lightened(0.1))
	c.streak(w / 2, 70, 40, Color(0.2, 0.15, 0.1, 0.4), 6)


static func _p_chimney(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	var bricks: Array[Color] = [Color("4a3a38"), Color("56423e"), Color("3e302e")]
	c.bricks(8, 20, w - 16, c.height() - 20, 24, 12, bricks, Color("201a1a"), 2)
	c.rect(0, 8, w, 18, Color("5a4844"))
	c.rect(0, 8, w, 4, Color("6a5652"))
	c.streak(w / 2, 26, 60, Color(0, 0, 0, 0.35), 4)


static func _p_hut(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.rect(0, 20, w, h - 20, Color("30384a"))
	c.corrugation(0, 20, w, h - 20, 12, Color("30384a"), 0.05, 0.08)
	c.rect(-2, 12, w + 4, 14, Color("46506a"))
	c.rect(0, 12, w, 4, Color("56627e"))
	c.rect(52, 52, 44, h - 52, DARK)
	c.rect(56, 56, 36, h - 56, Color("1a2030"))
	g.rect(110, 60, 36, 36, Color(1.0, 0.8, 0.45, 0.9))
	c.frame(110, 60, 36, 36, Color("46506a"), 3)
	c.vline(127, Color("46506a"), 60, 96, 2)
	g.rect(60, 50, 28, 3, Color(1.0, 0.75, 0.4, 0.8))


# ---- 街道 -----------------------------------------------------------------

static func _p_trash_can(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.polygon(PackedVector2Array([Vector2(6, 12), Vector2(w - 6, 12), Vector2(w - 10, c.height()), Vector2(10, c.height())]), Color("4a5260"))
	c.rect(2, 8, w - 4, 8, Color("5a6270"))
	_ribs(c, 8, 20, w - 16, c.height() - 24, 10, Color("30363f"))
	c.rect(w / 2 - 6, 2, 12, 6, DARK.lightened(0.1))


static func _p_dumpster(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.polygon(PackedVector2Array([Vector2(4, 24), Vector2(w - 4, 24), Vector2(w - 12, h - 8), Vector2(12, h - 8)]), Color("2e4a3a"))
	c.corrugation(12, 28, w - 24, h - 40, 10, Color("2e4a3a"), 0.06, 0.1)
	c.rect(0, 14, w, 14, Color("3a5a48"))
	c.rect(0, 14, w, 4, Color("4a6a58"))
	for x in [16, w - 24]:
		c.rect(x, h - 8, 8, 8, DARK)
	c.streak(40, 40, 50, Color(0.2, 0.1, 0.05, 0.3), 5)
	c.speckle(0.02, Color("a0c0b0"), 8, 12, 30, w - 24, 50)


static func _crate(c: EnvCanvas, x: int, y: int, w: int, h: int, base: Color) -> void:
	c.bevel(x, y, w, h, base, 0.07, 0.14, 3)
	c.line(Vector2i(x + 4, y + 4), Vector2i(x + w - 5, y + h - 5), base.darkened(0.3))
	c.line(Vector2i(x + w - 5, y + 4), Vector2i(x + 4, y + h - 5), base.darkened(0.3))
	c.frame(x + 6, y + 6, w - 12, h - 12, base.darkened(0.25), 2)


static func _p_crates(c: EnvCanvas, _g: EnvCanvas) -> void:
	_crate(c, 4, 60, 56, 52, Color("5a4a34"))
	_crate(c, 64, 64, 60, 48, Color("4a3e2c"))
	_crate(c, 24, 8, 60, 52, Color("665238"))


static func _p_barrels(c: EnvCanvas, _g: EnvCanvas) -> void:
	for p in [Vector2i(4, 14), Vector2i(40, 20), Vector2i(76, 14)]:
		var col := [Color("6a3a2a"), Color("3a5a6a"), Color("6a5a2a")][(p.x / 36) % 3] as Color
		c.rect(p.x, p.y, 34, 62, col)
		c.rect(p.x, p.y, 34, 6, col.lightened(0.15))
		c.rect(p.x, p.y + 20, 34, 4, col.darkened(0.3))
		c.rect(p.x, p.y + 44, 34, 4, col.darkened(0.3))
		c.rect(p.x + 4, p.y + 6, 5, 52, col.lightened(0.1))
		c.ellipse(p.x + 17.0, p.y + 2.0, 17.0, 5.0, col.lightened(0.12))


static func _p_fire_escape(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	# 兩層平台（上層是可站的單向平台）+ 斜梯 + 欄杆
	for y in [104, 232]:
		c.rect(0, y, w, 12, STEEL.lightened(0.05))
		c.rect(0, y, w, 3, STEEL.lightened(0.2))
		for x in range(8, w, 16):
			c.rect(x, y + 12, 4, 14, DARK.lightened(0.05))
		c.hline(y - 34, STEEL, 0, w, 4)
		for x in range(0, w, 24):
			c.rect(x, y - 34, 4, 34, STEEL.darkened(0.1))
	c.line(Vector2i(w - 60, 116), Vector2i(w - 20, 232), STEEL.lightened(0.05))
	c.line(Vector2i(w - 52, 116), Vector2i(w - 12, 232), STEEL.lightened(0.05))
	for i in 7:
		var t := float(i) / 6.0
		var p := Vector2i(int(lerpf(w - 56, w - 16, t)), int(lerpf(116, 232, t)))
		c.hline(p.y, STEEL.lightened(0.12), p.x - 8, p.x + 12, 3)
	c.rect(0, 240, 6, h - 240, DARK.lightened(0.05))
	c.rect(w - 6, 240, 6, h - 240, DARK.lightened(0.05))
	c.streak(30, 118, 40, RUST.lightened(0.1), 3)


static func _p_ladder(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(6, 0, 5, c.height(), STEEL)
	c.rect(w - 11, 0, 5, c.height(), STEEL)
	for y in range(8, c.height(), 16):
		c.rect(6, y, w - 12, 4, STEEL.lightened(0.1))


static func _p_pipe_v(c: EnvCanvas, _g: EnvCanvas) -> void:
	_pipe_v(c, 4, 0, c.width() - 8, c.height(), Color("4a5460"))
	for y in range(20, c.height(), 60):
		c.rect(0, y, c.width(), 8, STEEL.lightened(0.15))
		c.rect(0, y + 8, c.width(), 3, DARK)
	c.streak(c.width() / 2, 30, 80, Color(0.3, 0.2, 0.1, 0.35), 2)


static func _p_pipe_h(c: EnvCanvas, _g: EnvCanvas) -> void:
	_pipe_h(c, 0, 6, c.width(), c.height() - 12, Color("4a5460"))
	for x in range(30, c.width(), 90):
		c.rect(x, 0, 8, c.height(), STEEL.lightened(0.15))
		c.rect(x + 8, 0, 3, c.height(), DARK)
	c.streak(100, 22, 8, Color(0.2, 0.15, 0.1, 0.4), 4)


static func _p_puddle(c: EnvCanvas, g: EnvCanvas) -> void:
	c.ellipse(c.width() / 2.0, c.height() / 2.0, c.width() / 2.0 - 2.0, c.height() / 2.0 - 1.0, Color(0.08, 0.14, 0.24, 0.85))
	c.ellipse(c.width() / 2.0 - 10.0, c.height() / 2.0 - 1.0, c.width() / 3.0, c.height() / 3.0, Color(0.3, 0.45, 0.7, 0.35))
	g.ellipse(c.width() * 0.4, c.height() / 2.0, c.width() * 0.2, 2.0, Color(0.4, 0.55, 1.0, 0.35))


static func _p_graffiti(c: EnvCanvas, g: EnvCanvas) -> void:
	var tag := MAGENTA
	for i in 5:
		var x := 14 + i * 22
		c.line(Vector2i(x, 70 - (i % 2) * 24), Vector2i(x + 16, 20 + (i % 3) * 10), Color(tag, 0.85))
		c.line(Vector2i(x + 1, 70 - (i % 2) * 24), Vector2i(x + 17, 20 + (i % 3) * 10), Color(tag, 0.85))
		g.line(Vector2i(x, 70 - (i % 2) * 24), Vector2i(x + 16, 20 + (i % 3) * 10), Color(tag, 0.5))
	c.circle(100.0, 40.0, 18.0, Color(CYAN, 0.0))
	c.line(Vector2i(10, 82), Vector2i(118, 82), Color(CYAN, 0.7))
	g.line(Vector2i(10, 82), Vector2i(118, 82), Color(CYAN, 0.45))


static func _p_pole(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(w / 2 - 6, 24, 12, c.height() - 24, Color("3a3430"))
	c.rect(w / 2 - 6, 24, 4, c.height() - 24, Color("4a443e"))
	c.rect(w / 2 - 44, 40, 88, 8, Color("3a3430"))
	c.rect(w / 2 - 36, 80, 72, 6, Color("3a3430"))
	for x in [w / 2 - 44, w / 2 - 14, w / 2 + 14, w / 2 + 40]:
		c.rect(x, 34, 6, 8, Color("8a9aa8"))
	# 垂下的電線
	for i in 3:
		var y0 := 44 + i * 4
		c.line(Vector2i(0, y0 + 24), Vector2i(w / 2 - 40, y0), DARK.lightened(0.05))
		c.line(Vector2i(w / 2 + 40, y0), Vector2i(w, y0 + 28), DARK.lightened(0.05))


static func _p_street_lamp(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(w / 2 - 5, 30, 10, c.height() - 30, Color("2e343e"))
	c.rect(w / 2 - 5, 30, 3, c.height() - 30, Color("3e4650"))
	c.rect(w / 2 - 5, 20, 48, 8, Color("2e343e"))
	c.polygon(PackedVector2Array([Vector2(w / 2 + 30, 26), Vector2(w / 2 + 52, 26), Vector2(w / 2 + 46, 38), Vector2(w / 2 + 36, 38)]), Color("46505c"))
	g.rect(w / 2 + 36, 36, 10, 4, Color(1.0, 0.82, 0.5, 1.0))
	g.glow_blob(w / 2.0 + 41.0, 42.0, 22.0, Color(1.0, 0.8, 0.5, 1.0), 0.5)
	c.rect(w / 2 - 12, c.height() - 12, 24, 12, Color("2e343e"))


static func _p_vending(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	_metal(c, 0, 0, w, h, Color("2a3a5a"))
	c.rect(8, 8, w - 16, h - 52, Color("0a1018"))
	g.rect(8, 8, w - 16, h - 52, Color(0.5, 0.9, 1.0, 0.8))
	for r in 3:
		for col in 3:
			var color := [Color("ff5a4f"), Color("ffc94a"), Color("3dffa0"), Color("35e0ff")][(r + col) % 4] as Color
			c.rect(14 + col * 16, 14 + r * 20, 12, 14, color.darkened(0.2))
	c.rect(8, h - 38, w - 16, 14, Color("0e1420"))
	c.rect(w - 18, h - 38, 10, 8, Color("ffc94a").darkened(0.3))
	g.rect(w - 18, h - 38, 10, 8, Color(1.0, 0.8, 0.3, 0.7))
	c.rect(10, h - 16, w - 20, 8, DARK)


static func _p_neon_v(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(w / 2 - 3, 0, 6, 12, DARK.lightened(0.1))
	c.bevel(4, 12, w - 8, c.height() - 12, Color("1a1e2a"), 0.06, 0.1, 2)
	for i in 5:
		var y := 22 + i * 28
		var col := MAGENTA if i % 2 == 0 else CYAN
		c.rect(14, y, w - 28, 18, col.darkened(0.55))
		g.rect(14, y, w - 28, 18, Color(col, 0.95))
		g.glow_blob(w / 2.0, y + 9.0, 22.0, col, 0.5)


static func _p_neon_h(c: EnvCanvas, g: EnvCanvas) -> void:
	var h := c.height()
	c.bevel(4, 4, c.width() - 8, h - 8, Color("1a1e2a"), 0.06, 0.1, 2)
	for i in 4:
		var x := 14 + i * 38
		var col := CYAN if i % 2 == 0 else YELLOW
		c.rect(x, 14, 28, h - 28, col.darkened(0.55))
		g.rect(x, 14, 28, h - 28, Color(col, 0.95))
		g.glow_blob(x + 14.0, h / 2.0, 20.0, col, 0.45)
	c.rect(10, 0, 4, 6, DARK.lightened(0.1))
	c.rect(c.width() - 14, 0, 4, 6, DARK.lightened(0.1))


static func _p_billboard(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.rect(w / 2 - 6, h - 40, 12, 40, DARK.lightened(0.05))
	c.bevel(0, 0, w, h - 36, Color("181c28"), 0.05, 0.1, 4)
	c.rect(10, 10, w - 20, h - 56, Color("0a1020"))
	g.rect(10, 10, w - 20, h - 56, Color(0.35, 0.5, 0.95, 0.75))
	g.rect(24, 24, 70, 8, Color(1.0, 1.0, 1.0, 0.9))
	g.rect(24, 40, 110, 4, Color(1.0, 1.0, 1.0, 0.5))
	g.circle(w - 50.0, (h - 36) / 2.0, 22.0, Color(CYAN, 0.8))
	c.circle(w - 50.0, (h - 36) / 2.0, 22.0, Color("0a1020"))


static func _p_lanterns(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	c.line(Vector2i(0, 6), Vector2i(w / 2, 28), DARK.lightened(0.15))
	c.line(Vector2i(w / 2, 28), Vector2i(w, 6), DARK.lightened(0.15))
	for i in 6:
		var x := 28 + i * 60
		var t := absf(float(x) - w * 0.5) / (w * 0.5)
		var y := int(lerpf(30.0, 8.0, t)) + 4
		c.ellipse(x, y + 16.0, 12.0, 15.0, Color("a02a20"))
		c.rect(x - 6, y, 12, 4, DARK)
		g.ellipse(x, y + 16.0, 9.0, 12.0, Color(1.0, 0.55, 0.3, 0.95))
		g.glow_blob(x, y + 16.0, 26.0, Color(1.0, 0.5, 0.25, 1.0), 0.35)


static func _p_noodle_stall(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	# 雨棚（上層可站）、桌台、蒸氣鍋、燈
	c.rect(0, 28, w, 14, Color("7a2a2a"))
	for x in range(0, w, 24):
		c.rect(x, 28, 12, 14, Color("e0d0b8").darkened(0.35))
	c.rect(0, 28, w, 4, Color("9a4a40"))
	c.rect(10, 42, 6, h - 42, DARK.lightened(0.08))
	c.rect(w - 16, 42, 6, h - 42, DARK.lightened(0.08))
	c.rect(10, 120, w - 20, 10, Color("5a4a38"))
	c.rect(10, 130, w - 20, h - 130, Color("3a2e24"))
	c.rect(28, 100, 60, 22, Color("6a7480"))
	c.rect(28, 100, 60, 4, Color("8a94a0"))
	g.rect(30, 58, w - 60, 50, Color(1.0, 0.75, 0.4, 0.5))
	for i in 4:
		g.circle(40 + i * 54, 22, 7, Color(1.0, 0.55, 0.3, 0.95))
		c.circle(40 + i * 54, 22, 7, Color("a02a20"))
	g.glow_blob(w / 2.0, 80.0, 70.0, Color(1.0, 0.7, 0.4, 1.0), 0.35)
	c.rect(w - 56, 66, 40, 30, Color("e8e0d0").darkened(0.5))
	g.rect(w - 52, 70, 32, 6, Color(1.0, 0.9, 0.7, 0.8))


static func _p_awning(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.polygon(PackedVector2Array([Vector2(0, 18), Vector2(w, 18), Vector2(w - 8, 54), Vector2(8, 54)]), Color("2a4a6a"))
	for x in range(0, w, 32):
		c.polygon(PackedVector2Array([Vector2(x, 18), Vector2(x + 16, 18), Vector2(x + 14, 54), Vector2(x + 2, 54)]), Color("c0b8a8").darkened(0.45))
	c.rect(0, 16, w, 8, Color("3a5a7a"))
	c.hline(16, Color("5a7a9a"), 0, w, 3)
	c.ellipse(w / 2.0, 54.0, w / 2.0 - 8.0, 3.0, Color("1a2a3a"))


static func _p_bench(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	c.rect(4, 24, w - 8, 8, Color("5a4a38"))
	c.rect(4, 8, w - 8, 6, Color("4a3e2e"))
	c.rect(8, 14, 4, 12, STEEL)
	c.rect(w - 12, 14, 4, 12, STEEL)
	for x in [10, w - 14]:
		c.rect(x, 32, 4, c.height() - 32, STEEL.darkened(0.1))


static func _p_bus_stop(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.rect(8, 8, w - 16, 10, Color("2a4a6a"))
	for x in [8, w - 16]:
		c.rect(x, 18, 8, h - 18, Color("3a4452"))
	c.rect(16, 24, w - 40, h - 70, Color("0a1822"))
	g.rect(w - 24, 24, 16, h - 80, Color(0.6, 0.85, 1.0, 0.7))
	c.rect(w - 24, 24, 16, h - 80, Color("0a1822"))
	g.rect(w - 22, 28, 12, h - 88, Color(0.6, 0.85, 1.0, 0.7))
	c.line(Vector2i(24, h - 62), Vector2i(w - 40, 32), Color(1, 1, 1, 0.06))
	c.rect(20, h - 44, w - 56, 6, Color("5a4a38"))


# ---- 貨運站 ---------------------------------------------------------------

static func _p_container_prop(c: EnvCanvas, _g: EnvCanvas) -> void:
	c.corrugation(0, 0, c.width(), c.height(), 12, Color("4a5a6a"), 0.08, 0.12)
	c.frame(0, 0, c.width(), c.height(), Color("2a323c"), 4)
	c.rect(c.width() / 2 - 2, 4, 4, c.height() - 8, Color("2a323c"))
	c.streak(30, 6, 60, Color(0.3, 0.15, 0.05, 0.3), 2)


static func _p_crane(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	var steel := Color("3a4048")
	c.rect(60, 80, 16, h - 80, steel)
	c.rect(130, 80, 16, h - 80, steel)
	c.line(Vector2i(68, 90), Vector2i(138, h), steel.darkened(0.2))
	c.line(Vector2i(138, 90), Vector2i(68, h), steel.darkened(0.2))
	c.rect(0, 40, w, 30, steel.lightened(0.04))
	c.rect(0, 40, w, 6, steel.lightened(0.14))
	for x in range(10, w - 10, 30):
		c.line(Vector2i(x, 70), Vector2i(x + 15, 46), steel.darkened(0.25))
		c.line(Vector2i(x + 15, 46), Vector2i(x + 30, 70), steel.darkened(0.25))
	c.rect(w - 60, 24, 40, 40, Color("5a4a28"))
	c.line(Vector2i(w - 40, 64), Vector2i(w - 40, 200), DARK.lightened(0.2))
	c.rect(w - 52, 196, 24, 14, YELLOW.darkened(0.45))
	g.circle(w - 40.0, 30.0, 8.0, Color(1.0, 0.25, 0.15, 0.95))
	g.circle(20.0, 44.0, 6.0, Color(1.0, 0.25, 0.15, 0.8))


static func _p_forklift(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.rect(40, 40, 90, 40, Color("8a6a1a"))
	c.rect(40, 40, 90, 6, Color("a8841f"))
	c.rect(60, 12, 56, 32, Color("5a4a14"))
	c.rect(66, 18, 44, 22, Color("0a1018"))
	g.rect(66, 18, 44, 22, Color(0.5, 0.8, 1.0, 0.0))
	c.rect(130, 8, 8, h - 20, STEEL)
	c.rect(136, 60, 22, 4, STEEL.lightened(0.1))
	c.circle(60.0, h - 14.0, 14.0, DARK)
	c.circle(60.0, h - 14.0, 6.0, STEEL)
	c.circle(112.0, h - 12.0, 12.0, DARK)
	c.circle(112.0, h - 12.0, 5.0, STEEL)
	g.circle(86.0, 8.0, 6.0, Color(1.0, 0.7, 0.2, 0.95))
	c.rect(82, 4, 8, 8, YELLOW.darkened(0.4))


static func _p_fence(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	for x in range(0, w, 56):
		c.rect(x, 0, 6, h, STEEL)
	c.hline(8, STEEL, 0, w, 4)
	c.hline(h - 10, STEEL, 0, w, 4)
	for x in range(0, w, 12):
		c.line(Vector2i(x, 10), Vector2i(x + 24, h - 12), Color(STEEL, 0.5))
		c.line(Vector2i(x + 24, 10), Vector2i(x, h - 12), Color(STEEL, 0.5))
	c.rect(0, 0, w, 3, STEEL.lightened(0.15))


static func _p_worker_hut(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.rect(0, 28, w, h - 28, Color("3a4252"))
	c.corrugation(0, 28, w, h - 28, 14, Color("3a4252"), 0.05, 0.08)
	c.rect(-2, 18, w + 4, 16, Color("56627a"))
	c.rect(0, 18, w, 4, Color("6a7690"))
	c.rect(168, 56, 62, h - 56, DARK)
	c.rect(172, 60, 54, h - 60, Color("181e2c"))
	g.rect(24, 60, 120, 56, Color(1.0, 0.82, 0.5, 0.9))
	c.frame(24, 60, 120, 56, Color("56627a"), 4)
	c.vline(82, Color("56627a"), 60, 116, 3)
	g.rect(176, 44, 46, 4, Color(1.0, 0.8, 0.4, 0.85))
	c.rect(30, 100, 40, 14, Color(0, 0, 0, 0.5))


static func _p_pallets(c: EnvCanvas, _g: EnvCanvas) -> void:
	for i in 3:
		var y := c.height() - 20 - i * 26
		c.rect(4, y, c.width() - 8, 6, Color("6a5236"))
		for x in range(8, c.width() - 8, 36):
			c.rect(x, y + 6, 14, 14, Color("4a3a28"))
		c.rect(4, y + 20, c.width() - 8, 4, Color("6a5236"))
	c.rect(10, 8, c.width() - 20, 40, Color("c8c0b0").darkened(0.45))
	c.frame(10, 8, c.width() - 20, 40, Color("e0d8c8").darkened(0.5), 2)


# ---- 設施 -----------------------------------------------------------------

static func _p_console(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	_metal(c, 0, 36, w, h - 36, Color("2a3442"))
	c.polygon(PackedVector2Array([Vector2(8, 36), Vector2(w - 8, 36), Vector2(w - 16, 6), Vector2(16, 6)]), Color("1a222e"))
	c.polygon(PackedVector2Array([Vector2(20, 32), Vector2(w - 20, 32), Vector2(w - 26, 10), Vector2(26, 10)]), Color("0a1018"))
	g.polygon(PackedVector2Array([Vector2(20, 32), Vector2(w - 20, 32), Vector2(w - 26, 10), Vector2(26, 10)]), Color(CYAN, 0.7))
	for i in 5:
		g.rect(22 + i * 18, 44, 10, 4, Color([CYAN, MAGENTA, YELLOW, Color("3dffa0"), CYAN][i], 0.95))
	c.rect(w - 30, 54, 18, 24, DARK)
	c.rect(10, 54, 60, 8, DARK.lightened(0.05))


static func _p_rack(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	_metal(c, 0, 0, w, h, Color("202a38"))
	for i in 8:
		var y := 10 + i * 18
		c.rect(8, y, w - 16, 12, Color("0e1420"))
		for k in 4:
			var color := [CYAN, Color("3dffa0"), MAGENTA][(i + k) % 3] as Color
			g.rect(12 + k * 10, y + 4, 4, 4, Color(color, 0.9 if (i * 3 + k) % 4 != 0 else 0.25))
		c.hline(y + 8, DARK, w - 36, w - 12, 2)


static func _p_camera(c: EnvCanvas, g: EnvCanvas) -> void:
	c.rect(0, 0, 10, c.height(), STEEL)
	c.polygon(PackedVector2Array([Vector2(8, 10), Vector2(c.width() - 4, 4), Vector2(c.width() - 4, 30), Vector2(8, 28)]), Color("2e3640"))
	c.circle(c.width() - 12.0, 18.0, 8.0, Color("0a0e14"))
	g.circle(c.width() - 12.0, 18.0, 5.0, Color(1.0, 0.2, 0.15, 0.95))
	g.rect(18, 8, 4, 4, Color(1.0, 0.2, 0.15, 0.8))


static func _p_emergency(c: EnvCanvas, g: EnvCanvas) -> void:
	_metal(c, 0, 8, c.width(), c.height() - 8, Color("3a2a2a"))
	c.ellipse(c.width() / 2.0, 16.0, c.width() * 0.4, 14.0, Color("5a1a14"))
	g.ellipse(c.width() / 2.0, 16.0, c.width() * 0.35, 11.0, Color(1.0, 0.2, 0.15, 0.95))
	g.glow_blob(c.width() / 2.0, 16.0, 26.0, Color(1.0, 0.2, 0.15, 1.0), 0.45)


static func _p_cables(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	for i in 6:
		var x0 := 10 + i * 30
		var sag := 40 + (i % 3) * 30
		var col := Color("14181f") if i % 2 == 0 else Color("2a2018")
		c.line(Vector2i(x0, 0), Vector2i(x0 + 6, sag), col)
		c.line(Vector2i(x0 + 1, 0), Vector2i(x0 + 7, sag), col)
		c.line(Vector2i(x0 + 6, sag), Vector2i(x0 + 2, sag + 30), col)
		c.rect(x0 + 1, sag + 30, 6, 6, STEEL)


static func _p_gate(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	_metal(c, 0, 0, w, h, Color("2a3442"))
	c.rect(w / 2 - 3, 8, 6, h - 16, DARK)
	c.diagonal_stripes(8, h - 28, w - 16, 20, YELLOW.darkened(0.4), DARK, 12)
	g.rect(w / 2 - 2, 12, 4, h - 40, Color(CYAN, 0.8))
	c.rect(8, 8, w - 16, 14, DARK.lightened(0.04))
	g.rect(12, 12, w - 24, 4, Color(CYAN, 0.6))


static func _p_hazard(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	c.polygon(PackedVector2Array([Vector2(w / 2, 4), Vector2(w - 4, w - 6), Vector2(4, w - 6)]), YELLOW.darkened(0.35))
	c.polygon(PackedVector2Array([Vector2(w / 2, 14), Vector2(w - 14, w - 12), Vector2(14, w - 12)]), Color("14181f"))
	g.rect(w / 2 - 2, 28, 4, 14, Color(YELLOW, 0.95))
	g.rect(w / 2 - 2, 46, 4, 4, Color(YELLOW, 0.95))
	g.polygon(PackedVector2Array([Vector2(w / 2, 4), Vector2(w - 4, w - 6), Vector2(4, w - 6)]), Color(YELLOW, 0.12))


static func _p_facility_pipes(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	_pipe_h(c, 0, 8, w, 18, Color("3e4a5a"))
	_pipe_h(c, 0, 32, w, 14, Color("4a3a30"))
	_pipe_h(c, 0, 50, w, 10, Color("2e3a4a"))
	for x in range(24, w, 70):
		c.rect(x, 4, 10, 60, STEEL.lightened(0.12))
		c.rect(x + 10, 4, 3, 60, DARK)
	c.speckle(0.03, Color("8a9aa8"), 4, 0, 4, w, 56)


static func _p_marking(c: EnvCanvas, _g: EnvCanvas) -> void:
	c.diagonal_stripes(0, 0, c.width(), c.height(), YELLOW.darkened(0.2), DARK, 12)


# ---- 機庫 -----------------------------------------------------------------

static func _p_gantry(c: EnvCanvas, g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	var steel := Color("30363e")
	c.rect(30, 60, 24, h - 60, steel)
	c.rect(w - 54, 60, 24, h - 60, steel)
	c.rect(0, 30, w, 36, steel.lightened(0.03))
	c.rect(0, 30, w, 6, steel.lightened(0.14))
	for x in range(20, w - 40, 44):
		c.line(Vector2i(x, 66), Vector2i(x + 22, 36), steel.darkened(0.25))
		c.line(Vector2i(x + 22, 36), Vector2i(x + 44, 66), steel.darkened(0.25))
	c.rect(w / 2 - 40, 66, 80, 22, Color("5a4a28"))
	c.line(Vector2i(w / 2, 88), Vector2i(w / 2, h - 80), DARK.lightened(0.2))
	c.rect(w / 2 - 14, h - 84, 28, 18, YELLOW.darkened(0.4))
	g.circle(60.0, 40.0, 10.0, Color(1.0, 0.25, 0.15, 0.95))
	g.circle(w - 60.0, 40.0, 10.0, Color(1.0, 0.25, 0.15, 0.95))
	g.glow_blob(60.0, 40.0, 40.0, Color(1.0, 0.25, 0.15, 1.0), 0.4)
	c.diagonal_stripes(30, h - 40, 24, 40, YELLOW.darkened(0.45), DARK, 10)
	c.diagonal_stripes(w - 54, h - 40, 24, 40, YELLOW.darkened(0.45), DARK, 10)


static func _p_hangar_light(c: EnvCanvas, g: EnvCanvas) -> void:
	_metal(c, 0, 0, c.width(), 12, Color("3a424e"))
	c.polygon(PackedVector2Array([Vector2(8, 12), Vector2(c.width() - 8, 12), Vector2(c.width() - 20, c.height() - 2), Vector2(20, c.height() - 2)]), Color("2a323c"))
	g.rect(24, c.height() - 8, c.width() - 48, 6, Color(1.0, 0.92, 0.75, 1.0))
	g.glow_blob(c.width() / 2.0, c.height() - 4.0, 36.0, Color(1.0, 0.9, 0.7, 1.0), 0.4)


static func _p_tank(c: EnvCanvas, _g: EnvCanvas) -> void:
	var w := c.width()
	var h := c.height()
	c.ellipse(w / 2.0, 24.0, w / 2.0 - 4.0, 18.0, Color("56606c"))
	c.rect(4, 24, w - 8, h - 48, Color("46505c"))
	c.rect(4, 24, 14, h - 48, Color("5a6470"))
	c.rect(w - 22, 24, 18, h - 48, Color("323a44"))
	c.ellipse(w / 2.0, h - 24.0, w / 2.0 - 4.0, 18.0, Color("323a44"))
	c.diagonal_stripes(4, h - 60, w - 8, 14, YELLOW.darkened(0.35), DARK, 12)
	c.rect(w / 2 - 10, 4, 20, 8, STEEL)
	for y in [60, 90]:
		c.hline(y, Color("2a323c"), 4, w - 4, 3)
