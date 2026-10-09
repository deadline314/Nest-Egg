class_name SceneAudit
extends RefCounted
## 場景合理性檢查（NE-210）：對任何一張關卡地圖，檢查「看起來合理」的客觀部分——
## 站得穩（腳下有地）、不陷進地形（頭上與身側有空間）、梯子與門的高度對得上周圍空間、兩端梯子一樣高、
## 擺設在地圖內且落在地表、物件從起點走得到。資料只加不改程式：尺寸來自各資料資源（敵人體型、出入口寬高、機關格數）。
## 回傳的每一筆問題是 {severity: "error"|"warn", code, where, message}；error 一定要修，warn 要人看過。
## 用法與規則見 skill scene-staging；報告工具：godot --headless --path . res://tools/scene_report.tscn

const SOLID := "#"
const PLATFORM := "="
const GHOST := "~"
const SPIKES := "^"
const LASER := "|"
## 主角站著的身體（像素）：起點與檢查點至少要有這麼大的空間。
const PLAYER_SIZE := Vector2(12.0, 28.0)
## 身體與實心格擦邊的容許像素：擦過去不算陷進去（腳底與頭頂同樣適用）。
const EDGE_TOLERANCE := 4.0
## 可達性檢查裡主角佔的高度（格）。
const BODY_CELLS := 2
## 門的最低高度（像素）：矮於主角的門看起來像洞。
const MIN_DOOR_HEIGHT := 32
## 梯子頂端離天花板最多可以差幾格，再多就是「梯子沒爬到頂」。
const LADDER_CEILING_SLACK := 1
## 主角的移動能力（格）：跳上、橫跨（保守值，比實際略低；與 tools/level/build_ch1.py 的可達性檢查一致）。
const JUMP_UP_CELLS := 5
const JUMP_ACROSS_CELLS := 7
## 道具擺設可陷進實心地形的容許像素（貼邊的裝飾不算陷進）。
const PROP_OVERLAP_TOLERANCE := 4.0

const ERROR := "error"
const WARN := "warn"


## data/levels/ 底下所有關卡（.tres）的路徑，排序過。新增關卡不用登記，放進資料夾就會被檢查。
static func level_paths(root: String = "res://data/levels") -> PackedStringArray:
	var paths := PackedStringArray()
	for file in DirAccess.get_files_at(root):
		if file.ends_with(".tres"):
			paths.append("%s/%s" % [root, file])
	paths.sort()
	return paths


## 一個關卡的全部檢查。props_dirs 為空時略過擺設檢查（沒有環境主題的測試用資料）。
static func audit(data: LevelData, layout: LevelLayout) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if layout == null or not layout.is_valid():
		_add(issues, ERROR, "layout", data.id, "地圖無法解析")
		return issues
	_check_player_start(data, layout, issues)
	for spawn in layout.spawns:
		_check_spawn(data, layout, spawn, issues)
	if not layout.boss_spawn.is_empty():
		_check_spawn(data, layout, layout.boss_spawn, issues)
	for point in layout.checkpoints:
		_check_standing(data, layout, "checkpoint", point, PLAYER_SIZE, true, issues)
	for hint in layout.hints:
		_check_standing(data, layout, "hint", hint["position"], Vector2(12.0, 16.0), true, issues)
	for point in layout.health_pickups:
		_check_standing(data, layout, "health", point, Vector2(12.0, 12.0), false, issues)
	_check_props(data, layout, issues)
	_check_decor(data, layout, issues)
	_check_reachability(data, layout, issues)
	return issues


## 跨關卡檢查：每個出入口的另一端要存在、梯子兩端一樣高。resolver：路徑 → LevelLayout（呼叫端負責快取）。
static func audit_links(datas: Dictionary, layouts: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for path: String in datas:
		var data := datas[path] as LevelData
		for spawn in (layouts[path] as LevelLayout).spawns:
			var portal := spawn["resource"] as PortalData
			if portal == null or portal.is_locked_door() or portal.target_portal == &"":
				continue
			var other := _find_portal(layouts.get(portal.target_level) as LevelLayout, portal.target_portal)
			var where := "%s %s" % [data.id, _cell_text(spawn["cell"])]
			if other == null:
				_add(issues, ERROR, "portal_link", where, "出入口 %s 的另一端 %s（%s）不存在" % [portal.id, portal.target_portal, portal.target_level])
			elif portal.style == "ladder" and other.style == "ladder" and portal.height != other.height:
				_add(issues, WARN, "ladder_pair", where, "梯子 %s 高 %d，另一端 %s 高 %d：兩端看起來不是同一條梯子" % [portal.id, portal.height, other.id, other.height])
	return issues


# ---------------------------------------------------------------------------
# 過場舞台
# ---------------------------------------------------------------------------

## 站著或走動的演員腳底離舞台地板線（stage 的 floor）最多差幾像素；超過就是飄在半空或陷進地裡。
const STAGE_FLOOR_TOLERANCE := 14.0
## 同一個舞台上同一種角色的縮放最多差幾成（演員步驟的 scale）。
const STAGE_SCALE_SPREAD := 0.1
## 腳底不貼地板線的姿勢（坐、蹲、倒、跪由姿勢自己決定高度）。
const STAGE_FREE_POSES: Array[String] = ["sit", "squat", "kneel", "lie", "down", "crouch"]


## 掃描所有動畫過場（mode == animated）：演員的腳底貼著舞台地板、同舞台同角色縮放一致。
## stage_def：舞台 id → 舞台定義（StageLibrary.definition）；用 Callable 讓測試可以餵假資料。
static func audit_stages(scenes: Dictionary, stage_def: Callable) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var scales: Dictionary = {}  # "舞台|角色" → [縮放…]
	for scene_id: String in scenes:
		var scene := scenes[scene_id] as Dictionary
		if str(scene.get("mode", "")) != "animated":
			continue
		var floor_y := -1.0
		var stage_id := ""
		var poses: Dictionary = {}  # 演員 id → 目前姿勢
		for step: Dictionary in scene.get("steps", []):
			match str(step.get("do", "")):
				"scene":
					stage_id = str(step.get("id", ""))
					var def: Dictionary = stage_def.call(stage_id)
					floor_y = float(def.get("floor", -1.0))
					poses.clear()
				"actor":
					var id := str(step.get("id", ""))
					poses[id] = str(step.get("pose", "idle"))
					if step.has("scale") and stage_id != "":
						var key := "%s|%s" % [stage_id, step.get("kind", id)]
						(scales.get_or_add(key, []) as Array).append(float(step["scale"]))
					_check_stage_feet(issues, scene_id, stage_id, floor_y, str(poses[id]), step.get("pos", null), "演員 %s" % id)
				"pose":
					poses[str(step.get("id", ""))] = str(step.get("pose", "idle"))
				"move":
					var id := str(step.get("id", ""))
					_check_stage_feet(issues, scene_id, stage_id, floor_y, str(poses.get(id, "idle")), step.get("to", null), "演員 %s 走到" % id)
	for key: String in scales:
		var values: Array = scales[key]
		var low := float(values.min())
		var high := float(values.max())
		if low > 0.0 and (high - low) / low > STAGE_SCALE_SPREAD:
			_add(issues, WARN, "stage_scale", key, "同一個舞台上同一種角色縮放不一（%.2f–%.2f），看起來一個大一個小" % [low, high])
	return issues


static func _check_stage_feet(issues: Array[Dictionary], scene_id: String, stage_id: String, floor_y: float, pose: String, pos: Variant, label: String) -> void:
	if floor_y < 0.0 or not (pos is Array) or (pos as Array).size() < 2 or STAGE_FREE_POSES.has(pose):
		return
	var feet := float((pos as Array)[1])
	if absf(feet - floor_y) > STAGE_FLOOR_TOLERANCE:
		_add(issues, WARN, "stage_feet", "%s／%s" % [scene_id, stage_id], "%s 腳底 y=%.0f，舞台地板在 %.0f（差 %.0f 像素）" % [label, feet, floor_y, feet - floor_y])


# ---------------------------------------------------------------------------
# 單點檢查
# ---------------------------------------------------------------------------

static func _check_player_start(data: LevelData, layout: LevelLayout, issues: Array[Dictionary]) -> void:
	_check_standing(data, layout, "player_start", layout.player_start, PLAYER_SIZE, true, issues)


static func _check_spawn(data: LevelData, layout: LevelLayout, spawn: Dictionary, issues: Array[Dictionary]) -> void:
	var res := spawn["resource"] as Resource
	var cell: Vector2i = spawn["cell"]
	var feet: Vector2 = spawn["position"]
	var kind := _kind_of(res)
	var footprint := footprint_of(res, layout.tile_size)
	if footprint == Vector2.ZERO:
		return
	var label := "%s %s" % [kind, _name_of(res)]
	_check_standing(data, layout, label, feet, footprint, needs_ground(res), issues)
	var portal := res as PortalData
	if portal != null:
		_check_portal(data, layout, portal, cell, issues)


static func _check_portal(data: LevelData, layout: LevelLayout, portal: PortalData, cell: Vector2i, issues: Array[Dictionary]) -> void:
	var where := "%s %s" % [data.id, _cell_text(cell)]
	if portal.style == "road":
		return
	if portal.height < MIN_DOOR_HEIGHT:
		_add(issues, WARN, "door_small", where, "出入口 %s 只有 %d 像素高，比主角還矮" % [portal.id, portal.height])
	if portal.style != "ladder":
		return
	# 梯子：頂端要接到天花板或平台；離天花板還差好幾格，看起來就是「梯子太短、旁邊空間很高」。
	var top_row := cell.y - ceili(float(portal.height) / layout.tile_size) + 1
	var gap := 0
	var found_ceiling := false
	for y in range(top_row - 1, -1, -1):
		if _blocks_head(layout.cell(cell.x, y)):
			found_ceiling = true
			break
		gap += 1
	if found_ceiling and gap > LADDER_CEILING_SLACK:
		_add(issues, ERROR, "ladder_short", where, "梯子 %s 頂端離天花板還有 %d 格（梯高 %d 像素），看起來沒爬到頂" % [portal.id, gap, portal.height])
	elif not found_ceiling:
		# 沒有天花板（露天）：梯子要接到旁邊的平台或屋頂邊，頂端左右兩格內要有可站的地表。
		if not _has_ledge_near(layout, cell.x, top_row):
			_add(issues, WARN, "ladder_open", where, "梯子 %s 頂端（第 %d 列）附近沒有可踏上的平台或屋頂邊" % [portal.id, top_row])


## 在 feet（腳底像素）放一個 size_px（寬以腳底為中心）的東西：不陷進地形、需要時腳下要有地。
static func _check_standing(data: LevelData, layout: LevelLayout, label: String, feet: Vector2, size_px: Vector2, grounded: bool, issues: Array[Dictionary]) -> void:
	var tile := float(layout.tile_size)
	var cx := int(floorf(feet.x / tile))
	var left := int(floorf((feet.x - size_px.x * 0.5 + EDGE_TOLERANCE) / tile))
	var right := int(floorf((feet.x + size_px.x * 0.5 - EDGE_TOLERANCE - 0.01) / tile))
	if right < left:
		left = cx
		right = cx
	var bottom := int(ceilf(feet.y / tile)) - 1
	var top := int(floorf((feet.y - size_px.y + EDGE_TOLERANCE) / tile))
	var where := "%s (%d,%d)" % [data.id, cx, bottom]
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if layout.cell(x, y) == SOLID:
				_add(issues, ERROR, "embedded", where, "%s 陷進實心地形（格 %d,%d）" % [label, x, y])
				return
	if not grounded:
		return
	var supported := 0
	for x in range(left, right + 1):
		if _supports(layout.cell(x, bottom + 1)):
			supported += 1
	var columns := right - left + 1
	if _is_hazard(layout.cell(cx, bottom + 1)):
		_add(issues, ERROR, "on_hazard", where, "%s 站在尖刺或雷射上" % label)
	elif supported == 0:
		_add(issues, ERROR, "floating", where, "%s 腳下沒有地（懸空）" % label)
	elif supported * 2 < columns:
		_add(issues, WARN, "overhang", where, "%s 一半以上懸在地外（%d/%d 格有地）" % [label, supported, columns])


static func _check_props(data: LevelData, layout: LevelLayout, issues: Array[Dictionary]) -> void:
	if data.environment == null or data.layout_path.is_empty():
		return
	var dirs := data.environment.prop_dirs()
	var walls := BackWallGeometry.new()
	walls.setup(layout, hash(data.id), data.environment)
	var entries := data.load_props()
	for entry in entries:
		var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
		var where := "%s 欄 %d" % [data.id, int(entry["x"])]
		if prop == null:
			_add(issues, ERROR, "prop_missing", where, "擺設 %s 找不到資料" % entry["id"])
			continue
		var placed := PropPlacement.resolve(entry, prop, layout)
		if placed.is_empty():
			_add(issues, ERROR, "prop_floating", where, "擺設 %s 腳下沒有地表" % entry["id"])
			continue
		var rect: Rect2 = placed["rect"]
		var support_issue := ScenerySupport.check_prop(entry, prop, rect, layout, walls, entries, dirs)
		if not support_issue.is_empty():
			_add(issues, ERROR, support_issue, where, "擺設 %s 缺少 %s 支撐／接觸面：%s" % [entry["id"], entry.get("support", "ground"), rect])
		if rect.position.x < 0.0 or rect.end.x > layout.pixel_size().x:
			_add(issues, ERROR, "prop_outside", where, "擺設 %s 超出地圖左右邊界" % entry["id"])
		var buried := _buried_depth(layout, rect)
		# allow_overlap：看過畫面確認是景深（物件在牆後、吊掛在天花板上、貼著高牆）的擺設，不再警告。
		if buried > PROP_OVERLAP_TOLERANCE and not bool(entry.get("allow_overlap", false)):
			_add(issues, WARN, "prop_buried", where, "擺設 %s 有 %.0f 像素陷進實心地形" % [entry["id"], buried])


static func _check_decor(data: LevelData, layout: LevelLayout, issues: Array[Dictionary]) -> void:
	if layout.decor.is_empty():
		return
	var walls := BackWallGeometry.new()
	walls.setup(layout, hash(data.id), data.environment)
	for entry in layout.decor:
		if str(entry["kind"]) in ["neon_sign", "neon_sign_h", "billboard"]:
			var rect := ScenerySupport.decor_rect(entry, data)
			if not walls.covers(rect):
				_add(issues, ERROR, "decor_wall_missing", "%s %s" % [data.id, entry["cell"]], "%s 沒有完整的可見牆面：%s" % [entry["kind"], rect])


## rect 與實心格重疊的最小邊長（像素）；沒重疊為 0。上緣以下才算，貼著地面的底邊不算。
static func _buried_depth(layout: LevelLayout, rect: Rect2) -> float:
	var worst := 0.0
	for solid in layout.solid_rects:
		var box := layout.cells_to_pixels(solid)
		var overlap := rect.intersection(box)
		if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
			continue
		worst = maxf(worst, minf(overlap.size.x, overlap.size.y))
	return worst


# ---------------------------------------------------------------------------
# 可達性
# ---------------------------------------------------------------------------

## 從主角起點走、跳、落得到的站點集合（格座標 → true）。閘門視為打開，升降梯與光橋視為平台，水坑視為漲滿。
static func reachable_cells(layout: LevelLayout, extra_platforms: Array[Vector2i] = []) -> Dictionary:
	var extra: Dictionary = {}
	for cell in extra_platforms:
		extra[cell] = true
	var start_x := int(floorf(layout.player_start.x / layout.tile_size))
	var start_y := int(ceilf(layout.player_start.y / layout.tile_size)) - 1
	var start := _land(layout, extra, Vector2i(start_x, start_y))
	var seen: Dictionary = {}
	if start.x < 0:
		return seen
	seen[start] = true
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		for dx in range(-JUMP_ACROSS_CELLS, JUMP_ACROSS_CELLS + 1):
			var nx := at.x + dx
			if nx < 1 or nx >= layout.width - 1:
				continue
			for dy in range(-JUMP_UP_CELLS, 1):
				var ty := at.y + dy
				if ty < 0 or not _free_body(layout, nx, ty):
					continue
				if dy < 0 and _column_blocked(layout, at.x, at.y - 1, ty):
					continue
				if absi(dx) > 1 and dy == 0 and _row_blocked(layout, at.x, nx, at.y):
					continue
				var node := Vector2i(nx, ty) if _supported(layout, extra, nx, ty) else _land(layout, extra, Vector2i(nx, ty))
				if node.x >= 0 and not seen.has(node):
					seen[node] = true
					stack.append(node)
	return seen


static func _check_reachability(data: LevelData, layout: LevelLayout, issues: Array[Dictionary]) -> void:
	var extra := _mechanism_platforms(layout)
	var seen := reachable_cells(layout, extra)
	if seen.is_empty():
		_add(issues, ERROR, "start_unreachable", data.id, "主角起點落不到任何地面")
		return
	var targets: Array[Dictionary] = []
	for spawn in layout.spawns:
		var res := spawn["resource"] as Resource
		if res is PortalData or res is NpcData or res is ShopData or res is ConsumableData or res is StoryItemData or res is CreditPileData:
			targets.append({"label": "%s %s" % [_kind_of(res), _name_of(res)], "cell": spawn["cell"]})
	for point in layout.checkpoints:
		targets.append({"label": "checkpoint", "cell": Vector2i(int(point.x / layout.tile_size), int(ceilf(point.y / layout.tile_size)) - 1)})
	for target in targets:
		if not _near_seen(seen, target["cell"]):
			_add(issues, WARN, "unreachable", "%s %s" % [data.id, _cell_text(target["cell"])], "%s 從起點走不到（跳 %d 格高、%d 格遠內）" % [target["label"], JUMP_UP_CELLS, JUMP_ACROSS_CELLS])


## 升降梯在行程頂端、光橋與水坑浮橋額外多出來的可站格。
static func _mechanism_platforms(layout: LevelLayout) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for spawn in layout.spawns:
		var mech := spawn["resource"] as MechanismData
		if mech == null:
			continue
		var cell: Vector2i = spawn["cell"]
		match mech.kind:
			MechanismData.Kind.LIFT:
				for step in range(0, mech.travel_tiles + 1):
					for x in range(cell.x, cell.x + mech.size_tiles.x):
						cells.append(Vector2i(x, cell.y - step))
			MechanismData.Kind.FLOOD_PIT:
				for x in range(cell.x - 5, cell.x + 6):
					cells.append(Vector2i(x, cell.y - mech.size_tiles.y + 1))
	return cells


static func _near_seen(seen: Dictionary, cell: Vector2i) -> bool:
	for ax in range(-1, 2):
		for ay in range(-2, 2):
			if seen.has(Vector2i(cell.x + ax, cell.y + ay)):
				return true
	return false


static func _supported(layout: LevelLayout, extra: Dictionary, x: int, y: int) -> bool:
	return _supports(layout.cell(x, y + 1)) or extra.has(Vector2i(x, y + 1))


static func _free_body(layout: LevelLayout, x: int, y: int) -> bool:
	for k in BODY_CELLS:
		if layout.cell(x, y - k) == SOLID:
			return false
	return true


static func _land(layout: LevelLayout, extra: Dictionary, from: Vector2i) -> Vector2i:
	var y := from.y
	while y < layout.height - 1 and not _supported(layout, extra, from.x, y):
		y += 1
	if y >= layout.height - 1 or not _free_body(layout, from.x, y):
		return Vector2i(-1, -1)
	return Vector2i(from.x, y)


static func _column_blocked(layout: LevelLayout, x: int, from_y: int, to_y: int) -> bool:
	for y in range(to_y, from_y + 1):
		if layout.cell(x, y) == SOLID:
			return true
	return false


static func _row_blocked(layout: LevelLayout, x0: int, x1: int, y: int) -> bool:
	var step := 1 if x1 > x0 else -1
	for k in range(1, absi(x1 - x0)):
		if layout.cell(x0 + step * k, y) == SOLID:
			return true
	return false


# ---------------------------------------------------------------------------
# 尺寸與分類（資料驅動：新增物件種類只在這裡加一行）
# ---------------------------------------------------------------------------

## 物件在地圖上佔的大小（像素，寬以腳底為中心）；Vector2.ZERO＝不檢查（範圍、坑口等沒有實體的東西）。
static func footprint_of(res: Resource, tile: int) -> Vector2:
	if res is EnemyData:
		return (res as EnemyData).body_size
	if res is PortalData:
		var portal := res as PortalData
		return Vector2(12.0, 16.0) if portal.style == "road" else Vector2(portal.width, portal.height)
	if res is MechanismData:
		var mech := res as MechanismData
		match mech.kind:
			MechanismData.Kind.GATE:
				return Vector2(mech.size_tiles) * tile
			MechanismData.Kind.SWITCH, MechanismData.Kind.POWER_SWITCH:
				return Vector2(12.0, 16.0)
			_:
				return Vector2.ZERO
	if res is BreakableData:
		var breakable := res as BreakableData
		return Vector2.ZERO if breakable.look == BreakableData.Look.WALL else Vector2(breakable.size_tiles) * tile
	if res is NpcData:
		return Vector2(14.0, 44.0) if (res as NpcData).kind == NpcData.Kind.PERSON else Vector2(28.0, 28.0)
	if res is ShopData:
		return Vector2(28.0, 28.0)
	if res is ConsumableData or res is StoryItemData or res is CreditPileData or res is WeaponData:
		return Vector2(12.0, 12.0)
	return Vector2.ZERO


## 需要腳下有地的種類；道具與飛行敵人可以浮在空中。
static func needs_ground(res: Resource) -> bool:
	if res is EnemyData:
		return (res as EnemyData).uses_gravity
	if res is ConsumableData or res is StoryItemData or res is CreditPileData or res is WeaponData:
		return false
	return true


static func _kind_of(res: Resource) -> String:
	if res is EnemyData:
		return "敵人"
	if res is PortalData:
		return "出入口"
	if res is MechanismData:
		return "機關"
	if res is BreakableData:
		return "可破壞物"
	if res is NpcData:
		return "人物"
	if res is ShopData:
		return "商店"
	return "道具"


static func _name_of(res: Resource) -> String:
	var id: Variant = res.get(&"id")
	return str(id) if id != null else res.resource_path.get_file()


static func _find_portal(layout: LevelLayout, id: StringName) -> PortalData:
	if layout == null:
		return null
	for spawn in layout.spawns:
		var portal := spawn["resource"] as PortalData
		if portal != null and portal.id == id:
			return portal
	return null


static func _has_ledge_near(layout: LevelLayout, x: int, row: int) -> bool:
	for dx in range(-2, 3):
		for dy in range(-1, 2):
			if _supports(layout.cell(x + dx, row + dy)):
				return true
	return false


static func _supports(c: String) -> bool:
	return c == SOLID or c == PLATFORM or c == GHOST


static func _blocks_head(c: String) -> bool:
	return c == SOLID


static func _is_hazard(c: String) -> bool:
	return c == SPIKES or c == LASER


static func _cell_text(cell: Vector2i) -> String:
	return "(%d,%d)" % [cell.x, cell.y]


static func _add(issues: Array[Dictionary], severity: String, code: String, where: String, message: String) -> void:
	issues.append({"severity": severity, "code": code, "where": where, "message": message})


## 把問題依嚴重度分開，測試與報告共用。
static func split(issues: Array[Dictionary]) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	for issue in issues:
		(errors if issue["severity"] == ERROR else warnings).append(issue)
	return {"errors": errors, "warnings": warnings}


static func describe(issue: Dictionary) -> String:
	return "[%s] %s：%s（%s）" % [issue["severity"], issue["where"], issue["message"], issue["code"]]
