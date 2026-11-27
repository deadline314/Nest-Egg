class_name CollageDecal
extends Control
## 拼貼版面的小配件（NE-412）：貼在一個 Label 後面的實物外形，跟著 Label 的大小——
## tape＝膠帶（操作提示，兩端撕開）、stamp＝圓形戳章（版本號）、price＝價格吊牌（信用點，打孔穿繩）。
## 會裁字的 Label（clip_text）連子節點一起裁，外形要畫在 Label 的範圍裡（price 就是這樣）。
## 用 attach() 掛成 Label 的子節點並畫在字後面；靜態，只有大小變了才重畫。

var kind: StringName = &"tape"
var color := Palette.CYAN


## 把外形掛在 label 後面。kind 不認得時記錄並退回膠帶。
static func attach(label: Control, decal_kind: StringName, decal_color := Palette.CYAN) -> CollageDecal:
	var decal := CollageDecal.new()
	if decal_kind not in [&"tape", &"stamp", &"price"]:
		push_error("[CollageDecal] %s 的外形 %s 不認得，改用膠帶" % [label.name, decal_kind])
		decal_kind = &"tape"
	decal.kind = decal_kind
	decal.color = decal_color
	decal.show_behind_parent = true
	decal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_child(decal)
	decal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return decal


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	match kind:
		&"stamp":
			var center := rect.get_center()
			var radius := maxf(size.x, size.y) * 0.5 + 2.0
			draw_arc(center, radius, 0.0, TAU, 40, Color(color, 0.75), 2.0)
			draw_arc(center, radius - 5.0, 0.0, TAU, 36, Color(color, 0.5), 1.0)
			# 戳章沒蓋滿的缺口：兩小段深色蓋過外圈。
			draw_arc(center, radius, 0.7, 0.95, 4, Color(Palette.UI_PANEL_DEEP, 0.9), 3.0)
			draw_arc(center, radius, 3.9, 4.05, 3, Color(Palette.UI_PANEL_DEEP, 0.9), 3.0)
		&"price":
			var points := CollageShapes.tag_polygon(rect.grow(-0.5), 6.0)
			CollageShapes.draw_shape(self, points, Color("1a2430"), Color(color, 0.7), 1.0)
			var hole := (points[6] + points[7]) * 0.5 + (points[1] - points[0]).normalized() * 6.0
			CollageShapes.draw_hole(self, hole, 2.0, Color(color, 0.8), Color(Palette.UI_MUTED, 0.6), 0.0)
		_:
			# 膠帶：比字寬一點，兩端是撕開的鋸齒，上下各一條淡邊。
			var body := rect.grow_individual(8.0, 1.0, 8.0, 1.0)
			var points := PackedVector2Array()
			var teeth := 3
			for i in teeth + 1:
				points.append(Vector2(body.position.x + (2.5 if i % 2 == 0 else 0.0), body.position.y + body.size.y * float(i) / teeth))
			for i in teeth + 1:
				points.append(Vector2(body.end.x - (2.5 if i % 2 == 0 else 0.0), body.end.y - body.size.y * float(i) / teeth))
			draw_colored_polygon(points, Color("34414e", 0.95))
			draw_line(body.position + Vector2(3, 0), Vector2(body.end.x - 3, body.position.y), Color(color, 0.18), 1.0)
			draw_line(Vector2(body.position.x + 3, body.end.y), body.end - Vector2(3, 0), Color(color, 0.18), 1.0)
