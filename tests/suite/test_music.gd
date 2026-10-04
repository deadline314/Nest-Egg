class_name MusicSuite
extends EnemySuiteBase
## 背景音樂系統（NE-160）：曲目與 cue 對應、關卡內平靜／戰鬥／頭目切換與遲滯、死亡與選單曲目、
## 暫停與過場的音色、曲目遺失或資料損毀時的容錯、設定選單的音樂音量。
## 缺檔測試的曲目與 id 含 test_audio_，執行器會忽略它的錯誤輸出。

const FIXTURE_OK := "res://tests/fixtures/audio/music_ok.json"
const FIXTURE_BAD := "res://tests/fixtures/audio/music_bad.json"


func run() -> void:
	_test_shipped_data()
	_test_resolution()
	_test_validation()
	await _test_playback_and_crossfade()
	_test_missing_track()
	await _test_level_flow()
	await _test_death_and_screens()
	await _test_pause_and_cinematic()
	_test_music_bus()
	_restore()


func _restore() -> void:
	Music.stop(0.0)
	Music.load_data(Music.PATH, true)


func _test_shipped_data() -> void:
	var errors: PackedStringArray = Music.validate()
	check(errors.is_empty(), "shipped music data has no errors: %s" % ", ".join(errors))


func _test_resolution() -> void:
	Music.load_data(FIXTURE_OK, true)
	check(Music.validate().is_empty(), "fixture music data is valid: %s" % ", ".join(Music.validate()))
	check(Music.resolve_cue(&"cover_test", &"zone_x", &"calm") == &"calm_a", "the level's own cue wins over the zone's")
	check(Music.resolve_cue(&"other_level", &"zone_x", &"calm") == &"calm_b", "an unknown level falls back to the zone")
	check(Music.resolve_cue(&"other_level", &"zone_x", &"boss") == &"boss_a", "the zone can give a boss cue")
	check(Music.resolve_cue(&"cover_test", &"zone_x", &"boss") == &"boss_a", "each state looks at the level, then the zone: the zone supplies the missing boss cue")
	check(Music.resolve_cue(&"cover_test", &"nowhere", &"boss") == &"combat_a", "a boss state with no boss cue anywhere falls back to the combat cue")
	check(Music.resolve_cue(&"nowhere", &"nowhere", &"calm") == &"calm_b", "everything unknown falls back to the default")
	check(Music.resolve_cue(&"nowhere", &"nowhere", &"boss") == &"calm_b", "boss and combat fall back to calm when nothing else exists")
	check(Music.resolve_cue(&"nowhere", &"nowhere", &"test_no_such_state") == &"calm_b", "an unknown state is treated like calm")
	check(Music.screen_cue(&"menu") == &"menu_cue" and Music.screen_cue(&"nobody") == &"", "screens map to cues, unknown screens to nothing")


func _test_validation() -> void:
	Music.load_data(FIXTURE_BAD, true)
	var text := "\n".join(Music.validate())
	check(text.contains("t_gone") and text.contains("找不到檔案"), "validation flags a track whose file is missing")
	check(text.contains("t_json") and text.contains("不是音訊檔"), "validation flags a track that is not audio")
	check(text.contains("c_notrack") and text.contains("t_nobody"), "validation flags a cue pointing at a missing track")
	check(text.contains("c_neg") and text.contains("fade_in"), "validation flags a negative fade")
	check(text.contains("lobby"), "validation flags an unknown screen")
	check(text.contains("c_nobody"), "validation flags a screen or state pointing at a missing cue")
	check(text.contains("panic"), "validation flags an unknown state")
	check(text.contains("l1") and text.contains("要是字典"), "validation flags a level entry that is not a dictionary")


func _test_playback_and_crossfade() -> void:
	Music.load_data(FIXTURE_OK, true)
	Music.stop(0.0)
	await frames(2)
	check(Music.play_cue(&"calm_a"), "a cue starts")
	check(Music.current_cue() == &"calm_a" and Music.is_playing(), "the current cue is reported")
	check(not Music.play_cue(&"calm_a"), "the same cue does not restart")
	check(Music.play_cue(&"combat_a"), "another cue crossfades in")
	check(Music.player().voices_playing() == 2, "both tracks play during the crossfade")
	check(Music._positions.has("calm_a"), "the position of the cue we left is remembered so it can resume")
	for i in 20:
		Music.player()._process(0.1)
	check(Music.player().voices_playing() == 1, "the old track stops after the fade")
	check(is_equal_approx(Music.player().target_volume(), -2.0), "the cue's volume applies (%.1f)" % Music.player().target_volume())
	Music.play_cue(&"calm_a")
	check(is_equal_approx(Music.player().target_volume(), -3.0), "the track's own volume adds to the cue's (%.1f)" % Music.player().target_volume())
	Music.stop(0.0)
	for i in 5:
		Music.player()._process(0.1)
	check(not Music.is_playing() and Music.current_cue() == &"", "stop silences the music")


func _test_missing_track() -> void:
	Music.load_data(FIXTURE_BAD, true)
	Music.stop(0.0)
	check(not Music.play_cue(&"c_gone"), "a cue whose track file is missing does not play")
	check(not Music.is_playing(), "a missing track leaves the music silent without crashing")
	check(not Music.play_cue(&"test_audio_no_such_cue"), "an unknown cue is ignored")


func _test_level_flow() -> void:
	Music.load_data(FIXTURE_OK, true)
	await open_level(10.0)
	await frames(3)
	check(Music.current_cue() == &"calm_a", "entering the level plays its calm cue (%s)" % Music.current_cue())
	var enemy := spawn(GRUNT_PATH, 34.0)  # 離玩家約 24 格，在戰鬥偵測範圍內但還沒發現玩家
	await physics_frames(2)
	check(Music.engaged_enemies() == 0, "a patrolling enemy does not count as combat")
	enemy.raise_alert(level.player.global_position, 5.0)
	_tick_music()
	check(Music.current_state() == &"combat" and Music.current_cue() == &"combat_a", "an alerted enemy nearby switches to the combat cue (%s)" % Music.current_cue())
	enemy.hurtbox.receive(lethal())
	await physics_frames(3)
	_tick_music()
	check(Music.current_state() == &"combat", "combat does not end the instant the enemy dies")
	Music._no_enemy_time = Music.COMBAT_EXIT_DELAY - Music.COMBAT_CHECK_INTERVAL
	_tick_music()
	check(Music.current_state() == &"calm" and Music.current_cue() == &"calm_a", "combat ends a few seconds after the last enemy (%s)" % Music.current_cue())
	var far := spawn(GRUNT_PATH, 75.0)
	far.raise_alert(level.player.global_position, 5.0)
	_tick_music()
	check(Music.engaged_enemies() == 0 and Music.current_state() == &"calm", "an engaged enemy far away does not trigger combat music")
	far.queue_free()
	EventBus.boss_started.emit("測試頭目", 100)
	check(Music.current_cue() == &"combat_a", "the boss state falls back to the combat cue when the level has no boss cue")
	EventBus.boss_defeated.emit()
	check(Music.current_cue() == &"calm_a", "defeating the boss returns to the calm cue")
	await end_level(level)
	await frames(2)
	check(Music.current_cue() == &"" and not Music.is_playing(), "leaving the level stops the music")


## 直接推進音樂的戰鬥偵測一次（測試不依賴實際影格數）。
func _tick_music() -> void:
	Music._check_left = 0.0
	Music._process(Music.COMBAT_CHECK_INTERVAL)


func _test_death_and_screens() -> void:
	Music.load_data(FIXTURE_OK, true)
	Music.show_menu()
	check(Music.current_cue() == &"menu_cue", "the main menu plays its cue")
	Music.show_victory()
	check(Music.current_cue() == &"sting", "the victory screen plays its sting")
	await open_level(10.0)
	await frames(3)
	EventBus.player_died.emit(&"test")
	check(Music.current_cue() == &"sting", "dying plays the death sting")
	check(not bool(Music.player().current_stream().get("loop")), "a sting is not looped")
	await end_level(level)
	Music.stop(0.0)


func _test_pause_and_cinematic() -> void:
	var music_bus := AudioServer.get_bus_index(&"Music")
	check(AudioServer.get_bus_effect_count(music_bus) >= 2, "the music bus has the pause filter and ducking effects")
	runner.get_tree().paused = true
	Music._update_filters(1.0)
	var state: Dictionary = Music.filter_state()
	check(float(state["cutoff_hz"]) <= Music.PAUSE_CUTOFF_HZ + 1.0 and float(state["duck_db"]) <= Music.PAUSE_DUCK_DB + 0.01, "pausing muffles and lowers the music (%s)" % [state])
	runner.get_tree().paused = false
	Music._update_filters(1.0)
	state = Music.filter_state()
	check(float(state["cutoff_hz"]) >= Music.OPEN_CUTOFF_HZ - 1.0 and float(state["duck_db"]) >= -0.01, "resuming restores the music (%s)" % [state])
	Music._update_filters(0.0)
	check(is_equal_approx(float(Music.filter_state()["cutoff_hz"]), Music.OPEN_CUTOFF_HZ), "no time passing changes nothing")


func _test_music_bus() -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	check(bus >= 0, "the Music bus exists")
	var listed := false
	for entry in Settings.AUDIO_BUSES:
		listed = listed or entry["bus"] == &"Music"
	check(listed, "the settings menu lists a music volume slider")
	var previous := Settings.get_volume(&"Music")
	Settings.set_volume(&"Music", 0.4)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.4)), "the music slider drives the Music bus")
	Settings.set_volume(&"Music", previous)
