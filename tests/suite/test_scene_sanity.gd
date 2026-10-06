class_name SceneSanitySuite
extends TestSuite
## 場景合理性檢查（NE-210）：SceneAudit 對假地圖要抓得到問題（懸空、陷進地形、梯子太短、起點走不到的平台、
## 兩端梯子不一樣高、演員飄在舞台地板上），然後對全部真實關卡與過場舞台執行：不能有錯誤。


func run() -> void:
	_test_standing()
	_test_ladders()
	_test_reachability()
	_test_links()
	_test_stages()
	_test_real_levels()
	_test_real_stages()


# ---------------------------------------------------------------------------
# 假資料
# ---------------------------------------------------------------------------

## 以字串列建一張假地圖：# 實心、= 平台、^ 尖刺，其餘為空氣；起點在 start（格）。
func _layout(rows: Array[String], start := Vector2i(1, 0)) -> LevelLayout:
	var layout := LevelLayout.new()
	layout.rows = PackedStringArray(rows)
	layout.height = rows.size()
	layout.width = rows[0].length()
	layout.has_player_start = true
	layout.player_start = layout.cell_to_feet(start.x, start.y)
	return layout


func _data(id := "fake") -> LevelData:
	var data := LevelData.new()
	data.id = StringName(id)
	return data


func _enemy(size := Vector2(12, 20), gravity := true) -> EnemyData:
	var enemy := EnemyData.new()
	enemy.id = &"fake_enemy"
	enemy.body_size = size
	enemy.uses_gravity = gravity
	return enemy


func _portal(style: String, height: int, id := "p", width := 20) -> PortalData:
	var portal := PortalData.new()
	portal.id = StringName(id)
	portal.style = style
	portal.height = height
	portal.width = width
	return portal


func _spawn(layout: LevelLayout, res: Resource, cell: Vector2i) -> void:
	layout.spawns.append({"resource": res, "position": layout.cell_to_feet(cell.x, cell.y), "cell": cell})


func _codes(issues: Array[Dictionary]) -> PackedStringArray:
	var codes := PackedStringArray()
	for issue in issues:
		codes.append(issue["code"])
	return codes


# ---------------------------------------------------------------------------
# 站得穩、不陷進地形
# ---------------------------------------------------------------------------

func _test_standing() -> void:
	var layout := _layout([
		".........",
		".........",
		".........",
		".........",
		"##...####",
		"##.......",
	], Vector2i(0, 3))
	_spawn(layout, _enemy(), Vector2i(0, 3))   # 站在地面上
	_spawn(layout, _enemy(), Vector2i(3, 3))   # 下面是空的：懸空
	_spawn(layout, _enemy(Vector2(12, 20), false), Vector2i(3, 2))   # 飛行敵人浮著沒關係
	_spawn(layout, _enemy(Vector2(34, 24)), Vector2i(5, 3))   # 寬 34 的身體貼著右邊的牆：擦邊容許，不算陷進
	var issues := SceneAudit.audit(_data(), layout)
	var floating := issues.filter(func(i: Dictionary) -> bool: return i["code"] == "floating")
	check(floating.size() == 1 and str(floating[0]["where"]).contains("(3,3)"), "an enemy over empty air is reported once (%s)" % [_codes(issues)])
	check(not _codes(issues).has("embedded"), "an enemy brushing a wall by a few pixels is not embedded (%s)" % [_codes(issues)])
	var buried := _layout([
		".........",
		".........",
		"..#......",
		"..#......",
		"#########",
	], Vector2i(0, 3))
	_spawn(buried, _enemy(Vector2(40, 20)), Vector2i(1, 3))
	check(_codes(SceneAudit.audit(_data(), buried)).has("embedded"), "a 40 px wide enemy standing against a wall is embedded in it")
	var spikes := _layout(["....", "....", "^^^^"], Vector2i(0, 1))
	_spawn(spikes, _enemy(), Vector2i(2, 1))
	check(_codes(SceneAudit.audit(_data(), spikes)).has("on_hazard"), "standing on spikes is reported")
	var pit_start := _layout(["...", "...", "..."], Vector2i(1, 1))
	check(_codes(SceneAudit.audit(_data(), pit_start)).has("floating"), "a player start over nothing is reported")


# ---------------------------------------------------------------------------
# 梯子與門
# ---------------------------------------------------------------------------

func _test_ladders() -> void:
	var rows: Array[String] = ["########"]
	for i in 11:
		rows.append("#......#")
	rows.append("########")
	var hall := _layout(rows, Vector2i(1, 11))
	_spawn(hall, _portal("ladder", 48, "short"), Vector2i(3, 11))
	_spawn(hall, _portal("ladder", 176, "full"), Vector2i(5, 11))
	var by_code := {}
	for issue in SceneAudit.audit(_data(), hall):
		by_code[issue["code"]] = str(issue["message"])
	check(by_code.has("ladder_short") and str(by_code["ladder_short"]).contains("short"), "a 3 cell ladder in an 11 cell room is reported (%s)" % [by_code])
	var short_count := SceneAudit.audit(_data(), hall).filter(func(i: Dictionary) -> bool: return i["code"] == "ladder_short").size()
	check(short_count == 1, "the ladder that reaches the ceiling is not reported (%d)" % short_count)
	var low_door := _layout(["....", "....", "####"], Vector2i(0, 1))
	_spawn(low_door, _portal("door", 20, "tiny"), Vector2i(2, 1))
	check(_codes(SceneAudit.audit(_data(), low_door)).has("door_small"), "a door lower than the protagonist is reported")
	var hidden := _layout(["....", "....", "####"], Vector2i(0, 1))
	_spawn(hidden, _portal("hidden", 44, "hut"), Vector2i(2, 1))
	check(SceneAudit.audit(_data(), hidden).filter(func(i: Dictionary) -> bool: return i["severity"] == SceneAudit.ERROR).is_empty(), "a hidden portal on the ground is fine")


# ---------------------------------------------------------------------------
# 可達性
# ---------------------------------------------------------------------------

func _test_reachability() -> void:
	var rows: Array[String] = []
	for i in 14:
		rows.append("....................")
	rows[5] = ".......=.........=....."   # 離地面 8 格：跳不上去的平台（連箱子頂也差 6 格）
	rows[12] = "...#................."    # 一格高的箱子：跳得上去
	rows.append("####################")
	rows.append("####################")
	var layout := _layout(rows, Vector2i(1, 13))
	var seen := SceneAudit.reachable_cells(layout)
	check(seen.has(Vector2i(1, 13)), "the start cell itself is reachable")
	check(seen.has(Vector2i(3, 11)), "a 1 cell crate can be climbed")
	check(not seen.has(Vector2i(7, 4)), "a platform 8 cells above the ground cannot be jumped to")
	var island := _layout(["....", "....", "###.", "...."], Vector2i(0, 1))
	check(SceneAudit.reachable_cells(island).size() >= 1, "an island start still reaches its own ledge")
	var floating := _layout(rows, Vector2i(1, 13))
	_spawn(floating, _portal("door", 44, "high"), Vector2i(7, 4))
	check(_codes(SceneAudit.audit(_data(), floating)).has("unreachable"), "a door on an unreachable platform is reported")


# ---------------------------------------------------------------------------
# 出入口連結
# ---------------------------------------------------------------------------

func _test_links() -> void:
	var a := _layout(["....", "....", "####"], Vector2i(0, 1))
	var b := _layout(["....", "....", "####"], Vector2i(0, 1))
	var up := _portal("ladder", 152, "up")
	up.target_level = "res://b"
	up.target_portal = &"down"
	var down := _portal("ladder", 48, "down")
	down.target_level = "res://a"
	down.target_portal = &"up"
	_spawn(a, up, Vector2i(2, 1))
	_spawn(b, down, Vector2i(2, 1))
	var datas := {"res://a": _data("a"), "res://b": _data("b")}
	var layouts := {"res://a": a, "res://b": b}
	check(_codes(SceneAudit.audit_links(datas, layouts)).has("ladder_pair"), "two ladders of different heights are reported as a pair mismatch")
	down.style = "hidden"
	check(SceneAudit.audit_links(datas, layouts).is_empty(), "a ladder paired with a hidden stairwell door is fine")
	up.target_portal = &"nowhere"
	check(_codes(SceneAudit.audit_links(datas, layouts)).has("portal_link"), "a portal whose other end does not exist is an error")


# ---------------------------------------------------------------------------
# 過場舞台
# ---------------------------------------------------------------------------

func _test_stages() -> void:
	var defs := {"room": {"floor": 300}, "bare": {}}
	var resolve := func(id: String) -> Dictionary: return defs.get(id, {})
	var scenes := {
		"good": {"mode": "animated", "steps": [
			{"do": "scene", "id": "room"},
			{"do": "actor", "id": "a", "kind": "rin", "pos": [100, 302], "scale": 3.0},
			{"do": "actor", "id": "b", "kind": "rin", "pos": [200, 310], "pose": "squat", "scale": 3.1},
			{"do": "move", "id": "a", "to": [180, 298]},
		]},
		"floaty": {"mode": "animated", "steps": [
			{"do": "scene", "id": "room"},
			{"do": "actor", "id": "a", "kind": "k", "pos": [100, 250]},
			{"do": "actor", "id": "b", "kind": "k", "pos": [200, 300]},
			{"do": "move", "id": "b", "to": [220, 340]},
			{"do": "pose", "id": "b", "pose": "sit"},
			{"do": "move", "id": "b", "to": [240, 340]},
		]},
		"big_small": {"mode": "animated", "steps": [
			{"do": "scene", "id": "bare"},
			{"do": "actor", "id": "a", "kind": "nurse", "pos": [100, 250], "scale": 2.0},
			{"do": "actor", "id": "b", "kind": "nurse", "pos": [200, 250], "scale": 3.0},
		]},
		"not_animated": {"mode": "radio", "steps": []},
	}
	var issues := SceneAudit.audit_stages(scenes, resolve)
	var feet := issues.filter(func(i: Dictionary) -> bool: return i["code"] == "stage_feet")
	check(feet.size() == 2, "an actor floating above the floor and one walking below it are reported, not the seated or squatting ones (%d)" % feet.size())
	check(not str(feet).contains("good"), "a scene with feet on the floor is clean")
	var spread := issues.filter(func(i: Dictionary) -> bool: return i["code"] == "stage_scale")
	check(spread.size() == 1 and str(spread[0]["where"]).contains("nurse"), "two nurses at scale 2.0 and 3.0 on one stage are reported")


# ---------------------------------------------------------------------------
# 真實資料
# ---------------------------------------------------------------------------

func _test_real_levels() -> void:
	var paths := SceneAudit.level_paths()
	check(paths.size() >= 10, "every level under data/levels is audited (%d)" % paths.size())
	var datas: Dictionary = {}
	var layouts: Dictionary = {}
	for path in paths:
		var data := load(path) as LevelData
		check(data != null, "level loads: %s" % path)
		if data == null:
			continue
		datas[path] = data
		layouts[path] = LevelBuilder.parse(data)
		var split := SceneAudit.split(SceneAudit.audit(data, layouts[path]))
		for issue: Dictionary in split["errors"]:
			check(false, "scene sanity: %s" % SceneAudit.describe(issue))
		check(split["errors"].is_empty(), "%s has no scene sanity errors" % path.get_file())
		for issue: Dictionary in split["warnings"]:
			check(false, "scene sanity warning (reviewed warnings are marked in the data): %s" % SceneAudit.describe(issue))
	var links := SceneAudit.split(SceneAudit.audit_links(datas, layouts))
	for issue: Dictionary in links["errors"] + links["warnings"]:
		check(false, "scene link: %s" % SceneAudit.describe(issue))
	check(links["errors"].is_empty() and links["warnings"].is_empty(), "portal pairs across all levels are consistent")


func _test_real_stages() -> void:
	var issues := SceneAudit.audit_stages(Story.audit_data()["scenes"], StageLibrary.definition)
	for issue in issues:
		check(false, "stage sanity: %s" % SceneAudit.describe(issue))
	check(issues.is_empty(), "every animated scene keeps actors on the stage floor and the same size")
