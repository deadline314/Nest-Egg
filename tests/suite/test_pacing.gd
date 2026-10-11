class_name PacingSuite
extends TestSuite
## 第一章節奏估計（ST-11）：估計算法本身（假地圖：分群、無遭遇的連續段、時間加總）與真資料的節奏門檻
## （PACING_REFERENCE §5.2：首次通關 30–45 分鐘、警訊 <25 / >55；每分鐘遭遇 0.5–0.8；戰鬥區連續無遭遇 ≤ 60 秒；每區 ≤ 8 分鐘）。
## 估計用的是常數假設（core/pacing_estimate.gd），有遊測資料之後校正常數，不是量測值。

const IDS: Array[String] = ["pawnshop", "rooftop", "street", "booth_alley", "warehouse", "vault", "handoff", "lounge", "stall"]
const COMBAT_AREAS: Array[String] = ["street", "warehouse", "vault"]
const CUTSCENES: Array[String] = ["ch1_p01_door", "ch1_c09_wake", "ch1_c14_home"]
## 已知超過每區 8 分鐘的區域（目前沒有；倉庫已在 ST-14 拆成兩張地圖）。要暫時放行時列在這裡，修好之後從清單刪掉。
const KNOWN_LONG_AREAS: Array[String] = []
const MAX_AREA_MINUTES := 8.0


func run() -> void:
	_test_algorithm()
	_test_real_chapter()


func _enemy(health: int) -> EnemyData:
	var enemy := EnemyData.new()
	enemy.id = &"fake"
	enemy.max_health = health
	return enemy


func _layout(width: int, enemies: Array) -> LevelLayout:
	var layout := LevelLayout.new()
	layout.width = width
	layout.height = 10
	layout.tile_size = 16
	for entry: Array in enemies:
		layout.spawns.append({"resource": _enemy(entry[1]), "position": Vector2.ZERO, "cell": Vector2i(entry[0], 5)})
	return layout


func _test_algorithm() -> void:
	var none := func(_id: StringName) -> int: return 0
	var layout := _layout(200, [[40, 3], [44, 3], [100, 6]])
	var estimate := PacingEstimate.area(LevelData.new(), layout, none)
	check(int(estimate["encounters"]) == 2, "enemies 4 tiles apart are one encounter, far ones another (%d)" % int(estimate["encounters"]))
	var gaps: Array = estimate["quiet_gaps"]
	check(gaps.size() == 3, "two encounters leave three quiet stretches (%d)" % gaps.size())
	check(is_equal_approx(float(gaps[0]), 40.0 * 16.0 / PacingEstimate.WALK_SPEED), "the first stretch runs from the area start to the first enemy (%.1f s)" % float(gaps[0]))
	check(is_equal_approx(float(estimate["max_quiet"]), maxf(float(gaps[0]), maxf(float(gaps[1]), float(gaps[2])))), "the longest stretch is reported")
	var kills := 2.0 * (PacingEstimate.APPROACH_SECONDS + 3.0 * PacingEstimate.SECONDS_PER_HEALTH) + (PacingEstimate.APPROACH_SECONDS + 6.0 * PacingEstimate.SECONDS_PER_HEALTH)
	check(is_equal_approx(float(estimate["combat"]), kills), "combat time adds up from enemy health (%.1f vs %.1f)" % [float(estimate["combat"]), kills])
	var given := PacingEstimate.area(LevelData.new(), layout, none, [Vector2(30, 50), Vector2(90, 110), Vector2(150, 160)] as Array[Vector2])
	check(int(given["encounters"]) == 3, "encounter ranges from the design data override the enemy clustering")
	var chapter := PacingEstimate.chapter([{"total": 600.0, "encounters": 10}, {"total": 300.0, "encounters": 4}], 100.0)
	var expected := 900.0 * PacingEstimate.FIRST_TIME_FACTOR + float(PacingEstimate.EXPECTED_DEATHS) * PacingEstimate.RETRY_SECONDS + 100.0
	check(is_equal_approx(float(chapter["first_time_minutes"]) * 60.0, expected), "a first playthrough is the skilled time times the factor, plus deaths, plus cutscenes")
	check(int(chapter["encounters"]) == 14, "chapter encounters are summed")


func _test_real_chapter() -> void:
	var design: Dictionary = (load("res://data/levels/ch1_design.json") as JSON).data["areas"]
	var lines := func(scene: StringName) -> int: return Story.scene_lines(scene).size()
	var areas: Array = []
	for id in IDS:
		var data := load("res://data/levels/ch1_%s.tres" % id) as LevelData
		var ranges: Array[Vector2] = []
		for e: Dictionary in (design.get(id, {}) as Dictionary).get("encounters", []):
			ranges.append(Vector2(float(e["x0"]), float(e["x1"])))
		var entry := PacingEstimate.area(data, LevelBuilder.parse(data), lines, ranges)
		areas.append(entry)
		var minutes := float(entry["total"]) * PacingEstimate.FIRST_TIME_FACTOR / 60.0
		if KNOWN_LONG_AREAS.has(id):
			check(minutes > MAX_AREA_MINUTES, "%s is on the known-long list, so it should still be long (%.1f min); remove it from the list once fixed" % [id, minutes])
		else:
			check(minutes <= MAX_AREA_MINUTES, "%s takes at most %.0f minutes the first time (%.1f)" % [id, MAX_AREA_MINUTES, minutes])
		if COMBAT_AREAS.has(id):
			check(float(entry["max_quiet"]) <= PacingEstimate.MAX_QUIET_SECONDS, "%s never goes more than %.0f seconds without an encounter (%.0f s)" % [id, PacingEstimate.MAX_QUIET_SECONDS, float(entry["max_quiet"])])
	var cutscene_seconds := 0.0
	for id in CUTSCENES:
		cutscene_seconds += float((Story.audit_data()["scenes"][id] as Dictionary).get("budget", 0.0))
	check(cutscene_seconds > 0.0, "the three cutscenes declare their budgets (%.0f s)" % cutscene_seconds)
	var chapter := PacingEstimate.chapter(areas, cutscene_seconds)
	var minutes: float = chapter["first_time_minutes"]
	check(minutes >= PacingEstimate.WARN_MINUTES.x and minutes <= PacingEstimate.WARN_MINUTES.y, "the first playthrough is estimated at %.1f minutes, inside the warning band %.0f–%.0f" % [minutes, PacingEstimate.WARN_MINUTES.x, PacingEstimate.WARN_MINUTES.y])
	check(minutes >= PacingEstimate.TARGET_MINUTES.x and minutes <= PacingEstimate.TARGET_MINUTES.y, "and inside the target %.0f–%.0f (%.1f)" % [PacingEstimate.TARGET_MINUTES.x, PacingEstimate.TARGET_MINUTES.y, minutes])
	var rate: float = chapter["encounters_per_minute"]
	check(rate >= PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.x and rate <= PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.y, "%.2f encounters a minute is inside the %.1f–%.1f target" % [rate, PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.x, PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.y])
	check(float(chapter["cutscene_share"]) <= 0.08, "cutscenes take at most 8%% of the time (%.1f%%)" % (float(chapter["cutscene_share"]) * 100.0))
	check(int(chapter["encounters"]) >= 22 and int(chapter["encounters"]) <= 26, "the design lists 22–26 encounters (%d)" % int(chapter["encounters"]))
	_test_prologue(lines)


## 序章（ST-16）：首次 3～6 分鐘，鎖操作的電影與對話不超過一半；每項練習都算到可玩時間。
func _test_prologue(lines: Callable) -> void:
	var data := load("res://data/levels/ch1_prologue.tres") as LevelData
	var entry := PacingEstimate.area(data, LevelBuilder.parse(data), lines)
	check(float(entry["practice"]) >= PacingEstimate.PRACTICE_SECONDS * 5.0, "the prologue counts its five verb practices as play (%.0f s)" % float(entry["practice"]))
	var opening := PacingEstimate.along_path(entry, PacingEstimate.PROLOGUE_PATH, Story.pacing_info)
	for id in PacingEstimate.PROLOGUE_PATH:
		check(Story.has_scene(id), "the prologue path scene exists: %s" % id)
	var minutes: float = opening["first_time_minutes"]
	check(minutes >= PacingEstimate.PROLOGUE_MINUTES.x and minutes <= PacingEstimate.PROLOGUE_MINUTES.y, "the prologue is estimated at %.1f minutes, inside %.0f–%.0f" % [minutes, PacingEstimate.PROLOGUE_MINUTES.x, PacingEstimate.PROLOGUE_MINUTES.y])
	check(float(opening["locked_share"]) <= PacingEstimate.PROLOGUE_MAX_LOCKED_SHARE, "cutscenes and locked dialogue stay under half of the prologue (%.1f%%)" % (float(opening["locked_share"]) * 100.0))
