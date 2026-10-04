class_name ReloadCuesSuite
extends EnemySuiteBase
## 換彈聲音時間軸（NE-165）：預設三段與改動前相同、武器自訂整份取代、進度越過才播、完成補播、取消不補播、壞資料退回預設、寫回工具。

const WEAPON := &"test_audio_cue_weapon"


func run() -> void:
	_test_default_timeline()
	_test_override_and_inheritance()
	_test_validation()
	_test_broken_data_falls_back()
	_test_track()
	_test_writer()
	await _test_in_play()
	WeaponSounds.reload_data(true)


func _cues(weapon: StringName = WEAPON) -> Array[ReloadCues.Cue]:
	return ReloadCues.for_weapon(weapon)


func _test_default_timeline() -> void:
	for weapon_id in [&"pistol", &"rifle", &"launcher", &"test_audio_no_such_weapon", &""]:
		var cues := _cues(weapon_id)
		check(cues.size() == 3, "%s uses the default three-part reload (%d)" % [weapon_id, cues.size()])
		if cues.size() == 3:
			check(is_equal_approx(cues[0].at, 0.0) and is_equal_approx(cues[1].at, 0.55) and is_equal_approx(cues[2].at, 1.0), "%s default cue times are 0 / 0.55 / 1" % weapon_id)
			check(cues[0].kind == &"reload_start" and cues[1].kind == &"reload_mid" and cues[2].kind == &"reload_done", "%s default cues are start, mid, done" % weapon_id)
	check(ReloadCues.sound_of(&"pistol", _cues(&"pistol")[0]) == WeaponSounds.name_for(&"pistol", &"reload_start"), "a kind cue plays the weapon's own sound for that kind")
	check(ReloadCues.sound_of(&"pistol", _cues(&"pistol")[0]) != ReloadCues.sound_of(&"launcher", _cues(&"launcher")[0]), "different weapon families still start their reload with different sounds")
	check(ReloadCues.FALLBACK.size() == 3, "the built-in fallback is the same three parts")
	var errors := ReloadCues.validate_profiles(WeaponSounds.table(), Sfx.has_named)
	check(errors.is_empty(), "shipped reload cues have no errors: %s" % ", ".join(errors))


func _test_override_and_inheritance() -> void:
	var table := WeaponSounds.table()
	table.override(WEAPON, &"reload_cues", [{"at": 0.0, "sound": "reload_mid", "volume_db": -6.0}])
	var one := _cues()
	check(one.size() == 1 and one[0].sound == &"reload_mid" and is_equal_approx(one[0].volume_db, -6.0), "a weapon can use a single-part reload")
	check(ReloadCues.sound_of(WEAPON, one[0]) == &"reload_mid", "a sound cue plays the named sound directly")
	table.override(WEAPON, &"reload_cues", [])
	check(_cues().is_empty(), "an empty timeline means a silent reload")
	var five: Array = []
	for i in 5:
		five.append({"at": float(i) / 4.0, "kind": "reload_mid", "volume_db": -4.0})
	table.override(WEAPON, &"reload_cues", five)
	check(_cues().size() == 5, "a weapon can have five parts")
	table.override(WEAPON, &"reload_cues", [{"at": 0.8, "kind": "reload_done"}, {"at": 0.2, "kind": "reload_start"}, {"at": 0.2, "kind": "reload_mid"}])
	var sorted := _cues()
	check(sorted[0].kind == &"reload_start" and sorted[1].kind == &"reload_mid" and sorted[2].kind == &"reload_done", "cues are sorted by time and keep their written order on ties")
	# 沿用另一個 profile：自己沒寫的沿用基底的時間軸。
	table.override(&"test_audio_cue_base", &"reload_cues", [{"at": 0.5, "kind": "reload_start"}])
	table.override(WEAPON, &"extends", "test_audio_cue_base")
	table.raw_profiles()[String(WEAPON)].erase("reload_cues")
	var inherited := _cues()
	check(inherited.size() == 1 and is_equal_approx(inherited[0].at, 0.5), "a profile without its own timeline inherits the one it extends")
	WeaponSounds.reload_data(true)
	check(_cues().size() == 3, "reloading the data discards preview overrides (%d)" % _cues().size())


func _test_validation() -> void:
	var has := Sfx.has_named
	check(ReloadCues.validate_list(null, has).is_empty() and ReloadCues.validate_list([], has).is_empty(), "no timeline and an empty timeline are valid")
	check(not ReloadCues.validate_list("x", has).is_empty(), "a timeline must be an array")
	var bad_time := ReloadCues.validate_list([{"at": 0.1, "kind": "reload_start"}, {"at": 1.5, "kind": "reload_done"}], has)
	check(bad_time.size() == 1 and bad_time[0].contains("第 2 段") and bad_time[0].contains("at"), "a time outside 0 to 1 names the part: %s" % [bad_time])
	check(not ReloadCues.validate_list([{"at": 0.5, "kind": "nope"}], has).is_empty(), "an unknown kind is an error")
	check(not ReloadCues.validate_list([{"at": 0.5, "sound": "test_audio_no_such_sound"}], has).is_empty(), "a sound that does not exist is an error")
	check(ReloadCues.validate_list([{"at": 0.5, "sound": "test_audio_no_such_sound"}], has, true).is_empty(), "at run time a missing sound is only silent, not an error")
	check(not ReloadCues.validate_list([{"at": 0.5, "kind": "reload_mid", "sound": "reload_mid"}], has).is_empty(), "kind and sound cannot both be set")
	check(not ReloadCues.validate_list([{"at": 0.5, "kind": "reload_mid", "volume_db": 99}], has).is_empty(), "an out-of-range volume is an error")
	check(not ReloadCues.validate_list([{"at": 0.5, "kind": "reload_mid", "loud": true}], has).is_empty(), "an unknown field is an error")
	var many: Array = []
	for i in ReloadCues.MAX_CUES + 1:
		many.append({"at": 0.5, "kind": "reload_mid"})
	check(not ReloadCues.validate_list(many, has).is_empty(), "more than %d parts is an error" % ReloadCues.MAX_CUES)


func _test_broken_data_falls_back() -> void:
	var weapon := &"test_audio_cue_broken"
	WeaponSounds.table().override(weapon, &"reload_cues", [{"at": 7.0, "kind": "reload_start"}])
	check(_cues(weapon).size() == 3, "a broken timeline falls back to the built-in three parts instead of a silent reload")
	WeaponSounds.table().override(weapon, &"reload_cues", "not a list")
	check(_cues(weapon).size() == 3, "a timeline of the wrong type falls back too")
	WeaponSounds.reload_data(true)


func _test_track() -> void:
	WeaponSounds.table().override(WEAPON, &"reload_cues", [
		{"at": 0.0, "sound": "reload_start", "volume_db": -4.0},
		{"at": 0.4, "sound": "reload_mid", "volume_db": -4.0},
		{"at": 0.4, "sound": "reload_mid", "volume_db": -8.0},
		{"at": 1.0, "sound": "reload_done", "volume_db": -3.0},
	])
	var track := ReloadCueTrack.new()
	var played := []
	track.cue_played.connect(func(index: int, sound: StringName) -> void: played.append([index, sound]))
	track.begin(WEAPON)
	check(played.size() == 1 and played[0][1] == &"reload_start", "a cue at time 0 plays as soon as the reload begins")
	check(track.advance(0.3) == 0 and played.size() == 1, "nothing plays before the next cue time")
	check(track.advance(0.4) == 2 and played.size() == 3, "reaching a time plays every cue at that time, in order")
	check(track.advance(0.4) == 0, "a cue never plays twice")
	check(track.advance(0.99) == 0, "the last cue waits for its time")
	check(track.finish() == 1 and played.size() == 4 and played[3][1] == &"reload_done", "finishing plays the cues that are left")
	check(not track.is_active() and track.advance(1.0) == 0, "a finished track is idle")
	played.clear()
	track.begin(WEAPON)
	track.advance(0.5)
	track.cancel()
	check(track.advance(1.0) == 0 and track.finish() == 0, "a cancelled reload plays nothing more, even when finished")
	# 義體加速換彈：進度跳得比較快也一樣不漏。
	played.clear()
	track.begin(WEAPON)
	check(track.advance(0.95) == 2 and track.finish() == 1, "a big jump in progress still plays every cue once")
	# 缺的聲音只是不響，cue 仍然算播過。
	WeaponSounds.table().override(WEAPON, &"reload_cues", [{"at": 0.0, "sound": "test_audio_no_such_sound"}, {"at": 0.5, "kind": "reload_mid"}])
	played.clear()
	track.begin(WEAPON)
	check(played.size() == 1 and played[0][1] == &"", "a missing sound is skipped silently")
	track.cancel()
	# 整段換彈只用一個聲音：開始播一次，之後（包含完成時）不重複。
	WeaponSounds.table().override(WEAPON, &"reload_cues", [{"at": 0.0, "sound": "reload_start_heavy", "volume_db": -3.0}])
	played.clear()
	track.begin(WEAPON)
	check(played.size() == 1 and track.advance(0.5) == 0 and track.advance(1.0) == 0 and track.finish() == 0 and played.size() == 1, "a single sound for the whole reload plays once and never repeats")
	track.cancel()
	WeaponSounds.reload_data(true)


func _test_writer() -> void:
	var path := "user://test_audio_cues_writer.json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(WeaponSounds.PATH), ProjectSettings.globalize_path(path))
	var before := FileAccess.get_file_as_string(path)
	var timeline := [{"at": 0.0, "kind": "reload_start", "volume_db": -4.0}, {"at": 0.7, "kind": "reload_done", "volume_db": -3.0}]
	var change := {"path": ["profiles", "pistol", "reload_cues"], "value": timeline}
	var preview := AudioDataWriter.apply(path, [change], true)
	check((preview["errors"] as PackedStringArray).is_empty() and (preview["diff"] as PackedStringArray).size() == 1, "a timeline change previews as one difference: %s" % [preview])
	check(FileAccess.get_file_as_string(path) == before, "the preview writes nothing")
	var missing := AudioDataWriter.apply(path, [{"path": ["profiles", "test_audio_new_weapon", "reload_cues"], "value": timeline}])
	check(not (missing["errors"] as PackedStringArray).is_empty() and FileAccess.get_file_as_string(path) == before, "a weapon without a profile is an error unless the change asks to create it")
	var created := AudioDataWriter.apply(path, [{"path": ["profiles", "test_audio_new_weapon", "reload_cues"], "value": timeline, "ensure": true}])
	check((created["errors"] as PackedStringArray).is_empty() and created["backup"] == path + ".bak", "ensure creates the missing profile and keeps a backup")
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed["profiles"].has("test_audio_new_weapon") and parsed["profiles"]["test_audio_new_weapon"]["reload_cues"].size() == 2 and parsed["profiles"].has("pistol"), "only the new profile is added")
	var bad := AudioDataWriter.apply(path, [{"path": ["profiles", "pistol", "reload_cues"], "value": [{"at": 3.0, "kind": "reload_start"}]}])
	check(not (bad["errors"] as PackedStringArray).is_empty() and (bad["errors"][0] as String).contains("第 1 段"), "an invalid timeline is rejected with the part named: %s" % [bad["errors"]])
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


## 真的換彈：預設三段依序響、改成五段響五次、中途取消不再響。
func _test_in_play() -> void:
	await open_level(10.0)
	var player := level.player
	var played := []
	player.reload_track.cue_played.connect(func(index: int, sound: StringName) -> void: played.append(index))
	var weapon := player.loadout.active_weapon()
	check(weapon != null and weapon.has_magazine(), "the starting weapon has a magazine to reload")
	if weapon == null:
		return
	await _reload_once(player)
	check(played == [0, 1, 2], "a real reload plays the three default parts in order: %s" % [played])
	var five: Array = []
	for i in 5:
		five.append({"at": float(i) / 4.0, "kind": "reload_mid", "volume_db": -6.0})
	WeaponSounds.table().override(weapon.id, &"reload_cues", five)
	played.clear()
	await _reload_once(player)
	check(played == [0, 1, 2, 3, 4], "a five-part timeline plays five parts in a real reload: %s" % [played])
	WeaponSounds.table().override(weapon.id, &"reload_cues", [])
	played.clear()
	await _reload_once(player)
	check(played.is_empty(), "an empty timeline makes a silent reload")
	WeaponSounds.reload_data(true)
	played.clear()
	player.loadout.consume_ammo()
	player.loadout.start_reload()
	await physics_frames(3)
	var before := played.size()
	player.loadout.cancel_reload()
	await physics_frames(int(weapon.reload_time * 90.0))
	check(played.size() == before and not player.reload_track.is_active(), "cancelling the reload stops the remaining parts")
	await end_level(level)


func _reload_once(player: Player) -> void:
	player.loadout.consume_ammo()
	player.loadout.start_reload()
	check(player.loadout.is_reloading(), "the reload starts")
	var frames_left := int(player.loadout.active_weapon().reload_time * 240.0) + 30
	while player.loadout.is_reloading() and frames_left > 0:
		await physics_frames(1)
		frames_left -= 1
	await physics_frames(2)
