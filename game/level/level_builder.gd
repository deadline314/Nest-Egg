class_name LevelBuilder
extends RefCounted
## 把 LevelData（ASCII 地圖 + legend）解析成 LevelLayout。
## 只做解析，不建立節點；遇到格式問題會修正並記錄警告，而不是讓遊戲崩潰。

const SOLID := "#"
const PLATFORM := "="
const SPIKES := "^"
const LASER := "|"
const PLAYER_START := "P"
const CHECKPOINT := "C"
const HEALTH := "H"
const ARENA := "B"
const LAMP := "*"
const EMPTY := "."


static func parse(data: LevelData) -> LevelLayout:
	var layout := LevelLayout.new()
	if data == null:
		layout.warnings.append("LevelData 為 null")
		return layout
	layout.tile_size = maxi(4, data.tile_size)
	layout.height = maxi(1, data.height)
	layout.rows = _compose_rows(data, layout)
	layout.width = layout.rows[0].length() if not layout.rows.is_empty() else 0
	if layout.width == 0:
		layout.warnings.append("地圖是空的")
		return layout
	_scan_cells(data, layout)
	layout.solid_rects = _merge_cells(layout, SOLID, true, true)
	layout.platform_rects = _merge_cells(layout, PLATFORM, true, false)
	layout.spike_rects = _merge_cells(layout, SPIKES, true, false)
	layout.laser_rects = _merge_cells(layout, LASER, false, true)
	if not layout.has_player_start:
		layout.warnings.append("地圖缺少玩家起點 P")
	for warning in layout.warnings:
		push_warning("[LevelBuilder] %s: %s" % [data.id, warning])
	return layout


## 把各分段左右串接；列數不足或寬度不一致時補空氣並警告。
static func _compose_rows(data: LevelData, layout: LevelLayout) -> PackedStringArray:
	var rows := PackedStringArray()
	rows.resize(layout.height)
	rows.fill("")
	var segments := data.load_segments()
	for index in segments.size():
		var lines := segments[index]
		if lines.size() != layout.height:
			layout.warnings.append("第 %d 段有 %d 列，預期 %d 列" % [index, lines.size(), layout.height])
		var segment_width := 0
		for line in lines:
			segment_width = maxi(segment_width, line.length())
		for y in layout.height:
			var line: String = lines[y] if y < lines.size() else ""
			if line.length() < segment_width:
				layout.warnings.append("第 %d 段第 %d 列寬度不足，已補空氣" % [index, y])
				line = line.rpad(segment_width, EMPTY)
			rows[y] += line
	return rows


static func _scan_cells(data: LevelData, layout: LevelLayout) -> void:
	var unknown: Dictionary = {}
	for y in layout.height:
		for x in layout.width:
			var c := layout.cell(x, y)
			match c:
				SOLID, PLATFORM, SPIKES, LASER, EMPTY, " ":
					pass
				PLAYER_START:
					if layout.has_player_start:
						layout.warnings.append("有多個玩家起點，使用第一個")
					else:
						layout.has_player_start = true
						layout.player_start = layout.cell_to_feet(x, y)
				CHECKPOINT:
					layout.checkpoints.append(layout.cell_to_feet(x, y))
				HEALTH:
					layout.health_pickups.append(layout.cell_to_feet(x, y))
				LAMP:
					layout.lamps.append(Vector2((x + 0.5) * layout.tile_size, y * layout.tile_size))
				ARENA:
					var arena := float(x * layout.tile_size)
					layout.arena_x = arena if layout.arena_x < 0.0 else minf(layout.arena_x, arena)
				_:
					if c.is_valid_int():
						_add_hint(data, layout, c, x, y)
					elif data.legend.has(c):
						_add_spawn(data.legend[c], layout, c, x, y)
					elif not unknown.has(c):
						unknown[c] = true
						layout.warnings.append("未知字元 '%s'（第 %d 列第 %d 欄），視為空氣" % [c, y, x])


static func _add_hint(data: LevelData, layout: LevelLayout, c: String, x: int, y: int) -> void:
	var index := c.to_int() - 1
	if index < 0 or index >= data.hints.size():
		layout.warnings.append("教學看板 '%s' 沒有對應的 hints 文字" % c)
		return
	layout.hints.append({"text": data.hints[index], "position": layout.cell_to_feet(x, y)})


static func _add_spawn(resource: Variant, layout: LevelLayout, c: String, x: int, y: int) -> void:
	var res := resource as Resource
	if res == null:
		layout.warnings.append("legend '%s' 沒有指定資源" % c)
		return
	var entry := {"resource": res, "position": layout.cell_to_feet(x, y)}
	if res is EnemyData and (res as EnemyData).is_boss:
		if not layout.boss_spawn.is_empty():
			layout.warnings.append("有多個頭目，使用第一個")
		else:
			layout.boss_spawn = entry
	else:
		layout.spawns.append(entry)


## 貪婪合併相同字元的格子成矩形，大幅減少碰撞形狀與繪製數量。
static func _merge_cells(layout: LevelLayout, ch: String, grow_x: bool, grow_y: bool) -> Array[Rect2i]:
	var w := layout.width
	var h := layout.height
	var used := PackedByteArray()
	used.resize(w * h)
	used.fill(0)
	var result: Array[Rect2i] = []
	for y in h:
		for x in w:
			if used[y * w + x] != 0 or layout.cell(x, y) != ch:
				continue
			var rw := 1
			if grow_x:
				while x + rw < w and used[y * w + x + rw] == 0 and layout.cell(x + rw, y) == ch:
					rw += 1
			var rh := 1
			if grow_y:
				while y + rh < h and _row_span_free(layout, used, x, y + rh, rw, ch):
					rh += 1
			for yy in range(y, y + rh):
				for xx in range(x, x + rw):
					used[yy * w + xx] = 1
			result.append(Rect2i(x, y, rw, rh))
	return result


static func _row_span_free(layout: LevelLayout, used: PackedByteArray, x: int, y: int, span: int, ch: String) -> bool:
	for xx in range(x, x + span):
		if used[y * layout.width + xx] != 0 or layout.cell(xx, y) != ch:
			return false
	return true
