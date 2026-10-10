extends RefCounted
## 第一個還原通知必須看到完整的故事、物品、世界與死亡事實。

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const DISK := &"ch1_data_disk"


static func run(s: TestSuite) -> void:
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"credits": 731})
	StoryItems.acquire(DISK, false)
	StoryItems.transfer(DISK)
	GameState.world_flags["restore_observer_marker"] = "saved"
	GameState.area_state(&"restore_test")["consumed"]["disk@4,5"] = true
	GameState.deaths = 2
	GameState.run_time = 83.5
	var saved := RunSnapshot.capture(FIRST, {"health": 4, "position": [100, 160], "world": {}, "loadout": {}})
	GameState.start_new_run(GameState.difficulties[1])
	Progression.restore({"credits": 9})
	GameState.world_flags["restore_observer_marker"] = "live"
	var seen: Array[Dictionary] = []
	var on_credits := func(value: int, _delta: int) -> void:
		seen.append({"value": value, "marker": GameState.world_flags.get("restore_observer_marker"),
			"held": StoryItems.holds(DISK), "transferred": StoryItems.was_transferred(DISK),
			"consumed": GameState.area_states.get("restore_test", {}).get("consumed", {}).get("disk@4,5", false),
			"deaths": GameState.deaths, "time": GameState.run_time, "lives": GameState.lives_left})
	Progression.credits_changed.connect(on_credits)
	RunSnapshot.apply(saved)
	s.check(seen.size() == 1, "whole restore publishes one wallet snapshot without a temporary new-run reset")
	if seen.size() == 1:
		var first: Dictionary = seen[0]
		s.check(first["value"] == 731 and first["marker"] == "saved" and not first["held"] and first["transferred"] and first["consumed"], "first wallet observer sees restored story, transferred custody and world together")
		s.check(first["deaths"] == 2 and first["time"] == 83.5, "first wallet observer sees saved deaths and clock")
	seen.clear()
	GameState.deaths = 7
	GameState.lives_left = 3
	GameState.run_time = 127.5
	GameState.kills = 11
	GameState.finishers = 4
	GameState.last_death_clock = "12 點 03 分"
	GameState.world_flags["restore_observer_marker"] = "tentative"
	RunSnapshot.rollback_presentation(saved)
	s.check(seen.size() == 1, "presentation rollback publishes only the complete restored snapshot")
	if seen.size() == 1:
		s.check(seen[0]["deaths"] == 7 and seen[0]["lives"] == 3 and seen[0]["time"] == 127.5, "rollback observer retains actual deaths, lives and elapsed time")
		s.check(seen[0]["marker"] == "saved" and seen[0]["transferred"] and seen[0]["consumed"], "rollback observer sees restored custody and world before publication")
	s.check(GameState.kills == 11 and GameState.finishers == 4 and GameState.last_death_clock == "12 點 03 分", "rollback retains actual combat and death facts")
	seen.clear()
	RunSnapshot.apply(saved, false)
	s.check(seen.is_empty() and Progression.credits == 731 and StoryItems.was_transferred(DISK), "Main can finish route metadata before restore publication")
	RunSnapshot.publish_restored()
	s.check(seen.size() == 1, "explicit publication after Main metadata emits once")
	Progression.credits_changed.disconnect(on_credits)
	# 取消通知先看到舊的完整局，不是新旗標配舊錢包。
	var cancelled: Array[Dictionary] = []
	var scene := StringName(Story._scenes.keys()[0])
	Story._current_cinematic = scene
	Story._current_request = 9801
	GameState.world_flags["restore_observer_marker"] = "old"
	var on_cancel := func(_id: StringName, _context: Dictionary, _reason: StringName, _request: int) -> void:
		cancelled.append({"marker": GameState.world_flags.get("restore_observer_marker"), "credits": Progression.credits})
	Story.presentation_cancelled.connect(on_cancel)
	GameState.restore_story_progress(saved["story"])
	s.check(cancelled.size() == 1 and cancelled[0]["marker"] == "old" and cancelled[0]["credits"] == 731, "standalone story restore cancels the old presentation before replacing flags")
	Story.presentation_cancelled.disconnect(on_cancel)
	GameState.start_new_run(GameState.difficulties[1])
