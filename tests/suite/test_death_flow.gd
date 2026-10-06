class_name DeathFlowSuite
extends TestSuite
## 死亡與復活的流程（ST-13）：第一次死亡先到診間（不扣復原費、播完才寫旗標、登記最近的電話亭、重生時提示一次），
## 之後的死亡走一般死亡畫面並在電話亭醒來；死亡場景表的挑選規則與壞資料、旗標沒寫入／中途退出的容錯。

const BOOTH_AREA := "res://data/levels/ch1_booth_alley.tres"
const FIRST_DEATH_SCENE := &"ch1_c09_wake"
const SEEN_FLAG := &"ch1_first_death_done"


func run() -> void:
	_test_pick_rules()
	_test_pick_bad_data()
	_test_validation()
	_test_chapter_data()
	await _test_first_death_flow()
	await _test_second_death_uses_the_screen()
	await _test_unfinished_scene_plays_again()
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	Story.reset_progress()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _flags(set_flags: Array) -> Callable:
	return func(flag: StringName) -> bool: return set_flags.has(String(flag))


func _entries() -> Array:
	return [
		{"scene": "special", "unless_flag": "done", "cause": "flood", "free": true},
		{"scene": "later", "min_deaths": 3, "max_deaths": 5, "repeat": true},
		{"scene": "needs", "requires_flag": "key", "repeat": true},
	]


func _wait_for_scene(started: Array[StringName], id: StringName, frames_max := 400) -> bool:
	var guard := 0
	while not started.has(id) and guard < frames_max:
		await frames(1)
		guard += 1
	return started.has(id)


## 讓玩家真的死一次（致命傷害）。
func _kill(level: Level) -> void:
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"grunt_shot")
	lethal.ignore_invulnerability = true
	level.player.health.take_damage(lethal)


# ---------------------------------------------------------------------------
# 挑選規則（純資料）
# ---------------------------------------------------------------------------

func _test_pick_rules() -> void:
	var none := _flags([])
	var picked := StoryReactions.pick_death_scene(_entries(), 1, &"flood", none)
	check(str(picked.get("scene", "")) == "special", "the special scene wins the first matching death (cause and flag fit)")
	picked = StoryReactions.pick_death_scene(_entries(), 1, &"grunt_shot", none)
	check(picked.is_empty(), "a different cause skips a cause-bound scene (%s)" % [picked])
	picked = StoryReactions.pick_death_scene(_entries(), 1, &"flood", _flags(["done"]))
	check(picked.is_empty(), "unless_flag: once the flag is set the scene never plays again")
	picked = StoryReactions.pick_death_scene(_entries(), 4, &"x", none)
	check(str(picked.get("scene", "")) == "later", "min_deaths / max_deaths pick by death count")
	picked = StoryReactions.pick_death_scene(_entries(), 6, &"x", none)
	check(picked.is_empty(), "past max_deaths nothing plays")
	picked = StoryReactions.pick_death_scene(_entries(), 6, &"x", _flags(["key"]))
	check(str(picked.get("scene", "")) == "needs", "requires_flag plays only after the flag is set")
	picked = StoryReactions.pick_death_scene(_entries(), 1, &"flood", none)
	check(bool(picked.get("free", false)), "the entry carries its options (free)")


func _test_pick_bad_data() -> void:
	var none := _flags([])
	check(StoryReactions.pick_death_scene("oops", 1, &"x", none).is_empty(), "a non-array table is ignored")
	check(StoryReactions.pick_death_scene([1, null, {"min_deaths": 1}, {"scene": ""}], 1, &"x", none).is_empty(), "broken entries are skipped")
	var picked := StoryReactions.pick_death_scene([5, {"scene": "ok", "repeat": true}], 1, &"x", none)
	check(str(picked.get("scene", "")) == "ok", "a broken entry does not hide a good one after it")
	check(StoryReactions.max_deaths({"max_deaths": "x"}) > 1000000, "an invalid max_deaths means no upper limit")


func _test_validation() -> void:
	var has_scene := func(id: StringName) -> bool: return String(id) != "missing"
	var flags_of := func(id: StringName) -> Array: return ["done"] if String(id) == "special" else []
	var good := [{"scene": "special", "unless_flag": "done"}]
	check(StoryReactions.validate_death_scenes("t", good, has_scene, flags_of).is_empty(), "a consistent entry passes")
	check(not StoryReactions.validate_death_scenes("t", [{"scene": "missing", "repeat": true}], has_scene, flags_of).is_empty(), "a missing scene is reported")
	check(not StoryReactions.validate_death_scenes("t", [{"scene": "other", "unless_flag": "done"}], has_scene, flags_of).is_empty(),
			"unless_flag that the scene itself never sets is reported (it would replay on every death)")
	check(not StoryReactions.validate_death_scenes("t", [{"scene": "special"}], has_scene, flags_of).is_empty(),
			"no flag and no repeat is reported")
	check(not StoryReactions.validate_death_scenes("t", "x", has_scene, flags_of).is_empty(), "a non-array table is reported")
	check(not StoryReactions.validate_death_scenes("t", [3], has_scene, flags_of).is_empty(), "a non-object entry is reported")


func _test_chapter_data() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	check(Story.validate().is_empty(), "the story data passes validation: %s" % [Story.validate()])
	var entry := Story.death_scene_entry(&"ch1_kasa", &"flood", 1)
	check(str(entry.get("scene", "")) == String(FIRST_DEATH_SCENE), "chapter 1: the first death goes to the clinic scene (%s)" % [entry])
	check(bool(entry.get("free", false)) and bool(entry.get("register_checkpoint", false)), "the clinic scene is free and registers a booth")
	var scene_flags := Story._scene_set_flags(FIRST_DEATH_SCENE)
	check(scene_flags.has(String(SEEN_FLAG)), "the clinic scene writes its own flag when it finishes")
	check(not Story.death_scene_entry(&"ch1_kasa", &"grunt_shot", 1).is_empty(), "the first death uses the clinic whatever the cause")
	GameState.set_flag(SEEN_FLAG)
	check(Story.death_scene_entry(&"ch1_kasa", &"flood", 2).is_empty(), "after the flag, deaths take the normal path")
	# 之後各次死亡在電話亭醒來時的短句：前幾次完整、之後縮短，而且每次都播。
	check(Story.respawn_scene_ids(&"ch1_kasa", 1) == [&"ch1_d_back_a"], "deaths 1-3: the full line")
	check(Story.respawn_scene_ids(&"ch1_kasa", 5) == [&"ch1_d_back_b"], "deaths 4-9: the second line")
	check(Story.respawn_scene_ids(&"ch1_kasa", 12) == [&"ch1_d_back_c"], "deaths 10+: the shortest line")
	for text in Story.resolved_lines(FIRST_DEATH_SCENE):
		check(false, "the clinic scene is animated, so it has no flat lines")
		break
	GameState.start_new_run(GameState.difficulties[1])


# ---------------------------------------------------------------------------
# 流程
# ---------------------------------------------------------------------------

func _test_first_death_flow() -> void:
	Story.auto_skip = true
	Story.reset_progress()
	GameState.start_new_run(GameState.difficulties[1])
	Progression.credits = 1000
	var started: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: started.append(id)
	Story.scene_started.connect(on_started)
	var retried := [false]
	var level := await spawn_level(load(BOOTH_AREA) as LevelData)
	level.retry_requested.connect(func() -> void: retried[0] = true)
	check(not GameState.has_checkpoint, "no booth has been used yet")
	_kill(level)
	var played := await _wait_for_scene(started, FIRST_DEATH_SCENE)
	check(played, "the first death plays the clinic scene directly")
	var guard := 0
	while not retried[0] and guard < 300:
		await frames(1)
		guard += 1
	check(retried[0], "the level asks for the respawn only after the scene")
	check(GameState.has_flag(SEEN_FLAG), "the flag is written when the scene finishes")
	check(Progression.credits == 1000, "the story death does not charge the revival fee (%d)" % Progression.credits)
	check(GameState.has_checkpoint and GameState.checkpoint_level_path == BOOTH_AREA, "a booth is registered as the respawn point")
	var booths := LevelBuilder.parse(load(BOOTH_AREA) as LevelData).checkpoints
	check(booths.size() > 0 and GameState.checkpoint_position.distance_to(booths[0]) < 1.0, "the registered booth is the nearest one")
	check(GameState.checkpoint_notice_pending, "the next respawn announces the registration")
	var screens := level.get_children().filter(func(n: Node) -> bool: return n is DeathScreen)
	check(screens.is_empty(), "the clinic scene replaces the death screen (no detour through it)")
	await end_level(level)
	# 重生：提示一次，然後消耗掉。
	var toasts: Array[String] = []
	var on_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	level = await spawn_level(load(BOOTH_AREA) as LevelData)
	await frames(150)
	check(toasts.has(Level.REGISTERED_TOAST), "the respawn shows the booth-registered hint (%s)" % [toasts])
	check(not GameState.checkpoint_notice_pending, "the hint shows only once")
	check(is_instance_valid(level.player) and level.player.global_position.distance_to(booths[0]) < 60.0, "the player wakes at the booth")
	EventBus.toast_requested.disconnect(on_toast)
	Story.scene_started.disconnect(on_started)
	await end_level(level)


func _test_second_death_uses_the_screen() -> void:
	Story.auto_skip = true
	Story.reset_progress()
	GameState.start_new_run(GameState.difficulties[1])
	GameState.set_flag(SEEN_FLAG)
	Progression.credits = 1000
	var started: Array[StringName] = []
	var on_started := func(id: StringName, _mode: StringName) -> void: started.append(id)
	Story.scene_started.connect(on_started)
	var level := await spawn_level(load(BOOTH_AREA) as LevelData)
	_kill(level)
	var guard := 0
	var screens: Array = []
	while screens.is_empty() and guard < 300:
		await frames(1)
		screens = level.get_children().filter(func(n: Node) -> bool: return n is DeathScreen)
		guard += 1
	check(not screens.is_empty(), "a later death shows the normal death screen")
	check(not started.has(FIRST_DEATH_SCENE), "the clinic is not shown again")
	check(Progression.credits < 1000, "a normal death charges the revival fee (%d)" % Progression.credits)
	Story.scene_started.disconnect(on_started)
	await end_level(level)


## 診間過場沒播完（中途退出）：旗標沒寫、沒有登記電話亭，下一次死亡會再播，不會悄悄跳過解釋。
func _test_unfinished_scene_plays_again() -> void:
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	check(not GameState.has_flag(SEEN_FLAG) and not GameState.has_checkpoint, "a fresh run has neither flag nor booth")
	check(not Story.death_scene_entry(&"ch1_kasa", &"flood").is_empty() or GameState.deaths == 0,
			"without the flag the first death still resolves to the clinic")
	GameState.register_death()
	check(str(Story.death_scene_entry(&"ch1_kasa", &"flood").get("scene", "")) == String(FIRST_DEATH_SCENE), "no flag: the clinic plays again")
	# 沒有電話亭可登記：不崩潰、不登記。
	var level := await spawn_level(load("res://data/levels/ch1_stall.tres") as LevelData)
	check(not level._register_nearest_checkpoint() or GameState.has_checkpoint, "a level without booths registers nothing or falls back safely")
	await end_level(level)
	GameState.start_new_run(GameState.difficulties[1])
