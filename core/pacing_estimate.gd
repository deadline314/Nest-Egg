class_name PacingEstimate
extends RefCounted
## 章節遊玩時間與節奏的腳本估計（ST-11，見 design/13-story-v2/CH01_PACING_V2.md 與 PACING_REFERENCE.md §5.2）。
## 沒有真人遊測之前用資料算：走路、戰鬥、對話、拾取、機關、商店、過場各算一筆，再乘上「第一次玩」的係數。
## 所有假設都是下面的常數（單位秒或像素），有遊測資料後直接改常數校正；數字一律由資料算出（地圖、敵人血量、台詞行數），
## 所以改地圖或敵人之後報表自動跟著變。報告工具：godot --headless --path . res://tools/pacing_report.tscn

## 全速跑 150 px/s × 0.7（停下來瞄準、跳躍、看路、被擋）。
const WALK_SPEED := 105.0
## 擊倒一個敵人要花的秒數 ＝ 接近 + 血量 × 每點血的秒數。
const APPROACH_SECONDS := 4.0
const SECONDS_PER_HEALTH := 1.1
## 鎖場多出的時間（閘門、增援入場、清場後的停頓）。
const LOCK_OVERHEAD := 10.0
## 玩家主動按鍵的對話每句秒數（含讀字）；地圖氣泡邊走邊看，只算一半的注意力。
const TALK_LINE_SECONDS := 3.0
const BUBBLE_LINE_SECONDS := 1.5
## 繞路拾取一個東西。
const PICKUP_SECONDS := 2.5
## 一個機關（開關、升降梯、電力開關）與水坑謎題的操作時間。
const SWITCH_SECONDS := 20.0
const FLOOD_PIT_SECONDS := 45.0
## 商店與典當的停留（一次）。
const SHOP_SECONDS := 60.0
## 序章的一項操作練習（看提示、試做、失手重來一次）。
const PRACTICE_SECONDS := 10.0
## 序章目標（ST-16、PROLOGUE.md）：首次 3～6 分鐘，鎖操作的過場與對話不超過一半。
const PROLOGUE_MINUTES := Vector2(3.0, 6.0)
const PROLOGUE_MAX_LOCKED_SHARE := 0.5
## 序章完整路線上依序播出的場景（含一次訓練器失手；自願閱讀與重看不算）。
const PROLOGUE_PATH: Array[StringName] = [&"ch1_p01_door", &"ch1_p02_talk", &"ch1_p02_tool", &"ch1_p03_range", &"ch1_p03_hit",
	&"ch1_p04_intro", &"ch1_p04_melee", &"ch1_p04_fall", &"ch1_p04_guard", &"ch1_p04_dash", &"ch1_p05_service_fall", &"ch1_p06_call"]
## 第一次玩：學操作、迷路（比熟練者慢的倍率），加上預期死亡次數與每次重來的秒數（走回去、重打）。
const FIRST_TIME_FACTOR := 1.5
const EXPECTED_DEATHS := 3
const RETRY_SECONDS := 45.0
## 相鄰兩隻敵人超過這麼多格就算兩場遭遇。
const CLUSTER_TILES := 8
## 目標與警訊（PACING_REFERENCE §5.2）：首次通關分鐘數、每分鐘遭遇數、連續無遭遇秒數。
const TARGET_MINUTES := Vector2(30.0, 45.0)
const WARN_MINUTES := Vector2(25.0, 55.0)
const TARGET_ENCOUNTERS_PER_MINUTE := Vector2(0.5, 0.8)
const MAX_QUIET_SECONDS := 60.0


## 一個區域的估計。scene_lines：Callable(場景 id) -> 台詞行數（沒有場景回傳 0）。
## encounters：設計資料裡的遭遇範圍（Vector2 的 x 是起欄、y 是迄欄）；空陣列時改用敵人位置自己分群。
## 回傳 { walk, combat, talk, bubbles, pickups, puzzles, shop, total, encounters, quiet_gaps（秒，無遭遇的連續段）, max_quiet, width_tiles }。
static func area(data: LevelData, layout: LevelLayout, scene_lines: Callable, encounters: Array[Vector2] = []) -> Dictionary:
	var tile := float(layout.tile_size)
	var width_tiles := layout.width
	var result := {"walk": float(width_tiles) * tile / WALK_SPEED, "combat": 0.0, "talk": 0.0, "bubbles": 0.0, "pickups": 0.0, "puzzles": 0.0, "shop": 0.0, "practice": 0.0,
			"encounters": 0, "quiet_gaps": [], "max_quiet": 0.0, "width_tiles": width_tiles}
	var enemy_cells: Array[Dictionary] = []  # { x, health }
	var lock_count := 0
	for spawn in layout.spawns:
		var res := spawn["resource"] as Resource
		var cell: Vector2i = spawn["cell"]
		if res is EnemyData:
			enemy_cells.append({"x": cell.x, "health": (res as EnemyData).max_health})
		elif res is MechanismData:
			var mech := res as MechanismData
			match mech.kind:
				MechanismData.Kind.ENCOUNTER:
					lock_count += 1
					for reinforcement in mech.reinforcements:
						if reinforcement != null:
							result["combat"] += _kill_seconds(reinforcement.max_health)
				MechanismData.Kind.SWITCH, MechanismData.Kind.POWER_SWITCH, MechanismData.Kind.LIFT:
					result["puzzles"] += SWITCH_SECONDS if mech.kind != MechanismData.Kind.LIFT else 5.0
				MechanismData.Kind.FLOOD_PIT:
					result["puzzles"] += FLOOD_PIT_SECONDS
			if mech.start_scene != &"":
				result["bubbles"] += float(scene_lines.call(mech.start_scene)) * BUBBLE_LINE_SECONDS
		elif res is ConsumableData or res is StoryItemData or res is CreditPileData or res is WeaponData:
			result["pickups"] += PICKUP_SECONDS
		elif res is ShopData:
			result["shop"] += SHOP_SECONDS
		elif res is TrainingData:
			# 練習本身可玩；完成與失手的劇情保守算成鎖操作的對話。
			var training := res as TrainingData
			result["practice"] += PRACTICE_SECONDS if training.kind != TrainingData.Kind.REACH else 0.0
			for scene in [training.done_scene, training.fail_scene]:
				if scene != &"":
					result["talk"] += float(scene_lines.call(scene)) * TALK_LINE_SECONDS
		elif res is NpcData:
			for talk in (res as NpcData).talks:
				if talk != null:
					result["talk"] += float(scene_lines.call(talk.scene)) * TALK_LINE_SECONDS
	if not layout.boss_spawn.is_empty() and layout.boss_spawn["resource"] is EnemyData:
		enemy_cells.append({"x": (layout.boss_spawn["cell"] as Vector2i).x, "health": (layout.boss_spawn["resource"] as EnemyData).max_health})
	for id in data.story_triggers:
		result["bubbles"] += float(scene_lines.call(StringName(id))) * BUBBLE_LINE_SECONDS
	for health in enemy_cells.map(func(e: Dictionary) -> int: return int(e["health"])):
		result["combat"] += _kill_seconds(health)
	result["combat"] += float(lock_count) * LOCK_OVERHEAD
	# 遭遇分群：依 x 排序，相鄰超過 CLUSTER_TILES 就是新的一場
	enemy_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	var clusters: Array[Vector2] = encounters.duplicate()
	for e in enemy_cells if encounters.is_empty() else []:
		var x := float(e["x"])
		if clusters.is_empty() or x - clusters[clusters.size() - 1].y > CLUSTER_TILES:
			clusters.append(Vector2(x, x))
		else:
			clusters[clusters.size() - 1] = Vector2(clusters[clusters.size() - 1].x, x)
	result["encounters"] = clusters.size()
	# 沒有遭遇的連續段（秒）：從區域起點到第一場、場與場之間、最後一場到區域終點
	var gaps: Array[float] = []
	var cursor := 0.0
	for c in clusters:
		gaps.append(maxf(0.0, c.x - cursor) * tile / WALK_SPEED)
		cursor = c.y
	gaps.append(maxf(0.0, float(width_tiles) - cursor) * tile / WALK_SPEED)
	result["quiet_gaps"] = gaps
	result["max_quiet"] = gaps.max() if not gaps.is_empty() else 0.0
	result["total"] = float(result["walk"]) + float(result["combat"]) + float(result["talk"]) + float(result["bubbles"]) + float(result["pickups"]) + float(result["puzzles"]) + float(result["shop"]) + float(result["practice"])
	return result


## 整個章節：areas 是每個區域的 area() 結果，cutscene_seconds 是過場預估秒數的總和。
## 回傳 { seconds（技巧純熟）, first_time_minutes, encounters, encounters_per_minute, cutscene_share }。
static func chapter(areas: Array, cutscene_seconds: float) -> Dictionary:
	var play := 0.0
	var encounters := 0
	for entry: Dictionary in areas:
		play += float(entry["total"])
		encounters += int(entry["encounters"])
	# 過場是固定長度，不受「第一次玩」係數影響
	var first_time := play * FIRST_TIME_FACTOR + float(EXPECTED_DEATHS) * RETRY_SECONDS + cutscene_seconds
	var minutes := first_time / 60.0
	return {"seconds": play + cutscene_seconds, "first_time_minutes": minutes, "encounters": encounters,
			"encounters_per_minute": float(encounters) / maxf(0.1, minutes), "cutscene_share": cutscene_seconds / maxf(1.0, first_time)}


static func _kill_seconds(health: int) -> float:
	return APPROACH_SECONDS + float(health) * SECONDS_PER_HEALTH


## 序章（或任何短段落）沿一條實際路徑估計：entry 是 area() 的結果（取走路與練習秒數），scenes 是這條路上依序播出的場景，
## info：Callable(場景 id) -> { lines, mode, budget }。有 budget 的電影照 budget 算；bubbles／radio 邊走邊看算可玩；其餘鎖操作。
## 回傳 { first_time_minutes, locked_share, locked_seconds, free_seconds }。
static func along_path(entry: Dictionary, scenes: Array, info: Callable) -> Dictionary:
	var locked := 0.0
	var free := float(entry["walk"]) + float(entry["practice"]) + float(entry["pickups"])
	for id: Variant in scenes:
		var scene: Dictionary = info.call(StringName(str(id)))
		var budget := float(scene.get("budget", 0.0))
		var count := float(scene.get("lines", 0))
		if budget > 0.0:
			locked += budget
		elif str(scene.get("mode", "")) in ["bubbles", "radio"]:
			free += count * BUBBLE_LINE_SECONDS
		else:
			locked += count * TALK_LINE_SECONDS
	var first_time := free * FIRST_TIME_FACTOR + locked
	return {"first_time_minutes": first_time / 60.0, "locked_share": locked / maxf(1.0, first_time), "locked_seconds": locked, "free_seconds": free}
